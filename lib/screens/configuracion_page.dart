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

  List<Usuario> _usuarios = [];
  String? _usuarioSel; // usuario cuya config se está editando

  static const _seps = {';': 'Punto y coma  ( ; )', ',': 'Coma  ( , )',
    '\t': 'Tabulación'};
  static const _decs = {',': 'Coma  ( , )', '.': 'Punto  ( . )'};

  @override
  void initState() {
    super.initState();
    _usuarioSel = Supabase.instance.client.auth.currentUser?.id;
    _init();
  }

  Future<void> _init() async {
    final roles = await InventarioService.misRoles();
    _esAdmin = roles.contains(Roles.admin);
    if (_esAdmin) {
      try { _usuarios = await InventarioService.listarUsuarios(); } catch (_) {}
    }
    await _cargarConfigDe(_usuarioSel);
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarConfigDe(String? uid) async {
    if (uid == null) return;
    final (csv, dec) = await Ajustes.configDe(uid);
    if (mounted) setState(() { _csv = csv; _dec = dec; });
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
          if (_esAdmin && _usuarios.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _usuarioSel,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Usuario', border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person)),
              items: _usuarios.map((u) => DropdownMenuItem(
                  value: u.id,
                  child: Text(u.email ?? u.nombre ?? u.id,
                      overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) {
                setState(() => _usuarioSel = v);
                _cargarConfigDe(v);
              },
            ),
            const SizedBox(height: 16),
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
