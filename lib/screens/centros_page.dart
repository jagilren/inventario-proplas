import 'package:flutter/material.dart';
import '../data.dart';

class CentrosPage extends StatefulWidget {
  const CentrosPage({super.key});
  @override
  State<CentrosPage> createState() => _CentrosPageState();
}

class _CentrosPageState extends State<CentrosPage> {
  late Future<List<CentroCosto>> _future;
  final _busca = TextEditingController();

  /// El filtro es LOCAL sobre la lista ya cargada: se siente instantáneo y no
  /// vuelve a consultar el servidor con cada tecla.
  String _q = '';

  @override
  void initState() {
    super.initState();
    _future = InventarioService.centrosTodos();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _recargar() => setState(() {
        _future = InventarioService.centrosTodos();
      });

  static String _sinTildes(String s) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = con.indexOf(ch);
      b.write(i >= 0 ? sin[i] : ch);
    }
    return b.toString();
  }

  /// Busca en código, descripción y cliente a la vez, con las palabras en
  /// cualquier orden y sin importar tildes — igual que el resto de la app.
  List<CentroCosto> _filtrar(List<CentroCosto> todos) {
    final palabras = _sinTildes(_q).split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty).toList();
    if (palabras.isEmpty) return todos;
    return todos.where((c) {
      final texto = _sinTildes(
          [c.codigo, c.descripcion, c.cliente].where((e) => e != null).join(' '));
      return palabras.every(texto.contains);
    }).toList();
  }

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
          final todos = snap.data ?? [];
          final centros = _filtrar(todos);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  controller: _busca,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar por código, descripción o cliente…',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _busca.clear();
                              setState(() => _q = '');
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _q.isEmpty
                        ? '${todos.length} centros'
                        : '${centros.length} de ${todos.length}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ),
              ),
              Expanded(
                child: centros.isEmpty
                    ? const Center(child: Text('Sin coincidencias'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: centros.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = centros[i];
                          return ListTile(
                            leading: Icon(Icons.account_tree,
                                color: c.activo ? null : Colors.grey),
                            title: Text(
                                c.activo
                                    ? c.codigo
                                    : '${c.codigo}  (inactivo)',
                                style: c.activo
                                    ? null
                                    : const TextStyle(color: Colors.grey)),
                            subtitle: Text([c.descripcion, c.cliente]
                                .where((e) => e != null && e.isNotEmpty)
                                .join(' · ')),
                            trailing: const Icon(Icons.edit, size: 20),
                            onTap: () => _editar(c),
                          );
                        },
                      ),
              ),
            ],
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
          if (widget.centro != null)
            TextButton.icon(
              onPressed: _guardando
                  ? null
                  : (widget.centro!.activo ? _eliminar : _reactivar),
              icon: Icon(widget.centro!.activo ? Icons.delete : Icons.check_circle,
                  color: widget.centro!.activo ? Colors.red : Colors.green),
              label: Text(
                  widget.centro!.activo ? 'Desactivar centro' : 'Reactivar centro',
                  style: TextStyle(
                      color: widget.centro!.activo ? Colors.red : Colors.green)),
            ),
        ],
      ),
    );
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar centro de costo'),
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
      await InventarioService.eliminarCentro(widget.centro!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _reactivar() async {
    setState(() => _guardando = true);
    try {
      await InventarioService.reactivarCentro(widget.centro!.id);
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
