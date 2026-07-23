import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../util/tiempo.dart';

final _fmt = DateFormat('dd/MM/yyyy HH:mm');

/// Historial de cambios.
/// - Si [tabla] y [registroId] vienen, muestra el historial de ese registro.
/// - Si no, muestra la auditoría global reciente (admin).
class HistorialPage extends StatefulWidget {
  final String? tabla;
  final String? registroId;
  final String titulo;
  const HistorialPage({super.key, this.tabla, this.registroId,
      this.titulo = 'Historial de cambios'});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  late Future<List<Auditoria>> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.tabla != null && widget.registroId != null)
        ? InventarioService.historialRegistro(widget.tabla!, widget.registroId!)
        : InventarioService.auditoriaReciente();
  }

  Color _color(String accion) => switch (accion) {
        'INSERT' => Colors.green,
        'DELETE' => Colors.red,
        _ => Colors.blue,
      };

  IconData _icono(String accion) => switch (accion) {
        'INSERT' => Icons.add_circle_outline,
        'DELETE' => Icons.delete_outline,
        _ => Icons.edit_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: FutureBuilder<List<Auditoria>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
            ));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 44, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('Sin cambios registrados', textAlign: TextAlign.center),
                  SizedBox(height: 6),
                  Text('Los cambios que se hagan de ahora en adelante '
                       'aparecerán aquí.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = items[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _color(a.accion).withValues(alpha: 0.15),
                  child: Icon(_icono(a.accion), color: _color(a.accion), size: 20),
                ),
                title: Text(a.descripcion),
                subtitle: Text([
                  _fmt.format(horaColombia(a.fecha)),
                  if (a.usuarioEmail != null) a.usuarioEmail!,
                  if (widget.tabla == null && a.tabla != null) a.tabla!,
                ].join('  ·  ')),
                isThreeLine: false,
              );
            },
          );
        },
      ),
    );
  }
}
