// Servicio de sincronización (modo sin conexión).
//
// Reglas de oro:
//  · Nunca se pierde un movimiento: si no hay red, se guarda en la cola.
//  · Nunca se duplica: cada movimiento lleva (device_id, local_id) y la base
//    tiene una regla de unicidad sobre ese par, así que reintentar es seguro.
//  · La app siempre puede consultar: si no hay red, lee del caché local.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'data.dart';
import 'local_store.dart';

class SyncService {
  /// Cambia cuando hay o no conexión, y cuando cambia el nº de pendientes.
  static final ValueNotifier<bool> enLinea = ValueNotifier(true);
  static final ValueNotifier<int> pendientes = ValueNotifier(0);
  static final ValueNotifier<bool> sincronizando = ValueNotifier(false);

  static StreamSubscription? _sub;
  static Timer? _reintento;

  /// Arranca la vigilancia de la red. Se llama una vez al iniciar la app.
  static Future<void> iniciar() async {
    await refrescarPendientes();

    _sub = Connectivity().onConnectivityChanged.listen((estados) {
      final hayRed = !estados.contains(ConnectivityResult.none);
      enLinea.value = hayRed;
      // Al recuperar la señal, intentar subir lo pendiente.
      if (hayRed) sincronizar();
    });

    final estado = await Connectivity().checkConnectivity();
    enLinea.value = !estado.contains(ConnectivityResult.none);

    // Red de seguridad: reintentar cada 2 minutos por si el aviso de
    // conectividad falla o el servidor estaba caído.
    _reintento = Timer.periodic(const Duration(minutes: 2), (_) {
      if (pendientes.value > 0) sincronizar();
    });

    // OJO: no se descarga el catálogo aquí. Al arrancar la app todavía no
    // hay sesión iniciada y la base exige estar autenticado, así que no
    // bajaría nada. La descarga se dispara tras el login (ver alSesionIniciada).
  }

  /// Se llama cuando ya hay sesión: descarga el catálogo y sube pendientes.
  static Future<void> alSesionIniciada() async {
    if (!enLinea.value) return;
    await refrescarCache();
    await sincronizar();
  }

  static void detener() {
    _sub?.cancel();
    _reintento?.cancel();
  }

  static Future<void> refrescarPendientes() async {
    pendientes.value = await LocalStore.cantidadPendientes() +
        await LocalStore.cantidadPendientesEquipos();
  }

  /// Baja el catálogo completo al dispositivo para poder trabajar sin señal.
  static Future<bool> refrescarCache() async {
    try {
      final elementos = await supabase
          .from('elementos')
          .select()
          .eq('activo', true)
          .order('nombre');
      final centros = await supabase
          .from('centros_costo')
          .select()
          .eq('activo', true)
          .order('codigo');
      await LocalStore.guardarElementos(
          (elementos as List).cast<Map<String, dynamic>>());
      await LocalStore.guardarCentros(
          (centros as List).cast<Map<String, dynamic>>());

      // Equipos: se baja la VISTA, no la tabla, porque trae ya calculados
      // `disponible` y la ubicación vigente — recalcularlos en el aparato
      // sería repetir la regla en dos sitios y arriesgar que se separen.
      // Si el usuario no tiene acceso al módulo, la RLS devuelve cero filas
      // y el caché simplemente queda vacío: no es un error.
      try {
        final activos = await supabase
            .from('activos_disponibilidad')
            .select('*, activo_referencias(nombre), '
                'bodegas!activos_bodega_id_fkey(nombre)')
            .order('serial');
        await LocalStore.guardarActivos(
            (activos as List).cast<Map<String, dynamic>>());
      } catch (_) {
        // Que falle el catálogo de equipos no debe tumbar el del inventario,
        // que es el que usa todo el mundo.
      }

      enLinea.value = true;
      return true;
    } catch (_) {
      enLinea.value = false;
      return false;
    }
  }

  /// Sube los movimientos que quedaron en la cola.
  /// Devuelve cuántos logró subir.
  static Future<int> sincronizar() async {
    if (sincronizando.value) return 0;
    final cola = await LocalStore.pendientes();
    final colaEquipos = await LocalStore.pendientesEquipos();
    if (cola.isEmpty && colaEquipos.isEmpty) return 0;

    sincronizando.value = true;
    final subidos = <String>{};
    var subidosEquipos = 0;
    try {
      for (final mov in cola) {
        try {
          await supabase.from('movimientos').insert(mov);
          subidos.add(mov['local_id'] as String);
        } on Object catch (e) {
          final txt = e.toString();
          // 23505 = clave duplicada: ya estaba subido, se puede sacar
          // de la cola sin miedo (esto es lo que hace segura la reintentona).
          if (txt.contains('23505') || txt.contains('duplicate key')) {
            subidos.add(mov['local_id'] as String);
          } else if (txt.contains('Existencia insuficiente')) {
            // El servidor rechaza por reglas de negocio: sacarlo de la cola
            // para que no bloquee al resto. Queda registrado en el aviso.
            subidos.add(mov['local_id'] as String);
          } else {
            // Sin red o error temporal: dejar de intentar por ahora.
            enLinea.value = false;
            break;
          }
        }
      }
      // Los equipos van en su propia cola y a su propia tabla, pero se
      // suben en la misma pasada: para el usuario "subir pendientes" es
      // una sola acción, no dos.
      subidosEquipos = await _subirColaEquipos(colaEquipos);

      if (subidos.isNotEmpty || subidosEquipos > 0) {
        if (subidos.isNotEmpty) await LocalStore.quitarDeCola(subidos);
        enLinea.value = true;
        // Refrescar existencias reales tras subir
        await refrescarCache();
      }
    } finally {
      sincronizando.value = false;
      await refrescarPendientes();
    }
    return subidos.length + subidosEquipos;
  }

  /// Sube la cola de movimientos de equipos. Mismo criterio que la del
  /// inventario: una clave duplicada significa que ya había subido, así que
  /// se saca de la cola en vez de reintentarla para siempre.
  static Future<int> _subirColaEquipos(List<Map<String, dynamic>> cola) async {
    if (cola.isEmpty) return 0;
    final subidos = <String>{};
    for (final mov in cola) {
      try {
        await supabase.from('activo_movimientos').insert(mov);
        subidos.add(mov['local_id'] as String);
      } on Object catch (e) {
        final txt = e.toString();
        if (txt.contains('23505') || txt.contains('duplicate key')) {
          subidos.add(mov['local_id'] as String);
        } else {
          // Sin red o error temporal: se reintenta en la próxima pasada.
          enLinea.value = false;
          break;
        }
      }
    }
    if (subidos.isNotEmpty) await LocalStore.quitarDeColaEquipos(subidos);
    return subidos.length;
  }

  /// Búsqueda sobre el caché local (mismas reglas que el buscador del
  /// servidor: todas las palabras como fragmento, en cualquier orden).
  /// Pagina igual que el servidor para que "Cargar más" también sirva
  /// cuando no hay señal.
  static Future<List<Elemento>> buscarLocal(
    String q, {
    int offset = 0,
    int limit = 100,
  }) async {
    final filas = await LocalStore.leerElementos();
    final palabras = _normalizar(q).split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty).toList();

    final res = filas.where((e) {
      if (palabras.isEmpty) return true;
      final texto = _normalizar([
        e['nombre'], e['material'], e['sch'], e['codigo_barras'],
      ].where((x) => x != null).join(' '));
      return palabras.every(texto.contains);
    }).skip(offset).take(limit).map((e) => Elemento.fromMap(e)).toList();
    return res;
  }

  /// Quita tildes y pasa a minúsculas, igual que hace la base de datos.
  static String _normalizar(String s) {
    const conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
    const sinTilde = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = conTilde.indexOf(ch);
      b.write(i >= 0 ? sinTilde[i] : ch);
    }
    return b.toString();
  }
}
