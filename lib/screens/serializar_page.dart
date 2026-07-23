import 'package:flutter/material.dart';
import '../data.dart';

/// Convierte un elemento a serializado: se registran los seriales de las
/// unidades que ya tiene en stock (uno por unidad, con su bodega y costo).
class SerializarPage extends StatefulWidget {
  final Elemento elemento;
  const SerializarPage({super.key, required this.elemento});
  @override
  State<SerializarPage> createState() => _SerializarPageState();
}

class _SerializarPageState extends State<SerializarPage> {
  List<Bodega> _bodegas = [];
  Bodega? _bodega;
  final _serial = TextEditingController();
  final _costo = TextEditingController();
  final List<Map<String, dynamic>> _items = []; // {bodega_id, bodega, serial, costo}
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) setState(() { _bodegas = b; if (b.length == 1) _bodega = b.first; });
    });
  }

  void _agregar() {
    final s = _serial.text.trim();
    final c = num.tryParse(_costo.text.replaceAll(',', '.')) ?? 0;
    if (_bodega == null || s.isEmpty) return;
    if (_items.any((i) => i['serial'] == s)) return;
    setState(() {
      _items.add({'bodega_id': _bodega!.id, 'bodega': _bodega!.nombre,
        'serial': s, 'costo': c});
      _serial.clear();
    });
  }

  Future<void> _guardar() async {
    if (_items.isEmpty) return;
    setState(() => _guardando = true);
    try {
      await InventarioService.serializarElemento(widget.elemento.id,
          _items.map((i) => {'bodega_id': i['bodega_id'], 'serial': i['serial'],
              'costo': i['costo']}).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Elemento serializado')));
      Navigator.pop(context, true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Serializar elemento')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.elemento.nombre,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Existencia actual: ${widget.elemento.existencia}. '
                'Agrega un serial por cada unidad.',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),
            DropdownButtonFormField<Bodega>(
              initialValue: _bodega, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bodega',
                  border: OutlineInputBorder(), prefixIcon: Icon(Icons.warehouse)),
              items: _bodegas.map((b) => DropdownMenuItem(value: b,
                  child: Text(b.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _bodega = v),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: _serial,
                  onSubmitted: (_) => _agregar(),
                  decoration: const InputDecoration(labelText: 'Serial',
                      border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _costo,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Costo',
                      border: OutlineInputBorder()))),
              IconButton(iconSize: 32, icon: const Icon(Icons.add_circle),
                  onPressed: _agregar),
            ]),
          ]),
        ),
        Expanded(
          child: ListView(children: _items.map((i) => ListTile(
            dense: true,
            leading: const Icon(Icons.tag),
            title: Text(i['serial']),
            subtitle: Text('${i['bodega']} · \$${i['costo']}'),
            trailing: IconButton(icon: const Icon(Icons.delete, size: 20),
                onPressed: () => setState(() => _items.remove(i))),
          )).toList()),
        ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(height: 50, child: FilledButton.icon(
            onPressed: (_guardando || _items.isEmpty) ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text('Serializar (${_items.length} seriales)'),
          )),
        )),
      ]),
    );
  }
}
