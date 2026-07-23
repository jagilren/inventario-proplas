import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'kardex_page.dart';

final _qty = NumberFormat.decimalPattern('es_CO');

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});
  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  late Future<List<Elemento>> _bajoMin;
  late Future<List<Elemento>> _costoCero;

  @override
  void initState() {
    super.initState();
    _recargar();
    InventarioService.revision.addListener(_recargar);
  }

  void _recargar() {
    if (mounted) {
      setState(() {
        _bajoMin = InventarioService.bajoMinimo();
        _costoCero = InventarioService.costoCero();
      });
    }
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_recargar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.warning_amber), text: 'Stock mínimo'),
              Tab(icon: Icon(Icons.money_off), text: 'Costo 0'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Lista(
                  future: _bajoMin,
                  vacio: 'Ningún elemento bajo el mínimo',
                  icono: Icons.warning_amber,
                  color: Colors.orange,
                  subtitulo: (e) => 'Existencia ${_qty.format(e.existencia)} '
                      '· mínimo ${_qty.format(e.stockMinimo)} ${e.unidad}',
                ),
                _Lista(
                  future: _costoCero,
                  vacio: 'Sin elementos con existencia a costo 0',
                  icono: Icons.money_off,
                  color: Colors.red,
                  subtitulo: (e) => 'Existencia ${_qty.format(e.existencia)} '
                      '${e.unidad} · sin costo asociado',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  final Future<List<Elemento>> future;
  final String vacio;
  final IconData icono;
  final Color color;
  final String Function(Elemento) subtitulo;
  const _Lista({
    required this.future,
    required this.vacio,
    required this.icono,
    required this.color,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Elemento>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 8),
                Text(vacio),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = items[i];
            return ListTile(
              leading: Icon(icono, color: color),
              title: Text(e.nombre),
              subtitle: Text(subtitulo(e)),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => KardexPage(elemento: e))),
            );
          },
        );
      },
    );
  }
}
