import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../data.dart';
import '../util/picker.dart';
import '../util/import_archivo.dart';
import '../util/plantilla_import.dart';
import '../widgets/selector_recargable.dart';
import '../widgets/confirmar_descarte.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _qty = NumberFormat.decimalPattern('es_CO');

/// Una fila leída del archivo de devoluciones.
class _FilaDev {
  final String textoOriginal; // lo que traía la columna ELEMENTO del archivo
  num cantidad;               // editable antes de cargar
  Elemento? match; // EMPAREJAMIENTO con la BD
  double score; // qué tan seguro es el emparejamiento (0..1)
  // Costo unitario asignado a mano, solo cuando el costo promedio del
  // elemento es $0 (típicamente porque su existencia llegó a cero). Sin
  // esto la devolución se registraba igual, valorizada en $0 — le restaba
  // $0 de consumo al centro de costo aunque físicamente sí volvieron
  // unidades. `null` = usar el costo promedio del elemento, sin tocar.
  num? costoManual;
  _FilaDev(this.textoOriginal, this.cantidad, {this.match, this.score = 0});

  num get costoEfectivo => costoManual ?? (match?.costoPromedio ?? 0);
}

/// Carga masiva de DEVOLUCIONES: sube un Excel/CSV con columnas
/// ELEMENTO y CANTIDAD; la app empareja cada fila con un item de la BD
/// (coincidencia aproximada) y registra las entradas a la bodega elegida,
/// valorizadas al costo promedio actual de cada elemento.
class DevolucionesPage extends StatefulWidget {
  const DevolucionesPage({super.key});
  @override
  State<DevolucionesPage> createState() => _DevolucionesPageState();
}

class _DevolucionesPageState extends State<DevolucionesPage> {
  List<Bodega> _bodegas = [];
  Bodega? _bodega;
  List<CentroCosto> _centros = [];
  // Centro de costo ORIGEN: de dónde vuelve la mercancía. Obligatorio —
  // esta pantalla siempre carga devoluciones.
  CentroCosto? _cc;
  // Centro de costo DESTINO: a quién queda atribuida la mercancía.
  // Obligatorio siempre en una entrada; informativo, no afecta ningún
  // informe. Solo centros internos de RPCI (`esInterno`, administrado en
  // la maestra de Centros de Costo).
  CentroCosto? _ccDestino;
  List<CentroCosto> get _centrosDestinoEntrada =>
      _centros.where((c) => c.esInterno).toList();
  // Centro de costo ORIGEN: nunca interno de RPCI (de quién vuelve de
  // verdad, siempre un cliente externo).
  List<CentroCosto> get _centrosExternos =>
      _centros.where((c) => !c.esInterno).toList();
  /// Emparejador compartido con Salida y Compra masiva. Antes esta pantalla
  /// tenía su propia copia del algoritmo, y por eso se quedó sin el arreglo
  /// de las medidas (1/2" vs 2-1/2") cuando se corrigió en el módulo común.
  EmparejadorCatalogo? _emparejador;
  List<_FilaDev> _filas = [];
  bool _leyendo = false;
  bool _cargando = false;
  String? _archivo;
  bool _recargandoBodegas = false;
  bool _recargandoCentros = false;

  /// Vuelven a pedir el catálogo al servidor: sirve cuando alguien crea una
  /// bodega o un centro de costo mientras esta pantalla ya estaba abierta.
  Future<void> _recargarBodegas() async {
    setState(() => _recargandoBodegas = true);
    final nueva = await recargarCatalogo(
        context, InventarioService.bodegas, _bodegas.length);
    if (!mounted) return;
    setState(() {
      if (nueva != null) _bodegas = nueva;
      _recargandoBodegas = false;
    });
  }

  Future<void> _recargarCentros() async {
    setState(() => _recargandoCentros = true);
    final nueva = await recargarCatalogo(
        context, InventarioService.centrosCosto, _centros.length);
    if (!mounted) return;
    setState(() {
      if (nueva != null) _centros = nueva;
      _recargandoCentros = false;
    });
  }

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) {
        setState(() { _bodegas = b; if (b.length == 1) _bodega = b.first; });
      }
    });
    InventarioService.centrosCosto().then((c) {
      if (mounted) setState(() => _centros = c);
    });
    InventarioService.todosElementos().then((e) {
      if (mounted) setState(() => _emparejador = EmparejadorCatalogo(e));
    });
  }

  // ---- Lectura del archivo ----
  Future<void> _elegirArchivo() async {
    String nombre;
    Uint8List bytes;
    try {
      if (kIsWeb) {
        // Web: input HTML nativo (el diálogo se abre de inmediato).
        final r = await abrirArchivoWeb('.xlsx,.csv');
        if (r == null) return; // canceló
        nombre = r.name;
        bytes = r.bytes;
      } else {
        // Móvil/escritorio: file_picker.
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'csv'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        if (f.bytes == null) { _msg('No se pudo leer el archivo'); return; }
        nombre = f.name;
        bytes = f.bytes!;
      }
    } catch (e) {
      _msg('No se pudo abrir el archivo: $e');
      return;
    }

    setState(() { _leyendo = true; _archivo = nombre; });
    try {
      final crudas = leerArchivoImport(bytes, nombre);
      final filas = _emparejar(crudas);
      if (mounted) setState(() => _filas = filas);
    } on FormatException catch (e) {
      setState(() { _filas = []; _archivo = null; });
      _archivoInvalido(e.message);
    } catch (e) {
      setState(() { _filas = []; _archivo = null; });
      _archivoInvalido('No pude leer el archivo. Verifica que sea un Excel '
          '(.xlsx) o CSV válido.\n\nDetalle: $e');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  /// Muestra un aviso claro cuando el archivo no sirve, recordando el formato.
  Future<void> _archivoInvalido(String motivo) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
        title: const Text('Archivo inválido'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(motivo),
            const SizedBox(height: 12),
            const Text('Formato esperado:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('• Dos columnas: ELEMENTO y CANTIDAD (con encabezado).\n'
                '• Si trae columnas de más, no hay problema: se ignoran.\n'
                '• Excel (.xlsx) o CSV.'),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }


  List<_FilaDev> _emparejar(List<List<dynamic>> crudas) {
    final out = <_FilaDev>[];
    final emp = _emparejador;
    if (emp == null) return out; // el catálogo aún no ha llegado
    for (final r in crudas) {
      final texto = r[0].toString().trim();
      if (texto.isEmpty) continue;
      final cant = parseCantidad(r.length > 1 ? r[1].toString() : '');
      final (match, score) = emp.mejor(texto);
      out.add(_FilaDev(texto, cant, match: match, score: score));
    }
    return out;
  }

  // ---- Corrección manual del emparejamiento ----
  /// Edita la cantidad y, si hace falta, el costo unitario de una fila
  /// antes de cargar. El campo de costo solo se muestra cuando el costo
  /// promedio del elemento es $0 — en el caso normal la devolución se
  /// valoriza sola, sin que el usuario tenga que saber ni tocar el costo.
  Future<void> _editarLinea(_FilaDev fila) async {
    final cantCtrl = TextEditingController(text: fila.cantidad.toString());
    final sinCosto = (fila.match?.costoPromedio ?? 0) == 0;
    final costoCtrl = TextEditingController(
        text: fila.costoManual == null ? '' : fila.costoManual.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fila.match?.nombre ?? fila.textoOriginal),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: cantCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Cantidad', border: OutlineInputBorder()),
          ),
          if (sinCosto) ...[
            const SizedBox(height: 10),
            TextField(
              controller: costoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo unitario',
                helperText: 'Este elemento está en \$0 · sin esto la '
                    'devolución no resta consumo del centro de costo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = num.tryParse(cantCtrl.text.replaceAll(',', '.'));
              if (c == null || c <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Cantidad inválida')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        fila.cantidad = num.tryParse(cantCtrl.text.replaceAll(',', '.')) ?? fila.cantidad;
        if (sinCosto) {
          final c = num.tryParse(costoCtrl.text.replaceAll(',', '.'));
          fila.costoManual = (c != null && c > 0) ? c : null;
        }
      });
    }
  }

  Future<void> _corregir(_FilaDev fila) async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) setState(() { fila.match = sel; fila.score = 1; });
  }

  // ---- Cargar (registrar las entradas) ----
  Future<void> _cargar() async {
    if (_bodega == null) return _msg('Elige la bodega física donde entran');
    if (_cc == null) return _msg('Elige el centro de costo origen');
    if (_ccDestino == null) return _msg('Elige el centro de costo destino');
    final validas = _filas.where((f) => f.match != null && f.cantidad > 0
        && f.costoEfectivo > 0 && !(f.match!.serializado)).toList();
    if (validas.isEmpty) {
      return _msg('No hay filas listas para cargar (revisa emparejamientos, cantidades y costos)');
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se registrarán ${validas.length} entradas de devolución '
                'en "${_bodega!.nombre}", valorizadas al costo promedio actual.'),
            if (_sinCosto > 0) ...[
              const SizedBox(height: 8),
              Text('Se omiten $_sinCosto línea(s) en \$0: asígnales un costo '
                  'para poder cargarlas.',
                  style: const TextStyle(color: Colors.red)),
            ],
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cargar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _cargando = true);
    int cargados = 0, errores = 0;
    for (final f in validas) {
      try {
        await InventarioService.registrarMovimiento(
          tipo: 'entrada',
          elementoId: f.match!.id,
          bodegaId: _bodega!.id,
          cantidad: f.cantidad,
          costoUnitario: f.costoEfectivo,
          centroCostoId: _cc?.id,
          centroCostoDestinoId: _ccDestino?.id,
          referencia: 'DEVOLUCION',
        );
        cargados++;
      } catch (_) {
        errores++;
      }
    }
    final sinEmparejar = _filas.where((f) => f.match == null).length;
    final serializados = _filas.where((f) => f.match?.serializado ?? false).length;
    final omitidosPorCosto = _sinCosto;
    if (!mounted) return;
    setState(() { _cargando = false; _filas = []; _archivo = null; });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carga terminada'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('✓ Cargados: $cargados'),
            if (omitidosPorCosto > 0)
              Text('• Sin costo (omitidos, no cargados): $omitidosPorCosto'),
            if (sinEmparejar > 0) Text('• Sin emparejar (omitidos): $sinEmparejar'),
            if (serializados > 0) Text('• Serializados (omitidos): $serializados'),
            if (errores > 0) Text('• Con error: $errores'),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Listo')),
        ],
      ),
    );
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  int get _listas => _filas.where((f) =>
      f.match != null && f.cantidad > 0 && f.costoEfectivo > 0
      && !(f.match!.serializado)).length;

  /// Emparejadas, con cantidad y sin serializar, pero SIN costo (costo
  /// promedio del elemento en $0 y sin costo manual asignado todavía): no
  /// se pueden cargar hasta que alguien les asigne un costo a mano — de lo
  /// contrario la devolución entraría valorizada en $0 y no restaría nada
  /// del consumo del centro de costo en los informes.
  int get _sinCosto => _filas.where((f) =>
      f.match != null && f.cantidad > 0 && !(f.match!.serializado)
      && f.costoEfectivo <= 0).length;

  @override
  Widget build(BuildContext context) {
    return ConfirmarDescarte(
      hayTrabajoSinGuardar: _filas.isNotEmpty && !_cargando,
      queSePierde: '${_filas.length} línea(s) del archivo',
      child: _contenido(),
    );
  }

  Widget _contenido() {
    return Scaffold(
      appBar: AppBar(title: const Text('Devoluciones · carga masiva')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SelectorRecargable<Bodega>(
              etiqueta: 'Bodega física donde entran las devoluciones',
              icono: Icons.warehouse,
              valor: _bodega,
              opciones: _bodegas,
              textoDe: (b) => b.nombre,
              recargando: _recargandoBodegas,
              onRecargar: _recargarBodegas,
              onChanged: (v) => setState(() => _bodega = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SelectorRecargable<CentroCosto>(
              // Los centros de costo SIEMPRE con buscador.
              forzarBuscador: true,
              etiqueta: 'Centro de Costo Origen',
              icono: Icons.account_tree,
              valor: _cc,
              opciones: _centrosExternos,
              textoDe: (c) => c.etiqueta,
              recargando: _recargandoCentros,
              onRecargar: _recargarCentros,
              onChanged: (v) => setState(() => _cc = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SelectorRecargable<CentroCosto>(
              // Pocas opciones (solo centros internos de RPCI): sin
              // buscador.
              etiqueta: 'Centro de Costo Destino',
              icono: Icons.arrow_forward,
              valor: _ccDestino,
              opciones: _centrosDestinoEntrada,
              textoDe: (c) => c.etiqueta,
              recargando: _recargandoCentros,
              onRecargar: _recargarCentros,
              onChanged: (v) => setState(() => _ccDestino = v),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Estos dos centros aplican a TODO el archivo que subas abajo: '
              'el Excel/CSV solo trae elemento y cantidad, no lleva centro '
              'de costo por fila.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _leyendo ? null : _elegirArchivo,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_archivo == null
                      ? 'Elegir Excel/CSV'
                      : _archivo!, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 4),
              // Plantilla de ejemplo y ayuda del formato, a la mano ANTES de
              // equivocarse (antes esto solo salía si el archivo fallaba).
              TextButton.icon(
                onPressed: () => descargarPlantillaImport(context,
                    nombreArchivo: 'plantilla_devoluciones'),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Plantilla'),
              ),
              IconButton(
                onPressed: () => mostrarAyudaFormato(context),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Cómo armar el archivo',
                // Área táctil cómoda en móvil sin robarle ancho a la fila.
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ]),
          ),
          if (_leyendo) const LinearProgressIndicator(),
          if (_filas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${_filas.length} filas · $_listas listas para cargar'
                    '${_sinCosto > 0 ? ' · $_sinCosto sin costo' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          Expanded(
            child: _filas.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sube un archivo con dos columnas: ELEMENTO y CANTIDAD.\n\n'
                        'La app emparejará cada fila con un item de la base '
                        '(coincidencia aproximada). Las que no encuentre las '
                        'dejará en blanco para que las elijas con el buscador.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _filas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _filaWidget(_filas[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _filas.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: (_cargando || _listas == 0) ? null : _cargar,
                    icon: _cargando
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_done),
                    label: Text('CARGAR ($_listas)'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _filaWidget(_FilaDev f) {
    final m = f.match;
    final sinCosto = m != null && !m.serializado && f.costoEfectivo <= 0;
    final Color color = m == null
        ? Colors.red
        : (f.match!.serializado ? Colors.purple
            : (sinCosto ? Colors.red
                : (f.score >= 0.82 ? Colors.green : Colors.orange)));
    return ListTile(
      leading: InkWell(
        onTap: () => _editarLinea(f),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_qty.format(f.cantidad),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                      color: f.cantidad > 0 ? const Color(0xFF1565C0) : Colors.red)),
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit, size: 10, color: Colors.grey),
                SizedBox(width: 2),
                Text('cant.', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ],
          ),
        ),
      ),
      title: Text(f.match?.nombre ?? f.textoOriginal),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(children: [
            Icon(m == null ? Icons.help_outline
                : (f.match!.serializado ? Icons.tag
                    : (sinCosto ? Icons.money_off
                        : (f.score >= 0.82 ? Icons.check_circle : Icons.rule))),
                size: 15, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                m == null
                    ? 'Sin emparejar — toca para elegir'
                    : (m.serializado
                        ? '${m.nombre} (serializado: no se carga por cantidad)'
                        : sinCosto
                            ? '${m.nombre} · \$0 — toca la cantidad para asignar un costo'
                            : '${m.nombre} · ${_money.format(f.costoEfectivo)}'
                                '${f.costoManual != null ? ' (manual)' : ''}'),
                style: TextStyle(color: color,
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ]),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(m == null ? Icons.search : Icons.edit, size: 20),
            tooltip: 'Elegir emparejamiento',
            onPressed: () => _corregir(f),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            tooltip: 'Quitar de la carga',
            onPressed: () => setState(() => _filas.remove(f)),
          ),
        ],
      ),
      onTap: () => _corregir(f),
    );
  }
}

/// Buscador de elementos (para corregir el emparejamiento manualmente).
class _BuscadorElemento extends StatefulWidget {
  const _BuscadorElemento();
  @override
  State<_BuscadorElemento> createState() => _BuscadorElementoState();
}

class _BuscadorElementoState extends State<_BuscadorElemento> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    final r = await InventarioService.buscar(q);
    if (mounted) setState(() => _items = r);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl, autofocus: true, onChanged: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar el elemento correcto…',
                  prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text('Existencia: ${_qty.format(e.existencia)} '
                      '${e.unidad} · ${_money.format(e.costoPromedio)}'),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
