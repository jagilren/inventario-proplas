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

/// Dice si, en la fila de un informe, el centro de costo que aparece es el
/// ORIGEN (de dónde viene la mercancía) o el DESTINO (a dónde va) — para
/// una columna "Rol" explícita, sin tener que deducirlo cruzando con la
/// columna Tipo. Vacío si la fila no tiene centro (una compra, por ejemplo).
///
/// - `salida` → Destino (a qué centro se entrega).
/// - `entrada`/`inicial` con centro → Origen (de dónde vuelve).
/// - `ajuste`: hereda el rol de lo que revierte, a partir de su propio
///   signo — un ajuste positivo deshace una salida (revierte un cargo
///   "Destino", así que él mismo actúa como Origen); uno negativo deshace
///   una entrada (revierte un crédito "Origen", así que actúa como
///   Destino). Mismo signo que ya usa `cantidadConSigno`.
String rolCentro(String tipo, num cantidad, bool tieneCentro) {
  if (!tieneCentro) return '';
  switch (tipo) {
    case 'salida':
      return 'Destino';
    case 'entrada':
    case 'inicial':
      return 'Origen';
    case 'ajuste':
      return cantidad >= 0 ? 'Origen' : 'Destino';
    default:
      return '';
  }
}

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
