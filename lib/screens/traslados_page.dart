import 'package:flutter/material.dart';
import '../data.dart';

/// Traslado de stock de una bodega a otra (admin / coordinador).
class TrasladosPage extends StatefulWidget {
  const TrasladosPage({super.key});
  @override
  State<TrasladosPage> createState() => _TrasladosPageState();
}

class _TrasladosPageState extends State<TrasladosPage> {
  Elemento? _elemento;
  Bodega? _origen;
  Bodega? _destino;
  List<Bodega> _bodegas = [];
  List<ExistenciaBodega> _porBodega = [];
  final _cantidad = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) setState(() => _bodegas = b);
    });
  }

  Future<void> _elegirElemento() async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) {
      setState(() => _elemento = sel);
      final b = await InventarioService.existenciasPorBodega(sel.id);
      if (mounted) setState(() => _porBodega = b);
    }
  }

  num _existenciaEn(Bodega? b) {
    if (b == null) return 0;
    for (final x in _porBodega) {
      if (x.bodega == b.nombre) return x.existencia;
    }
    return 0;
  }

  Future<void> _trasladar() async {
    final el = _elemento;
    final cant = num.tryParse(_cantidad.text.replaceAll(',', '.'));
    if (el == null) return _msg('Selecciona un elemento');
    if (_origen == null) return _msg('Selecciona la bodega de origen');
    if (_destino == null) return _msg('Selecciona la bodega de destino');
    if (_origen!.id == _destino!.id) return _msg('Origen y destino no pueden ser iguales');
    if (cant == null || cant <= 0) return _msg('Cantidad inválida');
    if (cant > _existenciaEn(_origen)) {
      return _msg('No hay tanto en la bodega de origen (hay ${_existenciaEn(_origen)})');
    }

    setState(() => _guardando = true);
    try {
      await InventarioService.trasladar(
        elementoId: el.id, cantidad: cant,
        origenId: _origen!.id, destinoId: _destino!.id,
        obs: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
      );
      if (!mounted) return;
      _msg('✓ Traslado registrado');
      final b = await InventarioService.existenciasPorBodega(el.id);
      setState(() {
        _porBodega = b;
        _cantidad.clear(); _obs.clear();
      });
    } catch (e) {
      _msg('Error: ${e.toString().replaceAll('PostgrestException(message: ', '')}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final el = _elemento;
    return Scaffold(
      appBar: AppBar(title: const Text('Traslado entre bodegas')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2),
                title: Text(el?.nombre ?? 'Seleccionar elemento…'),
                subtitle: el == null ? null
                    : Text('Total: ${el.existencia} ${el.unidad}'),
                trailing: const Icon(Icons.search),
                onTap: _elegirElemento,
              ),
            ),
            if (_porBodega.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(spacing: 8, runSpacing: 6, children: _porBodega
                    .map((x) => Chip(
                        avatar: const Icon(Icons.warehouse, size: 16),
                        label: Text('${x.bodega}: ${x.existencia}'),
                        visualDensity: VisualDensity.compact))
                    .toList()),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Bodega>(
              initialValue: _origen,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Desde (origen)', border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.logout)),
              items: _bodegas.map((b) => DropdownMenuItem(value: b,
                  child: Text(b.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _origen = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Bodega>(
              initialValue: _destino,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Hacia (destino)', border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.login)),
              items: _bodegas.map((b) => DropdownMenuItem(value: b,
                  child: Text(b.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _destino = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cantidad,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad${el != null ? ' (${el.unidad})' : ''}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _obs,
              decoration: const InputDecoration(
                  labelText: 'Observación (opcional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _trasladar,
                icon: _guardando
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.swap_horiz),
                label: const Text('Trasladar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuscadorElemento extends StatefulWidget {
  const _BuscadorElemento();
  @override
  State<_BuscadorElemento> createState() => _BuscadorElementoState();
}

class _BuscadorElementoState extends State<_BuscadorElemento> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    final r = await InventarioService.buscar(q);
    if (mounted) setState(() => _items = r);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl, autofocus: true, onChanged: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar…', prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text('Total: ${e.existencia} ${e.unidad}'),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
