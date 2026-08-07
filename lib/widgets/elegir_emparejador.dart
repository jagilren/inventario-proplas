import 'package:flutter/material.dart';
import '../util/emparejador_ia.dart';

/// Qué eligió el usuario para emparejar este archivo.
class OpcionEmparejar {
  final bool usarIA;
  final ProveedorIA proveedor;
  final String? modelo; // null = el que tenga configurado el servidor
  const OpcionEmparejar(this.usarIA, this.proveedor, this.modelo);
}

/// Pregunta, al subir el archivo, si empareja con el algoritmo local o con
/// IA — y con cuál modelo.
///
/// Se pregunta CADA VEZ en vez de dejar un interruptor pegado: la opción de
/// IA cuesta plata, y un interruptor que quedó prendido gasta sin que nadie
/// lo note. Aquí el costo estimado del modelo elegido está a la vista al
/// momento de decidir.
Future<OpcionEmparejar?> elegirEmparejador(
  BuildContext context, {
  required int lineas,
}) {
  var proveedor = ProveedorIA.anthropic;
  var modelo = modelosPorProveedor[proveedor]!.first;

  String plata(double v) =>
      v < 0.01 ? 'menos de US\$0,01' : 'US\$${v.toStringAsFixed(2)}';

  return showDialog<OpcionEmparejar>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final modelos = modelosPorProveedor[proveedor]!;
        return AlertDialog(
          icon: const Icon(Icons.auto_awesome, color: Colors.teal, size: 40),
          title: const Text('¿Cómo emparejo los artículos?'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
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
                    titulo: 'Algoritmo local  ·  gratis',
                    detalle: 'Instantáneo y funciona sin internet.\n'
                        'Acierta con los nombres parecidos al catálogo, pero '
                        'deja sin emparejar los muy abreviados.',
                    onTap: () => Navigator.pop(ctx,
                        const OpcionEmparejar(false, ProveedorIA.anthropic, null)),
                  ),
                  const SizedBox(height: 10),
                  _Opcion(
                    icono: Icons.auto_awesome,
                    color: Colors.teal,
                    titulo:
                        'Inteligencia artificial  ·  ${plata(modelo.costo(lineas))}',
                    detalle: 'Entiende abreviaturas y nombres del proveedor '
                        'que no se parecen a los tuyos.\n'
                        'Usará ${modelo.etiqueta}. Necesita internet.',
                    onTap: () => Navigator.pop(
                        ctx, OpcionEmparejar(true, proveedor, modelo.id)),
                  ),

                  const Divider(height: 26),
                  const Text('Ajustes de la IA',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 8),

                  Row(children: [
                    const SizedBox(width: 74, child: Text('Proveedor',
                        style: TextStyle(fontSize: 12.5))),
                    Expanded(
                      child: DropdownButton<ProveedorIA>(
                        value: proveedor,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final p in ProveedorIA.values)
                            DropdownMenuItem(
                                value: p, child: Text(p.etiqueta)),
                        ],
                        onChanged: (v) => setD(() {
                          proveedor = v ?? proveedor;
                          // Cada proveedor tiene sus propios modelos: al
                          // cambiar, el elegido antes ya no aplica.
                          modelo = modelosPorProveedor[proveedor]!.first;
                        }),
                      ),
                    ),
                  ]),

                  Row(children: [
                    const SizedBox(width: 74, child: Text('Modelo',
                        style: TextStyle(fontSize: 12.5))),
                    Expanded(
                      child: DropdownButton<ModeloIA>(
                        value: modelo,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final m in modelos)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                '${m.etiqueta} · ${plata(m.costo(lineas))}'
                                '${m.nota.isEmpty ? '' : '  (${m.nota})'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setD(() => modelo = v ?? modelo),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 10),
                  const Text(
                    'El costo es una estimación para comparar, no una '
                    'factura. Elijas lo que elijas, después puedes revisar y '
                    'corregir cada línea a mano antes de registrar la compra.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
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
