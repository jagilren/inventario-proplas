// Modelos y acceso a datos (Supabase).
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        activo = (m['activo'] ?? true) as bool;

  bool get bajoMinimo => stockMinimo > 0 && existencia <= stockMinimo;
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
        orden = (m['orden'] ?? 0) as int;
}

class CentroCosto {
  final String id;
  final String codigo;
  final String? descripcion;
  final String? cliente;

  CentroCosto.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String,
        codigo = m['codigo'] as String,
        descripcion = m['descripcion'] as String?,
        cliente = m['cliente'] as String?;

  String get etiqueta =>
      [codigo, descripcion, cliente].where((e) => e != null && e.isNotEmpty).join(' · ');
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

  MovKardex.fromMap(Map<String, dynamic> m)
      : id = m['id'] as String?,
        fecha = DateTime.parse(m['fecha'] as String),
        tipo = m['tipo'] as String,
        cantidad = (m['cantidad'] ?? 0) as num,
        costoUnitario = m['costo_unitario'] as num?,
        centroCosto = m['centro_costo'] as String?,
        referencia = m['referencia'] as String?,
        observacion = m['observacion'] as String?;

  bool get esAnulacion => (referencia ?? '').startsWith('ANULACION');
}

class Resumen {
  final int totalElementos;
  final num valorizacionTotal;
  final int bajoMinimo;
  final int totalMovimientos;
  Resumen.fromMap(Map<String, dynamic> m)
      : totalElementos = (m['total_elementos'] ?? 0) as int,
        valorizacionTotal = (m['valorizacion_total'] ?? 0) as num,
        bajoMinimo = (m['bajo_minimo'] ?? 0) as int,
        totalMovimientos = (m['total_movimientos'] ?? 0) as int;
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

  static const todos = [admin, coordinador, operarioMas, operarioMenos];

  static String etiqueta(String rol) => switch (rol) {
        admin => 'Administrador',
        coordinador => 'Coordinador',
        operarioMas => 'Operario + (entradas)',
        operarioMenos => 'Operario − (salidas)',
        _ => rol,
      };
}

class InventarioService {
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

  static Future<List<MovKardex>> kardex(String elementoId) async {
    final res = await supabase.rpc('kardex_elemento', params: {'p_elemento': elementoId});
    return (res as List).map((e) => MovKardex.fromMap(e as Map<String, dynamic>)).toList();
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
    required num cantidad,
    String? centroCostoId,
    num? costoUnitario,
    String? referencia,
    String? observacion,
  }) async {
    // (device_id, local_id) es la llave que impide subir dos veces lo mismo.
    final deviceId = await LocalStore.deviceId();
    final localId = '${DateTime.now().microsecondsSinceEpoch}';

    final fila = {
      'tipo': tipo,
      'elemento_id': elementoId,
      'cantidad': cantidad,
      'centro_costo_id': centroCostoId,
      'costo_unitario': costoUnitario,
      'referencia': referencia,
      'observacion': observacion,
      'usuario_id': supabase.auth.currentUser?.id,
      'fecha': DateTime.now().toIso8601String(),
      'device_id': deviceId,
      'local_id': localId,
    };

    try {
      await supabase.from('movimientos').insert(fila);
      SyncService.enLinea.value = true;
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
      // Falla de red: guardar en la cola y ajustar el stock local para que
      // el bodeguero vea la existencia correcta mientras tanto.
      await LocalStore.encolar(fila);
      await LocalStore.ajustarExistenciaLocal(
          elementoId, tipo == 'salida' ? -cantidad : cantidad);
      SyncService.enLinea.value = false;
      await SyncService.refrescarPendientes();
      return false;
    }
  }
}
