import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../util/estado_servidor.dart';
import '../config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _cargando = false;
  String? _error;
  FalloEntrada? _fallo;

  Future<void> _entrar() async {
    setState(() { _cargando = true; _error = null; _fallo = null; });

    // Modo prueba: muestra el mensaje pedido sin llamar al servidor. Sirve
    // para revisar los textos sin pausar la base ni apagar el wifi. En
    // producción Config.simularFalloLogin va en null y este bloque no corre.
    final simulado = Config.simularFalloLogin;
    if (simulado != null) {
      final f = switch (simulado) {
        'servidor' => FalloEntrada.servidorNoDisponible,
        'sinInternet' => FalloEntrada.sinInternet,
        'credenciales' => FalloEntrada.credenciales,
        _ => FalloEntrada.desconocido,
      };
      setState(() {
        _fallo = f;
        _error = mensajeFallo(f, detalle: 'Simulación de prueba: $simulado');
        _cargando = false;
      });
      return;
    }

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      // AuthGate cambia solo al detectar la sesión.
    } catch (e) {
      // Antes cualquier fallo del servidor salía como "Error de conexión: ..."
      // con el error crudo de la librería, que no le dice a nadie qué hacer.
      // Lo más importante que hay que distinguir: si la base está pausada por
      // inactividad, el usuario no puede arreglarlo solo — tiene que avisarle
      // al administrador para que la reactive.
      final f = await clasificarFalloEntrada(e);
      if (mounted) {
        setState(() {
          _fallo = f;
          _error = mensajeFallo(f, detalle: e.toString());
        });
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _recuperar() async {
    final ctrl = TextEditingController(text: _email.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Escribe tu correo y te enviaremos un enlace para poner '
              'una contraseña nueva.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'Correo', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar enlace')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        ctrl.text.trim(),
        redirectTo: 'https://inventario-proplas.pages.dev',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✓ Te enviamos un correo con el enlace. Revisa tu '
                'bandeja (y el spam).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
                // Logo de los 10 años de RPCI
                Image.asset(
                  'assets/logo_rpci_10anos.png',
                  height: 140,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 20),
                Icon(Icons.inventory_2, size: 56,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text('Inventario PROPLAS',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Correo',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  onSubmitted: (_) => _entrar(),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  // El servidor caído se muestra en ámbar y no en rojo: no es
                  // un error del usuario, no hay nada que corregir en la
                  // pantalla, y el texto es largo porque explica a quién
                  // avisar.
                  Builder(builder: (_) {
                    final servidor =
                        _fallo == FalloEntrada.servidorNoDisponible;
                    final color =
                        servidor ? Colors.orange.shade900 : Colors.red;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(
                              servidor
                                  ? Icons.cloud_off
                                  : _fallo == FalloEntrada.sinInternet
                                      ? Icons.wifi_off
                                      : Icons.error_outline,
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tituloFallo(_fallo ?? FalloEntrada.desconocido),
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(_error!,
                              style: TextStyle(color: color, fontSize: 13)),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _cargando ? null : _entrar,
                    child: _cargando
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ingresar'),
                  ),
                ),
                TextButton(
                  onPressed: _cargando ? null : _recuperar,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
