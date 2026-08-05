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

final _qty = NumberFormat.decimalPattern('es_CO');

/// Una línea leída del archivo de salidas.
class _FilaSal {
  final String textoOriginal; // lo que traía la columna ELEMENTO
  num cantidad; // editable antes de cargar
  Elemento? match; // con qué elemento del catálogo se emparejó
  double score; // qué tan seguro es el emparejamiento (0..1)
  _FilaSal(this.textoOriginal, this.cantidad, {this.match, this.score = 0});
}

/// Carga masiva de SALIDAS: sube un Excel/CSV con columnas ELEMENTO y
/// CANTIDAD y despacha todo junto hacia un centro de costo.
///
/// A diferencia de las devoluciones (que siempre entran), una salida puede
/// ser rechazada por falta de existencia. Por eso aquí hay dos pasos: primero
/// se revisa el saldo de TODAS las líneas contra la bodega, y solo si el
/// usuario confirma se registra —y se registra en una sola transacción del
/// servidor, así que o entran todas o no entra ninguna.
class SalidaMasivaPage extends StatefulWidget {
  const SalidaMasivaPage({super.key});
  @override
  State<SalidaMasivaPage> createState() => _SalidaMasivaPageState();
}

class _SalidaMasivaPageState extends State<SalidaMasivaPage> {
  List<Bodega> _bodegas = [];
  Bodega? _bodega;
  List<CentroCosto> _centros = [];
  CentroCosto? _centro;
  EmparejadorCatalogo? _emparejador;
  List<_FilaSal> _filas = [];
  bool _leyendo = false;
  bool _cargando = false;
  bool _recargandoBodegas = false;
  bool _recargandoCentros = false;
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
    InventarioService.centrosCosto().then((c) {
      if (mounted) setState(() => _centros = c);
    });
    InventarioService.todosElementos().then((e) {
      if (mounted) setState(() => _emparejador = EmparejadorCatalogo(e));
    });
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
      _msg('No se pudo abrir el archivo: $e');
      return;
    }

    setState(() {
      _leyendo = true;
      _archivo = nombre;
    });
    try {
      final crudas = leerArchivoImport(bytes, nombre);
      final out = <_FilaSal>[];
      for (final r in crudas) {
        final texto = r[0].toString().trim();
        if (texto.isEmpty) continue;
        final cant = parseCantidad(r.length > 1 ? r[1].toString() : '');
        final (match, score) = _emparejador!.mejor(texto);
        out.add(_FilaSal(texto, cant, match: match, score: score));
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
              mostrarAyudaFormato(context);
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
  Future<void> _editarCantidad(_FilaSal fila) async {
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
              labelText: 'Cantidad a despachar',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, parseCantidad(ctrl.text)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (cant != null && mounted) setState(() => fila.cantidad = cant);
  }

  Future<void> _corregir(_FilaSal fila) async {
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

  /// Líneas que ya se pueden despachar: emparejadas, con cantidad y no
  /// serializadas (esas necesitan decir CUÁLES seriales salen).
  List<_FilaSal> get _validas => _filas
      .where((f) =>
          f.match != null && f.cantidad > 0 && !(f.match!.serializado))
      .toList();

  // ---- Revisión de saldos y carga ------------------------------------
  Future<void> _revisarYCargar() async {
    if (_bodega == null) return _msg('Elige la bodega de donde sale');
    if (_centro == null) return _msg('Elige el centro de costo destino');
    final validas = _validas;
    if (validas.isEmpty) {
      return _msg('No hay líneas listas (revisa emparejamientos y cantidades)');
    }

    final items = [
      for (final f in validas)
        {'elemento_id': f.match!.id, 'cantidad': f.cantidad}
    ];

    setState(() => _cargando = true);
    List<ValidacionSalida> revision;
    try {
      revision = await InventarioService.validarSalidaMasiva(
          bodegaId: _bodega!.id, items: items);
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      return _msg('No se pudo revisar la existencia: $e');
    }
    if (!mounted) return;
    setState(() => _cargando = false);

    final faltantes = revision.where((r) => !r.alcanza).toList();
    final ok = await _confirmar(revision, faltantes);
    if (ok != true) return;

    setState(() => _cargando = true);
    try {
      final n = await InventarioService.registrarSalidaMasiva(
        bodegaId: _bodega!.id,
        centroCostoId: _centro!.id,
        items: items,
        observacion: 'Salida masiva ➜ ${_centro!.codigo}',
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
          title: const Text('Salida registrada'),
          content: Text('Se despacharon $n líneas desde '
              '"${_bodega!.nombre}" hacia ${_centro!.etiqueta}.'),
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
      // El servidor deshizo TODO: no quedó ninguna salida a medias.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          title: const Text('No se registró nada'),
          content: SingleChildScrollView(
            child: Text('La carga se deshizo completa, tu inventario quedó '
                'como estaba. Ninguna línea se registró.\n\nMotivo:\n$e'),
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

  /// Muestra el resultado de la revisión antes de confirmar. Si algo no
  /// alcanza, no deja continuar: primero hay que arreglarlo.
  Future<bool?> _confirmar(
      List<ValidacionSalida> revision, List<ValidacionSalida> faltantes) {
    final hayProblema = faltantes.isNotEmpty;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(hayProblema ? Icons.warning_amber : Icons.fact_check,
            color: hayProblema ? Colors.orange : Colors.teal, size: 40),
        title: Text(hayProblema
            ? 'Falta existencia en ${faltantes.length}'
            : 'Confirmar salida'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hayProblema
                    ? 'Estas líneas piden más de lo que hay en '
                        '"${_bodega!.nombre}". Corrígelas y vuelve a intentar:'
                    : 'Se despacharán ${revision.length} artículos desde '
                        '"${_bodega!.nombre}" hacia ${_centro!.etiqueta}.'),
                const SizedBox(height: 12),
                for (final r in (hayProblema ? faltantes : revision).take(12))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(r.alcanza ? Icons.check : Icons.close,
                            size: 16,
                            color: r.alcanza ? Colors.green : Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${r.nombre}\n'
                            'pide ${_qty.format(r.pedido)} · '
                            'hay ${_qty.format(r.disponible)} ${r.unidad}'
                            '${r.alcanza ? '' : ' · faltan ${_qty.format(r.faltante)}'}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                if ((hayProblema ? faltantes : revision).length > 12)
                  Text('… y ${(hayProblema ? faltantes : revision).length - 12} más',
                      style: const TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                if (!hayProblema) ...[
                  const SizedBox(height: 10),
                  const Text(
                      'Se registra todo junto: si alguna fallara, no se '
                      'guarda ninguna.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(hayProblema ? 'Volver a corregir' : 'Cancelar')),
          if (!hayProblema)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Despachar')),
        ],
      ),
    );
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final serializados =
        _filas.where((f) => f.match?.serializado ?? false).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Salida masiva')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SelectorRecargable<Bodega>(
              etiqueta: 'Bodega de donde sale',
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
              etiqueta: 'Centro de costo destino',
              icono: Icons.account_tree,
              valor: _centro,
              opciones: _centros,
              textoDe: (c) => c.etiqueta,
              recargando: _recargandoCentros,
              onRecargar: _recargarCentros,
              onChanged: (v) => setState(() => _centro = v),
            ),
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
                    nombreArchivo: 'plantilla_salidas'),
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Plantilla'),
              ),
              IconButton(
                onPressed: () => mostrarAyudaFormato(context),
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
                  '${serializados > 0 ? ' · $serializados serializadas (se omiten)' : ''}',
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
                        'Sube un Excel o CSV con las columnas ELEMENTO y '
                        'CANTIDAD.\n\nSi no sabes cómo armarlo, baja la '
                        'plantilla: viene con ejemplos de tu propio catálogo.',
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
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800),
                  onPressed:
                      (_cargando || _validas.isEmpty) ? null : _revisarYCargar,
                  icon: const Icon(Icons.upload),
                  label: Text(_cargando
                      ? 'Procesando…'
                      : 'Revisar y despachar ${_validas.length}'),
                ),
              ),
            ),
    );
  }

  Widget _filaWidget(_FilaSal f) {
    final serial = f.match?.serializado ?? false;
    final sinMatch = f.match == null;
    final dudoso = !sinMatch && f.score < 0.8;
    return ListTile(
      dense: true,
      leading: Icon(
        sinMatch
            ? Icons.help_outline
            : serial
                ? Icons.block
                : dudoso
                    ? Icons.warning_amber
                    : Icons.check_circle,
        color: sinMatch
            ? Colors.red
            : serial
                ? Colors.grey
                : dudoso
                    ? Colors.orange
                    : Colors.green,
      ),
      title: Text(f.match?.nombre ?? f.textoOriginal,
          style: TextStyle(
              decoration: serial ? TextDecoration.lineThrough : null)),
      subtitle: Text(
        sinMatch
            ? 'Sin emparejar · del archivo: "${f.textoOriginal}"'
            : serial
                ? 'Serializado: se omite, despáchalo aparte eligiendo seriales'
                : 'Del archivo: "${f.textoOriginal}"'
                    '${dudoso ? ' · revisa el emparejamiento' : ''}',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _editarCantidad(f),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                '${_qty.format(f.cantidad)} ${f.match?.unidad ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  subtitle: Text('${_qty.format(e.existencia)} ${e.unidad}'
                      '${e.serializado ? ' · serializado' : ''}'),
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
