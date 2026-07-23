import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Se muestra cuando el usuario llega por el enlace de "Olvidé mi contraseña".
class NuevaPasswordPage extends StatefulWidget {
  final VoidCallback onListo;
  const NuevaPasswordPage({super.key, required this.onListo});
  @override
  State<NuevaPasswordPage> createState() => _NuevaPasswordPageState();
}

class _NuevaPasswordPageState extends State<NuevaPasswordPage> {
  final _pass = TextEditingController();
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (_pass.text.length < 6) {
      setState(() => _error = 'Mínimo 6 caracteres');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _pass.text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Contraseña actualizada')));
        widget.onListo();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_reset, size: 64,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text('Nueva contraseña',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('Escribe la nueva contraseña de tu cuenta.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _guardar(),
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña (mín. 6)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar contraseña'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
