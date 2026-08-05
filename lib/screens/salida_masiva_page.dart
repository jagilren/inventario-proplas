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

  /// Excepción: esta línea sale de OTRA bodega, no de la general.
  /// Sirve cuando el saldo está en otra bodega: en vez de abandonar la
  /// pantalla para hacer un traslado (perdiendo el trabajo), se despacha
  /// desde donde de verdad está el material.
  Bodega? bodegaPropia;

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

  /// Existencia de cada elemento en la bodega elegida, consultada al
  /// servidor apenas se carga el archivo (y cada vez que cambia algo).
  ///
  /// Antes esta revisión solo ocurría al pulsar "Despachar": el usuario veía
  /// 40 líneas en verde, se confiaba, y solo al final le decían que dos no
  /// alcanzaban. Ahora el problema se ve junto a la línea, de una.
  /// Clave: "elementoId|bodegaId", porque una misma línea puede salir de
  /// una bodega distinta a la general.
  Map<String, ValidacionSalida> _saldos = {};
  bool _revisandoSaldos = false;

  /// De qué bodega sale realmente una línea.
  Bodega? _bodegaDe(_FilaSal f) => f.bodegaPropia ?? _bodega;
  String _clave(String elementoId, String? bodegaId) =>
      '$elementoId|${bodegaId ?? ''}';

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
      if (mounted) {
        setState(() => _filas = out);
        await _revisarSaldos(); // marca de una las que no alcanzan
      }
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
    if (cant != null && mounted) {
      setState(() => fila.cantidad = cant);
      await _revisarSaldos(); // la cantidad nueva puede ya no alcanzar
    }
  }

  /// Ofrece despachar ESTA línea desde otra bodega, sin salir de la pantalla
  /// y sin hacer un traslado: si el material está allá, de allá sale. Así no
  /// se pierden los emparejamientos ya hechos.
  Future<void> _cambiarBodegaDeLinea(_FilaSal f) async {
    if (f.match == null) return;
    final opciones = await InventarioService.bodegasConSaldo(f.match!.id);
    if (!mounted) return;
    if (opciones.isEmpty) {
      return _msg('No hay saldo de este artículo en ninguna bodega');
    }
    final volverAGeneral = Bodega.fromMap(const {
      'id': '__general__',
      'nombre': '',
      'activo': true,
    });
    final sel = await showDialog<Bodega>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('¿Desde qué bodega sale?\n${f.match!.nombre}',
            style: const TextStyle(fontSize: 15)),
        children: [
          for (final o in opciones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                  ctx, _bodegas.where((x) => x.id == o.bodegaId).firstOrNull),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.warehouse),
                title: Text(o.bodega),
                subtitle: Text('${_qty.format(o.existencia)} disponibles'),
                trailing: _bodegaDe(f)?.id == o.bodegaId
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
              ),
            ),
          if (f.bodegaPropia != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, volverAGeneral),
              child: const ListTile(
                dense: true,
                leading: Icon(Icons.undo),
                title: Text('Volver a la bodega general'),
              ),
            ),
        ],
      ),
    );
    if (sel == null || !mounted) return; // cerró el diálogo: no cambia nada
    setState(() =>
        f.bodegaPropia = sel.id == '__general__' ? null : sel);
    await _revisarSaldos();
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
      await _revisarSaldos(); // otro artículo, otro saldo
    }
  }

  /// Líneas que ya se pueden despachar: emparejadas, con cantidad y no
  /// serializadas (esas necesitan decir CUÁLES seriales salen).
  List<_FilaSal> get _validas => _filas
      .where((f) =>
          f.match != null && f.cantidad > 0 && !(f.match!.serializado))
      .toList();

  /// Cuántos artículos distintos no tienen existencia suficiente.
  /// Se cuenta por artículo, no por línea: la revisión suma las líneas
  /// repetidas del mismo artículo contra el saldo.
  int get _sinExistencia =>
      _saldos.values.where((v) => !v.alcanza).length;

  /// Vuelve a preguntarle al servidor cuánto hay de cada artículo.
  /// Se llama al cargar el archivo, al cambiar de bodega y cada vez que se
  /// toca una cantidad o un emparejamiento.
  Future<void> _revisarSaldos() async {
    final validas = _validas;
    if (_bodega == null || validas.isEmpty) {
      if (mounted) setState(() => _saldos = {});
      return;
    }
    setState(() => _revisandoSaldos = true);
    try {
      final r = await InventarioService.validarSalidaMasiva(
        bodegaId: _bodega!.id,
        items: [
          for (final f in validas)
            {
              'elemento_id': f.match!.id,
              'cantidad': f.cantidad,
              if (f.bodegaPropia != null) 'bodega_id': f.bodegaPropia!.id,
            }
        ],
      );
      if (!mounted) return;
      setState(() =>
          _saldos = {for (final v in r) _clave(v.elementoId, v.bodegaId): v});
    } catch (_) {
      // Sin señal: se queda sin datos de saldo y no se bloquea nada. La
      // validación de verdad ocurre igual en el servidor al despachar.
      if (mounted) setState(() => _saldos = {});
    } finally {
      if (mounted) setState(() => _revisandoSaldos = false);
    }
  }

  // ---- Revisión de saldos y carga ------------------------------------
  Future<void> _revisarYCargar() async {
    if (_bodega == null) return _msg('Elige la bodega de donde sale');
    if (_centro == null) return _msg('Elige el centro de costo destino');
    final validas = _validas;
    if (validas.isEmpty) {
      return _msg('No hay líneas listas (revisa emparejamientos y cantidades)');
    }

    // Cada línea lleva su bodega si el usuario la cambió; si no, va sin ella
    // y el servidor usa la general.
    final items = [
      for (final f in validas)
        {
          'elemento_id': f.match!.id,
          'cantidad': f.cantidad,
          if (f.bodegaPropia != null) 'bodega_id': f.bodegaPropia!.id,
        }
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r.nombre}\n'
                                'pide ${_qty.format(r.pedido)} · '
                                'hay ${_qty.format(r.disponible)} ${r.unidad}'
                                '${r.alcanza ? '' : ' · faltan ${_qty.format(r.faltante)}'}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              if (!r.alcanza && r.hayEnOtras)
                                Text(
                                  '↪ hay ${_qty.format(r.enOtras)} en otra '
                                  'bodega — ${r.otrasDetalle}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF1565C0),
                                      fontWeight: FontWeight.w600),
                                ),
                            ],
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
              onChanged: (v) {
                setState(() => _bodega = v);
                _revisarSaldos(); // otra bodega, otros saldos
              },
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
                  '${_sinExistencia > 0 ? ' · $_sinExistencia sin existencia' : ''}'
                  '${serializados > 0 ? ' · $serializados serializadas (se omiten)' : ''}'
                  '${_revisandoSaldos ? ' · revisando saldos…' : ''}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _sinExistencia > 0 ? Colors.red : null),
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
    // Saldo revisado contra la bodega elegida (null si aún no se ha
    // consultado o si no hay señal).
    final bodegaLinea = _bodegaDe(f);
    final saldo = f.match == null
        ? null
        : _saldos[_clave(f.match!.id, bodegaLinea?.id)];
    final falta = saldo != null && !saldo.alcanza;
    final otraBodega = f.bodegaPropia != null;

    return ListTile(
      dense: true,
      leading: Icon(
        sinMatch
            ? Icons.help_outline
            : serial
                ? Icons.block
                : falta
                    ? Icons.remove_shopping_cart
                    : dudoso
                        ? Icons.warning_amber
                        : Icons.check_circle,
        color: sinMatch
            ? Colors.red
            : serial
                ? Colors.grey
                : falta
                    ? Colors.red
                    : dudoso
                        ? Colors.orange
                        : Colors.green,
      ),
      title: Text(f.match?.nombre ?? f.textoOriginal,
          style: TextStyle(
              decoration: serial ? TextDecoration.lineThrough : null)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                ? 'Sin emparejar: elige el artículo con ✎'
                : serial
                    ? 'Serializado: se omite, despáchalo aparte eligiendo '
                        'seriales'
                    : falta
                        ? 'NO ALCANZA: pide ${_qty.format(saldo.pedido)} · '
                            'hay ${_qty.format(saldo.disponible)} '
                            '${saldo.unidad} · faltan '
                            '${_qty.format(saldo.faltante)}'
                        : saldo != null
                            ? 'Hay ${_qty.format(saldo.disponible)} '
                                '${saldo.unidad} en bodega'
                                '${dudoso ? ' · revisa el emparejamiento' : ''}'
                            : dudoso
                                ? 'Revisa el emparejamiento'
                                : '',
            style: TextStyle(
              fontSize: 11.5,
              color: (falta || sinMatch) ? Colors.red : null,
              fontWeight: (falta || sinMatch) ? FontWeight.bold : null,
            ),
          ),
          // Esta línea sale de una bodega distinta a la general: hay que
          // decirlo bien claro, es una excepción.
          if (otraBodega)
            Text('➜ Sale desde ${f.bodegaPropia!.nombre}',
                style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF00695C),
                    fontWeight: FontWeight.bold)),
          // Si no alcanza AQUÍ pero sí hay en otra bodega, el problema no es
          // de inventario sino de ubicación. En vez de mandar al usuario a
          // hacer un traslado (perdiendo todo el trabajo de la pantalla), se
          // le ofrece despachar esa línea desde donde está el material.
          if (falta && saldo.hayEnOtras) ...[
            Text(
              '↪ Hay ${_qty.format(saldo.enOtras)} en otra bodega — '
              '${saldo.otrasDetalle}',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _cambiarBodegaDeLinea(f),
                icon: const Icon(Icons.move_down, size: 16),
                label: const Text('Despachar desde otra bodega',
                    style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
      isThreeLine: true,
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
