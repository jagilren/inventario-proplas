// Piezas visuales de los KITS (Referencias KITZABLES, Fase 3 —
// docs/plan-kits-equipos.md). Viven aquí y no dentro de la ficha del equipo
// para poder PROBARLAS: test/kit_componentes_widget_test.dart mide su
// accesibilidad (área táctil, nombres para el lector de pantalla, contraste)
// y que no se desborden en un celular de 360 px con la letra agrandada.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:intl/intl.dart';
import '../activos_service.dart';
import '../util/tiempo.dart';
import 'selector_recargable.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
String _cuando(DateTime f) => _fechaHora.format(horaColombia(f));

/// "2" y no "2.0"; "2,5" con coma, como se escribe en Colombia.
String textoCantidad(num n) =>
    n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', ',');

/// Cifras del mismo ancho: en una columna de valores los dígitos quedan
/// alineados y se comparan de un vistazo.
const _cifras = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// La marca "KIT" junto al nombre de una referencia kitzable. Ícono Y texto:
/// solo con color no lo nota quien no distingue colores, y un lector de
/// pantalla no lee colores.
class MarcaKit extends StatelessWidget {
  const MarcaKit({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Es un kit',
      // Que el lector diga "Es un kit" una vez, y no "ícono" + "KIT".
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 13, color: color),
            const SizedBox(width: 3),
            Text('KIT',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Una tarjeta por componente. Tarjeta y no fila de tabla: en 360 px una
/// tabla de cuatro columnas con nombres largos no se lee.
class TarjetaComponente extends StatelessWidget {
  final ActivoComponente componente;
  /// El porcentaje del equipo. Si es menor que 100 se muestra también el
  /// subtotal ponderado.
  final num porcentaje;
  /// Abrir el componente: su historia y registrar movimientos (Fase 5).
  final VoidCallback? onTap;
  const TarjetaComponente({
    super.key,
    required this.componente,
    required this.porcentaje,
    this.onTap,
  });

  /// Toda la tarjeta en UNA frase para el lector de pantalla. Sin esto leería
  /// "24 por 45.000" (el ×) y las cifras sueltas, sin decir qué es cada una.
  String get fraseAccesible {
    final c = componente;
    final cant = textoCantidad(c.cantidad);
    return [
      c.agotado ? '${c.nombre}, agotado' : c.nombre,
      '$cant ${c.cantidad == 1 ? "unidad" : "unidades"} a '
          '${_money.format(c.valorUnitario)} cada una',
      'subtotal ${_money.format(c.subtotal)}',
      if (porcentaje < 100)
        'al ${textoCantidad(porcentaje)} por ciento, '
            '${_money.format(c.subtotalAl(porcentaje))}',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final c = componente;
    final gris = Theme.of(context).colorScheme.onSurfaceVariant;
    final ponderado = porcentaje < 100;
    final cant = textoCantidad(c.cantidad);

    return Semantics(
      container: true,
      label: fraseAccesible,
      // excludeSemantics se "come" la acción de tocar del InkWell de adentro:
      // hay que declararla aquí, o para el lector de pantalla la tarjeta no
      // se podría abrir.
      button: onTap != null,
      onTap: onTap,
      hint: onTap == null
          ? null
          : 'Toca para ver su historia y registrar movimientos',
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(top: 10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      c.nombre,
                      // Agotado: en el color secundario del tema, NO con
                      // opacidad — la opacidad baja el contraste por debajo
                      // de lo legible.
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: c.agotado ? gris : null),
                    ),
                  ),
                  if (c.agotado)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Agotado',
                          style: TextStyle(
                              fontSize: 12,
                              color: gris,
                              fontWeight: FontWeight.w600)),
                    ),
                  // Señal visual de que se puede abrir.
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 20, color: gris),
                ],
              ),
              const SizedBox(height: 6),
              // Wrap y no Row: con la letra agrandada, el total baja de línea
              // en vez de desbordarse.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text('$cant × ${_money.format(c.valorUnitario)}',
                      style: _cifras.copyWith(color: gris)),
                  Text(_money.format(c.subtotal),
                      style: _cifras.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              if (ponderado) ...[
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text('al ${textoCantidad(porcentaje)}%',
                        style: TextStyle(fontSize: 12.5, color: gris)),
                    Text(_money.format(c.subtotalAl(porcentaje)),
                        style: _cifras.copyWith(fontSize: 12.5, color: gris)),
                  ],
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// El valor del kit, fijo al pie de la pestaña Componentes.
class PieTotalKit extends StatelessWidget {
  final num total;
  final num porcentaje;
  const PieTotalKit({super.key, required this.total, required this.porcentaje});

  @override
  Widget build(BuildContext context) {
    final ponderado = porcentaje < 100;
    final actual = total * porcentaje / 100;
    return Semantics(
      container: true,
      label: [
        'Valor del kit a nuevo, ${_money.format(total)}',
        if (ponderado)
          'al ${textoCantidad(porcentaje)} por ciento, ${_money.format(actual)}',
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    const Text('Valor del kit a nuevo'),
                    Text(_money.format(total),
                        style: _cifras.copyWith(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                if (ponderado) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text('Al ${textoCantidad(porcentaje)}% (su condición)'),
                      Text(_money.format(actual),
                          style: _cifras.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Íconos de cada tipo de movimiento: acompañan a la palabra, nunca la
/// reemplazan.
IconData iconoMovComponente(TipoMovComponente? t) => switch (t) {
      TipoMovComponente.alta => Icons.add_box_outlined,
      TipoMovComponente.aumento => Icons.add_circle_outline,
      TipoMovComponente.disminucion => Icons.remove_circle_outline,
      TipoMovComponente.salidaVenta => Icons.sell_outlined,
      TipoMovComponente.salidaGarantia => Icons.handshake_outlined,
      TipoMovComponente.bajaDano => Icons.report_problem_outlined,
      TipoMovComponente.anulacion => Icons.undo,
      null => Icons.help_outline,
    };

/// Hoja para registrar la vida de un componente: se agrega, se retira, se
/// vende, se va en garantía o se daña (Fase 5).
///
/// Las funciones que hablan con la base llegan como parámetros opcionales:
/// por defecto usan el servicio real, y las pruebas les pasan unas simuladas
/// para poder probar la hoja entera, guardado incluido, sin Supabase.
class HojaMovimientoComponente extends StatefulWidget {
  final ActivoComponente componente;
  final Future<List<ActivoTercero>> Function()? cargarTerceros;
  final Future<ActivoTercero> Function(String nombre, String tipo)? crearTercero;
  final Future<void> Function({
    required String componenteId,
    required TipoMovComponente tipo,
    required num cantidad,
    String? terceroId,
    String? observacion,
  })? registrar;

  const HojaMovimientoComponente({
    super.key,
    required this.componente,
    this.cargarTerceros,
    this.crearTercero,
    this.registrar,
  });

  @override
  State<HojaMovimientoComponente> createState() =>
      _HojaMovimientoComponenteState();
}

class _HojaMovimientoComponenteState extends State<HojaMovimientoComponente> {
  /// Sin opción por defecto a propósito: que "Retirar" quede marcado solo
  /// porque era el primero es la forma de registrar lo que no pasó.
  TipoMovComponente? _tipo;
  final _cantidad = TextEditingController();
  final _observacion = TextEditingController();
  List<ActivoTercero> _terceros = [];
  bool _cargandoTerceros = true;
  ActivoTercero? _tercero;
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    _cargarTerceros();
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _cargarTerceros() async {
    setState(() => _cargandoTerceros = true);
    try {
      final t = await (widget.cargarTerceros ?? ActivosService.todosLosTerceros)();
      if (!mounted) return;
      setState(() {
        _terceros = t;
        _cargandoTerceros = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoTerceros = false);
    }
  }

  /// Crear el tercero sin salir de aquí: si el cliente no está en el
  /// catálogo, obligar a ir a otra pantalla y volver a empezar empuja a no
  /// registrar a quién se vendió (lección del error 9.1).
  Future<void> _nuevoTercero() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Nuevo tercero'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Nombre', hintText: 'Ej: TINTEXA'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Crear')),
          ],
        );
      },
    );
    if (nombre == null || nombre.isEmpty) return;
    // A quien se le vende es un cliente; una garantía puede ir a un cliente
    // o a un proveedor, así que queda como "otro" (se corrige en Terceros).
    final tipo = _tipo == TipoMovComponente.salidaVenta ? 'cliente' : 'otro';
    try {
      final nuevo = await (widget.crearTercero ??
          (n, t) => ActivosService.crearTercero(nombre: n, tipo: t))(nombre, tipo);
      if (!mounted) return;
      setState(() {
        _terceros = [..._terceros, nuevo];
        _tercero = nuevo;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
    }
  }

  num? get _cant => num.tryParse(_cantidad.text.trim().replaceAll(',', '.'));

  /// Cuántos quedarían, si la cantidad es un número.
  num? get _quedarian {
    final c = _cant;
    final t = _tipo;
    if (c == null || t == null) return null;
    return widget.componente.cantidad + (t.suma ? c : -c);
  }

  String? get _errorTipo => _tipo == null ? 'Elige qué pasó' : null;

  String? get _errorCantidad {
    final c = _cant;
    if (_cantidad.text.trim().isEmpty) return 'Escribe cuántos';
    if (c == null) return 'No es un número';
    if (c <= 0) return 'Tiene que ser mayor que cero';
    final t = _tipo;
    if (t != null && !t.suma && c > widget.componente.cantidad) {
      return 'Solo hay ${textoCantidad(widget.componente.cantidad)}';
    }
    return null;
  }

  String? get _errorTercero =>
      (_tipo?.pideTercero ?? false) && _tercero == null
          ? 'Elige a quién'
          : null;

  // El motivo es obligatorio (schema_v67): es lo que se lee en el listado
  // de observaciones del equipo. La base también lo exige.
  String? get _errorMotivo => _observacion.text.trim().isEmpty
      ? 'Escribe por qué cambia la cantidad'
      : null;

  bool get _valido =>
      _errorTipo == null &&
      _errorCantidad == null &&
      _errorTercero == null &&
      _errorMotivo == null;

  Future<void> _guardar() async {
    if (!_valido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final registrar = widget.registrar ?? ActivosService.moverComponente;
      await registrar(
        componenteId: widget.componente.id,
        tipo: _tipo!,
        cantidad: _cant!,
        terceroId: _tipo!.pideTercero ? _tercero?.id : null,
        observacion: _observacion.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      // ErrorEquipos ya trae el mensaje listo; la hoja queda abierta.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo registrar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.componente;
    final esquema = Theme.of(context).colorScheme;
    final quedarian = _quedarian;

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
                  child: Text('Registrar movimiento',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${c.nombre} · hay ${textoCantidad(c.cantidad)}',
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('¿Qué pasó? *', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            // Wrap: en 360 px las opciones bajan de línea en vez de apretarse.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in TipoMovComponente.elegibles)
                  ChoiceChip(
                    avatar: Icon(iconoMovComponente(t), size: 18),
                    label: Text(t.accion),
                    selected: _tipo == t,
                    onSelected: (_) => setState(() {
                      _tipo = t;
                      if (!t.pideTercero) _tercero = null;
                    }),
                  ),
              ],
            ),
            if (_tipo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_tipo!.ayuda,
                    style: TextStyle(
                        fontSize: 12.5, color: esquema.onSurfaceVariant)),
              ),
            if (_mostrarErrores && _errorTipo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_errorTipo!,
                      style: TextStyle(fontSize: 12.5, color: esquema.error)),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _cantidad,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Cantidad *',
                border: const OutlineInputBorder(),
                // El error de "no alcanza" se ve al escribir, no al guardar.
                errorText: (_mostrarErrores ||
                        (_errorCantidad?.startsWith('Solo hay') ?? false))
                    ? _errorCantidad
                    : null,
                helperText: (quedarian != null && quedarian >= 0)
                    ? 'Quedarán ${textoCantidad(quedarian)}'
                    : null,
              ),
            ),
            if (_tipo?.pideTercero ?? false) ...[
              const SizedBox(height: 12),
              if (_cargandoTerceros)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SelectorRecargable<ActivoTercero>(
                  // Con buscador siempre: el catálogo de terceros crece.
                  forzarBuscador: true,
                  etiqueta: _tipo == TipoMovComponente.salidaVenta
                      ? '¿A quién se vendió? *'
                      : '¿A quién se entrega en garantía? *',
                  icono: Icons.person_outline,
                  valor: _tercero,
                  opciones: _terceros,
                  textoDe: (t) => t.nombre,
                  onRecargar: _cargarTerceros,
                  onChanged: (v) => setState(() => _tercero = v),
                  onAgregar: _nuevoTercero,
                  tooltipAgregar: 'Crear un tercero nuevo',
                  textoVacio: 'No hay terceros. Crea uno con el botón +.',
                  error: _mostrarErrores && _errorTercero != null,
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _observacion,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_mostrarErrores) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Motivo *',
                hintText: 'Ej: se rompieron al lavarlas en la planta',
                // Se lee en las observaciones del equipo, con la fecha,
                // quién y la cantidad: por eso se pide aquí.
                helperText: 'Queda en las observaciones del equipo',
                errorText: _mostrarErrores ? _errorMotivo : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// La composición de un kit MIENTRAS se crea (formulario de alta, Fase 4).
/// Todavía no está en la base: se puede cambiar, quitar y agregar.
///
/// Si viene de la plantilla (el kit más reciente de la misma referencia),
/// lo dice y de cuál. Es una sugerencia: el kit nuevo es dueño de lo suyo, no
/// queda amarrado al anterior.
class ComposicionBorrador extends StatelessWidget {
  final List<ComponentePlantilla> componentes;
  /// El serial del kit del que se copió; null si es el primero.
  final String? desdeSerial;
  final num porcentaje;
  final VoidCallback onAgregar;
  final void Function(int indice) onEditar;
  final void Function(int indice) onQuitar;
  /// Un problema que el usuario tiene que resolver antes de guardar.
  final String? error;

  const ComposicionBorrador({
    super.key,
    required this.componentes,
    required this.desdeSerial,
    required this.porcentaje,
    required this.onAgregar,
    required this.onEditar,
    required this.onQuitar,
    this.error,
  });

  num get total => componentes.fold<num>(0, (s, c) => s + c.subtotal);

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final gris = esquema.onSurfaceVariant;
    final ponderado = porcentaje < 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Componentes del kit',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: onAgregar,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: esquema.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                desdeSerial == null ? Icons.info_outline : Icons.content_copy,
                size: 18,
                color: esquema.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              // Expanded: sin esto el texto desborda en 360 px.
              Expanded(
                child: Text(
                  desdeSerial == null
                      ? 'Es el primer kit de esta referencia: agrégale sus '
                          'componentes. Los siguientes kits llegarán con esta '
                          'composición ya escrita.'
                      : 'Composición tomada del kit $desdeSerial. Puedes '
                          'cambiar, quitar o agregar antes de guardar: este kit '
                          'queda dueño de lo suyo, sin amarrarse al anterior.',
                  style: TextStyle(
                      fontSize: 12.5, color: esquema.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < componentes.length; i++)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      // Una frase para el lector, no cifras con "×".
                      label: '${componentes[i].nombre}. '
                          '${textoCantidad(componentes[i].cantidad)} a '
                          '${_money.format(componentes[i].valorUnitario)} cada '
                          'una. Subtotal ${_money.format(componentes[i].subtotal)}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(componentes[i].nombre,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${textoCantidad(componentes[i].cantidad)} × '
                              '${_money.format(componentes[i].valorUnitario)} = '
                              '${_money.format(componentes[i].subtotal)}',
                              style: _cifras.copyWith(color: gris),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Cada botón dice de QUÉ componente es: con diez líneas, el
                  // lector de pantalla no puede anunciar diez "Quitar" iguales.
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar ${componentes[i].nombre}',
                    onPressed: () => onEditar(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Quitar ${componentes[i].nombre}',
                    onPressed: () => onQuitar(i),
                  ),
                ],
              ),
            ),
          ),
        if (componentes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(
            container: true,
            label: [
              'Valor del kit a nuevo, ${_money.format(total)}',
              if (ponderado)
                'al ${textoCantidad(porcentaje)} por ciento, '
                    '${_money.format(total * porcentaje / 100)}',
            ].join('. '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    const Text('Valor del kit a nuevo'),
                    Text(_money.format(total),
                        style: _cifras.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (ponderado)
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text('Al ${textoCantidad(porcentaje)}%',
                          style: TextStyle(color: gris)),
                      Text(_money.format(total * porcentaje / 100),
                          style: _cifras.copyWith(color: gris)),
                    ],
                  ),
              ],
            ),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            // liveRegion: el lector lo anuncia en cuanto aparece.
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: esquema.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(error!, style: TextStyle(color: esquema.error)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Hoja para agregar un componente a un kit.
///
/// El valor unitario va en pesos ENTEROS y solo acepta dígitos: si alguien
/// escribe "45.000" como se escribe en Colombia, un campo decimal lo leería
/// como 45. Debajo de cada número se muestra cómo quedó entendido.
class HojaComponente extends StatefulWidget {
  /// Con activoId, GUARDA en la base al tocar el botón (pestaña
  /// Componentes). Sin él es un BORRADOR (ver [HojaComponente.borrador]).
  final String? activoId;
  final int orden;
  /// Para editar una línea del borrador: llega con sus datos escritos.
  final ComponentePlantilla? inicial;
  /// Los nombres que ya tiene el kit (o la lista del borrador). Un nombre
  /// repetido se avisa AL ESCRIBIR, no cuando la base lo rechaza al guardar.
  final List<String> nombresExistentes;

  const HojaComponente({
    super.key,
    required String this.activoId,
    required this.orden,
    this.nombresExistentes = const [],
  }) : inicial = null;

  /// Modo borrador, para el alta de un kit: el equipo todavía no existe, así
  /// que la hoja NO toca la base — devuelve lo escrito como
  /// [ComponentePlantilla] con `Navigator.pop`.
  const HojaComponente.borrador({
    super.key,
    this.inicial,
    this.orden = 0,
    this.nombresExistentes = const [],
  }) : activoId = null;

  bool get esBorrador => activoId == null;

  @override
  State<HojaComponente> createState() => _HojaComponenteState();
}

class _HojaComponenteState extends State<HojaComponente> {
  late final _nombre = TextEditingController(text: widget.inicial?.nombre ?? '');
  late final _cantidad = TextEditingController(
      text: widget.inicial == null ? '' : textoCantidad(widget.inicial!.cantidad));
  // Pesos enteros: el campo solo acepta dígitos.
  late final _valor = TextEditingController(
      text: widget.inicial == null
          ? ''
          : widget.inicial!.valorUnitario.round().toString());
  bool _guardando = false;
  bool _mostrarErrores = false;

  /// El nombre ya está en el kit. Al editar una línea, su propio nombre no
  /// cuenta como repetido.
  bool get _repetido {
    final clave = claveComponente(_nombre.text);
    if (clave.isEmpty) return false;
    final propio = widget.inicial == null
        ? null
        : claveComponente(widget.inicial!.nombre);
    return widget.nombresExistentes
        .map(claveComponente)
        .any((n) => n == clave && n != propio);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _valor.dispose();
    super.dispose();
  }

  /// Acepta coma o punto como separador DECIMAL ("2,5" = 2.5): una cantidad
  /// puede ser de metros de tela. Lo que se entendió se muestra en vivo.
  num? get _cant => num.tryParse(_cantidad.text.trim().replaceAll(',', '.'));
  int? get _vr => int.tryParse(_valor.text.trim());

  String? get _errorNombre {
    if (_nombre.text.trim().isEmpty) return 'Escribe el nombre del componente';
    if (_repetido) return 'Este kit ya tiene un componente con ese nombre';
    return null;
  }
  String? get _errorCantidad {
    final c = _cant;
    if (_cantidad.text.trim().isEmpty) return 'Escribe cuántos hay';
    if (c == null) return 'No es un número';
    if (c <= 0) return 'Tiene que ser mayor que cero';
    return null;
  }

  String? get _errorValor =>
      _valor.text.trim().isEmpty ? 'Escribe el valor de cada uno' : null;

  bool get _valido =>
      _errorNombre == null && _errorCantidad == null && _errorValor == null;

  Future<void> _guardar() async {
    if (!_valido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    if (widget.esBorrador) {
      // Nada de red: se devuelve lo escrito al formulario de alta.
      Navigator.pop(
        context,
        ComponentePlantilla(
          nombre: _nombre.text.trim(),
          cantidad: _cant!,
          valorUnitario: _vr!,
          orden: widget.inicial?.orden ?? widget.orden,
        ),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await ActivosService.agregarComponente(
        activoId: widget.activoId!,
        nombre: _nombre.text,
        cantidad: _cant!,
        valorUnitario: _vr!,
        orden: widget.orden,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      // ErrorEquipos ya trae el mensaje listo ("Este kit ya tiene un
      // componente con ese nombre."); la hoja queda abierta para corregir.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo agregar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).colorScheme.onSurfaceVariant;
    final cant = _cant;
    final vr = _vr;
    final subtotal = (cant != null && vr != null) ? cant * vr : null;

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
                          ? 'Agregar componente'
                          : 'Editar componente',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Tela filtros de los medios',
                border: const OutlineInputBorder(),
                // errorText y no solo un color: el lector de pantalla lo
                // anuncia. El repetido se avisa al escribir, sin esperar.
                errorText:
                    (_mostrarErrores || _repetido) ? _errorNombre : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cantidad,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Cantidad *',
                hintText: 'Ej: 24',
                border: const OutlineInputBorder(),
                errorText: _mostrarErrores ? _errorCantidad : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valor,
              keyboardType: TextInputType.number,
              // Solo dígitos: pesos enteros, sin puntos ni comas que se
              // puedan confundir con decimales.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _guardar(),
              decoration: InputDecoration(
                labelText: 'Valor unitario *',
                hintText: 'Ej: 45000',
                prefixText: '\$ ',
                border: const OutlineInputBorder(),
                errorText: _mostrarErrores ? _errorValor : null,
                // Lo que se entendió, en el formato de toda la app.
                helperText: vr == null
                    ? 'En pesos, sin puntos'
                    : '= ${_money.format(vr)} cada uno',
              ),
            ),
            if (subtotal != null) ...[
              const SizedBox(height: 14),
              // liveRegion: el lector anuncia el subtotal cuando cambia.
              Semantics(
                liveRegion: true,
                child: Text(
                  'Subtotal: ${textoCantidad(cant!)} × ${_money.format(vr)} = '
                  '${_money.format(subtotal)}',
                  style: _cifras.copyWith(color: gris, fontSize: 13.5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.inicial == null ? 'Agregar' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una línea del historial de un componente.
class LineaMovimientoComponente extends StatelessWidget {
  final MovimientoComponente movimiento;
  final bool anulado;
  final VoidCallback? onAnular;
  const LineaMovimientoComponente({
    super.key,
    required this.movimiento,
    required this.anulado,
    required this.onAnular,
  });

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final esquema = Theme.of(context).colorScheme;
    final gris = esquema.onSurfaceVariant;
    final detalle = [
      _cuando(m.fecha),
      if (m.usuarioEmail != null) m.usuarioEmail!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                // La línea completa en una frase, EN PALABRAS: "Venta,
                // salieron 1, a TINTEXA", y no "−1".
                label: [
                  m.descripcionAccesible,
                  detalle,
                  if (anulado) 'anulado',
                  if (m.observacion != null && m.observacion!.isNotEmpty)
                    'observación: ${m.observacion}',
                ].join('. '),
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: Icon(iconoMovComponente(m.tipo),
                          size: 20, color: gris),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(m.etiqueta,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(m.textoCantidad,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ])),
                              // ANULADO con texto, no solo tachado o en rojo.
                              if (anulado)
                                Text('ANULADO',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: esquema.error)),
                            ],
                          ),
                          if (m.terceroNombre != null)
                            Text('A ${m.terceroNombre}',
                                style: const TextStyle(fontSize: 13)),
                          Text(detalle,
                              style: TextStyle(fontSize: 12, color: gris)),
                          if (m.observacion != null &&
                              m.observacion!.isNotEmpty)
                            Text(m.observacion!,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                    color: gris)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (onAnular != null)
              IconButton(
                icon: const Icon(Icons.undo),
                // Dice QUÉ se anula: con varios movimientos, "Anular" a secas
                // no le dice nada a quien usa lector de pantalla.
                tooltip: 'Anular ${m.etiqueta.toLowerCase()} del '
                    '${_cuando(m.fecha)}',
                onPressed: onAnular,
              ),
          ],
        ),
      ),
    );
  }
}

/// Confirmar una anulación pidiendo el MOTIVO (schema_v67): devuelve el
/// motivo escrito, o null si se cancela. La anulación sale en las
/// observaciones del equipo y ahí tiene que decir por qué.
class DialogoAnularComponente extends StatefulWidget {
  /// Qué se anula, en palabras ("Daño, salieron 2, el 10/09/2026 14:05.").
  final String descripcion;

  const DialogoAnularComponente({super.key, required this.descripcion});

  @override
  State<DialogoAnularComponente> createState() =>
      _DialogoAnularComponenteState();
}

class _DialogoAnularComponenteState extends State<DialogoAnularComponente> {
  final _motivo = TextEditingController();
  bool _mostrarError = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final m = _motivo.text.trim();
    if (m.isEmpty) {
      setState(() => _mostrarError = true);
      return;
    }
    Navigator.pop(context, m);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Anular este movimiento?'),
      // Con scroll: en 360 px con letra grande el texto y el campo no caben.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.descripcion}\n\n'
              'Se registra un movimiento contrario que lo deshace. Nada se '
              'borra: los dos quedan en el historial.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motivo,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_mostrarError) setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Motivo de la anulación *',
                hintText: 'Ej: se registró en el kit equivocado',
                errorText: _mostrarError && _motivo.text.trim().isEmpty
                    ? 'Escribe por qué se anula'
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No')),
        FilledButton(onPressed: _confirmar, child: const Text('Sí, anular')),
      ],
    );
  }
}

/// Lo que se ve de la novedad de un componente en el listado de
/// OBSERVACIONES del equipo (schema_v67): qué componente, qué pasó y
/// cuántos, cuántos quedaron y el motivo. La fecha y el usuario van en la
/// línea gris de abajo, igual que en las demás observaciones.
class LineaObservacionComponente extends StatelessWidget {
  final ActivoObservacion observacion;

  const LineaObservacionComponente({super.key, required this.observacion});

  @override
  Widget build(BuildContext context) {
    final o = observacion;
    final esquema = Theme.of(context).colorScheme;
    // Una sola lectura, en orden, para el lector de pantalla: sin esto lee
    // cuatro textos sueltos.
    return Semantics(
      container: true,
      label: o.descripcionAccesible,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o.compNombre ?? 'Componente',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(o.movimientoComponente ?? '',
              style: TextStyle(fontSize: 13.5, color: esquema.onSurface)),
          // Dicho con palabras, no solo tachado: tachar no se oye.
          if (o.compAnulado)
            Text('Anulado después',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: esquema.error)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            const TextSpan(
                text: 'Motivo: ',
                style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: o.texto),
          ])),
        ],
      ),
    );
  }
}
