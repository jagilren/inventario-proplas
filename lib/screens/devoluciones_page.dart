import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import '../data.dart';
import '../util/picker.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _qty = NumberFormat.decimalPattern('es_CO');

/// Una fila leída del archivo de devoluciones.
class _FilaDev {
  final String textoOriginal; // lo que traía la columna ELEMENTO del archivo
  final num cantidad;
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
  List<Elemento> _catalogo = [];
  List<String> _catNorm = []; // nombres normalizados (paralelo a _catalogo)
  List<_FilaDev> _filas = [];
  bool _leyendo = false;
  bool _cargando = false;
  String? _archivo;

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) {
        setState(() { _bodegas = b; if (b.length == 1) _bodega = b.first; });
      }
    });
    InventarioService.todosElementos().then((e) {
      if (mounted) {
        setState(() {
          _catalogo = e;
          _catNorm = e.map((x) => _norm(x.nombre)).toList();
        });
      }
    });
  }

  // ---- Normalización y coincidencia aproximada (sin librerías) ----
  static String _norm(String s) {
    s = s.toLowerCase().trim();
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const to = 'aaaaaeeeeiiiiooooouuuun';
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch);
    }
    return sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        cur[j + 1] = [cur[j] + 1, prev[j + 1] + 1, prev[j] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      for (var k = 0; k <= b.length; k++) {
        prev[k] = cur[k];
      }
    }
    return prev[b.length];
  }

  static double _sim(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final ta = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final tb = b.split(' ').where((t) => t.isNotEmpty).toSet();
    double jac = 0;
    if (ta.isNotEmpty && tb.isNotEmpty) {
      jac = ta.intersection(tb).length / ta.union(tb).length;
    }
    double cont = 0;
    if (a.contains(b) || b.contains(a)) cont = 0.9;
    // Levenshtein solo si aún no hay buena señal (para no penalizar velocidad).
    double lev = 0;
    if (jac < 0.82 && cont < 0.82) {
      final d = _lev(a, b);
      final ml = a.length > b.length ? a.length : b.length;
      lev = ml == 0 ? 0 : 1 - d / ml;
    }
    return [jac, cont, lev].reduce((x, y) => x > y ? x : y);
  }

  Elemento? _mejor(String texto, [double umbral = 0.55]) {
    final nq = _norm(texto);
    if (nq.isEmpty) return null;
    Elemento? best;
    double bestScore = 0;
    for (var i = 0; i < _catalogo.length; i++) {
      final s = _sim(nq, _catNorm[i]);
      if (s > bestScore) { bestScore = s; best = _catalogo[i]; }
      if (bestScore == 1) break;
    }
    _ultimoScore = bestScore;
    return bestScore >= umbral ? best : null;
  }

  double _ultimoScore = 0;

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
      final crudas = nombre.toLowerCase().endsWith('.csv')
          ? _leerCsv(bytes)
          : _leerXlsx(bytes);
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

  /// Devuelve filas crudas [texto, cantidad] ya sin encabezado.
  List<List<dynamic>> _leerXlsx(Uint8List bytes) {
    final libro = Excel.decodeBytes(bytes);
    if (libro.tables.isEmpty) return [];
    final hoja = libro.tables[libro.tables.keys.first]!;
    final filas = <List<dynamic>>[];
    for (final row in hoja.rows) {
      filas.add(row.map((c) => _celda(c?.value)).toList());
    }
    return _sinEncabezado(filas);
  }

  List<List<dynamic>> _leerCsv(Uint8List bytes) {
    String txt;
    try {
      txt = utf8.decode(bytes);
    } catch (_) {
      txt = latin1.decode(bytes);
    }
    // Delimitador: el que más aparezca en la primera línea (; o ,)
    final primera = txt.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final delim = primera.split(';').length > primera.split(',').length ? ';' : ',';
    final filas = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(txt.replaceAll('\r\n', '\n'), fieldDelimiter: delim);
    return _sinEncabezado(filas);
  }

  /// Convierte el valor de una celda de excel a texto plano.
  /// En excel 4.x, TextCellValue.value es un TextSpan (no un String), así que
  /// se resuelve con toPlainText(); los numéricos exponen su valor crudo.
  String _celda(dynamic v) {
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    if (v is BoolCellValue) return v.value.toString();
    if (v is DateCellValue) return v.toString();
    return v.toString().trim();
  }

  /// Detecta las columnas ELEMENTO/CANTIDAD y devuelve solo los datos como
  /// [textoElemento, cantidadTexto]. Si el archivo no tiene esas dos columnas,
  /// lanza [FormatException] con un mensaje claro (archivo inválido).
  ///
  /// - Columnas de MÁS: no importan, se emparejan por el nombre del encabezado
  ///   y las demás se ignoran.
  /// - Columnas de MENOS (falta ELEMENTO o CANTIDAD): archivo inválido.
  List<List<dynamic>> _sinEncabezado(List<List<dynamic>> filas) {
    // Quita filas totalmente vacías.
    final rows = filas
        .where((f) => f.any((c) => c.toString().trim().isNotEmpty))
        .toList();
    if (rows.isEmpty) {
      throw const FormatException('El archivo está vacío.');
    }

    int idxHeader = -1, colElem = -1, colCant = -1;
    for (var r = 0; r < rows.length; r++) {
      final fila = rows[r];
      int ce = -1, cc = -1;
      for (var c = 0; c < fila.length; c++) {
        final t = _norm(fila[c].toString());
        if (ce < 0 && t.contains('elemento')) ce = c;
        if (cc < 0 && (t.contains('cantidad') || t == 'cant')) cc = c;
      }
      if (ce >= 0 && cc >= 0) { idxHeader = r; colElem = ce; colCant = cc; break; }
    }

    int inicio;
    if (idxHeader >= 0) {
      inicio = idxHeader + 1;
    } else {
      // Sin encabezado reconocible. Solo se acepta el modo posicional
      // (col A = ELEMENTO, col B = CANTIDAD) si de verdad se ve así:
      // todas las filas con ≥2 columnas y la 2ª con números.
      final conDos = rows.where((f) => f.length >= 2).length;
      final numericas = rows.where((f) =>
          f.length >= 2 && _parseCant(f[1].toString()) > 0).length;
      if (conDos < rows.length || numericas == 0) {
        throw const FormatException(
            'No encontré las columnas ELEMENTO y CANTIDAD.\n\n'
            'El archivo debe tener exactamente esas dos columnas '
            '(con su encabezado): ELEMENTO y CANTIDAD.');
      }
      colElem = 0; colCant = 1; inicio = 0;
    }

    final datos = <List<dynamic>>[];
    for (var r = inicio; r < rows.length; r++) {
      final fila = rows[r];
      final texto = colElem < fila.length ? fila[colElem].toString().trim() : '';
      final cant = colCant < fila.length ? fila[colCant].toString().trim() : '';
      if (texto.isEmpty && cant.isEmpty) continue;
      datos.add([texto, cant]);
    }
    if (datos.isEmpty) {
      throw const FormatException(
          'El archivo tiene los encabezados pero ninguna fila con datos.');
    }
    return datos;
  }

  num _parseCant(String s) {
    final limpio = s.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
    return num.tryParse(limpio) ?? 0;
  }

  List<_FilaDev> _emparejar(List<List<dynamic>> crudas) {
    final out = <_FilaDev>[];
    for (final r in crudas) {
      final texto = r[0].toString().trim();
      if (texto.isEmpty) continue;
      final cant = _parseCant(r.length > 1 ? r[1].toString() : '');
      final match = _mejor(texto);
      out.add(_FilaDev(texto, cant, match: match, score: match == null ? 0 : _ultimoScore));
    }
    return out;
  }

  // ---- Corrección manual del emparejamiento ----
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: Text('Se registrarán ${validas.length} entradas de devolución '
            'en "${_bodega!.nombre}", valorizadas al costo promedio actual.'),
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
          referencia: 'DEVOLUCION',
          observacion: 'Devolución (carga masiva) · archivo ${_archivo ?? ''}',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Devoluciones · carga masiva')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: DropdownButtonFormField<Bodega>(
              initialValue: _bodega,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Bodega física donde entran las devoluciones',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warehouse),
              ),
              items: _bodegas.map((b) => DropdownMenuItem(value: b,
                  child: Text(b.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _bodega = v),
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
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_qty.format(f.cantidad),
              style: TextStyle(fontWeight: FontWeight.bold,
                  color: f.cantidad > 0 ? null : Colors.red)),
          const Text('cant.', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
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
      trailing: IconButton(
        icon: Icon(m == null ? Icons.search : Icons.edit, size: 20),
        tooltip: 'Elegir emparejamiento',
        onPressed: () => _corregir(f),
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
