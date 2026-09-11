import 'package:flutter/material.dart';
import '../activos_service.dart';
import '../util/movimiento_fmt.dart';

/// Un REINGRESO en el listado de observaciones del equipo (schema_v69).
///
/// Pedido del usuario: el reingreso queda en los movimientos, pero TAMBIÉN
/// tiene que ser un elemento más de las observaciones. Se ve con las mismas
/// palabras, el mismo ícono y el mismo color que en la pestaña Movimientos
/// ("Entrada · REINGRESO", 🎯 origen ➡️ 🏬 bodega), para que se reconozca
/// como el mismo hecho. La fecha y el usuario van en la línea gris de abajo,
/// igual que en las demás observaciones.
class LineaObservacionReingreso extends StatelessWidget {
  final ActivoObservacion observacion;

  const LineaObservacionReingreso({super.key, required this.observacion});

  /// El mismo morado de los reingresos en la pestaña Movimientos.
  static const color = Colors.deepPurple;

  @override
  Widget build(BuildContext context) {
    final o = observacion;
    final esquema = Theme.of(context).colorScheme;
    final sinTexto = o.texto.trim().isEmpty;
    // Una sola lectura, en orden, para el lector de pantalla.
    return Semantics(
      container: true,
      label: o.descripcionAccesible,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o.etiquetaOrigen,
              style: const TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            flujoMovimiento(
              tipo: 'entrada',
              bodega: o.movBodega,
              centroCosto: o.movCentro,
              centroCostoDestino: o.movCentroDestino,
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
          if (o.movCondicion != null)
            Text('Volvió ${Activo.etiquetaCondicion(o.movCondicion!).toLowerCase()}',
                style: TextStyle(fontSize: 12.5, color: esquema.onSurface)),
          // Dicho con palabras: tachar o poner en rojo no se oye.
          if (o.movAnulado)
            Text('Anulado después',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: esquema.error)),
          const SizedBox(height: 4),
          // Sin texto, el reingreso sale igual: es un hecho, no una nota.
          Text(
            sinTexto ? 'Sin observación' : o.texto,
            style: sinTexto
                ? TextStyle(
                    fontStyle: FontStyle.italic,
                    color: esquema.onSurfaceVariant)
                : null,
          ),
        ],
      ),
    );
  }
}
