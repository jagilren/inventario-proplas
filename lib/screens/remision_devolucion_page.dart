import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../reportes.dart';
import 'escaner_page.dart';

final _qty = NumberFormat.decimalPattern('es_CO');

/// Un renglón de la remisión (temporal, en memoria).
class _ItemRemision {
  final Elemento elemento;
  num cantidad;
  _ItemRemision(this.elemento, this.cantidad);
}

/// Utilidad para ARMAR una remisión de devolución: se van agregando
/// elementos (por búsqueda o escaneo) con su cantidad a una lista temporal
/// editable, y al final se genera un CSV descargable. Ese mismo CSV se puede
/// importar luego con la utilidad de "Devoluciones".
///
/// Por ahora NO se guarda en la base (lista en memoria); a futuro se podría
/// persistir en una tabla de "remisiones".
class RemisionDevolucionPage extends StatefulWidget {
  const RemisionDevolucionPage({super.key});
  @override
  State<RemisionDevolucionPage> createState() => _RemisionDevolucionPageState();
}

class _RemisionDevolucionPageState extends State<RemisionDevolucionPage> {
  final List<_ItemRemision> _items = [];
  bool _generando = false;

  Future<void> _buscar() async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) _agregar(sel);
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    final elem = await InventarioService.porCodigoBarras(codigo);
    if (!mounted) return;
    if (elem != null) {
      _agregar(elem);
    } else {
      _msg('Código $codigo sin asociar a ningún elemento.');
    }
  }

  Future<void> _agregar(Elemento e) async {
    // Si ya está en la lista, se edita la cantidad en vez de duplicar.
    final idx = _items.indexWhere((it) => it.elemento.id == e.id);
    if (idx >= 0) {
      _msg('Ese elemento ya está en la lista; edita su cantidad.');
      _editarCantidad(idx);
      return;
    }
    final cant = await _pedirCantidad(e, null);
    if (cant != null && mounted) {
      setState(() => _items.add(_ItemRemision(e, cant)));
    }
  }

  Future<void> _editarCantidad(int idx) async {
    final it = _items[idx];
    final cant = await _pedirCantidad(it.elemento, it.cantidad);
    if (cant != null && mounted) setState(() => it.cantidad = cant);
  }

  /// Diálogo para capturar/editar la cantidad. Devuelve null si cancela.
  Future<num?> _pedirCantidad(Elemento e, num? actual) async {
    final ctrl = TextEditingController(text: actual?.toString() ?? '');
    return showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.nombre),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad (${e.unidad})',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
            if (c != null && c > 0) Navigator.pop(ctx, c);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
              if (c == null || c <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Cantidad inválida')));
                return;
              }
              Navigator.pop(ctx, c);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _eliminar(int idx) => setState(() => _items.removeAt(idx));

  Future<void> _generarCsv() async {
    if (_items.isEmpty) return;
    setState(() => _generando = true);
    try {
      final filas = <List<dynamic>>[
        ['ELEMENTO', 'CANTIDAD'],
        for (final it in _items) [it.elemento.nombre, it.cantidad],
      ];
      await Reportes.descargarCsv('remision_devolucion', filas);
      _msg('✓ CSV generado. Puedes importarlo en "Devoluciones".');
    } catch (e) {
      _msg('Error al generar: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remisión de devolución')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
                'Agrega elementos con su cantidad y genera el CSV. Ese archivo '
                'se puede cargar luego en "Devoluciones".',
                style: TextStyle(fontSize: 12, color: Color(0xFF1565C0))),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _buscar,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escanear,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear'),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  _items.isEmpty
                      ? 'Sin elementos aún'
                      : '${_items.length} elemento${_items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Usa "Buscar" o "Escanear" para ir agregando elementos '
                        'a la remisión.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                        title: Text(it.elemento.nombre),
                        subtitle: Text('${_qty.format(it.cantidad)} '
                            '${it.elemento.unidad}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: 'Editar cantidad',
                              onPressed: () => _editarCantidad(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              tooltip: 'Quitar',
                              onPressed: () => _eliminar(i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: (_generando || _items.isEmpty) ? null : _generarCsv,
              icon: _generando
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download),
              label: Text('Generar CSV (${_items.length})'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buscador de elementos del inventario oficial (excluye aprovechamiento).
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
                  hintText: 'Buscar elemento…',
                  prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text('Existencia: ${_qty.format(e.existencia)} '
                      '${e.unidad}'),
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
