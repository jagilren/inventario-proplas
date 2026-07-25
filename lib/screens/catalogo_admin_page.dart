import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'editar_elemento_page.dart';

final _qty = NumberFormat.decimalPattern('es_CO');

/// CRUD total del catálogo de elementos (solo admin). Sin filtros: muestra
/// activos, inactivos, de aprovechamiento y serializados.
class CatalogoAdminPage extends StatefulWidget {
  const CatalogoAdminPage({super.key});
  @override
  State<CatalogoAdminPage> createState() => _CatalogoAdminPageState();
}

class _CatalogoAdminPageState extends State<CatalogoAdminPage> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String q) async {
    setState(() => _cargando = true);
    try {
      final r = await InventarioService.catalogoCompleto(q);
      if (mounted) setState(() => _items = r);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => const EditarElementoPage(modoAdmin: true)));
    if (ok == true) _buscar(_ctrl.text);
  }

  Future<void> _editar(Elemento e) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => EditarElementoPage(elemento: e, modoAdmin: true)));
    if (ok == true) _buscar(_ctrl.text);
  }

  Future<void> _toggleActivo(Elemento e) async {
    try {
      await InventarioService.actualizarElemento(e.id, {'activo': !e.activo});
      _msg(e.activo ? '✓ Desactivado' : '✓ Activado');
      _buscar(_ctrl.text);
    } catch (err) {
      _msg('Error: $err');
    }
  }

  Future<void> _eliminar(Elemento e) async {
    final tiene = await InventarioService.elementoTieneHistorial(e.id);
    if (!mounted) return;
    if (tiene) {
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: Colors.orange, size: 38),
        title: const Text('No se puede borrar'),
        content: Text('"${e.nombre}" tiene historial (movimientos, tramos o '
            'seriales). Para no perder trazabilidad, no se borra: '
            'usa "Desactivar".'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'))],
      ));
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 38),
      title: const Text('Borrar definitivamente'),
      content: Text('"${e.nombre}" no tiene historial. '
          '¿Eliminarlo por completo? Esta acción no se puede deshacer.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar')),
      ],
    ));
    if (ok != true) return;
    try {
      await InventarioService.borrarElementoDefinitivo(e.id);
      _msg('✓ Elemento borrado');
      _buscar(_ctrl.text);
    } catch (err) {
      _msg('Error: ${err.toString().replaceAll('PostgrestException(message: ', '')}');
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
      appBar: AppBar(title: const Text('Catálogo completo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: 'Buscar en TODO el catálogo (sin filtros)…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _ctrl.clear(); _buscar(''); }),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_items.length} elementos (incluye inactivos y '
                  'de aprovechamiento)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
          if (_cargando) const LinearProgressIndicator(),
          Expanded(
            child: _items.isEmpty && !_cargando
                ? const Center(child: Text('Sin resultados'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      return ListTile(
                        title: Text(e.nombre,
                            style: TextStyle(
                                color: e.activo ? null : Colors.grey,
                                decoration: e.activo
                                    ? null : TextDecoration.lineThrough)),
                        subtitle: Wrap(spacing: 6, runSpacing: 2, children: [
                          Text('${_qty.format(e.existencia)} ${e.unidad}',
                              style: const TextStyle(fontSize: 12)),
                          if (!e.activo) _chip('INACTIVO', Colors.grey),
                          if (e.esAprovechamiento) _chip('APROVECH.', Colors.brown),
                          if (e.serializado) _chip('SERIAL', Colors.indigo),
                        ]),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'editar') _editar(e);
                            if (v == 'activo') _toggleActivo(e);
                            if (v == 'eliminar') _eliminar(e);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'editar',
                                child: ListTile(leading: Icon(Icons.edit),
                                    title: Text('Editar'), dense: true)),
                            PopupMenuItem(value: 'activo',
                                child: ListTile(
                                    leading: Icon(e.activo
                                        ? Icons.visibility_off : Icons.visibility),
                                    title: Text(e.activo ? 'Desactivar' : 'Activar'),
                                    dense: true)),
                            const PopupMenuItem(value: 'eliminar',
                                child: ListTile(
                                    leading: Icon(Icons.delete_forever, color: Colors.red),
                                    title: Text('Eliminar'), dense: true)),
                          ],
                        ),
                        onTap: () => _editar(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10, color: c,
            fontWeight: FontWeight.bold)),
      );
}
