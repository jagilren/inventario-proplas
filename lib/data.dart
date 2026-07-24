// Modelos y acceso a datos (Supabase).
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'phash.dart';
import 'local_store.dart';
import 'sync_service.dart';

final supabase = Supabase.instance.client;

class Elemento {
  final String id;
  final String nombre;
  final String? material;
  final String? sch;
  final String unidad;
  final String? codigoBarras;
  final String? imagenUrl;
  final num existencia;
  final num costoPromedio;
  final num stockMinimo;
  final bool activo;
  final bool serializado;

  Elemento.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        nombre = m['nombre'] as String,
        material = m['material'] as String?,
        sch = m['sch'] as String?,
        unidad = (m['unidad'] as String?) ?? 'UND',
        codigoBarras = m['codigo_barras'] as String?,
        imagenUrl = m['imagen_url'] as String?,
        existencia = (m['existencia'] ?? 0) as num,
        costoPromedio = (m['costo_promedio'] ?? 0) as num,
        stockMinimo = (m['stock_minimo'] ?? 0) as num,
        activo = (m['activo'] ?? true) as bool,
        serializado = (m['serializado'] ?? false) as bool;

  bool get bajoMinimo => stockMinimo > 0 && existencia <= stockMinimo;
}

/// Una unidad serializada (un serial) de un elemento.
class Serie {
  final String id;
  final String serial;
  final String? bodega;
  final String? bodegaId;
  final String estado;
  final num costo;
  Serie.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        serial = m['serial'] as String,
        bodega = (m['bodegas'] as Map?)?['nombre'] as String?,
        bodegaId = m['bodega_id'] as String?,
        estado = (m['estado'] as String?) ?? 'disponible',
        costo = (m['costo'] ?? 0) as num;
  bool get disponible => estado == 'disponible';
}

/// Una foto de la galería de un elemento.
class ImagenElem {
  final String id;
  final String url;
  final String ruta;
  final bool principal;
  final int orden;

  ImagenElem.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        url = m['url'] as String,
        ruta = m['ruta'] as String,
        principal = (m['principal'] ?? false) as bool,
        orden = ((m['orden'] ?? 0) as num).toInt();
}

class CentroCosto {
  final String id;
  final String codigo;
  final String? descripcion;
  final String? cliente;

  final bool activo;
  CentroCosto.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        codigo = m['codigo'] as String,
        descripcion = m['descripcion'] as String?,
        cliente = m['cliente'] as String?,
        activo = (m['activo'] ?? true) as bool;

  String get etiqueta =>
      [codigo, descripcion, cliente].where((e) => e != null && e.isNotEmpty).join(' · ');
}

class Bodega {
  final String id;
  final String nombre;
  final String? codigo;
  final bool activo;
  Bodega.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        nombre = m['nombre'] as String,
        codigo = m['codigo'] as String?,
        activo = (m['activo'] ?? true) as bool;
}

class ExistenciaBodega {
  final String bodega;
  final num existencia;
  final num costoPromedio;
  ExistenciaBodega.fromMap(Map<String, dynamic> m)
      : bodega = ((m['bodegas'] as Map?)?['nombre'] ?? m['bodega'] ?? '—') as String,
        existencia = (m['existencia'] ?? 0) as num,
        costoPromedio = (m['costo_promedio'] ?? 0) as num;
}

class MovKardex {
  final String? id;
  final DateTime fecha;
  final String tipo;
  final num cantidad;
  final num? costoUnitario;
  final String? centroCosto;
  final String? referencia;
  final String? observacion;
  final String? usuarioId;

  final String? bodega;

  MovKardex.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String?,
        fecha = DateTime.parse(m['fecha'] as String),
        tipo = m['tipo'] as String,
        cantidad = (m['cantidad'] ?? 0) as num,
        costoUnitario = m['costo_unitario'] as num?,
        centroCosto = ((m['centros_costo'] as Map?)?['codigo'] ?? m['centro_costo']) as String?,
        bodega = (m['bodegas'] as Map?)?['nombre'] as String?,
        referencia = m['referencia'] as String?,
        observacion = m['observacion'] as String?,
        usuarioId = m['usuario_id'] as String?;

  bool get esAnulacion => (referencia ?? '').startsWith('ANULACION');
}

/// Archivo adjunto a un movimiento (PDF, XLSX, imagen…).
class Adjunto {
  final String id;
  final String movimientoId;
  final String nombre;
  final String ruta;
  final String url;
  final String? tipo;
  final int? tamano;

  Adjunto.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        movimientoId = m['movimiento_id'] as String,
        nombre = m['nombre'] as String,
        ruta = m['ruta'] as String,
        url = m['url'] as String,
        tipo = m['tipo'] as String?,
        tamano = (m['tamano'] as num?)?.toInt();

  bool get esPdf => (tipo ?? '').contains('pdf') ||
      nombre.toLowerCase().endsWith('.pdf');
  bool get esExcel => (tipo ?? '').contains('sheet') ||
      (tipo ?? '').contains('excel') ||
      nombre.toLowerCase().endsWith('.xlsx') ||
      nombre.toLowerCase().endsWith('.xls');
  bool get esImagen => (tipo ?? '').startsWith('image/');
}

/// Un trozo/retazo aprovechable de un elemento. Inventario paralelo, $0.
class Trozo {
  final String id;
  final String elementoId;
  final String elementoNombre;
  final String unidad;
  final num longitud;        // longitud inicial
  final num longitudActual;  // lo que queda disponible
  final String? bodega;
  final String? observacion;
  final String? creadoEmail;
  final DateTime? creadoEn;
  final DateTime? consumidoEn;

  Trozo.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        elementoId = m['elemento_id'] as String,
        elementoNombre = ((m['elementos'] as Map?)?['nombre'] ?? '') as String,
        unidad = ((m['elementos'] as Map?)?['unidad'] ?? 'UND') as String,
        longitud = (m['longitud'] ?? 0) as num,
        longitudActual = (m['longitud_actual'] ?? 0) as num,
        bodega = (m['bodegas'] as Map?)?['nombre'] as String?,
        observacion = m['observacion'] as String?,
        creadoEmail = m['creado_email'] as String?,
        creadoEn = m['creado_en'] == null
            ? null : DateTime.parse(m['creado_en'] as String),
        consumidoEn = m['consumido_en'] == null
            ? null : DateTime.parse(m['consumido_en'] as String);

  bool get disponible => longitudActual > 0;
  bool get parcial => longitudActual < longitud;
}

/// Una sub-salida (segmento usado) de un trozo, para el historial.
class SalidaTrozo {
  final num cantidad;
  final String? centroCosto;
  final String? observacion;
  final String? usuarioEmail;
  final DateTime fecha;

  SalidaTrozo.fromMap(Map<String, dynamic> m)
      : cantidad = (m['cantidad'] ?? 0) as num,
        centroCosto = (m['centros_costo'] as Map?)?['codigo'] as String?,
        observacion = m['observacion'] as String?,
        usuarioEmail = m['usuario_email'] as String?,
        fecha = DateTime.parse(m['fecha'] as String);
}

/// Resumen por elemento de sus trozos: disponibles (con saldo) y total.
class TrozoResumen {
  final String elementoId;
  final String nombre;
  final String unidad;
  final int disponibles;   // # de trozos con saldo
  final num totalDisp;     // suma de los saldos disponibles
  final int totalTrozos;   // # de trozos en total (incluye consumidos)
  TrozoResumen(this.elementoId, this.nombre, this.unidad,
      this.disponibles, this.totalDisp, this.totalTrozos);
}

class Resumen {
  final int totalElementos;
  final num valorizacionTotal;
  final int bajoMinimo;
  final int totalMovimientos;
  Resumen.fromMap(Map<String, dynamic> m)
      : totalElementos = ((m['total_elementos'] ?? 0) as num).toInt(),
        valorizacionTotal = (m['valorizacion_total'] ?? 0) as num,
        bajoMinimo = ((m['bajo_minimo'] ?? 0) as num).toInt(),
        totalMovimientos = ((m['total_movimientos'] ?? 0) as num).toInt();
}

class MovReciente {
  final DateTime fecha;
  final String tipo;
  final num cantidad;
  final String elemento;
  final String unidad;
  final String? centroCosto;
  MovReciente.fromMap(Map<String, dynamic> m)
      : fecha = DateTime.parse(m['fecha'] as String),
        tipo = m['tipo'] as String,
        cantidad = (m['cantidad'] ?? 0) as num,
        elemento = m['elemento'] as String,
        unidad = (m['unidad'] as String?) ?? 'UND',
        centroCosto = m['centro_costo'] as String?;
}

class Usuario {
  final String id;
  final String? email;
  final String? nombre;
  final Set<String> roles;
  Usuario.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        email = m['email'] as String?,
        nombre = m['nombre'] as String?,
        roles = ((m['roles'] as List?) ?? []).map((e) => e as String).toSet();
}

class Auditoria {
  final DateTime fecha;
  final String? tabla;
  final String accion;
  final String? campo;
  final String? valorAnterior;
  final String? valorNuevo;
  final String? usuarioEmail;

  Auditoria.fromMap(Map<String, dynamic> m)
      : fecha = DateTime.parse(m['fecha'] as String),
        tabla = m['tabla'] as String?,
        accion = m['accion'] as String,
        campo = m['campo'] as String?,
        valorAnterior = m['valor_anterior'] as String?,
        valorNuevo = m['valor_nuevo'] as String?,
        usuarioEmail = m['usuario_email'] as String?;

  /// Descripción legible del cambio.
  String get descripcion => switch (accion) {
        'INSERT' => 'Creado',
        'DELETE' => 'Eliminado',
        _ => '${campo ?? '—'}: ${valorAnterior ?? '(vacío)'} → ${valorNuevo ?? '(vacío)'}',
      };
}

/// Catálogo de roles con etiqueta legible.
class Roles {
  static const admin = 'admin';
  static const coordinador = 'coordinador';
  static const operarioMas = 'operario_mas';
  static const operarioMenos = 'operario_menos';
  static const exportar = 'exportar';

  static const todos = [admin, coordinador, operarioMas, operarioMenos, exportar];

  static String etiqueta(String rol) => switch (rol) {
        admin => 'Administrador',
        coordinador => 'Coordinador',
        operarioMas => 'Operario + (entradas)',
        operarioMenos => 'Operario − (salidas)',
        exportar => 'Exportar informes',
        _ => rol,
      };
}

class InventarioService {
  /// Se incrementa tras cada cambio de inventario (movimiento o anulación).
  /// Las vistas abiertas (existencias, dashboard, alertas) lo escuchan y se
  /// recargan solas, sin que el usuario tenga que refrescar a mano.
  static final ValueNotifier<int> revision = ValueNotifier(0);
  /// Búsqueda inteligente (palabras en cualquier orden, sin tildes).
  /// Si no hay señal, busca en el caché local con las mismas reglas.
  static Future<List<Elemento>> buscar(String q) async {
    try {
      final res = await supabase.rpc('buscar_elementos', params: {'q': q});
      return (res as List)
          .map((e) => Elemento.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      SyncService.enLinea.value = false;
      return SyncService.buscarLocal(q);
    }
  }

  /// Busca un elemento por su código de barras. Sin señal, busca en el caché.
  static Future<Elemento?> porCodigoBarras(String codigo) async {
    try {
      final res = await supabase
          .from('elementos')
          .select()
          .eq('codigo_barras', codigo)
          .maybeSingle();
      return res == null ? null : Elemento.fromMap(res);
    } catch (_) {
      SyncService.enLinea.value = false;
      final filas = await LocalStore.leerElementos();
      final match = filas.where((e) => e['codigo_barras'] == codigo);
      return match.isEmpty ? null : Elemento.fromMap(match.first);
    }
  }

  /// Centros de costo. Sin señal, los toma del caché local.
  static Future<List<Bodega>> bodegas() async {
    final res = await supabase.from('bodegas').select()
        .eq('activo', true).order('nombre');
    return (res as List).map((e) => Bodega.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<List<ExistenciaBodega>> existenciasPorBodega(String elementoId) async {
    final res = await supabase.from('existencias')
        .select('existencia, costo_promedio, bodegas(nombre)')
        .eq('elemento_id', elementoId)
        .neq('existencia', 0)
        .order('existencia', ascending: false);
    return (res as List)
        .map((e) => ExistenciaBodega.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Traslado = salida del origen + entrada al destino, en una sola operación
  /// atómica sobre la tabla (evita el RPC). El costo viaja con el material.
  static Future<void> trasladar({
    required String elementoId, required num cantidad,
    required String origenId, required String destinoId, String? obs}) async {
    final ex = await supabase.from('existencias')
        .select('costo_promedio')
        .eq('elemento_id', elementoId).eq('bodega_id', origenId).maybeSingle();
    final costo = (ex?['costo_promedio'] ?? 0) as num;
    final uid = supabase.auth.currentUser?.id;
    await supabase.from('movimientos').insert([
      {
        'tipo': 'salida', 'elemento_id': elementoId, 'bodega_id': origenId,
        'cantidad': cantidad, 'costo_unitario': null, 'referencia': 'TRASLADO',
        'observacion': obs, 'usuario_id': uid,
        'fecha': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'tipo': 'entrada', 'elemento_id': elementoId, 'bodega_id': destinoId,
        'cantidad': cantidad, 'costo_unitario': costo, 'referencia': 'TRASLADO',
        'observacion': obs, 'usuario_id': uid,
        'fecha': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
    revision.value++;
  }

  static Future<void> guardarBodega({String? id, required String nombre,
      String? codigo}) async {
    final row = {'nombre': nombre, 'codigo': codigo};
    if (id == null) {
      await supabase.from('bodegas').insert(row);
    } else {
      await supabase.from('bodegas').update(row).eq('id', id);
    }
  }

  /// Todas las bodegas (activas e inactivas), para la pantalla de gestión.
  static Future<List<Bodega>> bodegasTodas() async {
    final res = await supabase.from('bodegas').select().order('nombre');
    return (res as List).map((e) => Bodega.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<List<CentroCosto>> centrosTodos() async {
    final res = await supabase.from('centros_costo').select().order('codigo');
    return (res as List).map((e) => CentroCosto.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Baja lógica. No se permite si la bodega tiene inventario.
  static Future<void> eliminarBodega(String id) async {
    final ex = await supabase.from('existencias')
        .select('existencia').eq('bodega_id', id).neq('existencia', 0).limit(1);
    if ((ex as List).isNotEmpty) {
      throw Exception('No se puede desactivar: la bodega tiene inventario. '
          'Traslada o consume el stock primero.');
    }
    await supabase.from('bodegas').update({'activo': false}).eq('id', id);
  }

  static Future<void> reactivarBodega(String id) async {
    await supabase.from('bodegas').update({'activo': true}).eq('id', id);
  }

  static Future<void> eliminarCentro(String id) async {
    await supabase.from('centros_costo').update({'activo': false}).eq('id', id);
  }

  static Future<void> reactivarCentro(String id) async {
    await supabase.from('centros_costo').update({'activo': true}).eq('id', id);
  }

  static Future<List<CentroCosto>> centrosCosto() async {
    try {
      final res = await supabase
          .from('centros_costo')
          .select()
          .eq('activo', true)
          .order('codigo');
      return (res as List)
          .map((e) => CentroCosto.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      SyncService.enLinea.value = false;
      final filas = await LocalStore.leerCentros();
      return filas.map(CentroCosto.fromMap).toList();
    }
  }

  static Future<List<Elemento>> bajoMinimo() async {
    final res = await supabase
        .from('elementos')
        .select()
        .filter('stock_minimo', 'gt', 0)
        .order('nombre');
    return (res as List)
        .map((e) => Elemento.fromMap(e as Map<String, dynamic>))
        .where((e) => e.bajoMinimo)
        .toList();
  }

  /// Todos los elementos activos (para emparejar la carga de devoluciones).
  static Future<List<Elemento>> todosElementos() async {
    final res = await supabase
        .from('elementos')
        .select()
        .eq('activo', true)
        .order('nombre');
    return (res as List)
        .map((e) => Elemento.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Elementos con existencia pero costo promedio en 0 (no valorizados).
  static Future<List<Elemento>> costoCero() async {
    final res = await supabase
        .from('elementos')
        .select()
        .gt('existencia', 0)
        .eq('costo_promedio', 0)
        .order('nombre');
    return (res as List)
        .map((e) => Elemento.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<MovKardex>> kardex(String elementoId) async {
    final res = await supabase.from('movimientos')
        .select('id, fecha, tipo, cantidad, costo_unitario, referencia, '
            'observacion, usuario_id, bodegas(nombre), centros_costo(codigo)')
        .eq('elemento_id', elementoId)
        .order('fecha', ascending: false)
        .order('created_at', ascending: false);
    return (res as List).map((e) => MovKardex.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Id del usuario autenticado (para saber si es autor de un movimiento).
  static String? get miUid => supabase.auth.currentUser?.id;

  /// Edita SOLO la observación de un movimiento (el candado de la base impide
  /// cambiar cualquier otra cosa). Permiso: admin, coordinador o autor.
  static Future<void> editarObservacion(String movId, String? obs) async {
    await supabase.from('movimientos')
        .update({'observacion': (obs == null || obs.trim().isEmpty) ? null : obs.trim()})
        .eq('id', movId);
    revision.value++;
  }

  static const _baldeAdjuntos = 'adjuntos-mov';

  /// Adjuntos de un movimiento (PDF/XLSX/imagen).
  static Future<List<Adjunto>> adjuntosMovimiento(String movId) async {
    final res = await supabase.from('movimiento_adjuntos')
        .select().eq('movimiento_id', movId).order('creado_en');
    return (res as List).map((e) => Adjunto.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Sube un archivo y lo asocia al movimiento. Devuelve el adjunto creado.
  static Future<Adjunto> agregarAdjunto(String movId, String nombre,
      Uint8List bytes, String tipo) async {
    final limpio = nombre.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final ruta = '$movId/${DateTime.now().millisecondsSinceEpoch}_$limpio';
    await supabase.storage.from(_baldeAdjuntos).uploadBinary(
          ruta, bytes,
          fileOptions: FileOptions(contentType: tipo, upsert: true),
        );
    final url = supabase.storage.from(_baldeAdjuntos).getPublicUrl(ruta);
    final res = await supabase.from('movimiento_adjuntos').insert({
      'movimiento_id': movId,
      'nombre': nombre,
      'ruta': ruta,
      'url': url,
      'tipo': tipo,
      'tamano': bytes.length,
      'subido_por': supabase.auth.currentUser?.id,
    }).select().single();
    return Adjunto.fromMap(res);
  }

  static Future<void> borrarAdjunto(Adjunto a) async {
    await supabase.from('movimiento_adjuntos').delete().eq('id', a.id);
    try {
      await supabase.storage.from(_baldeAdjuntos).remove([a.ruta]);
    } catch (_) {
      // Si el archivo ya no existe, el registro igual quedó borrado.
    }
  }

  // ---- APROVECHAMIENTOS (trozos/retazos, inventario paralelo a $0) ----

  /// Resumen por elemento de TODOS sus trozos (incluye los ya consumidos, para
  /// que se pueda ver su histórico). Trae disponibles + total.
  static Future<List<TrozoResumen>> aprovechamientosResumen() async {
    final res = await supabase
        .from('aprovechamiento_trozos')
        .select('elemento_id, longitud_actual, elementos(nombre, unidad)');
    final nombres = <String, String>{};
    final unidades = <String, String>{};
    final disp = <String, int>{};       // # con saldo
    final totalDisp = <String, num>{};  // suma de saldos
    final total = <String, int>{};      // # de trozos en total
    for (final e in (res as List)) {
      final m = e as Map<String, dynamic>;
      final id = m['elemento_id'] as String;
      final el = m['elementos'] as Map?;
      nombres[id] = (el?['nombre'] ?? '') as String;
      unidades[id] = (el?['unidad'] ?? 'UND') as String;
      final saldo = (m['longitud_actual'] ?? 0) as num;
      total[id] = (total[id] ?? 0) + 1;
      if (saldo > 0) {
        disp[id] = (disp[id] ?? 0) + 1;
        totalDisp[id] = (totalDisp[id] ?? 0) + saldo;
      }
    }
    final out = total.keys
        .map((id) => TrozoResumen(id, nombres[id] ?? '', unidades[id] ?? 'UND',
            disp[id] ?? 0, totalDisp[id] ?? 0, total[id] ?? 0))
        .toList();
    // Primero los que tienen saldo, luego alfabético.
    out.sort((a, b) {
      if ((a.disponibles > 0) != (b.disponibles > 0)) {
        return a.disponibles > 0 ? -1 : 1;
      }
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return out;
  }

  /// Todos los trozos (de todos los elementos, incluidos los consumidos) para
  /// el histórico global del módulo. Más reciente primero.
  static Future<List<Trozo>> todosLosTrozos() async {
    final res = await supabase
        .from('aprovechamiento_trozos')
        .select('*, elementos(nombre, unidad), bodegas(nombre)')
        .order('creado_en', ascending: false);
    return (res as List)
        .map((e) => Trozo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Trozos de un elemento (por defecto solo los que tienen saldo disponible).
  static Future<List<Trozo>> trozosDeElemento(String elementoId,
      {bool soloDisponibles = true}) async {
    var q = supabase
        .from('aprovechamiento_trozos')
        .select('*, elementos(nombre, unidad), bodegas(nombre)')
        .eq('elemento_id', elementoId);
    if (soloDisponibles) q = q.gt('longitud_actual', 0);
    final res = await q.order('creado_en');
    return (res as List)
        .map((e) => Trozo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Ingresa un trozo (entrada). Permiso: operario+ o admin.
  static Future<void> ingresarTrozo({
    required String elementoId,
    required num longitud,
    String? bodegaId,
    String? observacion,
  }) async {
    await supabase.from('aprovechamiento_trozos').insert({
      'elemento_id': elementoId,
      'longitud': longitud,
      'longitud_actual': longitud, // al ingresar, el saldo disponible = total
      'bodega_id': bodegaId,
      'observacion':
          (observacion == null || observacion.trim().isEmpty) ? null : observacion.trim(),
      'creado_por': supabase.auth.currentUser?.id,
      'creado_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  /// Saca un sub-segmento de un trozo (salida parcial). El trigger descuenta
  /// del saldo y valida que no exceda lo disponible. Permiso: operario- o admin.
  static Future<void> sacarDeTrozo(String trozoId,
      {required num cantidad, String? centroCostoId, String? observacion}) async {
    await supabase.from('aprovechamiento_salidas').insert({
      'trozo_id': trozoId,
      'cantidad': cantidad,
      'centro_costo_id': centroCostoId,
      'observacion':
          (observacion == null || observacion.trim().isEmpty) ? null : observacion.trim(),
      'usuario_id': supabase.auth.currentUser?.id,
      'usuario_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  /// Historial de sub-salidas de un trozo (para la trazabilidad), más reciente
  /// primero.
  static Future<List<SalidaTrozo>> salidasDeTrozo(String trozoId) async {
    final res = await supabase
        .from('aprovechamiento_salidas')
        .select('cantidad, observacion, usuario_email, fecha, centros_costo(codigo)')
        .eq('trozo_id', trozoId)
        .order('fecha');
    return (res as List)
        .map((e) => SalidaTrozo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Borra un trozo (corrección). Permiso: admin/coordinador.
  static Future<void> borrarTrozo(String trozoId) async {
    await supabase.from('aprovechamiento_trozos').delete().eq('id', trozoId);
    revision.value++;
  }

  static Future<Resumen> resumen() async {
    final res = await supabase.rpc('resumen_inventario');
    final row = (res as List).first as Map<String, dynamic>;
    return Resumen.fromMap(row);
  }

  static Future<List<MovReciente>> ultimosMovimientos() async {
    final res = await supabase.rpc('ultimos_movimientos', params: {'p_limit': 15});
    return (res as List).map((e) => MovReciente.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<void> anularMovimiento(String movId, String? motivo) async {
    await supabase.rpc('anular_movimiento',
        params: {'p_mov': movId, 'p_motivo': motivo});
    revision.value++;
  }

  /// Roles del usuario actual (puede tener varios).
  static Future<Set<String>> misRoles() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return {};
    final res = await supabase.from('usuario_roles').select('rol').eq('usuario_id', uid);
    return (res as List).map((e) => e['rol'] as String).toSet();
  }

  // ---- Gestión de usuarios (solo admin) ----
  static Future<List<Usuario>> listarUsuarios() async {
    final res = await supabase.rpc('listar_usuarios');
    return (res as List).map((e) => Usuario.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Busca usuarios por correo o nombre (servidor, máx. 30). Para el selector
  /// de configuración cuando hay muchos usuarios.
  static Future<List<Usuario>> buscarUsuarios(String q) async {
    final base = supabase.from('profiles').select('id, email, nombre');
    final filtrado = q.trim().isEmpty
        ? base
        : base.or('email.ilike.%$q%,nombre.ilike.%$q%');
    final res = await filtrado.order('email').limit(30);
    return (res as List).map((e) => Usuario.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<void> asignarRol(String usuarioId, String rol) async {
    await supabase.from('usuario_roles').insert({'usuario_id': usuarioId, 'rol': rol});
  }

  static Future<void> quitarRol(String usuarioId, String rol) async {
    await supabase.from('usuario_roles').delete()
        .eq('usuario_id', usuarioId).eq('rol', rol);
  }

  static Future<void> crearUsuario({
    required String email,
    required String password,
    String? nombre,
    required List<String> roles,
  }) async {
    final res = await supabase.functions.invoke('crear-usuario', body: {
      'email': email, 'password': password, 'nombre': nombre, 'roles': roles,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }
  }

  // ---- CRUD centros de costo (admin / coordinador) ----
  static Future<void> guardarCentro({String? id, required String codigo,
      String? descripcion, String? cliente}) async {
    final row = {'codigo': codigo, 'descripcion': descripcion, 'cliente': cliente};
    if (id == null) {
      await supabase.from('centros_costo').insert(row);
    } else {
      await supabase.from('centros_costo').update(row).eq('id', id);
    }
  }

  static Future<void> actualizarElemento(String id, Map<String, dynamic> cambios) async {
    await supabase.from('elementos').update(cambios).eq('id', id);
  }

  /// Crea un elemento nuevo (admin o coordinador).
  static Future<void> crearElemento(Map<String, dynamic> datos) async {
    await supabase.from('elementos').insert(datos);
  }

  // ---- Galería de imágenes del elemento (máximo 3) ----
  static const _baldeImagenes = 'elementos-img';
  static const maxImagenes = 3;

  /// Fotos de un elemento, la principal primero.
  static Future<List<ImagenElem>> imagenesElemento(String elementoId) async {
    final res = await supabase
        .rpc('imagenes_elemento', params: {'p_elemento': elementoId});
    return (res as List)
        .map((e) => ImagenElem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Agrega una foto a la galería. La base rechaza si ya hay 3.
  /// Cada archivo va en su propia carpeta: {elemento_id}/{marca}.jpg
  static Future<void> agregarImagen(String elementoId, Uint8List bytes) async {
    final ruta = '$elementoId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await supabase.storage.from(_baldeImagenes).uploadBinary(
          ruta,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    final url = supabase.storage.from(_baldeImagenes).getPublicUrl(ruta);
    // El disparador de la base marca la principal y actualiza elementos.imagen_url
    await supabase.from('elemento_imagenes').insert({
      'elemento_id': elementoId,
      'url': url,
      'ruta': ruta,
      'usuario_id': supabase.auth.currentUser?.id,
    });
    // Huella visual para reconocer el elemento por foto.
    final h = PHash.dhash(bytes);
    if (h != null) {
      await supabase.from('elementos').update({'phash': h}).eq('id', elementoId);
    }
  }

  /// Reconoce un elemento a partir de una foto (compara huellas visuales).
  /// Devuelve los mejores candidatos (más parecidos primero).
  static Future<List<Elemento>> reconocerPorFoto(Uint8List bytes) async {
    final q = PHash.dhash(bytes);
    if (q == null) return [];
    final res = await supabase.from('elementos')
        .select('id,nombre,material,sch,unidad,codigo_barras,imagen_url,'
            'existencia,costo_promedio,stock_minimo,phash')
        .eq('activo', true)
        .not('phash', 'is', null);
    final lista = (res as List)
        .map((e) => (Elemento.fromMap(e as Map<String, dynamic>),
            PHash.hamming(q, e['phash'] as String)))
        .toList();
    lista.sort((a, b) => a.$2.compareTo(b.$2));
    return lista.take(8).map((e) => e.$1).toList();
  }

  // ---- Serializados (elementos con serial, ej. Blowers) ----
  static Future<List<Serie>> seriesDisponibles(String elementoId, String bodegaId) async {
    final res = await supabase.from('series')
        .select('id, serial, bodega_id, estado, costo')
        .eq('elemento_id', elementoId).eq('bodega_id', bodegaId)
        .eq('estado', 'disponible').order('serial');
    return (res as List).map((e) => Serie.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Serie>> seriesDeElemento(String elementoId) async {
    final res = await supabase.from('series')
        .select('id, serial, bodega_id, estado, costo, bodegas(nombre)')
        .eq('elemento_id', elementoId).order('estado').order('serial');
    return (res as List).map((e) => Serie.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Marca un elemento como serializado y carga los seriales de sus unidades
  /// actuales. items = [{bodega_id, serial, costo}].
  static Future<void> serializarElemento(
      String elementoId, List<Map<String, dynamic>> items) async {
    await supabase.rpc('serializar_elemento',
        params: {'p_elemento': elementoId, 'p_items': items});
    revision.value++;
  }

  /// Movimiento de un elemento serializado (por operaciones directas: el
  /// trigger de `series` mantiene las existencias).
  static Future<void> moverSerie({
    required String tipo, required String elementoId, required String bodegaId,
    required List<String> serials, num? costo, String? centroCostoId,
    String? observacion, String? bodegaDestinoId}) async {
    final uid = supabase.auth.currentUser?.id;
    final n = serials.length;
    final ahora = DateTime.now().toUtc().toIso8601String();
    if (tipo == 'entrada') {
      final mov = await supabase.from('movimientos').insert({
        'tipo': 'entrada', 'elemento_id': elementoId, 'bodega_id': bodegaId,
        'cantidad': n, 'costo_unitario': costo ?? 0, 'observacion': observacion,
        'usuario_id': uid, 'fecha': ahora,
      }).select('id').single();
      await supabase.from('series').insert(serials.map((s) => {
        'elemento_id': elementoId, 'serial': s, 'bodega_id': bodegaId,
        'costo': costo ?? 0, 'movimiento_ingreso': mov['id'],
      }).toList());
    } else if (tipo == 'salida') {
      final mov = await supabase.from('movimientos').insert({
        'tipo': 'salida', 'elemento_id': elementoId, 'bodega_id': bodegaId,
        'cantidad': n, 'centro_costo_id': centroCostoId, 'observacion': observacion,
        'usuario_id': uid, 'fecha': ahora,
      }).select('id').single();
      await supabase.from('series')
          .update({'estado': 'consumido', 'movimiento_salida': mov['id']})
          .eq('elemento_id', elementoId).eq('bodega_id', bodegaId)
          .eq('estado', 'disponible').inFilter('serial', serials);
    } else if (tipo == 'traslado') {
      await supabase.from('movimientos').insert([
        {'tipo': 'salida', 'elemento_id': elementoId, 'bodega_id': bodegaId,
         'cantidad': n, 'costo_unitario': null, 'referencia': 'TRASLADO',
         'observacion': observacion, 'usuario_id': uid, 'fecha': ahora},
        {'tipo': 'entrada', 'elemento_id': elementoId, 'bodega_id': bodegaDestinoId,
         'cantidad': n, 'costo_unitario': costo ?? 0, 'referencia': 'TRASLADO',
         'observacion': observacion, 'usuario_id': uid, 'fecha': ahora},
      ]);
      await supabase.from('series').update({'bodega_id': bodegaDestinoId})
          .eq('elemento_id', elementoId).eq('bodega_id', bodegaId)
          .eq('estado', 'disponible').inFilter('serial', serials);
    }
    revision.value++;
  }

  /// Borra una foto de la galería (archivo + registro).
  static Future<void> borrarImagen(ImagenElem img) async {
    await supabase.from('elemento_imagenes').delete().eq('id', img.id);
    try {
      await supabase.storage.from(_baldeImagenes).remove([img.ruta]);
    } catch (_) {
      // Si el archivo ya no existe, el registro igual quedó borrado.
    }
  }

  /// Marca una foto como la principal (la que sale en la lista).
  static Future<void> marcarPrincipal(String imagenId) async {
    await supabase
        .from('elemento_imagenes')
        .update({'principal': true}).eq('id', imagenId);
  }

  // ---- Auditoría ----
  /// Historial de cambios de un registro concreto.
  static Future<List<Auditoria>> historialRegistro(String tabla, String id) async {
    final res = await supabase.rpc('historial_registro',
        params: {'p_tabla': tabla, 'p_id': id});
    return (res as List).map((e) => Auditoria.fromMap(e as Map<String, dynamic>)).toList();
  }

  /// Auditoría reciente global.
  static Future<List<Auditoria>> auditoriaReciente({int limite = 100}) async {
    final res = await supabase.rpc('auditoria_reciente', params: {'p_limit': limite});
    return (res as List).map((e) => Auditoria.fromMap(e as Map<String, dynamic>)).toList();
  }

  static Future<void> cambiarPassword(String nueva) async {
    await supabase.auth.updateUser(UserAttributes(password: nueva));
  }

  /// Registra un movimiento (entrada / salida / ajuste).
  ///
  /// Si no hay señal NO se pierde: queda en la cola local y sube solo cuando
  /// vuelva el internet. Devuelve true si se guardó directo en el servidor,
  /// false si quedó pendiente de subir.
  static Future<bool> registrarMovimiento({
    required String tipo,
    required String elementoId,
    required String bodegaId,
    required num cantidad,
    String? centroCostoId,
    num? costoUnitario,
    String? referencia,
    String? observacion,
  }) async {
    // (device_id, local_id) es la llave que impide subir dos veces lo mismo.
    final deviceId = await LocalStore.deviceId();
    // En web solo hay precisión de milisegundos: dos movimientos en el mismo
    // ms tendrían igual id y uno se perdería. Se añade un sufijo aleatorio.
    final localId = '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random().nextInt(0xFFFFFF).toRadixString(16)}';

    final fila = {
      'tipo': tipo,
      'elemento_id': elementoId,
      'bodega_id': bodegaId,
      'cantidad': cantidad,
      'centro_costo_id': centroCostoId,
      'costo_unitario': costoUnitario,
      'referencia': referencia,
      'observacion': observacion,
      'usuario_id': supabase.auth.currentUser?.id,
      'fecha': DateTime.now().toUtc().toIso8601String(),
      'device_id': deviceId,
      'local_id': localId,
    };

    try {
      await supabase.from('movimientos').insert(fila);
      SyncService.enLinea.value = true;
      revision.value++;
      return true;
    } on Object catch (e) {
      // Si el rechazo viene de una REGLA DEL NEGOCIO (por ejemplo, no hay
      // existencia suficiente), no se encola: es un error real que el
      // usuario debe ver y corregir, no un problema de red.
      final txt = e.toString();
      if (txt.contains('Existencia insuficiente') ||
          txt.contains('obligatorio') ||
          txt.contains('violates row-level security')) {
        rethrow;
      }
      // Falla de red: antes de encolar una SALIDA, validar el stock local
      // para no sacar más de lo que hay (el servidor la rechazaría después).
      if (tipo == 'salida') {
        final existLocal = await LocalStore.existenciaLocal(elementoId);
        if (existLocal != null && cantidad > existLocal) {
          throw Exception('Existencia insuficiente: hay $existLocal y se '
              'intenta sacar $cantidad');
        }
      }
      // Guardar en la cola y ajustar el stock local para que el bodeguero
      // vea la existencia correcta mientras tanto.
      await LocalStore.encolar(fila);
      await LocalStore.ajustarExistenciaLocal(
          elementoId, tipo == 'salida' ? -cantidad : cantidad);
      SyncService.enLinea.value = false;
      await SyncService.refrescarPendientes();
      revision.value++;
      return false;
    }
  }
}
