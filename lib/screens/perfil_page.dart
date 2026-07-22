import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import 'gestion_usuarios_page.dart';
import 'centros_page.dart';
import 'historial_page.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});
  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  Set<String> _roles = {};

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() => _roles = r);
    });
  }

  bool get _admin => _roles.contains(Roles.admin);
  bool get _coord => _roles.contains(Roles.coordinador);

  Future<void> _cambiarPassword() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva contraseña'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Mínimo 6 caracteres',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cambiar')),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.length < 6) {
      _msg('La contraseña debe tener al menos 6 caracteres');
      return;
    }
    try {
      await InventarioService.cambiarPassword(ctrl.text);
      _msg('✓ Contraseña actualizada');
    } catch (e) {
      _msg('Error: $e');
    }
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  /// Cierra sesión y vuelve al inicio. Sin el popUntil, esta pantalla
  /// quedaba encima tapando el login y parecía que el botón no hacía nada.
  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres salir?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (confirmar != true) return;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.person, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Correo'),
            subtitle: Text(email),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Mis roles'),
            subtitle: _roles.isEmpty
                ? const Text('Sin roles asignados')
                : Wrap(
                    spacing: 6,
                    children: _roles
                        .map((r) => Chip(
                              label: Text(Roles.etiqueta(r),
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
          ),
          const Divider(),
          if (_admin)
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Gestión de usuarios'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GestionUsuariosPage())),
            ),
          if (_admin || _coord)
            ListTile(
              leading: const Icon(Icons.account_tree),
              title: const Text('Centros de costo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CentrosPage())),
            ),
          if (_admin || _coord)
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Auditoría de cambios'),
              subtitle: const Text('Quién cambió qué y cuándo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const HistorialPage(
                      titulo: 'Auditoría de cambios'))),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Cambiar contraseña'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _cambiarPassword,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar sesión',
                style: TextStyle(color: Colors.red)),
            onTap: _cerrarSesion,
          ),
        ],
      ),
    );
  }
}
