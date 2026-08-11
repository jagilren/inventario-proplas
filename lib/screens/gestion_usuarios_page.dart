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

  Future<void> _activar(Usuario u, bool activo) async {
    if (!activo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Inactivar a ${u.email ?? u.nombre ?? 'este usuario'}?'),
          content: const Text(
            'No podrá entrar a hacer nada NI ver nada: ni existencias, ni '
            'costos, ni movimientos.\n\n'
            'Conserva sus roles, así que reactivarlo lo devuelve exactamente '
            'como estaba.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Inactivar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await InventarioService.inactivarUsuario(u.id, activo);
      _recargar();
    } catch (e) {
      _error(e);
    }
  }

  /// Borrar de verdad, solo si no tiene nada atado. Si tiene, se explica por
  /// qué no se puede y se ofrece inactivarlo, que es lo que corresponde.
  Future<void> _borrar(Usuario u) async {
    final quien = u.email ?? u.nombre ?? 'este usuario';
    try {
      final usos = await InventarioService.usosDeUsuario(u.id);
      if (!mounted) return;
      if (usos.movimientos > 0 || usos.imagenes > 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No se puede borrar'),
            content: Text(
              '$quien tiene ${usos.movimientos} movimiento(s) y '
              '${usos.imagenes} imagen(es) a su nombre.\n\n'
              'Borrarlo dejaría esos registros sin autor y se perdería la '
              'trazabilidad. Lo correcto es inactivarlo.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Borrar a $quien?'),
          content: const Text(
            'No tiene movimientos ni imágenes, así que se puede borrar sin '
            'romper nada. Esta acción NO se puede deshacer.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await InventarioService.borrarUsuario(u.id);
      _recargar();
    } catch (e) {
      _error(e);
    }
  }

  void _error(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $e')));
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
              // Los inactivos se ven apagados, para no confundirlos de un
              // vistazo con la gente que sí está trabajando.
              color: u.activo ? null : Colors.grey.shade200,
              child: ExpansionTile(
                leading: Icon(u.activo ? Icons.person : Icons.person_off,
                    color: u.activo ? null : Colors.grey),
                title: Text(
                  u.email ?? u.nombre ?? '—',
                  style: TextStyle(
                    color: u.activo ? null : Colors.grey.shade700,
                    decoration: u.activo ? null : TextDecoration.lineThrough,
                  ),
                ),
                subtitle: Text(
                  u.activo
                      ? (u.roles.isEmpty
                          ? 'Sin roles'
                          : u.roles.map(Roles.etiqueta).join(', '))
                      : 'INACTIVO · no puede entrar ni ver nada'
                          '${u.roles.isEmpty ? '' : ' · conserva: '
                              '${u.roles.map(Roles.etiqueta).join(', ')}'}',
                  style: TextStyle(
                      color: u.activo ? null : Colors.red.shade700,
                      fontWeight: u.activo ? null : FontWeight.w600),
                ),
                children: [
                  SwitchListTile(
                    dense: true,
                    secondary: const Icon(Icons.verified_user),
                    title: const Text('Usuario activo'),
                    subtitle: const Text(
                        'Al inactivarlo pierde el acceso completo, pero '
                        'conserva sus roles'),
                    value: u.activo,
                    onChanged: (v) => _activar(u, v),
                  ),
                  const Divider(height: 1),
                  // Los roles solo tienen sentido tocarlos si está activo:
                  // estando inactivo no surten efecto de todos modos.
                  ...Roles.todos.map((rol) => SwitchListTile(
                        dense: true,
                        title: Text(Roles.etiqueta(rol)),
                        value: u.roles.contains(rol),
                        onChanged: u.activo
                            ? (v) => _toggleRol(u, rol, v)
                            : null,
                      )),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_forever,
                        color: Colors.red.shade700),
                    title: Text('Borrar definitivamente',
                        style: TextStyle(color: Colors.red.shade700)),
                    subtitle: const Text(
                        'Solo si no tiene movimientos ni imágenes'),
                    onTap: () => _borrar(u),
                  ),
                ],
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
