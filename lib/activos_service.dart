// Modelos y acceso a datos del Módulo de EQUIPOS (Supabase).
//
// Módulo aparte del inventario de venta (activos-no-son-elementos.md): sin
// ninguna FK hacia elementos/movimientos. Diseño completo en
// docs/plan-modulo-equipos.md — sección 3 (modelo de datos) y 11 (fases).
// Esta es la Fase 2: capa de datos, CRUD paginado desde el día 1, igual que
// InventarioService en data.dart. Sin pantallas todavía (Fase 4).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, PostgrestFilterBuilder;
import 'data.dart';
import 'local_store.dart';
import 'sync_service.dart';

class ActivoReferencia {
  final String id;
  final String nombre;
  final String? marca;
  final String? modelo;
  final String? tipo;
  final bool activo;
  /// Referencia KITZABLE: sus equipos valen la suma de sus componentes
  /// (schema_v64). Inmutable en cuanto la referencia tenga equipos.
  final bool esKit;

  ActivoReferencia.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      nombre = m['nombre'] as String,
      marca = m['marca'] as String?,
      modelo = m['modelo'] as String?,
      tipo = m['tipo'] as String?,
      activo = (m['activo'] ?? true) as bool,
      esKit = (m['es_kit'] ?? false) as bool;

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
  /// Para mostrar junto a la referencia en los resultados de búsqueda: si
  /// alguien busca "grundfos", tiene que ver por qué salió ese equipo.
  final String? referenciaMarca;
  /// Si su referencia es un kit: su valor nuevo lo calcula la base desde los
  /// componentes y NO se escribe a mano (schema_v64).
  final bool referenciaEsKit;
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
      referenciaMarca =
          (m['activo_referencias'] as Map?)?['marca'] as String?,
      referenciaEsKit =
          ((m['activo_referencias'] as Map?)?['es_kit'] ?? false) as bool,
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
  /// Para repuestos o de baja: puede estar en la bodega, pero NO se entrega.
  /// Misma regla que la vista `activos_disponibilidad` (schema_v55).
  bool get noEntregable => condicion == 'repuestos' || condicion == 'baja';

  /// "Operativo" solo quiere decir "listo para entregar" si la condición lo
  /// permite. Un equipo que volvió para repuestos queda en estado operativo
  /// (está en la bodega, no en mantenimiento) pero no se puede entregar, y
  /// la etiqueta tiene que decir eso y no "Operativo".
  String get estadoEtiqueta => estado == 'operativo' && noEntregable
      ? 'No disponible'
      : (_etiquetasEstado[estado] ?? estado);

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

/// Una línea del listado cronológico de observaciones del equipo. Viene de
/// la vista `activo_observaciones_todas`, que une tres orígenes distintos.
class ActivoObservacion {
  /// Id de la fila en su tabla de ORIGEN (activos, activo_ubicaciones o
  /// activo_observaciones, según [origen]). Es lo que se edita.
  final String id;
  final DateTime fecha;
  final String texto;
  final String origen; // alta | ubicacion | estado | manual
  final String? contexto;
  final String? usuarioEmail;
  /// Si el texto se cambió alguna vez después de escrito (schema_v60).
  final bool editada;

  ActivoObservacion.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      fecha = DateTime.parse(m['fecha'] as String),
      texto = m['texto'] as String,
      origen = m['origen'] as String,
      contexto = m['contexto'] as String?,
      usuarioEmail = m['usuario_email'] as String?,
      editada = (m['editada'] as bool?) ?? false;

  String get etiquetaOrigen => switch (origen) {
    'alta' => 'Al crear el equipo',
    'ubicacion' => 'Cambio de ubicación',
    'estado' => 'Cambio de estado',
    _ => 'Nota',
  };
}

/// Un cambio en el texto de una observación: quién, cuándo, y qué decía
/// antes y después.
class CambioObservacion {
  final DateTime fecha;
  final String? antes;
  final String? despues;
  final String? usuarioEmail;

  CambioObservacion.fromMap(Map<String, dynamic> m)
    : fecha = DateTime.parse(m['fecha'] as String),
      antes = m['antes'] as String?,
      despues = m['despues'] as String?,
      usuarioEmail = m['usuario_email'] as String?;
}

// ---------------------------------------------------------------------
// KITS — Referencias KITZABLES (docs/plan-kits-equipos.md, schema_v64)
// ---------------------------------------------------------------------

/// Error con un mensaje listo para mostrarle al usuario.
///
/// `toString()` devuelve SOLO el mensaje: en el resto de la app el error se
/// muestra con `'No se pudo guardar: $e'`, y un `Exception` normal saldría
/// como "Exception: ..." o con todo el "PostgrestException(message: ...,
/// code: P0001...)".
class ErrorEquipos implements Exception {
  final String mensaje;
  const ErrorEquipos(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Traduce un error de la base a algo que se le pueda decir al usuario.
///
/// La base de los kits ya responde en español cuando rompe una regla
/// (`raise exception`, código P0001: "No hay suficientes...", "Este
/// movimiento ya fue anulado"), así que esos se pasan tal cual. Lo que
/// viene en jerga de Postgres se traduce aquí, en UN solo sitio.
///
/// Función pura (sin red): se prueba en test/kits_modelos_test.dart.
String mensajeDeErrorEquipos(String? codigo, String mensaje) {
  switch (codigo) {
    case 'P0001':
      return mensaje;
    case '23505':
      if (mensaje.contains('activo_componentes_uniq')) {
        return 'Este kit ya tiene un componente con ese nombre.';
      }
      if (mensaje.contains('activo_comp_mov_anula_uniq')) {
        return 'Este movimiento ya fue anulado.';
      }
      return 'Ese registro ya existe.';
    case '23514':
      if (mensaje.contains('activo_comp_mov_tercero_check')) {
        return 'Para vender o dar en garantía hay que decir a quién (el tercero).';
      }
      return 'Hay un valor que no es válido: la cantidad tiene que ser mayor '
          'que cero y el valor no puede ser negativo.';
    case '42501':
      return 'No tienes permiso para hacer esto.';
    default:
      return mensaje;
  }
}

/// La forma en que la BASE compara nombres de componentes para el índice
/// único `activo_componentes_uniq`: sin espacios en los bordes, espacios
/// internos colapsados, en mayúsculas. (Sin quitar tildes: la base tampoco
/// las quita, así que "Guías" y "Guias" son distintos para ella.)
///
/// Si la app normalizara distinto, diría "está bien" y la base lo rechazaría
/// al guardar — o al revés.
String claveComponente(String nombre) =>
    nombre.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

/// Revisa la composición de un kit antes de mandarla a la base. Devuelve el
/// primer problema en palabras, o null si está bien.
///
/// Es lo mismo que la base vuelve a comprobar (agregar_componentes,
/// schema_v65), pero dicho ANTES de ir a la red y señalando cuál línea.
String? validarComposicionKit(List<ComponentePlantilla> lista) {
  if (lista.isEmpty) {
    return 'Agrégale al menos un componente: un kit vale la suma de sus partes.';
  }
  final vistos = <String>{};
  for (final c in lista) {
    final nombre = c.nombre.trim();
    if (nombre.isEmpty) return 'Hay un componente sin nombre.';
    if (c.cantidad <= 0) {
      return 'La cantidad de "$nombre" tiene que ser mayor que cero.';
    }
    if (c.valorUnitario < 0) {
      return 'El valor de "$nombre" no puede ser negativo.';
    }
    if (!vistos.add(claveComponente(nombre))) {
      return 'El componente "$nombre" está repetido.';
    }
  }
  return null;
}

/// Los tipos de movimiento de un componente, con todo lo que una pantalla
/// necesita saber de cada uno.
///
/// UN solo sitio para las etiquetas: si la ficha, la hoja de mover y el
/// informe armaran las suyas, tarde o temprano dirían cosas distintas (la
/// lección de la etiqueta de REINGRESO, schema_v63). Todas en palabras
/// completas, sin abreviaturas: también las lee un lector de pantalla.
enum TipoMovComponente {
  alta('alta',
      accion: 'Alta',
      historial: 'Alta',
      ayuda: 'Entró con el kit al crearlo.',
      suma: true),
  aumento('aumento',
      accion: 'Agregar',
      historial: 'Se agregó',
      ayuda: 'Entran más unidades al kit.',
      suma: true),
  disminucion('disminucion',
      accion: 'Retirar',
      historial: 'Se retiró',
      ayuda: 'Salen del kit sin destino: una corrección o un retiro.',
      suma: false),
  salidaVenta('salida_venta',
      accion: 'Vender',
      historial: 'Venta',
      ayuda: 'Se vendieron a un tercero. Hay que decir a quién.',
      suma: false,
      pideTercero: true),
  salidaGarantia('salida_garantia',
      accion: 'Garantía',
      historial: 'Garantía',
      ayuda: 'Se entregan como garantía a un tercero. Hay que decir a quién.',
      suma: false,
      pideTercero: true),
  bajaDano('baja_dano',
      accion: 'Daño',
      historial: 'Daño',
      ayuda: 'Se dañaron y salen del kit.',
      suma: false),
  anulacion('anulacion',
      accion: 'Anular',
      historial: 'Anulación',
      ayuda: 'Deshace un movimiento anterior con uno contrario.',
      suma: false);

  const TipoMovComponente(
    this.valor, {
    required this.accion,
    required this.historial,
    required this.ayuda,
    required this.suma,
    this.pideTercero = false,
  });

  /// Qué significa, en una frase. Se muestra al elegir la opción: la
  /// diferencia entre "Retirar" y "Daño" no es obvia para quien la ve la
  /// primera vez.
  final String ayuda;

  /// Como lo guarda la base.
  final String valor;
  /// Verbo para el botón o chip que lo dispara ("Vender").
  final String accion;
  /// Cómo se lee en el historial ("Venta").
  final String historial;
  /// Si suma al componente. La anulación NO tiene signo propio: toma el
  /// contrario del movimiento que anula, y la base se lo pone.
  final bool suma;
  /// Venta y garantía exigen decir a quién (constraint en la base).
  final bool pideTercero;

  /// Los que el usuario elige a mano en la hoja de mover un componente.
  /// `alta` la crea agregar_componente(); `anulacion`, el botón de anular.
  static const elegibles = [
    aumento,
    disminucion,
    salidaVenta,
    salidaGarantia,
    bajaDano,
  ];

  /// null si la base devuelve un tipo que esta versión de la app no conoce
  /// (por ejemplo, uno agregado después). Mejor mostrar el texto crudo que
  /// tumbar la pantalla.
  static TipoMovComponente? desde(String valor) {
    for (final t in values) {
      if (t.valor == valor) return t;
    }
    return null;
  }
}

/// Un componente de un kit: de qué está hecho el equipo.
class ActivoComponente {
  final String id;
  final String activoId;
  final String nombre;
  final num valorUnitario;
  /// DERIVADA de los movimientos en la base. La app la lee, nunca la escribe.
  final num cantidad;
  /// Columna generada en la base: cantidad × valor unitario.
  final num subtotal;
  final int orden;

  ActivoComponente.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      activoId = m['activo_id'] as String,
      nombre = m['nombre'] as String,
      valorUnitario = (m['valor_unitario'] ?? 0) as num,
      cantidad = (m['cantidad'] ?? 0) as num,
      subtotal = (m['subtotal'] ?? 0) as num,
      orden = (m['orden'] ?? 0) as int;

  /// Ya no queda nada (se retiró, vendió o dañó todo). Se sigue mostrando,
  /// atenuado: su historia no desaparece.
  bool get agotado => cantidad <= 0;

  /// El subtotal ponderado al porcentaje del equipo, SOLO para mostrar.
  /// El valor del kit lo calcula la base aplicando el porcentaje una sola
  /// vez al total (evita el arrastre de redondeo, plan §4.2).
  num subtotalAl(num porcentaje) => subtotal * porcentaje / 100;
}

/// Un movimiento de un componente: la vida del kit.
class MovimientoComponente {
  final String id;
  final String componenteId;
  /// Como lo guarda la base. Ver [tipo].
  final String tipoValor;
  /// +1 suma, −1 resta. Lo estampa la base al insertar.
  final int signo;
  final num cantidad;
  /// Estampado: lo que pasó, pasó a ese precio.
  final num valorUnitario;
  final String? terceroNombre;
  final String? anulaMovimientoId;
  final String? observacion;
  final String? usuarioEmail;
  final DateTime fecha;

  MovimientoComponente.fromMap(Map<String, dynamic> m)
    : id = m['id'] as String,
      componenteId = m['componente_id'] as String,
      tipoValor = m['tipo'] as String,
      signo = (m['signo'] ?? 1) as int,
      cantidad = (m['cantidad'] ?? 0) as num,
      valorUnitario = (m['valor_unitario'] ?? 0) as num,
      terceroNombre = (m['activo_terceros'] as Map?)?['nombre'] as String?,
      anulaMovimientoId = m['anula_movimiento_id'] as String?,
      observacion = m['observacion'] as String?,
      usuarioEmail = m['usuario_email'] as String?,
      fecha = DateTime.parse(m['fecha'] as String);

  TipoMovComponente? get tipo => TipoMovComponente.desde(tipoValor);
  bool get esAnulacion => anulaMovimientoId != null;

  /// Cómo se lee en el historial ("Venta", "Se retiró", "Anulación").
  String get etiqueta => tipo?.historial ?? tipoValor;

  num get cantidadConSigno => signo * cantidad;

  /// Para ver: "+2" o "−3", con el signo menos tipográfico (U+2212).
  String get textoCantidad {
    final n = cantidad % 1 == 0 ? cantidad.toInt().toString() : '$cantidad';
    return signo > 0 ? '+$n' : '−$n';
  }

  /// Para el lector de pantalla: en palabras, sin signos. Un "−3" se lee
  /// distinto según el lector (o no se lee); "salieron 3" no tiene pérdida.
  String get descripcionAccesible {
    final n = cantidad % 1 == 0 ? cantidad.toInt().toString() : '$cantidad';
    final movio = signo > 0 ? 'entraron $n' : 'salieron $n';
    return [
      etiqueta,
      movio,
      if (terceroNombre != null && terceroNombre!.isNotEmpty)
        'a $terceroNombre',
    ].join(', ');
  }
}

/// Una línea de la composición sugerida para un kit nuevo: sale del kit MÁS
/// RECIENTE de la misma referencia (plantilla_kit en la base). Es solo una
/// sugerencia para el formulario: el equipo nuevo es dueño de lo suyo.
class ComponentePlantilla {
  final String nombre;
  final num cantidad;
  final num valorUnitario;
  final int orden;
  /// De qué kit se copió, para decírselo al usuario.
  final String? desdeSerial;

  const ComponentePlantilla({
    required this.nombre,
    required this.cantidad,
    required this.valorUnitario,
    this.orden = 0,
    this.desdeSerial,
  });

  ComponentePlantilla.fromMap(Map<String, dynamic> m)
    : nombre = m['nombre'] as String,
      cantidad = (m['cantidad'] ?? 0) as num,
      valorUnitario = (m['valor_unitario'] ?? 0) as num,
      orden = (m['orden'] ?? 0) as int,
      desdeSerial = m['desde_serial'] as String?;

  num get subtotal => cantidad * valorUnitario;
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
  /// Entrada de un equipo que se había entregado y vuelve. Lo estampa la
  /// base al insertar (schema_v63); la app nunca lo decide.
  final bool esReingreso;

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
      fecha = DateTime.parse(m['fecha'] as String),
      esReingreso = (m['es_reingreso'] as bool?) ?? false;

  /// El nombre del movimiento como lo reconoce el usuario. Una entrada no es
  /// lo mismo si es el alta de un equipo nuevo o si es uno que vuelve de un
  /// centro de costo; en listados e informes tiene que verse la diferencia.
  String get tipoEtiqueta => etiquetaTipo(tipo, esReingreso);

  /// Una sola definición para la ficha y para los informes: si cada uno
  /// armara su propia etiqueta, tarde o temprano dirían cosas distintas.
  static String etiquetaTipo(String tipo, bool esReingreso) => switch (tipo) {
    'entrada' when esReingreso => 'Entrada · REINGRESO',
    'entrada' => 'Entrada',
    'salida' => 'Salida',
    _ => 'Anulación',
  };

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

/// Deja el texto como lo guarda la columna `serial_busqueda` de la base:
/// mayúsculas y sin tildes. Los dos lados TIENEN que normalizar igual, o la
/// búsqueda no encuentra lo que el usuario ve en pantalla.
String normalizarSerial(String s) {
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇøØ';
  const sin = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNCoO';
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    final i = con.indexOf(ch);
    sb.write(i >= 0 ? sin[i] : ch);
  }
  return sb.toString().toUpperCase();
}

class ActivosService {
  /// Mismo patrón que InventarioService.revision: las pantallas que lo
  /// escuchan se recargan solas tras un alta/movimiento/cambio de ubicación.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static const _selectMovimiento =
      'id, activo_id, tipo, anula_movimiento_id, condicion, usable, valor, '
      'centro_costo_id, observacion, usuario_email, fecha, es_reingreso, '
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

  /// TODAS las referencias activas, trayéndolas por páginas hasta agotarlas.
  ///
  /// Es lo que necesita un SELECTOR: si se pide un lote fijo, las que queden
  /// fuera son imposibles de elegir — y el buscador no las rescata, porque
  /// solo filtra lo que ya se descargó. Un listado paginado en pantalla puede
  /// permitirse mostrar de a poco; un desplegable no.
  static Future<List<ActivoReferencia>> todasLasReferencias({
    bool soloActivas = true,
  }) async {
    const porPagina = 500;
    final todas = <ActivoReferencia>[];
    var offset = 0;
    while (true) {
      final pagina = await referencias(
          offset: offset, limit: porPagina, soloActivas: soloActivas);
      todas.addAll(pagina);
      if (pagina.length < porPagina) break;
      offset += pagina.length;
    }
    return todas;
  }

  /// Todos los terceros activos, por el mismo motivo: alimenta el selector
  /// de "Cambiar ubicación", y un tercero que no se descargue es un tercero
  /// al que el equipo no se puede mandar.
  static Future<List<ActivoTercero>> todosLosTerceros() async {
    const porPagina = 500;
    final todos = <ActivoTercero>[];
    var offset = 0;
    while (true) {
      final pagina = await terceros(offset: offset, limit: porPagina);
      todos.addAll(pagina);
      if (pagina.length < porPagina) break;
      offset += pagina.length;
    }
    return todos;
  }

  static Future<ActivoReferencia> crearReferencia({
    required String nombre,
    String? marca,
    String? modelo,
    String? tipo,
    bool esKit = false,
  }) async {
    final res = await supabase
        .from('activo_referencias')
        .insert({
          'nombre': nombre,
          'marca': marca,
          'modelo': modelo,
          'tipo': tipo,
          'es_kit': esKit,
        })
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
    // Solo se manda si se pasa. La base rechaza cambiarlo si la referencia
    // ya tiene equipos (schema_v64); mandarlo igual que antes no molesta.
    bool? esKit,
  }) async {
    final cambios = <String, dynamic>{};
    if (nombre != null) cambios['nombre'] = nombre;
    if (marca != null) cambios['marca'] = marca;
    if (modelo != null) cambios['modelo'] = modelo;
    if (tipo != null) cambios['tipo'] = tipo;
    if (activo != null) cambios['activo'] = activo;
    if (esKit != null) cambios['es_kit'] = esKit;
    if (cambios.isEmpty) return;
    // SIN traducir el error a propósito: la pantalla de referencias reconoce
    // un duplicado buscando 'activo_referencias_uniq' / '23505' en el texto
    // crudo. Traducirlo aquí le rompería ese aviso.
    await supabase.from('activo_referencias').update(cambios).eq('id', id);
    revision.value++;
  }

  /// Si la referencia ya tiene equipos. La pantalla lo usa para deshabilitar
  /// el interruptor "Es un kit" y DECIR por qué, en vez de dejarlo oprimir y
  /// que la base lo rechace después.
  static Future<bool> referenciaTieneEquipos(String referenciaId) async {
    final res = await supabase
        .from('activos')
        .select('id')
        .eq('referencia_id', referenciaId)
        .limit(1);
    return (res as List).isNotEmpty;
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
      '*, activo_referencias(nombre, marca, es_kit), bodegas(nombre)';

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
    // Búsqueda UNIVERSAL: serial, nombre de la referencia, marca, modelo y
    // tipo, sin importar mayúsculas ni tildes, y cada palabra por separado.
    // La hace la base (RPC buscar_activos, schema_v59) porque la referencia
    // vive en otra tabla y filtrar entre las dos desde aquí no escala.
    String? texto,
  }) async {
    // Los mismos filtros sirven para los dos caminos (tabla o RPC). Con una
    // RPC tienen que ir ANTES del select: el select de una RPC ya es una
    // transformación y no admite .eq().
    PostgrestFilterBuilder<T> filtrar<T>(PostgrestFilterBuilder<T> q) {
      if (estado != null) q = q.eq('estado', estado);
      if (bodegaId != null) q = q.eq('bodega_id', bodegaId);
      if (referenciaId != null) q = q.eq('referencia_id', referenciaId);
      if (serial != null && serial.trim().isNotEmpty) {
        // Se filtra por la columna normalizada (mayúsculas y sin tildes), no
        // por `serial`: ilike ignora mayúsculas pero NO tildes.
        q = q.like('serial_busqueda', '%${normalizarSerial(serial.trim())}%');
      }
      return q;
    }

    try {
      final hayTexto = texto != null && texto.trim().isNotEmpty;
      final res = hayTexto
          ? await filtrar(supabase.rpc('buscar_activos',
                  params: {'p_texto': texto.trim()}))
              .select(_selectActivo)
              .order('creado_en', ascending: false)
              .range(offset, offset + limit - 1)
          : await filtrar(supabase.from('activos').select(_selectActivo))
              .order('creado_en', ascending: false)
              .range(offset, offset + limit - 1);
      return (res as List)
          .map((e) => Activo.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      SyncService.enLinea.value = false;
      return _desdeCache(
        offset: offset,
        limit: limit,
        estado: estado,
        bodegaId: bodegaId,
        referenciaId: referenciaId,
        serial: serial,
        texto: texto,
      );
    }
  }

  /// Mismo filtrado que arriba, pero sobre el catálogo guardado en el
  /// aparato. Solo sirve para consultar y para elegir un equipo al que
  /// registrarle un movimiento: el detalle (piezas, mantenimientos,
  /// historial) sí necesita conexión.
  static Future<List<Activo>> _desdeCache({
    int offset = 0,
    int limit = 50,
    String? estado,
    String? bodegaId,
    String? referenciaId,
    String? serial,
    String? texto,
    bool? disponible,
  }) async {
    final filas = await LocalStore.leerActivos();
    final q = serial == null ? null : normalizarSerial(serial.trim());
    // Misma regla que buscar_activos en la base: cada palabra tiene que
    // aparecer en el serial o en la referencia (nombre, marca, modelo, tipo).
    final palabras = texto == null
        ? const <String>[]
        : normalizarSerial(texto.trim())
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();
    final filtradas = filas.where((a) {
      if (palabras.isNotEmpty) {
        final r = a['activo_referencias'] as Map?;
        final pajar = normalizarSerial([
          a['serial'], r?['nombre'], r?['marca'], r?['modelo'], r?['tipo'],
        ].where((e) => e != null).join(' '));
        if (!palabras.every(pajar.contains)) return false;
      }
      if (estado != null && a['estado'] != estado) return false;
      if (bodegaId != null && a['bodega_id'] != bodegaId) return false;
      if (referenciaId != null && a['referencia_id'] != referenciaId) {
        return false;
      }
      if (disponible != null && (a['disponible'] == true) != disponible) {
        return false;
      }
      if (q != null && q.isNotEmpty) {
        if (!normalizarSerial((a['serial'] ?? '').toString()).contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    if (offset >= filtradas.length) return [];
    final fin = (offset + limit).clamp(0, filtradas.length);
    return filtradas
        .sublist(offset, fin)
        .map((e) => Activo.fromMap(e))
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
    // El serial se filtra CONTRA LA BASE, no en memoria: esta consulta
    // viene paginada, así que filtrar lo ya descargado diría "no existe"
    // cuando el equipo está en una página posterior.
    String? serial,
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
    if (serial != null && serial.trim().isNotEmpty) {
      q = q.like('serial_busqueda', '%${normalizarSerial(serial.trim())}%');
    }
    try {
      final res = await q.order('serial').range(offset, offset + limit - 1);
      return (res as List)
          .map((e) => ActivoDisponibilidad.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      SyncService.enLinea.value = false;
      // El caché guarda las filas de esta misma vista, así que se pueden
      // reconstruir tal cual, con su `disponible` ya calculado.
      final filas = await LocalStore.leerActivos();
      final q = serial == null ? null : normalizarSerial(serial.trim());
      final filtradas = filas.where((a) {
        if (disponible != null && (a['disponible'] == true) != disponible) {
          return false;
        }
        if (bodegaId != null && a['ubicacion_actual_bodega_id'] != bodegaId) {
          return false;
        }
        if (referenciaId != null && a['referencia_id'] != referenciaId) {
          return false;
        }
        if (q != null && q.isNotEmpty) {
          if (!normalizarSerial((a['serial'] ?? '').toString()).contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();
      if (offset >= filtradas.length) return [];
      final fin = (offset + limit).clamp(0, filtradas.length);
      return filtradas
          .sublist(offset, fin)
          .map(ActivoDisponibilidad.fromMap)
          .toList();
    }
  }

  /// En mantenimiento (interno o externo), para la 4ª pestaña del módulo.
  static Future<List<Activo>> enMantenimiento({
    int offset = 0,
    int limit = 50,
  }) async {
    try {
      final res = await supabase
          .from('activos')
          .select(_selectActivo)
          .inFilter('estado',
              ['mantenimiento_interno', 'mantenimiento_externo'])
          .order('creado_en', ascending: false)
          .range(offset, offset + limit - 1);
      return (res as List)
          .map((e) => Activo.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      SyncService.enLinea.value = false;
      final cache = await _desdeCache(limit: 100000);
      final enMant = cache
          .where((a) =>
              a.estado == 'mantenimiento_interno' ||
              a.estado == 'mantenimiento_externo')
          .toList();
      if (offset >= enMant.length) return [];
      return enMant.sublist(offset, (offset + limit).clamp(0, enMant.length));
    }
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
      // Desde schema_v58 los movimientos aceptan 'repuestos'. Antes aquí se
      // mandaba 'usado' en su lugar, y con schema_v57 (la entrada copia la
      // condición a la ficha) eso habría dejado como "usado" un alta que
      // era "para repuestos".
      'condicion': condicion,
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

  /// Cambia la condición de un equipo a mano (por ejemplo, reclasificarlo a
  /// 'repuestos' mientras está en la bodega). Desde schema_v58 también se
  /// puede fijar al reingresarlo: la entrada copia su condición a la ficha.
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
    await _registrar({
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
    }, estadoResultante: _estadoTrasEntrada(condicion, usable));
  }

  /// El mismo criterio que aplica el trigger de la base al insertar una
  /// entrada. Se repite aquí SOLO para poder mostrar el estado correcto
  /// mientras el movimiento está encolado sin señal; cuando sube, manda lo
  /// que diga el servidor.
  static String _estadoTrasEntrada(String condicion, bool? usable) {
    if (condicion == 'baja') return 'baja';
    if (condicion == 'usado' && !(usable ?? true)) {
      return 'mantenimiento_interno';
    }
    return 'operativo';
  }

  /// Inserta el movimiento; si no hay señal lo deja en la cola del aparato
  /// y ajusta el caché local para que la app no siga mostrando el equipo
  /// como si nada hubiera pasado.
  ///
  /// El par device_id + local_id es lo que impide que un reintento suba dos
  /// veces el mismo movimiento (hay un índice único en la base).
  static Future<void> _registrar(
    Map<String, dynamic> mov, {
    required String estadoResultante,
  }) async {
    try {
      await supabase.from('activo_movimientos').insert(mov);
    } catch (_) {
      SyncService.enLinea.value = false;
      final localId =
          '${DateTime.now().microsecondsSinceEpoch}-${mov['activo_id']}';
      await LocalStore.encolarEquipo({
        ...mov,
        'device_id': await LocalStore.deviceId(),
        'local_id': localId,
        'fecha': DateTime.now().toUtc().toIso8601String(),
      });
      await LocalStore.ajustarEstadoActivoLocal(
          mov['activo_id'] as String, estadoResultante);
      await SyncService.refrescarPendientes();
    }
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
    await _registrar({
      'activo_id': activoId,
      'tipo': 'salida',
      'centro_costo_id': centroCostoId,
      'valor': valor,
      'observacion': observacion,
      'usuario_id': uid,
      'usuario_email': supabase.auth.currentUser?.email,
    }, estadoResultante: 'entregado');
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
  // Observaciones
  // ---------------------------------------------------------------------

  /// Todas las observaciones del equipo en UN solo listado cronológico:
  /// las del alta, las de cada cambio de ubicación y las de cada cambio de
  /// estado. Sale de una vista que las une; ningún texto se guarda dos veces.
  static Future<List<ActivoObservacion>> observaciones(
    String activoId, {
    int limit = 50,
  }) async {
    final res = await supabase
        .from('activo_observaciones_todas')
        .select('id, fecha, texto, origen, contexto, usuario_email, editada')
        .eq('activo_id', activoId)
        .order('fecha', ascending: false)
        .limit(limit);
    return (res as List)
        .map((e) => ActivoObservacion.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Guarda una observación suelta. `contexto` es lo que estaba pasando
  /// cuando se escribió, para que después se entienda sin adivinar.
  static Future<void> agregarObservacion({
    required String activoId,
    required String texto,
    String? contexto,
    String origen = 'estado',
  }) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    await supabase.from('activo_observaciones').insert({
      'activo_id': activoId,
      'texto': t,
      'origen': origen,
      'contexto': contexto,
      'usuario_id': supabase.auth.currentUser?.id,
      'usuario_email': supabase.auth.currentUser?.email,
    });
    revision.value++;
  }

  /// Edita el texto de una observación EN SU TABLA DE ORIGEN. No hay tabla
  /// de observaciones "maestra": cada texto tiene un solo dueño, y editarlo
  /// ahí hace que el trigger fn_auditoria guarde el antes, el después, el
  /// usuario y la fecha, sin código extra.
  static Future<void> editarObservacion({
    required String origen,
    required String id,
    required String texto,
  }) async {
    final t = texto.trim();
    // Vaciarla la haría desaparecer del listado sin dejar rastro visible.
    if (t.isEmpty) {
      throw ArgumentError('La observación no puede quedar vacía.');
    }
    final (tabla, campo) = switch (origen) {
      'alta' => ('activos', 'observacion'),
      'ubicacion' => ('activo_ubicaciones', 'detalle'),
      _ => ('activo_observaciones', 'texto'),
    };
    await supabase.from(tabla).update({campo: t}).eq('id', id);
    revision.value++;
  }

  /// Los cambios que ha tenido el texto de una observación, más reciente
  /// primero. Sale de la auditoría por una función SECURITY DEFINER que
  /// devuelve SOLO esto: la tabla `auditoria` en sí no la lee el rol
  /// `equipos`, y no debe (guarda cambios de todo el sistema).
  static Future<List<CambioObservacion>> historialObservacion({
    required String origen,
    required String id,
  }) async {
    final res = await supabase.rpc('observacion_historial',
        params: {'p_origen': origen, 'p_id': id});
    return (res as List)
        .map((e) => CambioObservacion.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------
  // Kits: componentes y su vida (schema_v64)
  // ---------------------------------------------------------------------
  //
  // La base hace cumplir TODAS las reglas: la cantidad de un componente y el
  // valor de un kit los calcula ella, estampa el signo, el valor unitario y
  // el usuario de cada movimiento, y rechaza lo que no se puede. Aquí solo
  // se pide y se traduce el error. Nada de esto escribe `cantidad` ni el
  // `valor_nuevo` de un kit.

  static const _selectComponente =
      'id, activo_id, nombre, valor_unitario, cantidad, subtotal, orden';

  static const _selectMovComponente =
      'id, componente_id, tipo, signo, cantidad, valor_unitario, '
      'anula_movimiento_id, observacion, usuario_email, fecha, '
      'activo_terceros(nombre)';

  /// Ejecuta una llamada y convierte el error de la base en un ErrorEquipos
  /// con mensaje para el usuario.
  static Future<T> _conMensaje<T>(Future<T> Function() llamada) async {
    try {
      return await llamada();
    } on PostgrestException catch (e) {
      throw ErrorEquipos(mensajeDeErrorEquipos(e.code, e.message));
    }
  }

  /// Los componentes de un kit, en su orden. Incluye los agotados
  /// (cantidad 0): se muestran atenuados, su historia no desaparece.
  static Future<List<ActivoComponente>> componentes(String activoId) =>
      _conMensaje(() async {
        final res = await supabase
            .from('activo_componentes')
            .select(_selectComponente)
            .eq('activo_id', activoId)
            .order('orden')
            .order('nombre');
        return (res as List)
            .map((e) => ActivoComponente.fromMap(e as Map<String, dynamic>))
            .toList();
      });

  /// Agrega un componente a un kit, con su movimiento de alta, en UNA sola
  /// operación de la base (agregar_componente). Si fueran dos llamadas desde
  /// aquí, un corte de red en medio dejaría un componente en cero sin historia.
  static Future<String> agregarComponente({
    required String activoId,
    required String nombre,
    required num cantidad,
    required num valorUnitario,
    int orden = 0,
    String? observacion,
  }) async {
    if (nombre.trim().isEmpty) {
      throw const ErrorEquipos('El componente necesita un nombre.');
    }
    if (cantidad <= 0) {
      throw ErrorEquipos(
          'La cantidad de "${nombre.trim()}" tiene que ser mayor que cero.');
    }
    if (valorUnitario < 0) {
      throw const ErrorEquipos('El valor unitario no puede ser negativo.');
    }
    final id = await _conMensaje(() => supabase.rpc('agregar_componente',
        params: {
          'p_activo': activoId,
          'p_nombre': nombre.trim(),
          'p_cantidad': cantidad,
          'p_valor_unitario': valorUnitario,
          'p_orden': orden,
          'p_observacion':
              (observacion == null || observacion.trim().isEmpty)
                  ? null
                  : observacion.trim(),
        }));
    revision.value++;
    return id as String;
  }

  /// Agrega VARIOS componentes a un kit en UNA operación de la base
  /// (agregar_componentes, schema_v65): entran todos o ninguno. Es lo que usa
  /// el alta de un kit: con una llamada por componente, un corte de red a
  /// mitad dejaría el kit con 2 de sus 4 partes, valiendo menos, sin que
  /// nadie lo note. Devuelve cuántos se agregaron.
  static Future<int> agregarComponentes(
    String activoId,
    List<ComponentePlantilla> lista,
  ) async {
    final problema = validarComposicionKit(lista);
    if (problema != null) throw ErrorEquipos(problema);
    final res = await _conMensaje(() => supabase.rpc('agregar_componentes',
        params: {
          'p_activo': activoId,
          'p_componentes': [
            for (var i = 0; i < lista.length; i++)
              {
                'nombre': lista[i].nombre.trim(),
                'cantidad': lista[i].cantidad,
                'valor_unitario': lista[i].valorUnitario,
                'orden': i + 1,
              },
          ],
        }));
    revision.value++;
    return res as int;
  }

  /// Corrige el nombre, el valor unitario vigente o el orden de un
  /// componente. La CANTIDAD no está aquí a propósito: cambia solo con un
  /// movimiento (moverComponente), para que quede el porqué y el para quién.
  static Future<void> editarComponente(
    String id, {
    String? nombre,
    num? valorUnitario,
    int? orden,
  }) async {
    final cambios = <String, dynamic>{};
    if (nombre != null) {
      if (nombre.trim().isEmpty) {
        throw const ErrorEquipos('El componente necesita un nombre.');
      }
      cambios['nombre'] = nombre.trim();
    }
    if (valorUnitario != null) {
      if (valorUnitario < 0) {
        throw const ErrorEquipos('El valor unitario no puede ser negativo.');
      }
      cambios['valor_unitario'] = valorUnitario;
    }
    if (orden != null) cambios['orden'] = orden;
    if (cambios.isEmpty) return;
    await _conMensaje(
        () => supabase.from('activo_componentes').update(cambios).eq('id', id));
    revision.value++;
  }

  /// La historia de un componente, del más reciente al más antiguo (regla
  /// de históricos del proyecto).
  static Future<List<MovimientoComponente>> movimientosComponente(
    String componenteId, {
    int limit = 100,
  }) =>
      _conMensaje(() async {
        final res = await supabase
            .from('activo_componente_movimientos')
            .select(_selectMovComponente)
            .eq('componente_id', componenteId)
            .order('fecha', ascending: false)
            .limit(limit);
        return (res as List)
            .map((e) =>
                MovimientoComponente.fromMap(e as Map<String, dynamic>))
            .toList();
      });

  /// Registra la vida de un componente: se agrega, se retira, se vende, se
  /// va en garantía o se daña. Solo los tipos que el usuario elige a mano
  /// (TipoMovComponente.elegibles): el alta la hace agregarComponente y la
  /// anulación, anularMovimientoComponente.
  ///
  /// Se valida aquí lo mismo que la base, para decirlo ANTES de ir a la red
  /// — la base lo vuelve a comprobar de todas formas.
  static Future<void> moverComponente({
    required String componenteId,
    required TipoMovComponente tipo,
    required num cantidad,
    String? terceroId,
    String? observacion,
  }) async {
    if (!TipoMovComponente.elegibles.contains(tipo)) {
      throw ErrorEquipos('"${tipo.accion}" no se registra desde aquí.');
    }
    if (cantidad <= 0) {
      throw const ErrorEquipos('La cantidad tiene que ser mayor que cero.');
    }
    if (tipo.pideTercero && terceroId == null) {
      throw const ErrorEquipos(
          'Para vender o dar en garantía hay que decir a quién (el tercero).');
    }
    await _conMensaje(
        () => supabase.from('activo_componente_movimientos').insert({
              'componente_id': componenteId,
              'tipo': tipo.valor,
              'cantidad': cantidad,
              'tercero_id': tipo.pideTercero ? terceroId : null,
              'observacion':
                  (observacion == null || observacion.trim().isEmpty)
                      ? null
                      : observacion.trim(),
            }));
    revision.value++;
  }

  /// Deshace un movimiento con otro movimiento que lo anula. La base copia
  /// su cantidad y valor y le pone el signo contrario; rechaza anular dos
  /// veces y anular una anulación. Nada se borra.
  static Future<void> anularMovimientoComponente(
    MovimientoComponente original, {
    String? observacion,
  }) async {
    if (original.esAnulacion) {
      throw const ErrorEquipos(
          'Una anulación no se anula: registra un movimiento nuevo.');
    }
    await _conMensaje(
        () => supabase.from('activo_componente_movimientos').insert({
              'componente_id': original.componenteId,
              'tipo': TipoMovComponente.anulacion.valor,
              // La base la reemplaza por la del original; va porque la
              // columna no admite nulos antes de que corra el trigger.
              'cantidad': original.cantidad,
              'anula_movimiento_id': original.id,
              'observacion':
                  (observacion == null || observacion.trim().isEmpty)
                      ? null
                      : observacion.trim(),
            }));
    revision.value++;
  }

  /// La composición del kit MÁS RECIENTE de una referencia, para proponerla
  /// al crear el siguiente (plantilla_kit en la base). Vacía si es el primer
  /// kit de esa referencia.
  static Future<List<ComponentePlantilla>> plantillaKit(
          String referenciaId) =>
      _conMensaje(() async {
        final res = await supabase
            .rpc('plantilla_kit', params: {'p_referencia': referenciaId});
        return (res as List)
            .map((e) => ComponentePlantilla.fromMap(e as Map<String, dynamic>))
            .toList();
      });

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
