import 'package:flutter/material.dart';
import '../util/emparejador_ia.dart';

/// Qué eligió el usuario para emparejar este archivo.
class OpcionEmparejar {
  final bool usarIA;
  final ProveedorIA proveedor;
  const OpcionEmparejar(this.usarIA, this.proveedor);
}

/// Pregunta, al subir el archivo, si empareja con el algoritmo local o con
/// IA.
///
/// Se pregunta CADA VEZ en vez de dejar un interruptor pegado: la opción de
/// IA cuesta plata, y un interruptor que quedó prendido gasta sin que nadie
/// lo note. Aquí el costo estimado está a la vista al momento de decidir.
Future<OpcionEmparejar?> elegirEmparejador(
  BuildContext context, {
  required int lineas,
}) {
  var proveedor = ProveedorIA.anthropic;
  // Estimado con Haiku 4.5 y el filtro local previo: ~US$0,00035 por línea.
  // Es una guía de orden de magnitud, no una factura.
  final costo = (lineas * 0.00035);
  final costoTxt = costo < 0.01
      ? 'menos de US\$0,01'
      : 'US\$${costo.toStringAsFixed(2)} aprox.';

  return showDialog<OpcionEmparejar>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        icon: const Icon(Icons.auto_awesome, color: Colors.teal, size: 40),
        title: const Text('¿Cómo emparejo los artículos?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('El archivo trae $lineas línea(s).',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),

              _Opcion(
                icono: Icons.bolt,
                color: Colors.green,
                titulo: 'Algoritmo local',
                detalle: 'Gratis e instantáneo, y funciona sin internet.\n'
                    'Acierta con los nombres parecidos al catálogo, pero '
                    'deja sin emparejar los muy abreviados.',
                onTap: () => Navigator.pop(
                    ctx, const OpcionEmparejar(false, ProveedorIA.anthropic)),
              ),
              const SizedBox(height: 10),
              _Opcion(
                icono: Icons.auto_awesome,
                color: Colors.teal,
                titulo: 'Inteligencia artificial',
                detalle: 'Entiende abreviaturas y nombres del proveedor que '
                    'no se parecen a los tuyos.\n'
                    'Cuesta $costoTxt y necesita internet.',
                onTap: () =>
                    Navigator.pop(ctx, OpcionEmparejar(true, proveedor)),
              ),

              const SizedBox(height: 14),
              // El proveedor solo importa si elige IA; se deja abajo para no
              // estorbar a quien va a usar el algoritmo local.
              Row(children: [
                const Text('Proveedor de IA:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<ProveedorIA>(
                    value: proveedor,
                    isExpanded: true,
                    isDense: true,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: [
                      for (final p in ProveedorIA.values)
                        DropdownMenuItem(value: p, child: Text(p.etiqueta)),
                    ],
                    onChanged: (v) => setD(() => proveedor = v ?? proveedor),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Elijas lo que elijas, después puedes revisar y corregir '
                'cada línea a mano antes de registrar la compra.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );
}

class _Opcion extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  const _Opcion({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 3),
                  Text(detalle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
