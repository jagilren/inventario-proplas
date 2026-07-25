/// Muestra el flujo origen ➡️ destino de un movimiento, con emojis coloridos.
///
/// - **Devolución** (referencia DEVOLUCION): 🎯 C.Costo origen ➡️ 🏬 Bodega destino
/// - **Salida**: 🏬 Bodega origen ➡️ 🎯 C.Costo destino
/// - Otros (entrada normal, inicial, traslado): 🏬 Bodega
String flujoMovimiento({
  required String tipo,
  String? referencia,
  String? bodega,
  String? centroCosto,
}) {
  const cc = '🎯';        // centro de costo
  const bod = '🏬';       // bodega
  const flecha = '➡️';    // flecha azul, colorida
  final devolucion = (referencia ?? '').toUpperCase().startsWith('DEVOLUCION');

  if (devolucion) {
    return '$cc ${centroCosto ?? '—'} $flecha $bod ${bodega ?? '—'}';
  }
  if (tipo == 'salida') {
    return '$bod ${bodega ?? '—'} $flecha $cc ${centroCosto ?? '—'}';
  }
  return bodega != null ? '$bod $bodega' : '';
}
