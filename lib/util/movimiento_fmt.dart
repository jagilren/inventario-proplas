/// Cantidad con SIGNO para mostrar en informes e históricos: lo que sale
/// resta y lo que entra suma, como en un extracto bancario.
///
/// La base guarda las cantidades en positivo y es el `tipo` el que dice si
/// suma o resta (así lo aplica el disparador de existencias). Este ayudante
/// hace visible ese signo, sin tocar el dato guardado.
///
/// - `salida` → negativo.
/// - `entrada` e `inicial` → positivo. Aquí entran también las devoluciones
///   y las cargas masivas: para la base son entradas normales, lo que las
///   distingue es la referencia.
/// - `ajuste` → se deja tal cual: ese tipo YA viene con su propio signo
///   (positivo si suma, negativo si resta), y forzarlo lo dañaría.
num cantidadConSigno(String tipo, num cantidad) {
  if (tipo == 'ajuste') return cantidad;
  return tipo == 'salida' ? -cantidad.abs() : cantidad.abs();
}

/// Muestra el flujo origen ➡️ destino de un movimiento, con emojis coloridos.
///
/// - **Devolución con reasignación** (schema_v37, `centroCostoOrigen` no
///   nulo): 🎯 C.Costo origen ➡️ 🎯 C.Costo destino. La bodega física no se
///   muestra aquí: la reasignación es puramente contable, la bodega ya se
///   ve en la fila del movimiento.
/// - **Devolución simple** (referencia DEVOLUCION): 🎯 C.Costo origen ➡️ 🏬 Bodega destino
/// - **Salida**: 🏬 Bodega origen ➡️ 🎯 C.Costo destino
/// - Otros (entrada normal, inicial, traslado): 🏬 Bodega
String flujoMovimiento({
  required String tipo,
  String? referencia,
  String? bodega,
  String? centroCosto,
  String? centroCostoOrigen,
}) {
  const cc = '🎯';        // centro de costo
  const bod = '🏬';       // bodega
  const flecha = '➡️';    // flecha azul, colorida
  final devolucion = (referencia ?? '').toUpperCase().startsWith('DEVOLUCION');

  // Primero que nada: si tiene centro origen, es una reasignación, sin
  // importar la referencia (la Entrada individual no pone 'DEVOLUCION',
  // solo la carga masiva de Devoluciones — el dato que de verdad importa
  // es que exista un centro origen).
  if (centroCostoOrigen != null) {
    return '$cc $centroCostoOrigen $flecha $cc ${centroCosto ?? '—'}';
  }
  if (devolucion) {
    return '$cc ${centroCosto ?? '—'} $flecha $bod ${bodega ?? '—'}';
  }
  if (tipo == 'salida') {
    return '$bod ${bodega ?? '—'} $flecha $cc ${centroCosto ?? '—'}';
  }
  return bodega != null ? '$bod $bodega' : '';
}
