import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../util/dinero.dart';
import '../util/import_archivo.dart';
import '../util/plantilla_import.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Hoja para proponer, en la remisión de devolución, un artículo que NO
/// está en el catálogo (docs/plan-remision-elementos-nuevos.md).
///
/// Devuelve con `Navigator.pop`:
/// - un [Elemento], si resultó que sí existía (se tocó uno de los parecidos);
/// - una [LineaDevolucion] nueva, con nombre, unidad, cantidad y costo
///   estimado;
/// - null, si se cerró sin guardar.
///
/// Los parecidos van ARRIBA del formulario a propósito: casi siempre el
/// artículo ya existe escrito de otra forma, y un duplicado en el catálogo
/// cuesta mucho más que diez segundos de mirar.
class HojaElementoNuevo extends StatefulWidget {
  /// Al editar una línea nueva que ya estaba en la remisión.
  final LineaDevolucion? inicial;

  /// Lo que se había escrito en el buscador, para no volver a escribirlo.
  final String nombreInicial;

  /// El catálogo para buscar parecidos. Null si no se pudo traer (sin
  /// señal): la hoja lo dice y la bodega lo revisa al cargar.
  final EmparejadorCatalogo? catalogo;

  /// Nombres (ya normalizados) de las otras líneas NUEVAS de la remisión.
  final Set<String> nuevosEnLista;

  const HojaElementoNuevo({
    super.key,
    this.inicial,
    this.nombreInicial = '',
    this.catalogo,
    this.nuevosEnLista = const {},
  });

  @override
  State<HojaElementoNuevo> createState() => _HojaElementoNuevoState();
}

class _HojaElementoNuevoState extends State<HojaElementoNuevo> {
  late final _nombre =
      TextEditingController(text: widget.inicial?.nombre ?? widget.nombreInicial);
  late final _cantidad = TextEditingController(
      text: widget.inicial == null ? '' : _texto(widget.inicial!.cantidad));
  late final _costo = TextEditingController(
      text: widget.inicial?.costoEstimado?.round().toString() ?? '');
  late String? _unidad = widget.inicial?.unidad;
  bool _mostrarErrores = false;

  static String _texto(num n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  List<Elemento> get _parecidos => widget.catalogo == null
      ? const []
      : [for (final p in widget.catalogo!.parecidos(_nombre.text)) p.$1];

  Elemento? get _mismoNombre => widget.catalogo?.mismoNombre(_nombre.text);

  num? get _cant => num.tryParse(_cantidad.text.trim().replaceAll(',', '.'));

  String? get _errorNombre {
    final t = _nombre.text.trim();
    if (t.isEmpty) return 'Escribe el nombre del artículo';
    final igual = _mismoNombre;
    if (igual != null) {
      return 'Ya existe en el catálogo: "${igual.nombre}". Tócalo arriba.';
    }
    if (widget.nuevosEnLista.contains(normalizarTexto(t))) {
      return 'Ya está en la remisión como nuevo: edita esa línea';
    }
    return null;
  }

  String? get _errorUnidad => _unidad == null ? 'Elige la unidad' : null;

  String? get _errorCantidad {
    if (_cantidad.text.trim().isEmpty) return 'Escribe cuántos';
    final c = _cant;
    if (c == null) return 'No es un número';
    if (c <= 0) return 'Tiene que ser mayor que cero';
    return null;
  }

  String? get _errorCosto {
    if (_costo.text.trim().isEmpty) return 'Escribe cuánto vale UNA unidad';
    final c = leerPesos(_costo.text);
    if (c == null) return 'No es un valor';
    if (c <= 0) return 'Tiene que ser mayor que cero';
    return null;
  }

  bool get _valido =>
      _errorNombre == null &&
      _errorUnidad == null &&
      _errorCantidad == null &&
      _errorCosto == null;

  void _guardar() {
    if (!_valido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    Navigator.pop(
      context,
      LineaDevolucion.nueva(
        nombre: _nombre.text.trim(),
        cantidad: _cant!,
        unidad: _unidad!,
        costoEstimado: leerPesos(_costo.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final parecidos = _parecidos;
    // El error del nombre repetido se ve AL ESCRIBIR; "vacío", al guardar.
    final errorNombre = _errorNombre;
    final mostrarErrorNombre = _mostrarErrores ||
        (errorNombre != null && _nombre.text.trim().isNotEmpty);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      widget.inicial == null
                          ? 'Artículo NUEVO'
                          : 'Editar artículo nuevo',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              'Solo si no está en el catálogo. La bodega lo revisa al cargar '
              'la devolución, y un coordinador lo crea.',
              style: TextStyle(fontSize: 13, color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (widget.catalogo == null)
              Text(
                'Sin conexión no pude revisar si ya existe en el catálogo. '
                'La bodega lo revisará al cargar.',
                style: TextStyle(fontSize: 13, color: esquema.onSurfaceVariant),
              )
            else if (parecidos.isNotEmpty) ...[
              Text('¿Es alguno de estos?',
                  style: Theme.of(context).textTheme.labelLarge),
              for (final e in parecidos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(e.nombre),
                  subtitle: Text('${e.unidad} · costo promedio '
                      '${_money.format(e.costoPromedio)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, e),
                ),
              const Divider(height: 20),
            ],
            TextField(
              controller: _nombre,
              autofocus: widget.inicial == null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Válvula mariposa 4" wafer',
                helperText: 'Como debería quedar en el catálogo',
                errorText: mostrarErrorNombre ? errorNombre : null,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Unidad *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final u in unidadesElemento)
                  ChoiceChip(
                    label: Text(u),
                    selected: _unidad == u,
                    onSelected: (_) => setState(() => _unidad = u),
                  ),
              ],
            ),
            if (_mostrarErrores && _errorUnidad != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_errorUnidad!,
                      style: TextStyle(fontSize: 12.5, color: esquema.error)),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _cantidad,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                if (_mostrarErrores) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Cantidad *',
                errorText: _mostrarErrores ? _errorCantidad : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costo,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Costo estimado por unidad *',
                // Cómo quedó entendido lo escrito ("185.000" = $185.000).
                helperText: pesosEntendidos(_costo.text) ??
                    'Lo que crees que vale UNA unidad',
                errorText: _mostrarErrores ? _errorCosto : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardar,
              child: Text(widget.inicial == null
                  ? 'Agregar a la remisión'
                  : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Qué hacer con un artículo que llegó como NUEVO en el archivo, además de
/// elegir uno de los parecidos (eso devuelve el [Elemento] directamente).
enum AccionNuevo { buscar, crear, quitar }

/// Hoja de la bodega, en Devoluciones, para resolver una fila que llegó
/// como NUEVO: nunca se empareja sola (regla 1 del plan). Devuelve un
/// [Elemento] (era uno del catálogo), una [AccionNuevo], o null.
class HojaResolverNuevo extends StatelessWidget {
  final String propuesto;
  final num cantidad;
  final String? unidad;
  final num? costoEstimado;
  final String? estimadoPor;
  final List<Elemento> parecidos;
  /// Crear en el catálogo: solo admin y coordinador (RLS `cud_elem`).
  final bool puedeCrear;

  const HojaResolverNuevo({
    super.key,
    required this.propuesto,
    required this.cantidad,
    this.unidad,
    this.costoEstimado,
    this.estimadoPor,
    this.parecidos = const [],
    required this.puedeCrear,
  });

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final cant = cantidad % 1 == 0
        ? cantidad.toInt().toString()
        : cantidad.toString().replaceAll('.', ',');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Artículo NUEVO por resolver',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin resolver',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('"$propuesto"',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [
                '$cant ${unidad ?? '(sin unidad)'}',
                costoEstimado == null
                    ? 'sin costo estimado'
                    : 'estimado ${_money.format(costoEstimado)} c/u',
                if (estimadoPor != null) 'por $estimadoPor',
              ].join(' · '),
              style: TextStyle(fontSize: 13, color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (parecidos.isNotEmpty) ...[
              Text('¿Es alguno de estos?',
                  style: Theme.of(context).textTheme.labelLarge),
              for (final e in parecidos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(e.nombre),
                  subtitle: Text('${e.unidad} · costo promedio '
                      '${_money.format(e.costoPromedio)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, e),
                ),
              const SizedBox(height: 8),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('No encontré nada parecido en el catálogo.',
                    style: TextStyle(
                        fontSize: 13, color: esquema.onSurfaceVariant)),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Buscar otro en el catálogo'),
              onPressed: () => Navigator.pop(context, AccionNuevo.buscar),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Crear en el catálogo'),
              onPressed: puedeCrear
                  ? () => Navigator.pop(context, AccionNuevo.crear)
                  : null,
            ),
            if (!puedeCrear)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Solo un coordinador o un administrador puede crearlo en '
                  'el catálogo. Pídeselo, o déjalo por fuera de esta carga.',
                  style:
                      TextStyle(fontSize: 12.5, color: esquema.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Dejar por fuera de esta carga'),
              onPressed: () => Navigator.pop(context, AccionNuevo.quitar),
            ),
          ],
        ),
      ),
    );
  }
}
