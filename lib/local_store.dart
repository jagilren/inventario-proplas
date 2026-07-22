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
      id = 'dev-${DateTime.now().millisecondsSinceEpoch}-'
          '${r.nextInt(1 << 32).toRadixString(16)}';
      await p.setString(_kDeviceId, id);
    }
    return id;
  }

  // ---- Caché del catálogo --------------------------------------------
  static Future<void> guardarElementos(List<Map<String, dynamic>> filas) async {
    final p = await _p;
    await p.setString(_kElementos, jsonEncode(filas));
    await p.setString(_kUltimaSync, DateTime.now().toIso8601String());
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
  }
}
