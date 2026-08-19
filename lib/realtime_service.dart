// Avisos en vivo (Supabase Realtime).
//
// PROBLEMA QUE RESUELVE: `InventarioService.revision` es un ValueNotifier que
// vive en la memoria de CADA aparato. Se incrementa cuando ese aparato escribe,
// así que las vistas abiertas se refrescan solas... pero solo ante los cambios
// propios. Si un usuario en Pekín registra una salida, el que está en Santiago
// mirando la lista de "últimas salidas" no se entera hasta que recarga a mano.
//
// SOLUCIÓN: escuchar la tabla `movimientos` y, ante un cambio ajeno, empujar el
// mismo `revision` de siempre. Así se refrescan de una las seis vistas que ya lo
// escuchan (Entrada, Salida, Dashboard, Alertas, Existencias, Aprovechamientos)
// sin tocar una sola de esas pantallas.
//
// EL EVENTO ES SOLO UN CAMPANAZO: no se pinta el payload. La fila que llega trae
// los ids pelados, no los nombres de elemento, centro y usuario que muestran las
// listas. Al recibirlo se vuelve a consultar con la query normal, que además
// respeta RLS y el orden de más reciente a más antiguo.
//
// COSTO: Realtime está incluido en el plan Free (200 conexiones concurrentes,
// 100 mensajes/segundo). Cada usuario con la app abierta gasta una conexión.
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data.dart';
import 'local_store.dart';

class RealtimeService {
  static RealtimeChannel? _canal;
  static Timer? _debounce;
  static String? _deviceId;

  /// Espera antes de avisar. Una carga masiva inserta cientos de filas de un
  /// tirón: sin esto la pantalla pediría cientos de recargas seguidas.
  static const _espera = Duration(milliseconds: 800);

  /// Se llama cuando ya hay sesión. Llamarla dos veces no hace nada.
  static Future<void> iniciar() async {
    if (_canal != null) return;
    _deviceId = await LocalStore.deviceId();
    // Sin señal no se suscribe; al reconectar, el cliente de Supabase
    // restablece el socket solo.
    _canal = supabase
        .channel('movimientos-en-vivo')
        .onPostgresChanges(
          // `all` y no solo `insert`: una anulación es un UPDATE y también
          // cambia lo que muestran las listas.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'movimientos',
          callback: _alCambio,
        )
        .subscribe();
  }

  static void _alCambio(PostgresChangePayload payload) {
    // El eco de lo que registró este mismo aparato se ignora: al guardar ya se
    // incrementó `revision` localmente, recargar de nuevo sería en vano.
    // En un DELETE llega vacío, así que no coincide y sí se avisa.
    if (payload.newRecord['device_id'] == _deviceId) return;
    _debounce?.cancel();
    _debounce = Timer(_espera, () => InventarioService.revision.value++);
  }

  /// Se llama al cerrar sesión: sin esto el socket queda vivo gastando una
  /// conexión y el siguiente usuario heredaría la suscripción del anterior.
  static Future<void> detener() async {
    _debounce?.cancel();
    _debounce = null;
    final canal = _canal;
    _canal = null;
    if (canal != null) await supabase.removeChannel(canal);
  }
}
