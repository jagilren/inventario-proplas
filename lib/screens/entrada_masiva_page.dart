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

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _qty = NumberFormat.decimalPattern('es_CO');

/// Una línea leída del archivo de compra.
class _FilaComp {
  final String textoOriginal;
  num cantidad;
  num costo; // UNITARIO y sin IVA
  Elemento? match;
  double score;
  _FilaComp(this.textoOriginal, this.cantidad, this.costo,
      {this.match, this.score = 0});

  num get total => cantidad * costo;
}

/// Carga masiva de ENTRADAS por COMPRA a proveedor: sube un Excel/CSV con
/// ELEMENTO, CANTIDAD y COSTO UNITARIO.
///
/// Se diferencia de las Devoluciones en lo que más pesa: una devolución
/// entra al costo promedio que el artículo ya tenía, mientras que una compra
/// entra al precio pagado — y ese precio es el que RECALCULA el promedio
/// ponderado. Por eso aquí el costo es obligatorio y no se hereda de nada.
class EntradaMasivaPage extends StatefulWidget {
  const EntradaMasivaPage({super.key});
  @override
  State<EntradaMasivaPage> createState() => _EntradaMasivaPageState();
}

class _EntradaMasivaPageState extends State<EntradaMasivaPage> {
  List<Bodega> _bodegas = [];
  Bodega? _bodega;
  EmparejadorCatalogo? _emparejador;
  List<_FilaComp> _filas = [];
  final _factura = TextEditingController();
  final _proveedor = TextEditingController();
  bool _leyendo = false;
  bool _cargando = false;
  bool _recargandoBodegas = false;
  String? _archivo;

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) {
        setState(() {
          _bodegas = b;
          if (b.length == 1) _bodega = b.first;
        });
      }
    });
    InventarioService.todosElementos().then((e) {
      if (mounted) setState(() => _emparejador = EmparejadorCatalogo(e));
    });
  }

  @override
  void dispose() {
    _factura.dispose();
    _proveedor.dispose();
    super.dispose();
  }

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

  // ---- Lectura del archivo ------------------------------------------
  Future<void> _elegirArchivo() async {
    if (_emparejador == null) {
      return _msg('Espera: todavía se está cargando el catálogo');
    }
    Uint8List bytes;
    String nombre;
    try {
      if (kIsWeb) {
        final r = await abrirArchivoWeb('.xlsx,.csv');
        if (r == null) return;
        nombre = r.name;
        bytes = r.bytes;
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'csv'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        if (f.bytes == null) return _msg('No se pudo leer el archivo');
        nombre = f.name;
        bytes = f.bytes!;
      }
    } catch (e) {
      return _msg('No se pudo abrir el archivo: $e');
    }

    setState(() {
      _leyendo = true;
      _archivo = nombre;
    });
    try {
      // conCosto: exige la tercera columna; sin ella la base rechazaría todo.
      final crudas = leerArchivoImport(bytes, nombre, conCosto: true);
      final out = <_FilaComp>[];
      for (final r in crudas) {
        final texto = r[0].toString().trim();
        if (texto.isEmpty) continue;
        final cant = parseCantidad(r.length > 1 ? r[1].toString() : '');
        final costo = parseCantidad(r.length > 2 ? r[2].toString() : '');
        final (match, score) = _emparejador!.mejor(texto);
        out.add(_FilaComp(texto, cant, costo, match: match, score: score));
      }
      if (mounted) setState(() => _filas = out);
    } on FormatException catch (e) {
      setState(() {
        _filas = [];
        _archivo = null;
      });
      _archivoInvalido(e.message);
    } catch (e) {
      setState(() {
        _filas = [];
        _archivo = null;
      });
      _archivoInvalido('No pude leer el archivo. Verifica que sea un Excel '
          '(.xlsx) o CSV válido.\n\nDetalle: $e');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  Future<void> _archivoInvalido(String motivo) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
        title: const Text('Archivo inválido'),
        content: SingleChildScrollView(child: Text(motivo)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              mostrarAyudaFormato(context, compra: true);
            },
            child: const Text('Ver formato'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  // ---- Corrección manual --------------------------------------------
  Future<void> _editarLinea(_FilaComp fila) async {
    final cantCtrl = TextEditingController(text: fila.cantidad.toString());
    final costoCtrl = TextEditingController(
        text: fila.costo == 0 ? '' : fila.costo.toString());
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
          const SizedBox(height: 10),
          TextField(
            controller: costoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Costo unitario (sin IVA)',
              helperText: 'Lo que pagaste por UNA unidad',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        fila.cantidad = parseCantidad(cantCtrl.text);
        fila.costo = parseCantidad(costoCtrl.text);
      });
    }
  }

  Future<void> _corregir(_FilaComp fila) async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null && mounted) {
      setState(() {
        fila.match = sel;
        fila.score = 1;
      });
    }
  }

  /// Listas para cargar: emparejadas, con cantidad, CON costo y NO
  /// serializadas.
  ///
  /// Los serializados quedan por fuera a propósito: registrar la entrada
  /// subiría la existencia sin crear los seriales en `series`, y el elemento
  /// quedaría con unidades pero sin ninguna unidad identificable. Esas
  /// compras se registran aparte, indicando el serial de cada unidad.
  List<_FilaComp> get _validas => _filas
      .where((f) =>
          f.match != null &&
          f.cantidad > 0 &&
          f.costo > 0 &&
          !(f.match!.serializado))
      .toList();

  int get _sinCosto => _filas
      .where((f) =>
          f.match != null &&
          !(f.match!.serializado) &&
          f.cantidad > 0 &&
          f.costo <= 0)
      .length;

  int get _serializados =>
      _filas.where((f) => f.match?.serializado ?? false).length;

  num get _totalCompra =>
      _validas.fold<num>(0, (s, f) => s + f.total);

  // ---- Carga ----------------------------------------------------------
  Future<void> _cargar() async {
    if (_bodega == null) return _msg('Elige la bodega donde entra la mercancía');
    final validas = _validas;
    if (validas.isEmpty) {
      return _msg('No hay líneas listas (revisa emparejamientos y costos)');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fact_check, color: Colors.teal, size: 40),
        title: const Text('Confirmar compra'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Entran ${validas.length} artículos a '
                    '"${_bodega!.nombre}".'),
                const SizedBox(height: 8),
                Text('Total de la compra: ${_money.format(_totalCompra)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_factura.text.trim().isNotEmpty)
                  Text('Documento: ${_factura.text.trim()}'),
                const SizedBox(height: 12),
                const Text(
                  'El costo de cada línea recalcula el costo promedio del '
                  'artículo. Revisa que sean precios unitarios sin IVA.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (_sinCosto > 0) ...[
                  const SizedBox(height: 8),
                  Text('Se omiten $_sinCosto línea(s) sin costo.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orange)),
                ],
                if (_serializados > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                      'Se omiten $_serializados línea(s) de artículos '
                      'serializados: hay que registrarlos aparte indicando '
                      'el serial de cada unidad.',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.orange)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar compra')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _cargando = true);
    try {
      final prov = _proveedor.text.trim();
      final n = await InventarioService.registrarEntradaMasiva(
        bodegaId: _bodega!.id,
        items: [
          for (final f in validas)
            {
              'elemento_id': f.match!.id,
              'cantidad': f.cantidad,
              'costo': f.costo,
            }
        ],
        referencia: _factura.text.trim().isEmpty ? null : _factura.text.trim(),
        observacion: prov.isEmpty ? 'Compra' : 'Compra a $prov',
      );
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _filas = [];
        _archivo = null;
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Compra registrada'),
          content: Text('Entraron $n líneas a "${_bodega!.nombre}" por '
              '${_money.format(_totalCompra)}.\n\n'
              'Los costos promedio de esos artículos ya quedaron '
              'actualizados.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          title: const Text('No se registró nada'),
          content: SingleChildScrollView(
            child: Text('La carga se deshizo completa, tu inventario quedó '
                'como estaba. Ninguna línea entró.\n\nMotivo:\n$e'),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido')),
          ],
        ),
      );
    }
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmarDescarte(
      hayTrabajoSinGuardar: _filas.isNotEmpty && !_cargando,
      queSePierde: '${_filas.length} línea(s) de la compra',
      child: _contenido(),
    );
  }

  Widget _contenido() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compra masiva'),
        actions: [
          IconButton(
            onPressed: () => mostrarAyudaFormato(context, compra: true),
            icon: const Icon(Icons.info_outline),
            tooltip: 'Cómo armar el archivo',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SelectorRecargable<Bodega>(
              etiqueta: 'Bodega donde entra la mercancía',
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
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _proveedor,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor',
                    prefixIcon: Icon(Icons.local_shipping),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _factura,
                  decoration: const InputDecoration(
                    labelText: 'Factura / OC',
                    prefixIcon: Icon(Icons.receipt_long),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _leyendo ? null : _elegirArchivo,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_archivo ?? 'Elegir Excel/CSV',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => descargarPlantillaImport(context,
                    nombreArchivo: 'plantilla_compra', compra: true),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Plantilla'),
              ),
              IconButton(
                onPressed: () => mostrarAyudaFormato(context, compra: true),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Cómo armar el archivo',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ]),
          ),
          if (_leyendo || _cargando) const LinearProgressIndicator(),
          if (_filas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filas.length} filas · ${_validas.length} listas'
                  '${_sinCosto > 0 ? ' · $_sinCosto sin costo' : ''}'
                  '${_serializados > 0 ? ' · $_serializados serializadas (se omiten)' : ''}'
                  '  ·  ${_money.format(_totalCompra)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Expanded(
            child: _filas.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Sube el Excel de la compra con las columnas '
                        'ELEMENTO, CANTIDAD y COSTO UNITARIO.\n\n'
                        'El costo va sin IVA y por unidad: es el que '
                        'recalcula el costo promedio de cada artículo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
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
                child: FilledButton.icon(
                  onPressed: (_cargando || _validas.isEmpty) ? null : _cargar,
                  icon: const Icon(Icons.download),
                  label: Text(_cargando
                      ? 'Registrando…'
                      : 'Registrar ${_validas.length} · '
                          '${_money.format(_totalCompra)}'),
                ),
              ),
            ),
    );
  }

  Widget _filaWidget(_FilaComp f) {
    final sinMatch = f.match == null;
    final serial = f.match?.serializado ?? false;
    final sinCosto = !sinMatch && !serial && f.costo <= 0;
    final dudoso = !sinMatch && f.score < 0.8;
    return ListTile(
      dense: true,
      leading: Icon(
        sinMatch
            ? Icons.help_outline
            : serial
                ? Icons.block
                : sinCosto
                    ? Icons.attach_money
                    : dudoso
                        ? Icons.warning_amber
                        : Icons.check_circle,
        color: sinMatch
            ? Colors.red
            : serial
                ? Colors.grey
                : sinCosto
                    ? Colors.red
                    : dudoso
                        ? Colors.orange
                        : Colors.green,
      ),
      // El título es el elemento de la BASE DE DATOS con el que se emparejó.
      title: Text(f.match?.nombre ?? f.textoOriginal,
          style: TextStyle(
              decoration: serial ? TextDecoration.lineThrough : null)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Y aquí SIEMPRE el texto tal como venía en el Excel: sin verlo al
          // lado del nombre de la base, el usuario no tiene cómo saber si el
          // emparejamiento quedó bien.
          Text(
            'Del archivo: "${f.textoOriginal}"',
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: sinMatch ? Colors.red : Colors.grey.shade700,
            ),
          ),
          Text(
            sinMatch
                ? 'Sin emparejar: elige el artículo con ⇄'
                : serial
                    ? 'Serializado: se omite. Regístralo aparte indicando el '
                        'serial de cada unidad'
                    : sinCosto
                        ? 'FALTA EL COSTO: tócala para escribirlo'
                        : '${_qty.format(f.cantidad)} × '
                            '${_money.format(f.costo)}'
                            ' = ${_money.format(f.total)}'
                            '${dudoso ? '  ·  revisa el emparejamiento' : ''}',
            style: TextStyle(
              fontSize: 11.5,
              color: (sinCosto || sinMatch) ? Colors.red : null,
              fontWeight:
                  (sinCosto || sinMatch) ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_note, size: 20),
            tooltip: 'Cantidad y costo',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => _editarLinea(f),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 20),
            tooltip: 'Cambiar el artículo',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => _corregir(f),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Quitar esta línea',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => setState(() => _filas.remove(f)),
          ),
        ],
      ),
    );
  }
}

/// Buscador para corregir a mano con qué artículo se empareja una línea.
class _BuscadorElemento extends StatefulWidget {
  const _BuscadorElemento();
  @override
  State<_BuscadorElemento> createState() => _BuscadorElementoState();
}

class _BuscadorElementoState extends State<_BuscadorElemento> {
  final _ctrl = TextEditingController();
  List<Elemento> _res = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    setState(() => _cargando = true);
    final r = await InventarioService.buscar(q);
    if (mounted) {
      setState(() {
        _res = r;
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _buscar,
              decoration: const InputDecoration(
                hintText: 'Buscar el artículo correcto…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (_cargando) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _res.length,
              itemBuilder: (_, i) {
                final e = _res[i];
                return ListTile(
                  dense: true,
                  title: Text(e.nombre),
                  subtitle: Text('${_qty.format(e.existencia)} ${e.unidad} · '
                      'prom. ${_money.format(e.costoPromedio)}'),
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
