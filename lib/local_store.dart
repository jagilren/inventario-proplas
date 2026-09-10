// Almacén local para el modo sin conexión.
//
// Guarda dos cosas en el dispositivo:
//  1. CACHÉ  — copia de elementos y centros de costo, para poder consultar
//              y buscar aunque no haya señal.
//  2. COLA   — movimientos registrados sin internet, esperando subir.
//
// Se usa shared_preferences (JSON) en vez de una base local completa porque
// el catálogo es pequeño (~959 elementos, unos 250 KB) y así funciona igual
// en Android y en navegador sin complicaciones.
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static const _kElementos = 'cache_elementos';
  static const _kCentros = 'cache_centros';
  static const _kPendientes = 'cola_pendientes';
  static const _kUltimaSync = 'ultima_sync';
  static const _kDeviceId = 'device_id';
  // Equipos va en claves APARTE, no mezclado con lo del inventario: son
  // tablas distintas y se suben a endpoints distintos. Compartir la cola
  // habría obligado a marcar cada fila con su tabla destino y a tocar el
  // camino que ya funciona para el inventario.
  static const _kActivos = 'cache_activos';
  static const _kPendientesEquipos = 'cola_pendientes_equipos';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---- Identificador único de este dispositivo -----------------------
  /// Junto con el local_id forma la llave que impide subir dos veces el
  /// mismo movimiento (la base tiene una regla de unicidad sobre ambos).
  static Future<String> deviceId() async {
    final p = await _p;
    var id = p.getString(_kDeviceId);
    if (id == null) {
      final r = Random();
      // 0xFFFFFFFF (no "1 << 32"): en web, 1<<32 se desborda a 0 y nextInt(0)
      // revienta con RangeError. 0xFFFFFFFF es seguro en web y en móvil.
      id = 'dev-${DateTime.now().millisecondsSinceEpoch}-'
          '${r.nextInt(0xFFFFFFFF).toRadixString(16)}';
      await p.setString(_kDeviceId, id);
    }
    return id;
  }

  // ---- Caché del catálogo --------------------------------------------
  static Future<void> guardarElementos(List<Map<String, dynamic>> filas) async {
    final p = await _p;
    await p.setString(_kElementos, jsonEncode(filas));
    await p.setString(_kUltimaSync, DateTime.now().toUtc().toIso8601String());
  }

  static Future<List<Map<String, dynamic>>> leerElementos() async {
    final p = await _p;
    final txt = p.getString(_kElementos);
    if (txt == null) return [];
    return (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> guardarCentros(List<Map<String, dynamic>> filas) async {
    final p = await _p;
    await p.setString(_kCentros, jsonEncode(filas));
  }

  static Future<List<Map<String, dynamic>>> leerCentros() async {
    final p = await _p;
    final txt = p.getString(_kCentros);
    if (txt == null) return [];
    return (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
  }

  static Future<DateTime?> ultimaSincronizacion() async {
    final p = await _p;
    final t = p.getString(_kUltimaSync);
    return t == null ? null : DateTime.tryParse(t);
  }

  // ---- Cola de movimientos pendientes --------------------------------
  static Future<List<Map<String, dynamic>>> pendientes() async {
    final p = await _p;
    final txt = p.getString(_kPendientes);
    if (txt == null) return [];
    return (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> _guardarCola(List<Map<String, dynamic>> cola) async {
    final p = await _p;
    await p.setString(_kPendientes, jsonEncode(cola));
  }

  static Future<void> encolar(Map<String, dynamic> movimiento) async {
    final cola = await pendientes();
    cola.add(movimiento);
    await _guardarCola(cola);
  }

  /// Quita de la cola los movimientos ya subidos (por su local_id).
  static Future<void> quitarDeCola(Set<String> localIds) async {
    final cola = await pendientes();
    cola.removeWhere((m) => localIds.contains(m['local_id']));
    await _guardarCola(cola);
  }

  static Future<int> cantidadPendientes() async => (await pendientes()).length;

  // ---- Equipos: caché y cola propias ---------------------------------

  static Future<void> guardarActivos(List<Map<String, dynamic>> filas) async {
    final p = await _p;
    await p.setString(_kActivos, jsonEncode(filas));
  }

  static Future<List<Map<String, dynamic>>> leerActivos() async {
    final p = await _p;
    final txt = p.getString(_kActivos);
    if (txt == null) return [];
    return (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> pendientesEquipos() async {
    final p = await _p;
    final txt = p.getString(_kPendientesEquipos);
    if (txt == null) return [];
    return (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> encolarEquipo(Map<String, dynamic> movimiento) async {
    final cola = await pendientesEquipos();
    cola.add(movimiento);
    final p = await _p;
    await p.setString(_kPendientesEquipos, jsonEncode(cola));
  }

  static Future<void> quitarDeColaEquipos(Set<String> localIds) async {
    final cola = await pendientesEquipos();
    cola.removeWhere((m) => localIds.contains(m['local_id']));
    final p = await _p;
    await p.setString(_kPendientesEquipos, jsonEncode(cola));
  }

  static Future<int> cantidadPendientesEquipos() async =>
      (await pendientesEquipos()).length;

  /// Deja el equipo en el caché con el estado que tendrá una vez suba el
  /// movimiento, para que el usuario no siga viendo "disponible" un equipo
  /// que él mismo acaba de entregar. El servidor manda: al sincronizar se
  /// vuelve a bajar el catálogo y esto se sobreescribe con la verdad.
  static Future<void> ajustarEstadoActivoLocal(
      String activoId, String estado) async {
    final activos = await leerActivos();
    for (final a in activos) {
      if (a['id'] == activoId) {
        a['estado'] = estado;
        // `disponible` viene calculado de la vista activos_disponibilidad;
        // se recalcula IGUAL que allá para que las listas offline no se
        // contradigan con las de línea. Si cambia la fórmula en la vista,
        // hay que cambiarla aquí (schema_v55).
        a['disponible'] = estado == 'operativo' &&
            a['condicion'] != 'repuestos' &&
            a['condicion'] != 'baja' &&
            a['ubicacion_actual_bodega_id'] != null;
        break;
      }
    }
    await guardarActivos(activos);
  }

  /// Existencia guardada en caché para un elemento (null si no está en caché).
  /// Sirve para validar el stock cuando no hay conexión.
  static Future<num?> existenciaLocal(String elementoId) async {
    final elementos = await leerElementos();
    for (final e in elementos) {
      if (e['id'] == elementoId) return (e['existencia'] ?? 0) as num;
    }
    return null;
  }

  /// Ajusta la existencia guardada en caché, para que el bodeguero vea el
  /// stock correcto aunque el movimiento todavía no haya subido.
  static Future<void> ajustarExistenciaLocal(
      String elementoId, num delta) async {
    final elementos = await leerElementos();
    for (final e in elementos) {
      if (e['id'] == elementoId) {
        e['existencia'] = ((e['existencia'] ?? 0) as num) + delta;
        break;
      }
    }
    final p = await _p;
    await p.setString(_kElementos, jsonEncode(elementos));
  }

  static Future<void> limpiarTodo() async {
    final p = await _p;
    await p.remove(_kElementos);
    await p.remove(_kCentros);
    await p.remove(_kPendientes);
    await p.remove(_kUltimaSync);
    await p.remove(_kActivos);
    await p.remove(_kPendientesEquipos);
  }
}
