import 'package:flutter/material.dart';
import '../data.dart';

class BodegasPage extends StatefulWidget {
  const BodegasPage({super.key});
  @override
  State<BodegasPage> createState() => _BodegasPageState();
}

class _BodegasPageState extends State<BodegasPage> {
  late Future<List<Bodega>> _future;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.bodegas();
  }

  void _recargar() => setState(() => _future = InventarioService.bodegas());

  Future<void> _editar([Bodega? b]) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BodegaForm(bodega: b),
    );
    if (guardado == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bodegas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: FutureBuilder<List<Bodega>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final bodegas = snap.data ?? [];
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: bodegas.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = bodegas[i];
              return ListTile(
                leading: const Icon(Icons.warehouse),
                title: Text(b.nombre),
                subtitle: b.codigo == null ? null : Text(b.codigo!),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: () => _editar(b),
              );
            },
          );
        },
      ),
    );
  }
}

class _BodegaForm extends StatefulWidget {
  final Bodega? bodega;
  const _BodegaForm({this.bodega});
  @override
  State<_BodegaForm> createState() => _BodegaFormState();
}

class _BodegaFormState extends State<_BodegaForm> {
  late final TextEditingController _nombre;
  late final TextEditingController _codigo;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.bodega?.nombre ?? '');
    _codigo = TextEditingController(text: widget.bodega?.codigo ?? '');
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await InventarioService.guardarBodega(
        id: widget.bodega?.id,
        nombre: _nombre.text.trim(),
        codigo: _codigo.text.trim().isEmpty ? null : _codigo.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.bodega == null ? 'Nueva bodega' : 'Editar bodega',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre',
                border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _codigo,
            decoration: const InputDecoration(labelText: 'Código (opcional)',
                border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar'),
          )),
          if (widget.bodega != null)
            TextButton.icon(
              onPressed: _guardando ? null : _eliminar,
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('Desactivar bodega',
                  style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar bodega'),
        content: const Text('Se dará de baja (desaparece de las listas). '
            'El historial de movimientos se conserva. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desactivar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await InventarioService.eliminarBodega(widget.bodega!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _guardando = false);
      }
    }
  }
}
