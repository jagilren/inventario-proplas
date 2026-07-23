import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'ajustes.dart';
import 'sync_service.dart';
import 'screens/login_page.dart';
import 'screens/home_page.dart';
import 'screens/nueva_password_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabasePublishableKey,
  );
  await Ajustes.cargar(); // config regional de exportaciones
  // Vigilancia de la red + subida de lo que quedó pendiente.
  // No se espera (unawaited) para no demorar el arranque de la app.
  SyncService.iniciar();
  runApp(const InventarioApp());
}

class InventarioApp extends StatelessWidget {
  const InventarioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventario PROPLAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Muestra Login, la pantalla de nueva contraseña (si llegó por el enlace de
/// recuperación) o Home según haya sesión activa.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recuperando = false;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.passwordRecovery) {
        setState(() => _recuperando = true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recuperando) {
      return NuevaPasswordPage(
          onListo: () => setState(() => _recuperando = false));
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) return const HomePage();
    return const LoginPage();
  }
}
