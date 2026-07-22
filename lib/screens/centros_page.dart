import 'package:flutter/material.dart';
import '../data.dart';

class CentrosPage extends StatefulWidget {
  const CentrosPage({super.key});
  @override
  State<CentrosPage> createState() => _CentrosPageState();
}

class _CentrosPageState extends State<CentrosPage> {
  late Future<List<CentroCosto>> _future;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.centrosCosto();
  }

  void _recargar() => setState(() {
        _future = InventarioService.centrosCosto();
      });

  Future<void> _editar([CentroCosto? cc]) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CentroForm(centro: cc),
    );
    if (guardado == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centros de costo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: FutureBuilder<List<CentroCosto>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final centros = snap.data ?? [];
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: centros.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = centros[i];
              return ListTile(
                leading: const Icon(Icons.account_tree),
                title: Text(c.codigo),
                subtitle: Text([c.descripcion, c.cliente]
                    .where((e) => e != null && e.isNotEmpty).join(' · ')),
                trailing: const Icon(Icons.edit, size: 20),
                onTap: () => _editar(c),
              );
            },
          );
        },
      ),
    );
  }
}

class _CentroForm extends StatefulWidget {
  final CentroCosto? centro;
  const _CentroForm({this.centro});
  @override
  State<_CentroForm> createState() => _CentroFormState();
}

class _CentroFormState extends State<_CentroForm> {
  late final TextEditingController _codigo;
  late final TextEditingController _desc;
  late final TextEditingController _cliente;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _codigo = TextEditingController(text: widget.centro?.codigo ?? '');
    _desc = TextEditingController(text: widget.centro?.descripcion ?? '');
    _cliente = TextEditingController(text: widget.centro?.cliente ?? '');
  }

  Future<void> _guardar() async {
    if (_codigo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El código es obligatorio')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await InventarioService.guardarCentro(
        id: widget.centro?.id,
        codigo: _codigo.text.trim(),
        descripcion: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        cliente: _cliente.text.trim().isEmpty ? null : _cliente.text.trim(),
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
          Text(widget.centro == null ? 'Nuevo centro de costo' : 'Editar centro',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: _codigo,
            decoration: const InputDecoration(labelText: 'Código (ej. NP00034)',
                border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _desc,
            decoration: const InputDecoration(labelText: 'Descripción',
                border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _cliente,
            decoration: const InputDecoration(labelText: 'Cliente',
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
        ],
      ),
    );
  }
}
