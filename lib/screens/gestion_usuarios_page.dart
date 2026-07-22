import 'package:flutter/material.dart';
import '../data.dart';

class GestionUsuariosPage extends StatefulWidget {
  const GestionUsuariosPage({super.key});
  @override
  State<GestionUsuariosPage> createState() => _GestionUsuariosPageState();
}

class _GestionUsuariosPageState extends State<GestionUsuariosPage> {
  late Future<List<Usuario>> _future;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.listarUsuarios();
  }

  void _recargar() => setState(() {
        _future = InventarioService.listarUsuarios();
      });

  Future<void> _toggleRol(Usuario u, String rol, bool activar) async {
    try {
      if (activar) {
        await InventarioService.asignarRol(u.id, rol);
      } else {
        await InventarioService.quitarRol(u.id, rol);
      }
      _recargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _crearUsuario() async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NuevoUsuarioForm(),
    );
    if (creado == true) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearUsuario,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
      ),
      body: FutureBuilder<List<Usuario>>(
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
          final usuarios = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: usuarios.map((u) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: ExpansionTile(
                leading: const Icon(Icons.person),
                title: Text(u.email ?? u.nombre ?? '—'),
                subtitle: Text(u.roles.isEmpty
                    ? 'Sin roles'
                    : u.roles.map(Roles.etiqueta).join(', ')),
                children: Roles.todos.map((rol) => SwitchListTile(
                  dense: true,
                  title: Text(Roles.etiqueta(rol)),
                  value: u.roles.contains(rol),
                  onChanged: (v) => _toggleRol(u, rol, v),
                )).toList(),
              ),
            )).toList(),
          );
        },
      ),
    );
  }
}

class _NuevoUsuarioForm extends StatefulWidget {
  const _NuevoUsuarioForm();
  @override
  State<_NuevoUsuarioForm> createState() => _NuevoUsuarioFormState();
}

class _NuevoUsuarioFormState extends State<_NuevoUsuarioForm> {
  final _email = TextEditingController();
  final _nombre = TextEditingController();
  final _pass = TextEditingController();
  final Set<String> _roles = {};
  bool _guardando = false;

  Future<void> _crear() async {
    if (_email.text.trim().isEmpty || _pass.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Correo válido y contraseña de 6+ caracteres')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await InventarioService.crearUsuario(
        email: _email.text.trim(),
        password: _pass.text,
        nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
        roles: _roles.toList(),
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
          const Text('Nuevo usuario',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo',
                border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _nombre,
            decoration: const InputDecoration(labelText: 'Nombre (opcional)',
                border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _pass, obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña',
                border: OutlineInputBorder())),
          const SizedBox(height: 14),
          const Align(alignment: Alignment.centerLeft,
              child: Text('Roles:', style: TextStyle(fontWeight: FontWeight.bold))),
          ...Roles.todos.map((rol) => CheckboxListTile(
            dense: true,
            title: Text(Roles.etiqueta(rol)),
            value: _roles.contains(rol),
            onChanged: (v) => setState(() =>
                v == true ? _roles.add(rol) : _roles.remove(rol)),
          )),
          const SizedBox(height: 12),
          SizedBox(height: 48, child: FilledButton.icon(
            onPressed: _guardando ? null : _crear,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Crear usuario'),
          )),
        ],
      ),
    );
  }
}
