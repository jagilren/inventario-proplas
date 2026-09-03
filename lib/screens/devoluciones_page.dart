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
  _FilaDev(this.textoOriginal, this.cantidad, {this.match, this.score = 0});
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
  // `_cc` alimenta `centro_costo_id`: en una devolución simple sigue
  // siendo "quien devuelve" (como siempre), y aparece en POSITIVO. Si se
  // activa la reasignación, pasa a ser el DESTINO (a quién se le carga),
  // y `_ccOrigen` (centro_costo_origen_id, schema_v37) es entonces quien
  // devuelve de verdad — aparece en NEGATIVO en "Neto por centro de costo".
  CentroCosto? _cc;
  bool _reasignar = false;
  CentroCosto? _ccOrigen;
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
  /// Edita la cantidad de una fila antes de cargar.
  Future<void> _editarCantidad(_FilaDev fila) async {
    final ctrl = TextEditingController(text: fila.cantidad.toString());
    final cant = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fila.match?.nombre ?? fila.textoOriginal),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Cantidad', border: OutlineInputBorder()),
          onSubmitted: (_) {
            final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
            if (c != null && c > 0) Navigator.pop(ctx, c);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
              if (c == null || c <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Cantidad inválida')));
                return;
              }
              Navigator.pop(ctx, c);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (cant != null && mounted) setState(() => fila.cantidad = cant);
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
    final validas = _filas.where((f) => f.match != null && f.cantidad > 0
        && !(f.match!.serializado)).toList();
    if (validas.isEmpty) {
      return _msg('No hay filas listas para cargar (revisa emparejamientos y cantidades)');
    }
    if (_reasignar) {
      if (_cc == null) return _msg('Elige el centro de costo destino');
      if (_ccOrigen == null) return _msg('Elige el centro de costo origen');
      if (_cc!.id == _ccOrigen!.id) {
        return _msg('Origen y destino no pueden ser el mismo centro');
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Text('Se registrarán ${validas.length} entradas de devolución '
            'en "${_bodega!.nombre}", valorizadas al costo promedio actual.'
            '${_reasignar ? '\n\nSe reasignan de "${_ccOrigen!.etiqueta}" '
                'a "${_cc!.etiqueta}".' : ''}'),
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
    int cargados = 0, aCostoCero = 0, errores = 0;
    for (final f in validas) {
      try {
        await InventarioService.registrarMovimiento(
          tipo: 'entrada',
          elementoId: f.match!.id,
          bodegaId: _bodega!.id,
          cantidad: f.cantidad,
          costoUnitario: f.match!.costoPromedio,
          // `_cc`: a quién se le abona (en devolución simple, quien
          // devuelve; en reasignación, el destino). `_ccOrigen`: solo con
          // reasignación, quien devuelve de verdad (aparece en negativo).
          centroCostoId: _cc?.id,
          centroCostoOrigenId: _reasignar ? _ccOrigen?.id : null,
          referencia: 'DEVOLUCION',
        );
        cargados++;
        if (f.match!.costoPromedio == 0) aCostoCero++;
      } catch (_) {
        errores++;
      }
    }
    final sinEmparejar = _filas.where((f) => f.match == null).length;
    final serializados = _filas.where((f) => f.match?.serializado ?? false).length;
    if (!mounted) return;
    setState(() { _cargando = false; _filas = []; _archivo = null; });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carga terminada'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('✓ Cargados: $cargados'),
            if (aCostoCero > 0) Text('• A costo 0 (revisa Alertas): $aCostoCero'),
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
      f.match != null && f.cantidad > 0 && !(f.match!.serializado)).length;

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
              etiqueta: _reasignar
                  ? 'Centro de costo destino (a quién se le carga)'
                  : 'Centro de costo de origen (de dónde vuelve)',
              icono: Icons.account_tree,
              valor: _cc,
              opciones: _centros,
              textoDe: (c) => c.etiqueta,
              recargando: _recargandoCentros,
              onRecargar: _recargarCentros,
              onChanged: (v) => setState(() => _cc = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            child: CheckboxListTile(
              value: _reasignar,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                  'Es un movimiento de devolución desde otro C.Costo',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                  'Ej.: Tintexa devuelve, pero el material queda cargado '
                  'a otro centro.',
                  style: TextStyle(fontSize: 11.5)),
              onChanged: (v) => setState(() {
                _reasignar = v ?? false;
                if (!_reasignar) _ccOrigen = null;
              }),
            ),
          ),
          if (_reasignar)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: SelectorRecargable<CentroCosto>(
                forzarBuscador: true,
                icono: Icons.undo,
                etiqueta: 'Centro de costo origen (quien devuelve)',
                valor: _ccOrigen,
                opciones: _centros,
                textoDe: (c) => c.etiqueta,
                recargando: _recargandoCentros,
                onRecargar: _recargarCentros,
                onChanged: (v) => setState(() => _ccOrigen = v),
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
                child: Text('${_filas.length} filas · $_listas listas para cargar',
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
    final Color color = m == null
        ? Colors.red
        : (f.match!.serializado ? Colors.purple
            : (f.score >= 0.82 ? Colors.green : Colors.orange));
    return ListTile(
      leading: InkWell(
        onTap: () => _editarCantidad(f),
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
      title: Text(f.textoOriginal),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(children: [
            Icon(m == null ? Icons.help_outline
                : (f.match!.serializado ? Icons.tag
                    : (f.score >= 0.82 ? Icons.check_circle : Icons.rule)),
                size: 15, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                m == null
                    ? 'Sin emparejar — toca para elegir'
                    : (m.serializado
                        ? '${m.nombre} (serializado: no se carga por cantidad)'
                        : '${m.nombre} · ${_money.format(m.costoPromedio)}'
                            '${m.costoPromedio == 0 ? ' ⚠ costo 0' : ''}'),
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
