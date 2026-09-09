// Modelos y acceso a datos del Módulo de EQUIPOS (Supabase).
//
// Módulo aparte del inventario de venta (activos-no-son-elementos.md): sin
// ninguna FK hacia elementos/movimientos. Diseño completo en
// docs/plan-modulo-equipos.md — sección 3 (modelo de datos) y 11 (fases).
// Esta es la Fase 2: capa de datos, CRUD paginado desde el día 1, igual que
// InventarioService en data.dart. Sin pantallas todavía (Fase 4).
import 'package:flutter/foundation.dart';
import 'data.dart';

class ActivoReferencia {
  final String id;
  final String nombre;
  final String? marca;
  final String? modelo;
  final String? tipo;
  final bool activo;

  ActivoReferencia.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      nombre = m['nombre'] as String,
      marca = m['marca'] as String?,
      modelo = m['modelo'] as String?,
      tipo = m['tipo'] as String?,
      activo = (m['activo'] ?? true) as bool;

  String get etiqueta => [
    nombre,
    marca,
    modelo,
  ].where((e) => e != null && e.isNotEmpty).join(' · ');

  // Igualdad por id: mismo motivo que Bodega/CentroCosto en data.dart, para
  // que un DropdownButtonFormField no pierda la selección al recargar.
  @override
  bool operator ==(Object other) => other is ActivoReferencia && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class ActivoTercero {
  final String id;
  final String nombre;
  final String? tipo;
  final String? contacto;
  final bool activo;

  ActivoTercero.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      nombre = m['nombre'] as String,
      tipo = m['tipo'] as String?,
      contacto = m['contacto'] as String?,
      activo = (m['activo'] ?? true) as bool;

  @override
  bool operator ==(Object other) => other is ActivoTercero && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Activo {
  final String id;
  final String referenciaId;
  final String? referenciaNombre;
  final String serial;
  final String condicion; // nuevo | usado | repuestos | baja
  // operativo | mantenimiento_interno | mantenimiento_externo | entregado | baja
  final String estado;
  final String? mantenimientoActor;
  final String bodegaId;
  final String? bodegaNombre;
  final num valorNuevo;
  final num porcentajeValor;
  final num valorActual;
  final String? observacion;
  final DateTime creadoEn;

  Activo.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      referenciaId = m['referencia_id'] as String,
      referenciaNombre =
          (m['activo_referencias'] as Map?)?['nombre'] as String?,
      serial = m['serial'] as String,
      condicion = m['condicion'] as String,
      estado = m['estado'] as String,
      mantenimientoActor = m['mantenimiento_actor'] as String?,
      bodegaId = m['bodega_id'] as String,
      bodegaNombre = (m['bodegas'] as Map?)?['nombre'] as String?,
      valorNuevo = (m['valor_nuevo'] ?? 0) as num,
      porcentajeValor = (m['porcentaje_valor'] ?? 100) as num,
      valorActual = (m['valor_actual'] ?? 0) as num,
      observacion = m['observacion'] as String?,
      creadoEn = DateTime.parse(m['creado_en'] as String);

  static const _etiquetasEstado = {
    'operativo': 'Operativo',
    'mantenimiento_interno': 'En mantenimiento (interno)',
    'mantenimiento_externo': 'En mantenimiento (externo)',
    'entregado': 'Entregado',
    'baja': 'De baja',
  };
  String get estadoEtiqueta => _etiquetasEstado[estado] ?? estado;

  static const _etiquetasCondicion = {
    'nuevo': 'Nuevo',
    'usado': 'Usado',
    'repuestos': 'Para repuestos',
    'baja': 'De baja',
  };
  String get condicionEtiqueta => _etiquetasCondicion[condicion] ?? condicion;
}

/// Fila de la vista `activos_disponibilidad`: el activo + su ubicación
/// vigente + si está disponible (derivado, nunca un campo manual).
class ActivoDisponibilidad {
  final Activo activo;
  final bool disponible;
  final String? ubicacionBodegaId;
  final String? ubicacionTerceroId;
  final DateTime? ubicacionDesde;

  ActivoDisponibilidad.fromMap(Map<String, dynamic> m)
    : activo = Activo.fromMap(m),
      disponible = (m['disponible'] ?? false) as bool,
      ubicacionBodegaId = m['ubicacion_actual_bodega_id'] as String?,
      ubicacionTerceroId = m['ubicacion_actual_tercero_id'] as String?,
      ubicacionDesde = m['ubicacion_actual_desde'] == null
          ? null
          : DateTime.parse(m['ubicacion_actual_desde'] as String);
}

class ActivoUbicacion {
  final String id;
  final String activoId;
  final String? bodegaId;
  final String? bodegaNombre;
  final String? terceroId;
  final String? terceroNombre;
  final String? detalle;
  final DateTime fechaDesde;
  final DateTime? fechaHasta;
  final String? usuarioEmail;

  ActivoUbicacion.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      activoId = m['activo_id'] as String,
      bodegaId = m['bodega_id'] as String?,
      bodegaNombre = (m['bodegas'] as Map?)?['nombre'] as String?,
      terceroId = m['tercero_id'] as String?,
      terceroNombre = (m['activo_terceros'] as Map?)?['nombre'] as String?,
      detalle = m['detalle'] as String?,
      fechaDesde = DateTime.parse(m['fecha_desde'] as String),
      fechaHasta = m['fecha_hasta'] == null
          ? null
          : DateTime.parse(m['fecha_hasta'] as String),
      usuarioEmail = m['usuario_email'] as String?;

  bool get vigente => fechaHasta == null;
  String get lugar => bodegaNombre ?? terceroNombre ?? '—';
}

class ActivoPieza {
  final String id;
  final String activoId;
  final String nombre;
  final String estado; // buena | mala | desconocido
  final String? observacion;
  final String? actualizadoEmail;
  final DateTime actualizadoEn;

  ActivoPieza.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      activoId = m['activo_id'] as String,
      nombre = m['nombre'] as String,
      estado = (m['estado'] ?? 'desconocido') as String,
      observacion = m['observacion'] as String?,
      actualizadoEmail = m['actualizado_email'] as String?,
      actualizadoEn = DateTime.parse(m['actualizado_en'] as String);
}

class ActivoMantenimiento {
  final String id;
  final String activoId;
  final DateTime fecha;
  final String? tipo;
  final String descripcion;
  final String? responsable;
  final num costo;
  final String? usuarioEmail;

  ActivoMantenimiento.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      activoId = m['activo_id'] as String,
      fecha = DateTime.parse(m['fecha'] as String),
      tipo = m['tipo'] as String?,
      descripcion = m['descripcion'] as String,
      responsable = m['responsable'] as String?,
      costo = (m['costo'] ?? 0) as num,
      usuarioEmail = m['usuario_email'] as String?;
}

class ActivoMovimiento {
  final String id;
  final String activoId;
  final String tipo; // entrada | salida | ajuste
  final String? anulaMovimientoId;
  final String? centroCostoId;
  final String? centroCosto;
  final String? centroCostoDestino;
  final String? bodega;
  final String? condicion;
  final bool? usable;
  final num? valor;
  final String? observacion;
  final String? usuarioEmail;
  final DateTime fecha;

  ActivoMovimiento.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      activoId = m['activo_id'] as String,
      tipo = m['tipo'] as String,
      anulaMovimientoId = m['anula_movimiento_id'] as String?,
      centroCostoId = m['centro_costo_id'] as String?,
      centroCosto = (m['centros_costo'] as Map?)?['codigo'] as String?,
      centroCostoDestino =
          (m['centro_costo_destino'] as Map?)?['codigo'] as String?,
      bodega = (m['bodegas'] as Map?)?['nombre'] as String?,
      condicion = m['condicion'] as String?,
      usable = m['usable'] as bool?,
      valor = m['valor'] as num?,
      observacion = m['observacion'] as String?,
      usuarioEmail = m['usuario_email'] as String?,
      fecha = DateTime.parse(m['fecha'] as String);

  /// Igual criterio que MovKardex.esAnulacion en data.dart.
  bool get esAnulacion => anulaMovimientoId != null;
}

/// Valorizado de una bodega, sumando los dos módulos. La suma la hace la
/// base con dos agregaciones independientes (sección 9.1 del plan).
class ValorizadoBodega {
  final String bodega;
  final num inventario;
  final num equipos;
  final num total;

  ValorizadoBodega.fromMap(Map<String, dynamic> m)
    : bodega = (m['bodega'] ?? '') as String,
      inventario = (m['valorizado_inventario'] ?? 0) as num,
      equipos = (m['valorizado_equipos'] ?? 0) as num,
      total = (m['valorizado_total'] ?? 0) as num;
}

/// Fila del Nivel 1: un modelo con sus contadores, agregados en la base.
class ResumenReferencia {
  final String referenciaId;
  final String nombre;
  final String? marca;
  final String? modelo;
  final int total;
  final int disponibles;

  ResumenReferencia.fromMap(Map<String, dynamic> m)
    : referenciaId = m['referencia_id'] as String,
      nombre = m['nombre'] as String,
      marca = m['marca'] as String?,
      modelo = m['modelo'] as String?,
      total = ((m['total'] ?? 0) as num).toInt(),
      disponibles = ((m['disponibles'] ?? 0) as num).toInt();

  int get noDisponibles => total - disponibles;

  String get etiqueta => [
    nombre,
    marca,
    modelo,
  ].where((e) => e != null && e.isNotEmpty).join(' · ');
}

class ActivosService {
  /// Mismo patrón que InventarioService.revision: las pantallas que lo
  /// escuchan se recargan solas tras un alta/movimiento/cambio de ubicación.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static const _selectMovimiento =
      'id, activo_id, tipo, anula_movimiento_id, condicion, usable, valor, '
      'centro_costo_id, observacion, usuario_email, fecha, '
      'bodegas(nombre), '
      'centros_costo!activo_movimientos_centro_costo_id_fkey(codigo), '
      'centro_costo_destino:centros_costo!activo_movimientos_centro_costo_destino_id_fkey(codigo)';

  // ---------------------------------------------------------------------
  // Referencias (catálogo de modelos)
  // ---------------------------------------------------------------------

  static Future<List<ActivoReferencia>> referencias({
    int offset = 0,
    int limit = 100,
    bool soloActivas = true,
  }) async {
    var q = supabase.from('activo_referencias').select();
    if (soloActivas) q = q.eq('activo', true);
    final res = await q.order('nombre').range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoReferencia.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ActivoReferencia> crearReferencia({
    required String nombre,
    String? marca,
    String? modelo,
    String? tipo,
  }) async {
    final res = await supabase
        .from('activo_referencias')
        .insert({'nombre': nombre, 'marca': marca, 'modelo': modelo, 'tipo': tipo})
        .select()
        .single();
    revision.value++;
    return ActivoReferencia.fromMap(res);
  }

  static Future<void> editarReferencia(
    String id, {
    String? nombre,
    String? marca,
    String? modelo,
    String? tipo,
    bool? activo,
  }) async {
    final cambios = <String, dynamic>{};
    if (nombre != null) cambios['nombre'] = nombre;
    if (marca != null) cambios['marca'] = marca;
    if (modelo != null) cambios['modelo'] = modelo;
    if (tipo != null) cambios['tipo'] = tipo;
    if (activo != null) cambios['activo'] = activo;
    if (cambios.isEmpty) return;
    await supabase.from('activo_referencias').update(cambios).eq('id', id);
    revision.value++;
  }

  // ---------------------------------------------------------------------
  // Terceros (talleres/clientes/proveedores externos)
  // ---------------------------------------------------------------------

  static Future<List<ActivoTercero>> terceros({
    int offset = 0,
    int limit = 100,
    bool soloActivos = true,
  }) async {
    var q = supabase.from('activo_terceros').select();
    if (soloActivos) q = q.eq('activo', true);
    final res = await q.order('nombre').range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoTercero.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ActivoTercero> crearTercero({
    required String nombre,
    String? tipo,
    String? contacto,
  }) async {
    final res = await supabase
        .from('activo_terceros')
        .insert({'nombre': nombre, 'tipo': tipo, 'contacto': contacto})
        .select()
        .single();
    revision.value++;
    return ActivoTercero.fromMap(res);
  }

  static Future<void> editarTercero(
    String id, {
    String? nombre,
    String? tipo,
    String? contacto,
    bool? activo,
  }) async {
    final cambios = <String, dynamic>{};
    if (nombre != null) cambios['nombre'] = nombre;
    if (tipo != null) cambios['tipo'] = tipo;
    if (contacto != null) cambios['contacto'] = contacto;
    if (activo != null) cambios['activo'] = activo;
    if (cambios.isEmpty) return;
    await supabase.from('activo_terceros').update(cambios).eq('id', id);
    revision.value++;
  }

  // ---------------------------------------------------------------------
  // Activos (equipos individuales)
  // ---------------------------------------------------------------------

  /// Valorizado por bodega, inventario + equipos.
  static Future<List<ValorizadoBodega>> valorizadoPorBodega() async {
    final res = await supabase.rpc('valorizado_total_por_bodega');
    return (res as List)
        .map((e) => ValorizadoBodega.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Nivel 1: resumen por modelo, contado en la base.
  static Future<List<ResumenReferencia>> resumenPorReferencia() async {
    final res = await supabase.rpc('activos_resumen_por_referencia');
    return (res as List)
        .map((e) => ResumenReferencia.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static const _selectActivo =
      '*, activo_referencias(nombre), bodegas(nombre)';

  /// Listado general, con filtros opcionales. `q` busca por serial (además
  /// del filtro por nombre de referencia, que se hace en el cliente porque
  /// requiere el join). Paginado desde el día 1.
  static Future<List<Activo>> listar({
    int offset = 0,
    int limit = 50,
    String? estado,
    String? bodegaId,
    String? referenciaId,
    String? serial,
  }) async {
    var q = supabase.from('activos').select(_selectActivo);
    if (estado != null) q = q.eq('estado', estado);
    if (bodegaId != null) q = q.eq('bodega_id', bodegaId);
    if (referenciaId != null) q = q.eq('referencia_id', referenciaId);
    if (serial != null && serial.trim().isNotEmpty) {
      q = q.ilike('serial', '%${serial.trim()}%');
    }
    final res = await q
        .order('creado_en', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => Activo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Activo?> porSerial(String serial) async {
    final res = await supabase
        .from('activos')
        .select(_selectActivo)
        .eq('serial', serial)
        .maybeSingle();
    return res == null ? null : Activo.fromMap(res);
  }

  static Future<Activo> detalle(String id) async {
    final res = await supabase
        .from('activos')
        .select(_selectActivo)
        .eq('id', id)
        .single();
    return Activo.fromMap(res);
  }

  /// Consulta la vista `activos_disponibilidad`, donde "disponible" es una
  /// regla derivada (`estado='operativo'` + ubicación vigente en bodega
  /// propia), nunca un campo manual.
  ///
  /// [disponible] en null trae todos; en true/false filtra.
  static Future<List<ActivoDisponibilidad>> disponibles({
    int offset = 0,
    int limit = 50,
    bool? disponible = true,
    String? bodegaId,
    String? referenciaId,
  }) async {
    // OJO: la vista llega a `bodegas` por DOS caminos (la bodega dueña y la
    // de la ubicación vigente), así que hay que calificar la FK o PostgREST
    // responde PGRST201 — el mismo error que ya nos mordió con los centros
    // de costo. Aquí se quiere la bodega DUEÑA.
    var q = supabase
        .from('activos_disponibilidad')
        .select('*, activo_referencias(nombre), '
            'bodegas!activos_bodega_id_fkey(nombre)');
    if (disponible != null) q = q.eq('disponible', disponible);
    if (bodegaId != null) q = q.eq('ubicacion_actual_bodega_id', bodegaId);
    if (referenciaId != null) q = q.eq('referencia_id', referenciaId);
    final res = await q.order('serial').range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoDisponibilidad.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// En mantenimiento (interno o externo), para la 4ª pestaña del módulo.
  static Future<List<Activo>> enMantenimiento({
    int offset = 0,
    int limit = 50,
  }) async {
    final res = await supabase
        .from('activos')
        .select(_selectActivo)
        .inFilter('estado', ['mantenimiento_interno', 'mantenimiento_externo'])
        .order('creado_en', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => Activo.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Alta de un equipo nuevo: crea el activo y su primer movimiento de
  /// 'entrada' (abre la ubicación inicial vía el trigger de negocio). No es
  /// una transacción real (el cliente no puede abrir una), mismo riesgo que
  /// ya asume moverSerie() en data.dart para el inventario normal.
  static Future<Activo> alta({
    required String referenciaId,
    required String serial,
    required String condicion, // nuevo | usado | repuestos | baja
    required String bodegaId,
    required num valorNuevo,
    num porcentajeValor = 100,
    String? mantenimientoActor,
    String? observacion,
    required String centroCostoId,
    String? centroCostoDestinoId,
    bool? usable,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    final email = supabase.auth.currentUser?.email;
    final res = await supabase
        .from('activos')
        .insert({
          'referencia_id': referenciaId,
          'serial': serial,
          'condicion': condicion,
          'bodega_id': bodegaId,
          'valor_nuevo': valorNuevo,
          'porcentaje_valor': porcentajeValor,
          'mantenimiento_actor': mantenimientoActor,
          'observacion': observacion,
          'creado_por': uid,
          'creado_email': email,
        })
        .select(_selectActivo)
        .single();
    final activo = Activo.fromMap(res);

    await supabase.from('activo_movimientos').insert({
      'activo_id': activo.id,
      'tipo': 'entrada',
      'centro_costo_id': centroCostoId,
      'centro_costo_destino_id': centroCostoDestinoId,
      'bodega_id': bodegaId,
      // Nunca 'repuestos' en un movimiento: es una reclasificación posterior.
      'condicion': condicion == 'repuestos' ? 'usado' : condicion,
      'usable': condicion == 'usado' ? (usable ?? true) : null,
      'usuario_id': uid,
      'usuario_email': email,
    });
    revision.value++;
    return activo;
  }

  /// Ajusta la valorización de un equipo. `valor_actual` es una columna
  /// generada, así que se recalcula sola.
  static Future<void> actualizarValor(
    String activoId, {
    num? valorNuevo,
    num? porcentajeValor,
  }) async {
    final cambios = <String, dynamic>{};
    if (valorNuevo != null) cambios['valor_nuevo'] = valorNuevo;
    if (porcentajeValor != null) cambios['porcentaje_valor'] = porcentajeValor;
    if (cambios.isEmpty) return;
    await supabase.from('activos').update(cambios).eq('id', activoId);
    revision.value++;
  }

  /// Estados que se pueden poner a mano desde la ficha del equipo.
  ///
  /// `entregado` NO está y no debe estarlo: ese estado significa que el
  /// equipo salió del inventario, y eso solo puede pasar registrando una
  /// salida real. Ponerlo a mano dejaría el inventario diciendo una cosa y
  /// los movimientos otra. Lo mismo al revés: un equipo entregado solo
  /// vuelve con una entrada, así que a ese no se le cambia el estado a mano.
  static const estadosManuales = [
    'operativo',
    'mantenimiento_interno',
    'mantenimiento_externo',
    'baja',
  ];

  /// Saca un equipo de mantenimiento, lo manda a un taller externo o lo da
  /// de baja. Es el contrapeso del trigger: la base pone el estado cuando
  /// hay un movimiento, y esto lo ajusta cuando el cambio ocurre sin que
  /// entre ni salga nada (se reparó, se mandó al taller, se dio de baja).
  ///
  /// [mantenimientoActor] es texto libre a propósito (decisión explícita
  /// del usuario) y solo aplica a `mantenimiento_externo`: en cualquier
  /// otro estado se limpia, para no dejar colgado el nombre de un taller
  /// donde el equipo ya no está.
  static Future<void> cambiarEstado(
    String activoId, {
    required String estado,
    String? mantenimientoActor,
  }) async {
    if (!estadosManuales.contains(estado)) {
      throw ArgumentError(
          'El estado "$estado" no se puede poner a mano: depende de un movimiento.');
    }
    await supabase.from('activos').update({
      'estado': estado,
      'mantenimiento_actor':
          estado == 'mantenimiento_externo' ? mantenimientoActor : null,
    }).eq('id', activoId);
    revision.value++;
  }

  /// Cambia la condición de un equipo (por ejemplo, reclasificarlo a
  /// 'repuestos'). Es una decisión manual posterior, nunca parte de un
  /// movimiento.
  static Future<void> cambiarCondicion(String activoId, String condicion) async {
    await supabase
        .from('activos')
        .update({'condicion': condicion})
        .eq('id', activoId);
    revision.value++;
  }

  /// Reingreso de un equipo existente (vuelve de mantenimiento externo, de
  /// un cliente, etc.): sección 3.7 del plan.
  static Future<void> registrarEntrada({
    required String activoId,
    required String centroCostoId,
    String? centroCostoDestinoId,
    required String bodegaId,
    required String condicion, // nuevo | usado | baja
    bool? usable,
    num? valor,
    String? observacion,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    await supabase.from('activo_movimientos').insert({
      'activo_id': activoId,
      'tipo': 'entrada',
      'centro_costo_id': centroCostoId,
      'centro_costo_destino_id': centroCostoDestinoId,
      'bodega_id': bodegaId,
      'condicion': condicion,
      'usable': condicion == 'usado' ? (usable ?? true) : null,
      'valor': valor,
      'observacion': observacion,
      'usuario_id': uid,
      'usuario_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  /// Salida a un centro de costo (interno o de cliente). Si no se manda
  /// `valor`, el trigger lo estampa con `activos.valor_actual` vigente.
  static Future<void> registrarSalida({
    required String activoId,
    required String centroCostoId,
    num? valor,
    String? observacion,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    await supabase.from('activo_movimientos').insert({
      'activo_id': activoId,
      'tipo': 'salida',
      'centro_costo_id': centroCostoId,
      'valor': valor,
      'observacion': observacion,
      'usuario_id': uid,
      'usuario_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  /// Anula un movimiento (nunca lo borra: inserta un 'ajuste' enlazado).
  /// Rechaza anular la alta (primer movimiento) de un equipo — ver
  /// `anular_activo_movimiento()` en la migración.
  static Future<void> anularMovimiento(String movId, {String? motivo}) async {
    await supabase.rpc(
      'anular_activo_movimiento',
      params: {'p_mov': movId, 'p_motivo': motivo},
    );
    revision.value++;
  }

  /// Kardex de movimientos de un equipo, más reciente primero, paginado.
  static Future<List<ActivoMovimiento>> movimientos(
    String activoId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final res = await supabase
        .from('activo_movimientos')
        .select(_selectMovimiento)
        .eq('activo_id', activoId)
        .order('fecha', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoMovimiento.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Fecha del primer movimiento de equipos que existe. Sirve para el
  /// "desde el principio de los tiempos" de los informes: se pregunta la
  /// fecha real en vez de barrer años vacíos.
  static Future<DateTime?> primeraFechaMovimiento() async {
    final res = await supabase
        .from('activo_movimientos')
        .select('fecha')
        .order('fecha')
        .limit(1)
        .maybeSingle();
    return res == null ? null : DateTime.parse(res['fecha'] as String);
  }

  /// Ids de movimientos ya anulados de un equipo (para marcar "ANULADO" sin
  /// importar en qué página de kardex quedó el original). Mismo patrón que
  /// InventarioService.idsAnuladosDeElemento.
  static Future<Set<String>> idsAnuladosDeActivo(String activoId) async {
    final res = await supabase
        .from('activo_movimientos')
        .select('anula_movimiento_id')
        .eq('activo_id', activoId)
        .not('anula_movimiento_id', 'is', null);
    return (res as List)
        .map((r) => r['anula_movimiento_id'] as String)
        .toSet();
  }

  // ---------------------------------------------------------------------
  // Ubicaciones
  // ---------------------------------------------------------------------

  static const _selectUbicacion =
      'id, activo_id, bodega_id, tercero_id, detalle, fecha_desde, '
      'fecha_hasta, usuario_email, bodegas(nombre), activo_terceros(nombre)';

  /// Historial de ubicación de un equipo, más reciente primero, paginado.
  static Future<List<ActivoUbicacion>> historialUbicacion(
    String activoId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final res = await supabase
        .from('activo_ubicaciones')
        .select(_selectUbicacion)
        .eq('activo_id', activoId)
        .order('fecha_desde', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoUbicacion.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ActivoUbicacion?> ubicacionVigente(String activoId) async {
    final res = await supabase
        .from('activo_ubicaciones')
        .select(_selectUbicacion)
        .eq('activo_id', activoId)
        .isFilter('fecha_hasta', null)
        .maybeSingle();
    return res == null ? null : ActivoUbicacion.fromMap(res);
  }

  /// Cambia la ubicación física de un equipo (RPC: cierra la vigente, abre
  /// la nueva en un solo paso). Exactamente una de bodegaId/terceroId.
  static Future<void> cambiarUbicacion({
    required String activoId,
    String? bodegaId,
    String? terceroId,
    String? detalle,
  }) async {
    await supabase.rpc(
      'cambiar_ubicacion_activo',
      params: {
        'p_activo': activoId,
        'p_bodega_id': bodegaId,
        'p_tercero_id': terceroId,
        'p_detalle': detalle,
      },
    );
    revision.value++;
  }

  // ---------------------------------------------------------------------
  // Piezas (buenas/malas)
  // ---------------------------------------------------------------------

  static Future<List<ActivoPieza>> piezas(String activoId) async {
    final res = await supabase
        .from('activo_piezas')
        .select()
        .eq('activo_id', activoId)
        .order('nombre');
    return (res as List)
        .map((e) => ActivoPieza.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> agregarPieza({
    required String activoId,
    required String nombre,
    String estado = 'desconocido',
    String? observacion,
  }) async {
    await supabase.from('activo_piezas').insert({
      'activo_id': activoId,
      'nombre': nombre,
      'estado': estado,
      'observacion': observacion,
      'actualizado_por': supabase.auth.currentUser?.id,
      'actualizado_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  static Future<void> editarPieza(
    String id, {
    String? estado,
    String? observacion,
  }) async {
    final cambios = <String, dynamic>{
      'actualizado_por': supabase.auth.currentUser?.id,
      'actualizado_email': supabase.auth.currentUser?.email,
      'actualizado_en': DateTime.now().toUtc().toIso8601String(),
    };
    if (estado != null) cambios['estado'] = estado;
    if (observacion != null) cambios['observacion'] = observacion;
    await supabase.from('activo_piezas').update(cambios).eq('id', id);
    revision.value++;
  }

  // ---------------------------------------------------------------------
  // Mantenimientos (hoja de vida)
  // ---------------------------------------------------------------------

  static Future<List<ActivoMantenimiento>> mantenimientos(
    String activoId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final res = await supabase
        .from('activo_mantenimientos')
        .select()
        .eq('activo_id', activoId)
        .order('fecha', ascending: false)
        .range(offset, offset + limit - 1);
    return (res as List)
        .map((e) => ActivoMantenimiento.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> registrarMantenimiento({
    required String activoId,
    DateTime? fecha,
    String? tipo,
    required String descripcion,
    String? responsable,
    num costo = 0,
  }) async {
    await supabase.from('activo_mantenimientos').insert({
      'activo_id': activoId,
      'fecha': (fecha ?? DateTime.now()).toIso8601String().substring(0, 10),
      'tipo': tipo,
      'descripcion': descripcion,
      'responsable': responsable,
      'costo': costo,
      'usuario_id': supabase.auth.currentUser?.id,
      'usuario_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }
}
