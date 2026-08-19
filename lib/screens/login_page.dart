import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _verPass = false;
  bool _recordar = true;

  /// Solo se recuerda el CORREO. La contraseña no se guarda nunca: en un
  /// equipo compartido (que es el caso en bodega) eso sería entregarle la
  /// cuenta al siguiente que se siente.
  static const _claveCorreo = 'login_correo';

  @override
  void initState() {
    super.initState();
    _cargarCorreo();
  }

  Future<void> _cargarCorreo() async {
    final p = await SharedPreferences.getInstance();
    final guardado = p.getString(_claveCorreo);
    if (guardado != null && guardado.isNotEmpty && mounted) {
      setState(() => _email.text = guardado);
    }
  }

  Future<void> _guardarCorreo() async {
    final p = await SharedPreferences.getInstance();
    if (_recordar) {
      await p.setString(_claveCorreo, _email.text.trim());
    } else {
      await p.remove(_claveCorreo);
    }
  }

  Future<void> _entrar() async {
    setState(() { _cargando = true; _error = null; _fallo = null; });

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      await _guardarCorreo();
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
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      // Degradado muy tenue del color de marca hacia el fondo. Da profundidad
      // sin competir con el logo ni restarle legibilidad al aviso de error.
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.primary.withValues(alpha: 0.12), c.surface],
          ),
        ),
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo de los 10 años de RPCI. Antes debajo iba además un
                // ícono de caja: dos elementos gráficos seguidos diciendo lo
                // mismo. Se deja solo el logo y se baja un poco su alto, para
                // hacerle sitio a lo que se agregó abajo.
                Image.asset(
                  'assets/logo_rpci_10anos.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
                Text('Inventario PROPLAS',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Control de existencias y movimientos',
                    style: TextStyle(fontSize: 13, color: c.onSurfaceVariant)),
                const SizedBox(height: 26),
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
                  obscureText: !_verPass,
                  onSubmitted: (_) => _entrar(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    // Sin esto no hay forma de saber qué se escribió, y en el
                    // celular equivocarse es lo normal.
                    suffixIcon: IconButton(
                      icon: Icon(_verPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      tooltip: _verPass ? 'Ocultar' : 'Mostrar',
                      onPressed: () => setState(() => _verPass = !_verPass),
                    ),
                  ),
                ),
                CheckboxListTile(
                  value: _recordar,
                  onChanged: (v) => setState(() => _recordar = v ?? true),
                  title: const Text('Recordar mi correo',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                      'Solo el correo. La contraseña nunca se guarda.',
                      style: TextStyle(fontSize: 11)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
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
                const SizedBox(height: 12),
                // Saber qué versión está corriendo evita la discusión de
                // "a mí no me aparece" cuando alguien quedó con una vieja.
                Text('Versión ${Config.versionApp}',
                    style: TextStyle(fontSize: 11, color: c.outline)),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
