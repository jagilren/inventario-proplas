import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../reportes.dart';

final _f = DateFormat('dd/MM/yyyy');

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});
  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
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

  Future<void> _pick(bool desde) async {
    final d = await showDatePicker(
      context: context,
      initialDate: desde ? _desde : _hasta,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => desde ? _desde = d : _hasta = d);
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informes'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2), text: 'Inventario'),
              Tab(icon: Icon(Icons.recycling), text: 'Aprovechamientos'),
            ],
          ),
        ),
        body: Column(
          children: [
            _rangoFechas(),
            Expanded(
              child: TabBarView(
                children: [
                  _tabInventario(),
                  _tabAprovechamientos(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Selector de rango de fechas (compartido; aplica a los informes por fecha).
  Widget _rangoFechas() => Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.date_range, size: 20),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(
                  onPressed: () => _pick(true),
                  child: Text('Desde\n${_f.format(_desde)}',
                      textAlign: TextAlign.center))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(
                  onPressed: () => _pick(false),
                  child: Text('Hasta\n${_f.format(_hasta)}',
                      textAlign: TextAlign.center))),
            ],
          ),
        ),
      );

  /// Pestaña 1: informes del inventario oficial.
  Widget _tabInventario() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _reporte('existencias', 'Existencias valorizadas',
              'Inventario actual por elemento y bodega, con valorización.',
              Icons.inventory_2, () => Reportes.existenciasValorizadas()),
          _reporte('movimientos', 'Movimientos por fecha',
              'Entradas, salidas, traslados y ajustes del rango elegido.',
              Icons.swap_vert, () => Reportes.movimientos(_desde, _hasta)),
          _reporte('consumo', 'Consumo por centro de costo',
              'Salidas del rango agrupables por centro de costo.',
              Icons.account_tree, () => Reportes.consumoPorCentro(_desde, _hasta)),
          _reporte('minimo', 'Elementos bajo mínimo',
              'Lo que hay que reponer (existencia bajo el mínimo).',
              Icons.warning_amber, () => Reportes.bajoMinimo()),
        ],
      );

  /// Pestaña 2: informes de aprovechamientos (trozos/tramos a $0).
  Widget _tabAprovechamientos() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _reporte('aprov_existencias', 'Existencias actuales',
              'Tramos disponibles ahora (con saldo), por elemento y bodega. '
              'No usa fechas.',
              Icons.inventory_2, () => Reportes.existenciasAprovechamientos()),
          _reporte('aprov_movimientos', 'Movimientos por fecha',
              'Entradas (tramos creados) y salidas (consumo) del rango elegido.',
              Icons.swap_vert,
              () => Reportes.movimientosAprovechamientos(_desde, _hasta)),
        ],
      );

  Widget _reporte(String id, String titulo, String desc, IconData icono,
      Future<void> Function() fn) {
    final generando = _generando == id;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ListTile(
        leading: Icon(icono, color: Theme.of(context).colorScheme.primary),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(desc),
        trailing: generando
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
        onTap: _generando != null ? null : () => _descargar(id, fn),
      ),
    );
  }
}
