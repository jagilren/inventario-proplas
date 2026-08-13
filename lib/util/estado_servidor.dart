import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Por qué no se pudo entrar. Sirve para decirle al usuario qué hacer, en vez
/// de mostrarle el error crudo de la librería.
enum FalloEntrada {
  /// Correo o contraseña mal. Es culpa del dato que escribió.
  credenciales,

  /// El dispositivo no tiene red. No es culpa del servidor.
  sinInternet,

  /// Hay red, pero el servidor no responde. La causa más probable en este
  /// proyecto es que Supabase haya PAUSADO la base por inactividad.
  servidorNoDisponible,

  /// No se pudo clasificar: se muestra el error tal cual.
  desconocido,
}

/// Clasifica el error de un intento de inicio de sesión.
///
/// La distinción que importa es entre "no hay internet aquí" y "el servidor no
/// está": se ven igual desde la app, pero lo que el usuario debe hacer es
/// completamente distinto. Por eso primero se pregunta por la red del
/// dispositivo y solo si SÍ hay red se culpa al servidor.
///
/// Sobre Supabase pausado: en el plan gratuito el proyecto se pausa tras unos
/// días sin actividad, y mientras está pausado la API responde con error de
/// servidor (5xx). Desde el cliente no hay forma de distinguir con certeza
/// "pausado" de "caído", así que el mensaje nombra la pausa como causa más
/// probable sin afirmarla como un hecho.
Future<FalloEntrada> clasificarFalloEntrada(Object e) async {
  // Credenciales: el servidor respondió, y respondió que no.
  if (e is AuthApiException) {
    final codigo = int.tryParse(e.statusCode ?? '');
    if (codigo != null && codigo >= 400 && codigo < 500) {
      return FalloEntrada.credenciales;
    }
  }

  // ¿Es el dispositivo o es el servidor? Sin esta pregunta, quedarse sin datos
  // en el celular se vería como "la base está caída" y alguien saldría a
  // reactivar algo que nunca se pausó.
  try {
    final red = await Connectivity().checkConnectivity();
    if (red.contains(ConnectivityResult.none)) return FalloEntrada.sinInternet;
  } catch (_) {
    // Si ni siquiera se puede consultar la red, no se inventa un diagnóstico.
  }

  // Hay red y el servidor no contestó (o contestó 5xx).
  if (e is AuthRetryableFetchException) return FalloEntrada.servidorNoDisponible;
  if (e is AuthException) {
    final codigo = int.tryParse(e.statusCode ?? '');
    if (codigo == null || codigo >= 500) return FalloEntrada.servidorNoDisponible;
    return FalloEntrada.credenciales;
  }
  // Errores de red crudos (timeout, DNS, conexión rechazada) con red presente.
  return FalloEntrada.servidorNoDisponible;
}

/// Título corto para mostrar arriba del mensaje.
String tituloFallo(FalloEntrada f) => switch (f) {
      FalloEntrada.credenciales => 'Correo o contraseña incorrectos',
      FalloEntrada.sinInternet => 'Sin conexión a internet',
      FalloEntrada.servidorNoDisponible => 'El servidor no responde',
      FalloEntrada.desconocido => 'No se pudo entrar',
    };

/// Explicación con lo que el usuario puede hacer.
String mensajeFallo(FalloEntrada f, {String? detalle}) => switch (f) {
      FalloEntrada.credenciales =>
        'Revisa el correo y la contraseña. Si no la recuerdas, usa '
            '"¿Olvidaste tu contraseña?".',
      FalloEntrada.sinInternet =>
        'Tu dispositivo no tiene internet. Revisa el wifi o los datos y '
            'vuelve a intentar. El problema no es de la aplicación.',
      FalloEntrada.servidorNoDisponible =>
        'Hay internet en tu dispositivo, pero la base de datos no contesta.\n\n'
            'La causa más probable es que esté PAUSADA por inactividad: '
            'Supabase pausa los proyectos gratuitos cuando pasan varios días '
            'sin usarse.\n\n'
            'Avísale al administrador para que la reactive desde el panel de '
            'Supabase. Reactivarla tarda uno o dos minutos y no se pierde '
            'ningún dato.',
      FalloEntrada.desconocido =>
        detalle ?? 'Ocurrió un error inesperado. Intenta de nuevo.',
    };
