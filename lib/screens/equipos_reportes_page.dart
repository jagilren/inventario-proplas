import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../reportes.dart';
import '../activos_service.dart';

final _f = DateFormat('dd/MM/yyyy');

/// Informes del Módulo de Equipos (sección 9 del plan).
///
/// Familia propia, aparte de los de Inventario y Aprovechamientos: son datos
/// de otra naturaleza. La excepción es el "Valorizado total por bodega", que
/// sí suma los dos mundos — pero sumando totales ya calculados, nunca
/// cruzando las filas crudas de tablas incompatibles.
class EquiposReportesPage extends StatefulWidget {
  const EquiposReportesPage({super.key});
  @override
  State<EquiposReportesPage> createState() => _EquiposReportesPageState();
}

class _EquiposReportesPageState extends State<EquiposReportesPage> {
  late DateTime _desde;
  late DateTime _hasta;
  String? _generando;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, 1); // inicio de mes
    _hasta = hoy;
  }

  Future<void> _pickRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      helpText: 'Rango de fechas del informe',
    );
    if (r != null) setState(() { _desde = r.start; _hasta = r.end; });
  }

  /// El rango arranca en el PRIMER movimiento que existe, no en un 2020 al
  /// azar: así no se deja nada por fuera ni se barren años vacíos.
  Future<void> _desdeElPrincipio() async {
    final primera = await ActivosService.primeraFechaMovimiento();
    if (!mounted) return;
    if (primera == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Todavía no hay movimientos de equipos registrados')));
      return;
    }
    setState(() {
      _desde = DateTime(primera.year, primera.month, primera.day);
      _hasta = DateTime.now();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Rango completo: desde ${_f.format(primera)} hasta hoy'),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _descargar(String id, Future<void> Function() fn) async {
    setState(() => _generando = id);
    try {
      await fn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Informe descargado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _generando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informes de Equipos')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rango de fechas',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  // Wrap: en un teléfono angosto los botones bajan de línea
                  // en vez de apretarse.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickRango,
                        icon: const Icon(Icons.date_range),
                        label: Text(
                            '${_f.format(_desde)}  →  ${_f.format(_hasta)}'),
                      ),
                      TextButton.icon(
                        onPressed: _desdeElPrincipio,
                        icon: const Icon(Icons.all_inclusive),
                        label: const Text('Desde el principio'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'El rango solo aplica al informe de movimientos. Los otros '
                    'dos son una foto del estado actual.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _reporte(
            'eq_movimientos',
            'Movimientos de equipos',
            'Entradas y salidas del rango elegido, con la marca ANULADO '
                'cuando corresponde.',
            Icons.swap_vert,
            () => Reportes.movimientosEquipos(_desde, _hasta),
          ),
          _reporte(
            'eq_valorizacion',
            'Valorización de activos',
            'Foto actual: una fila por equipo con su estado, ubicación y '
                'valor, con fila TOTAL.',
            Icons.attach_money,
            () => Reportes.valorizacionActivos(),
          ),
          _reporte(
            'eq_total_bodega',
            'Valorizado total por bodega',
            'Suma el inventario de piping y los equipos de cada bodega, para '
                'saber cuánto vale todo lo que hay guardado.',
            Icons.warehouse,
            () => Reportes.valorizadoTotalPorBodega(),
          ),
        ],
      ),
    );
  }

  Widget _reporte(String id, String titulo, String detalle, IconData icono,
      Future<void> Function() fn) {
    final generando = _generando == id;
    return Card(
      child: ListTile(
        leading: Icon(icono),
        title: Text(titulo),
        subtitle: Text(detalle),
        isThreeLine: true,
        trailing: generando
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
        onTap: _generando != null ? null : () => _descargar(id, fn),
      ),
    );
  }
}
