import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _int = NumberFormat.decimalPattern('es_CO');
final _fecha = DateFormat('dd/MM HH:mm');

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Resumen? _resumen;
  List<MovReciente> _movs = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final r = await InventarioService.resumen();
      final m = await InventarioService.ultimosMovimientos();
      if (mounted) setState(() { _resumen = r; _movs = m; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No se pudo cargar el resumen.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    final r = _resumen!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.extent(
            // ancho máximo por tarjeta: en el PC caben más y no se estiran
            maxCrossAxisExtent: 260,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _tile('Valorización total', _money.format(r.valorizacionTotal),
                  Icons.payments, Colors.teal),
              _tile('Elementos', _int.format(r.totalElementos),
                  Icons.inventory_2, Colors.indigo),
              _tile('Bajo mínimo', _int.format(r.bajoMinimo),
                  Icons.warning_amber, r.bajoMinimo > 0 ? Colors.orange : Colors.green),
              _tile('Movimientos', _int.format(r.totalMovimientos),
                  Icons.swap_vert, Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('Últimos movimientos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (_movs.isEmpty)
            const Padding(padding: EdgeInsets.all(16),
                child: Text('Sin movimientos todavía')),
          ..._movs.map((m) {
            final salida = m.tipo == 'salida';
            final color = salida ? Colors.orange
                : (m.tipo == 'ajuste' ? Colors.purple : Colors.green);
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: Icon(salida ? Icons.upload : Icons.download, color: color),
                title: Text(m.elemento, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${m.tipo.toUpperCase()} · ${m.cantidad} ${m.unidad}'
                    '${m.centroCosto != null ? ' · ${m.centroCosto}' : ''}'),
                trailing: Text(_fecha.format(m.fecha),
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _tile(String label, String value, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(child: Text(value,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      );
}
