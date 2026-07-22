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
  late Future<List<Elemento>> _future;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.bajoMinimo();
    InventarioService.revision.addListener(_recargar);
  }

  void _recargar() {
    if (mounted) setState(() => _future = InventarioService.bajoMinimo());
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_recargar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Elemento>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 8),
                Text('Ningún elemento bajo el mínimo'),
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
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: Text(e.nombre),
              subtitle: Text('Existencia ${_qty.format(e.existencia)} '
                  '· mínimo ${_qty.format(e.stockMinimo)} ${e.unidad}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => KardexPage(elemento: e))),
            );
          },
        );
      },
    );
  }
}
