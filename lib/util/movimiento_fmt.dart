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
/// - **Entrada con origen Y destino** (devolución con destino informativo):
///   🎯 C.Costo origen ➡️ 🎯 C.Costo destino.
/// - **Entrada con origen, sin destino** (devolución, caso raro hoy que el
///   destino es obligatorio): 🎯 C.Costo origen ➡️ 🏬 Bodega.
/// - **Entrada solo con destino** (compra, sin devolución): 🏬 Bodega ➡️
///   🎯 C.Costo destino — el destino es puramente informativo, no una
///   salida real: no afecta ningún informe de valorización.
/// - **Salida**: 🏬 Bodega origen ➡️ 🎯 C.Costo destino.
/// - Otros (inicial, traslado): 🏬 Bodega.
String flujoMovimiento({
  required String tipo,
  String? referencia,
  String? bodega,
  String? centroCosto,
  String? centroCostoDestino,
}) {
  const cc = '🎯';        // centro de costo
  const bod = '🏬';       // bodega
  const flecha = '➡️';    // flecha azul, colorida
  final devolucion = (referencia ?? '').toUpperCase().startsWith('DEVOLUCION');

  if (centroCosto != null && centroCostoDestino != null) {
    return '$cc $centroCosto $flecha $cc $centroCostoDestino';
  }
  if (devolucion || (tipo == 'entrada' && centroCosto != null)) {
    return '$cc ${centroCosto ?? '—'} $flecha $bod ${bodega ?? '—'}';
  }
  if (tipo == 'salida') {
    return '$bod ${bodega ?? '—'} $flecha $cc ${centroCosto ?? '—'}';
  }
  if (tipo == 'entrada' && centroCostoDestino != null) {
    return '$bod ${bodega ?? '—'} $flecha $cc $centroCostoDestino';
  }
  return bodega != null ? '$bod $bodega' : '';
}
