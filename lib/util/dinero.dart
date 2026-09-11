// Lectura de valores en PESOS tal como los escribe una persona en Colombia.
//
// Antes cada pantalla hacía `num.tryParse(texto.replaceAll(',', '.'))`, que
// trata el punto como decimal. Pero en Colombia el PUNTO separa miles:
//   "45.000"    → se leía como 45            (debía ser 45.000)
//   "1.540.000" → no se podía leer → $0     (debía ser 1.540.000)
// y las dos cosas pasaban EN SILENCIO. Hallado el 2026-09-10 (SDD §9.9).
//
// Solo para DINERO. Las cantidades y longitudes NO usan esto a propósito:
// ahí "2.5" puede ser de verdad dos metros y medio.
import 'package:intl/intl.dart';

final _pesos =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Lee un valor en pesos. Devuelve null si no se puede leer (texto vacío o
/// que no es un número).
///
/// Las reglas, en orden:
/// - Se ignoran espacios, "$" y "COP".
/// - Si hay PUNTO y COMA, el que aparece de ÚLTIMO es el decimal:
///   "1.234,5" = 1234,5 · "1,234.5" = 1234,5.
/// - Si el mismo separador aparece VARIAS veces, son miles, en grupos de 3:
///   "1.540.000" = 1540000 · "1,540,000" = 1540000.
/// - Si aparece UNA vez seguido de exactamente 3 dígitos, son miles:
///   "45.000" = 45000 · "45,000" = 45000. (Un valor en pesos no tiene tres
///   decimales, así que no hay otra lectura razonable.)
/// - Si aparece UNA vez seguido de 1 o 2 dígitos, es decimal:
///   "45,5" = 45,5 · "45.50" = 45,5.
num? leerPesos(String texto) {
  var t = texto
      .replaceAll(RegExp(r'cop', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s$ ]'), '');
  if (t.isEmpty) return null;
  var signo = 1;
  if (t.startsWith('-')) {
    signo = -1;
    t = t.substring(1);
  }
  if (!RegExp(r'^[\d.,]+$').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) {
    return null;
  }

  final hayPunto = t.contains('.');
  final hayComa = t.contains(',');
  String limpio;

  if (hayPunto && hayComa) {
    // El último separador es el decimal; el otro, de miles.
    final decimal = t.lastIndexOf('.') > t.lastIndexOf(',') ? '.' : ',';
    final miles = decimal == '.' ? ',' : '.';
    final partes = t.split(decimal);
    if (partes.length != 2) return null;
    final entera = partes[0];
    // Los miles tienen que venir bien agrupados: "1.234" sí, "12.34" no.
    if (!RegExp('^\\d{1,3}(\\$miles\\d{3})*\$').hasMatch(entera)) {
      return null;
    }
    limpio = '${entera.replaceAll(miles, '')}.${partes[1]}';
  } else if (hayPunto || hayComa) {
    final sep = hayPunto ? '.' : ',';
    final veces = sep.allMatches(t).length;
    if (veces > 1) {
      if (!RegExp('^\\d{1,3}(\\$sep\\d{3})+\$').hasMatch(t)) return null;
      limpio = t.replaceAll(sep, '');
    } else {
      final partes = t.split(sep);
      final despues = partes[1];
      if (despues.length == 3 && partes[0].isNotEmpty && partes[0].length <= 3) {
        limpio = partes.join(); // miles: "45.000"
      } else {
        limpio = '${partes[0].isEmpty ? '0' : partes[0]}.$despues';
      }
    }
  } else {
    limpio = t;
  }

  final n = num.tryParse(limpio);
  return n == null ? null : n * signo;
}

/// Lo que se entendió de lo escrito, para mostrarlo debajo del campo:
/// "= $1.540.000". null si el campo está vacío; un aviso si no se puede leer.
/// Con esto, el valor que se va a guardar se VE antes de guardarlo.
String? pesosEntendidos(String texto) {
  if (texto.trim().isEmpty) return null;
  final n = leerPesos(texto);
  if (n == null) return 'No se entiende como valor en pesos';
  return '= ${_pesos.format(n)}';
}
