import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ajustes.dart';
import '../data.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});
  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  String _csv = Ajustes.csvSep;
  String _dec = Ajustes.decSep;
  bool _guardando = false;
  bool _esAdmin = false;
  bool _cargando = true;

  String? _usuarioSel;    // id del usuario cuya config se edita
  String _usuarioLabel = 'Mi configuración';

  static const _seps = {';': 'Punto y coma  ( ; )', ',': 'Coma  ( , )',
    '\t': 'Tabulación'};
  static const _decs = {',': 'Coma  ( , )', '.': 'Punto  ( . )'};

  @override
  void initState() {
    super.initState();
    final u = Supabase.instance.client.auth.currentUser;
    _usuarioSel = u?.id;
    _usuarioLabel = '${u?.email ?? ''}  (yo)';
    _init();
  }

  Future<void> _init() async {
    final roles = await InventarioService.misRoles();
    _esAdmin = roles.contains(Roles.admin);
    await _cargarConfigDe(_usuarioSel);
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarConfigDe(String? uid) async {
    if (uid == null) return;
    final (csv, dec) = await Ajustes.configDe(uid);
    if (mounted) setState(() { _csv = csv; _dec = dec; });
  }

  Future<void> _elegirUsuario() async {
    final sel = await showModalBottomSheet<Usuario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorUsuario(),
    );
    if (sel != null) {
      final propio = sel.id == Supabase.instance.client.auth.currentUser?.id;
      setState(() {
        _usuarioSel = sel.id;
        _usuarioLabel = (sel.email ?? sel.nombre ?? sel.id) + (propio ? '  (yo)' : '');
      });
      await _cargarConfigDe(sel.id);
    }
  }

  bool get _conflicto => _csv == _dec;

  Future<void> _guardar() async {
    if (_conflicto || _usuarioSel == null) return;
    setState(() => _guardando = true);
    try {
      await Ajustes.guardar(_csv, _dec, paraUsuario: _usuarioSel);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Configuración guardada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Exportación de informes (CSV)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(_esAdmin
              ? 'Como administrador, puedes ajustar la configuración de cualquier '
                  'usuario. Cada quien descarga sus informes con la suya.'
              : 'Ajusta el formato para que Excel abra bien tus archivos. En '
                  'Colombia lo normal es «;» y decimales con «,».',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 18),
          if (_esAdmin) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_search),
                title: Text(_usuarioLabel),
                subtitle: const Text('Toca para elegir el usuario'),
                trailing: const Icon(Icons.search),
                onTap: _elegirUsuario,
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _csv,
            decoration: const InputDecoration(
                labelText: 'Separador de columnas', border: OutlineInputBorder()),
            items: _seps.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _csv = v ?? ';'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _dec,
            decoration: const InputDecoration(
                labelText: 'Separador de decimales', border: OutlineInputBorder()),
            items: _decs.entries.map((e) => DropdownMenuItem(
                value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _dec = v ?? ','),
          ),
          if (_conflicto) ...[
            const SizedBox(height: 12),
            const Text('El separador de columnas y el de decimales no pueden '
                'ser el mismo (se confundirían los datos).',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Ejemplo de una fila:\n'
                  'Tornillo${_csv == '\t' ? '⇥' : _csv} 12 UND'
                  '${_csv == '\t' ? '⇥' : _csv} 4500${_dec}50',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: (_guardando || _conflicto) ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar configuración'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Buscador de usuarios (servidor, por correo/nombre).
class _BuscadorUsuario extends StatefulWidget {
  const _BuscadorUsuario();
  @override
  State<_BuscadorUsuario> createState() => _BuscadorUsuarioState();
}

class _BuscadorUsuarioState extends State<_BuscadorUsuario> {
  final _ctrl = TextEditingController();
  List<Usuario> _items = [];

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    final r = await InventarioService.buscarUsuarios(q);
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
                  hintText: 'Buscar usuario por correo o nombre…',
                  prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final u = _items[i];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(u.email ?? u.nombre ?? u.id),
                  subtitle: u.nombre != null && u.email != null
                      ? Text(u.nombre!) : null,
                  onTap: () => Navigator.pop(context, u),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
