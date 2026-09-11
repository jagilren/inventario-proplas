import '../data.dart';

// "Armar salida": el carrito para despachar sin archivo de Excel
// (docs/plan-armar-salida.md). Lógica pura, sin pantallas ni red.
//
// Alimenta las MISMAS funciones de la base que la salida masiva por Excel
// (validar_salida_masiva y registrar_salida_masiva): una salida armada aquí
// y una cargada de un archivo tienen que comportarse igual, y la que decide
// si alcanza el saldo es siempre la base.

/// Una línea del carrito: un artículo y cuánto se despacha.
class LineaSalida {
  final Elemento elemento;
  num cantidad;

  LineaSalida(this.elemento, this.cantidad);

  /// Lo que vale esta línea al costo promedio de hoy. Es una estimación
  /// para el usuario: el costo que queda en el movimiento lo estampa la
  /// base al despachar.
  num get valor => cantidad * elemento.costoPromedio;
}

/// Dónde está un artículo en el carrito, o -1 si no está.
int indiceEnCarrito(List<LineaSalida> lineas, String elementoId) {
  for (var i = 0; i < lineas.length; i++) {
    if (lineas[i].elemento.id == elementoId) return i;
  }
  return -1;
}

/// Por qué NO se puede despachar una línea. Null si está bien.
///
/// [saldo] es lo que respondió la base para esta línea (null si todavía no
/// se ha podido preguntar, por ejemplo sin señal).
String? problemaLinea(LineaSalida l, ValidacionSalida? saldo) {
  if (l.cantidad <= 0) return 'La cantidad tiene que ser mayor que cero.';
  if (l.elemento.serializado) {
    return 'Es serializado: se despacha eligiendo sus seriales, en '
        'Movimientos → Salida.';
  }
  if (saldo != null && !saldo.alcanza) {
    final hay = textoCantidadSalida(saldo.disponible);
    return saldo.enOtras > 0
        ? 'Solo hay $hay aquí. En otras bodegas: ${saldo.otrasDetalle}.'
        : 'Solo hay $hay y se piden ${textoCantidadSalida(l.cantidad)}.';
  }
  return null;
}

/// Las líneas que sí se pueden despachar.
List<LineaSalida> lineasListas(
        List<LineaSalida> lineas, Map<String, ValidacionSalida> saldos) =>
    [
      for (final l in lineas)
        if (problemaLinea(l, saldos[l.elemento.id]) == null) l,
    ];

/// Lo que se le manda a la base (validar_salida_masiva y
/// registrar_salida_masiva esperan lo mismo).
List<Map<String, dynamic>> itemsSalida(List<LineaSalida> lineas) => [
      for (final l in lineas)
        {'elemento_id': l.elemento.id, 'cantidad': l.cantidad},
    ];

/// Cuánto vale el carrito, al costo promedio de hoy.
num totalCarrito(List<LineaSalida> lineas) =>
    lineas.fold<num>(0, (s, l) => s + l.valor);

/// "3 artículos · 26 unidades": lo primero que mira quien despacha.
String resumenCarrito(List<LineaSalida> lineas) {
  final unidades = lineas.fold<num>(0, (s, l) => s + l.cantidad);
  return '${lineas.length} artículo${lineas.length == 1 ? '' : 's'} · '
      '${textoCantidadSalida(unidades)} unidad'
      '${unidades == 1 ? '' : 'es'}';
}

/// Cantidad sin ".0" y con coma decimal, como se escribe en Colombia.
String textoCantidadSalida(num n) => n % 1 == 0
    ? n.toInt().toString()
    : n.toString().replaceAll('.', ',');

/// Las filas del CSV de lo despachado, para imprimir o mandar la remisión.
/// El mismo orden del carrito.
List<List<dynamic>> filasCsvSalida(
  List<LineaSalida> lineas, {
  required String bodega,
  required String centro,
}) =>
    [
      ['BODEGA', bodega, 'CENTRO DE COSTO', centro],
      ['ELEMENTO', 'CANTIDAD', 'UNIDAD', 'COSTO PROMEDIO', 'VALOR'],
      for (final l in lineas)
        [
          l.elemento.nombre,
          l.cantidad,
          l.elemento.unidad,
          l.elemento.costoPromedio.round(),
          l.valor.round(),
        ],
      ['TOTAL', '', '', '', totalCarrito(lineas).round()],
    ];
