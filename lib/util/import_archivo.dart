import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:csv/csv.dart';
import '../data.dart';

/// Lectura y emparejamiento de los archivos de carga masiva (Excel/CSV con
/// columnas ELEMENTO y CANTIDAD).
///
/// Vive aparte porque lo usan varias pantallas (Devoluciones y Salida
/// masiva): es lógica delicada — detección de encabezados, acentos,
/// separadores, similitud de nombres — y tenerla en un solo sitio evita que
/// una se arregle y la otra se quede con el error.

/// Quita acentos, baja a minúsculas y deja solo letras/números separados por
/// espacios. Es la forma en que se comparan los nombres.
///
/// Lo importante: **las medidas fraccionarias se convierten en UN solo
/// número decimal** antes de partir el texto. Antes `1/2"` se partía en dos
/// palabras (`1` y `2`) y `2-1/2"` en tres (`2`, `1`, `2`); como el parecido
/// se calcula con CONJUNTOS de palabras, y un conjunto descarta repetidos,
/// ambos quedaban como `{1,2}` — idénticos. Resultado: dos artículos de
/// medidas distintas daban parecido perfecto. Ahora quedan `0.5` y `2.5`,
/// que son palabras distintas.
///
/// De paso, esto hace que `1 1/2"` y `1-1/2"` (que en el catálogo se
/// escriben de las dos formas) se reconozcan como la misma medida.
String normalizarTexto(String s) {
  s = s.toLowerCase().trim();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const to = 'aaaaaeeeeiiiiooooouuuun';
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  var t = sb.toString();

  // Número mixto: "2-1/2", "1 1/2", "1- 1/2"  ->  2.5 / 1.5
  // Solo si la parte entera es chica (<= 12, o sea una medida en pulgadas):
  // así "SCH 40 1/2" NO se lee como "cuarenta y medio" — el 40 es el
  // schedule y el 1/2 es el diámetro, son dos números distintos.
  t = t.replaceAllMapped(RegExp(r'(\d+)[\s\-]+(\d+)\s*/\s*(\d+)'), (m) {
    final ent = int.parse(m[1]!);
    final num = int.parse(m[2]!);
    final den = int.parse(m[3]!);
    if (den == 0) return m[0]!;
    if (ent <= 12 && num < den) return _limpiarDecimal(ent + num / den);
    return '$ent ${_limpiarDecimal(num / den)}';
  });

  // Fracción suelta: "1/2" -> 0.5 ; "3/4" -> 0.75
  t = t.replaceAllMapped(RegExp(r'(\d+)\s*/\s*(\d+)'), (m) {
    final den = int.parse(m[2]!);
    if (den == 0) return m[0]!;
    return _limpiarDecimal(int.parse(m[1]!) / den);
  });

  // Se conserva el punto para no volver a partir los decimales.
  return t.replaceAll(RegExp(r'[^a-z0-9.]+'), ' ').replaceAll(
      RegExp(r'\s+'), ' ').trim();
}

/// 2.50 -> "2.5" ; 3.0 -> "3" (para que la misma medida escrita de dos
/// formas dé exactamente el mismo texto).
String _limpiarDecimal(double v) {
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Los números que aparecen en un texto ya normalizado.
/// En un catálogo industrial los números SON la identidad del artículo
/// (diámetro, schedule, aleación), no un detalle decorativo.
Set<String> firmaNumerica(String normalizado) => RegExp(r'\d+(?:\.\d+)?')
    .allMatches(normalizado)
    .map((m) => m[0]!)
    .toSet();

/// ¿Las medidas de los dos textos pueden ser del mismo artículo?
///
/// Regla: uno de los conjuntos debe estar contenido en el otro. Así
/// "TUBO PVC 2 PULG" {2} sigue emparejando con "Tubo PVC SCH 40 2\"" {2,40}
/// (el usuario escribió menos datos, no datos distintos), pero
/// "Tapon SCH 40 1/2\"" {40, 0.5} NO empareja con "Tapon SCH 40 2-1/2\""
/// {40, 2.5}, porque cada uno trae una medida que el otro contradice.
///
/// Si alguno no tiene números, no se opina: manda el parecido del texto.
bool medidasCompatibles(String normA, String normB) {
  final fa = firmaNumerica(normA);
  final fb = firmaNumerica(normB);
  if (fa.isEmpty || fb.isEmpty) return true;
  return fa.containsAll(fb) || fb.containsAll(fa);
}

/// Tope para cuando las medidas no cuadran. Queda por debajo del umbral de
/// emparejamiento (0.55), así que la línea sale "sin emparejar" y el usuario
/// elige a mano — que es lo correcto cuando el archivo no dice qué medida es.
const double _topeMedidaDistinta = 0.45;

int _lev(String a, String b) {
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

/// Qué tan parecidos son dos textos ya normalizados (0..1).
///
/// Si las medidas se contradicen, el parecido se topa por debajo del umbral
/// de emparejamiento: por muy iguales que sean las palabras, un tapón de
/// 1/2" no es un tapón de 2-1/2". Sin este tope, Levenshtein los rescataba
/// igual (cambian 3 letras de 33) y quedaban emparejados con confianza alta.
double similitud(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  if (!medidasCompatibles(a, b)) return _topeMedidaDistinta;
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

/// Lee una cantidad tolerando separadores y basura ("10 und", "1.234,5").
num parseCantidad(String s) {
  final limpio = s.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.');
  return num.tryParse(limpio) ?? 0;
}

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
/// [textoElemento, cantidadTexto]. Lanza [FormatException] con un mensaje
/// claro si el archivo no sirve.
///
/// - Columnas de MÁS: se ignoran, se ubican por el nombre del encabezado.
/// - Sin encabezado reconocible: solo acepta el modo posicional (col A =
///   ELEMENTO, col B = CANTIDAD) si el archivo de verdad se ve así.
List<List<dynamic>> _sinEncabezado(List<List<dynamic>> filas,
    {bool conCosto = false}) {
  final rows =
      filas.where((f) => f.any((c) => c.toString().trim().isNotEmpty)).toList();
  if (rows.isEmpty) {
    throw const FormatException('El archivo está vacío.');
  }

  int idxHeader = -1, colElem = -1, colCant = -1, colCosto = -1;
  for (var r = 0; r < rows.length; r++) {
    final fila = rows[r];
    int ce = -1, cc = -1, ck = -1;
    for (var c = 0; c < fila.length; c++) {
      final t = normalizarTexto(fila[c].toString());
      if (ce < 0 && t.contains('elemento')) ce = c;
      if (cc < 0 && (t.contains('cantidad') || t == 'cant')) cc = c;
      // "costo", "costo unitario", "valor unitario", "precio"…
      if (ck < 0 && (t.contains('costo') || t.contains('precio') ||
          t.contains('valor'))) {
        ck = c;
      }
    }
    if (ce >= 0 && cc >= 0) {
      idxHeader = r;
      colElem = ce;
      colCant = cc;
      colCosto = ck;
      break;
    }
  }

  int inicio;
  if (idxHeader >= 0) {
    inicio = idxHeader + 1;
    if (conCosto && colCosto < 0) {
      throw const FormatException(
          'Falta la columna del COSTO UNITARIO.\n\n'
          'Para una compra hacen falta tres columnas: ELEMENTO, CANTIDAD y '
          'COSTO UNITARIO (el precio que le pagaste al proveedor por una '
          'unidad, sin IVA).');
    }
  } else {
    // Sin encabezado reconocible: modo posicional, solo si de verdad se ve así.
    final minCols = conCosto ? 3 : 2;
    final conMin = rows.where((f) => f.length >= minCols).length;
    final numericas = rows
        .where((f) => f.length >= minCols && parseCantidad(f[1].toString()) > 0)
        .length;
    if (conMin < rows.length || numericas == 0) {
      throw FormatException(conCosto
          ? 'No encontré las columnas ELEMENTO, CANTIDAD y COSTO UNITARIO.\n\n'
              'El archivo debe traer esas tres columnas con su encabezado.'
          : 'No encontré las columnas ELEMENTO y CANTIDAD.\n\n'
              'El archivo debe tener exactamente esas dos columnas '
              '(con su encabezado): ELEMENTO y CANTIDAD.');
    }
    colElem = 0;
    colCant = 1;
    colCosto = conCosto ? 2 : -1;
    inicio = 0;
  }

  final datos = <List<dynamic>>[];
  for (var r = inicio; r < rows.length; r++) {
    final fila = rows[r];
    final texto = colElem < fila.length ? fila[colElem].toString().trim() : '';
    final cant = colCant < fila.length ? fila[colCant].toString().trim() : '';
    final costo = (colCosto >= 0 && colCosto < fila.length)
        ? fila[colCosto].toString().trim()
        : '';
    if (texto.isEmpty && cant.isEmpty) continue;
    datos.add([texto, cant, costo]);
  }
  if (datos.isEmpty) {
    throw const FormatException(
        'El archivo tiene los encabezados pero ninguna fila con datos.');
  }
  return datos;
}

List<List<dynamic>> _leerXlsx(Uint8List bytes, bool conCosto) {
  final libro = Excel.decodeBytes(bytes);
  if (libro.tables.isEmpty) return [];
  final hoja = libro.tables[libro.tables.keys.first]!;
  final filas = <List<dynamic>>[];
  for (final row in hoja.rows) {
    filas.add(row.map((c) => _celda(c?.value)).toList());
  }
  return _sinEncabezado(filas, conCosto: conCosto);
}

List<List<dynamic>> _leerCsvInterno(Uint8List bytes, bool conCosto) {
  String txt;
  try {
    txt = utf8.decode(bytes);
  } catch (_) {
    txt = latin1.decode(bytes);
  }
  // Delimitador: el que más aparezca en la primera línea (; o ,)
  final primera = txt
      .split(RegExp(r'\r?\n'))
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final delim =
      primera.split(';').length > primera.split(',').length ? ';' : ',';
  final filas = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
      .convert(txt.replaceAll('\r\n', '\n'), fieldDelimiter: delim);
  return _sinEncabezado(filas, conCosto: conCosto);
}

/// Lee el archivo (Excel o CSV según el nombre) y devuelve las filas
/// [textoElemento, cantidadTexto].
/// [conCosto] exige además una tercera columna de COSTO UNITARIO: la usan
/// las compras a proveedor, donde el precio pagado es obligatorio (la base
/// rechaza las entradas sin costo, y es el que recalcula el promedio móvil).
List<List<dynamic>> leerArchivoImport(Uint8List bytes, String nombre,
        {bool conCosto = false}) =>
    nombre.toLowerCase().endsWith('.csv')
        ? _leerCsvInterno(bytes, conCosto)
        : _leerXlsx(bytes, conCosto);

/// Empareja textos sueltos contra el catálogo, por parecido de nombre.
/// Guarda los nombres ya normalizados para no repetir ese trabajo en cada
/// comparación (el catálogo puede tener miles de elementos).
class EmparejadorCatalogo {
  final List<Elemento> catalogo;
  final List<String> _norm;

  EmparejadorCatalogo(this.catalogo)
      : _norm = catalogo.map((e) => normalizarTexto(e.nombre)).toList();

  /// Devuelve el elemento más parecido y su puntaje (0..1).
  /// Si no llega al [umbral], el elemento va null pero el puntaje se conserva.
  (Elemento?, double) mejor(String texto, {double umbral = 0.55}) {
    final nq = normalizarTexto(texto);
    if (nq.isEmpty) return (null, 0);
    Elemento? best;
    double bestScore = 0;
    for (var i = 0; i < catalogo.length; i++) {
      final s = similitud(nq, _norm[i]);
      if (s > bestScore) {
        bestScore = s;
        best = catalogo[i];
      }
      if (bestScore == 1) break;
    }
    return (bestScore >= umbral ? best : null, bestScore);
  }
}
