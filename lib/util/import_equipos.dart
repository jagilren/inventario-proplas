import '../activos_service.dart';
import '../data.dart';
import 'dinero.dart';
import 'import_archivo.dart';

// Carga masiva de EQUIPOS (docs/plan-importar-equipos.md, schema_v70).
//
// Todo lo de este archivo es lógica pura, sin pantallas ni red: leer la
// plantilla, agrupar cada kit con sus componentes y revisar cada fila contra
// el catálogo real. Así se prueba entero, y la pantalla solo muestra lo que
// sale de aquí.

/// Las columnas de la plantilla, en orden. Se ubican por su NOMBRE COMPLETO
/// (no "que contenga"): hay tres columnas con "valor" y dos con "centro".
const List<String> encabezadoImportEquipos = [
  'SERIAL',
  'REFERENCIA',
  'MARCA',
  'MODELO',
  'ES KIT',
  'CONDICION',
  'PORCENTAJE',
  'VALOR NUEVO',
  'BODEGA',
  'CENTRO ORIGEN',
  'CENTRO DESTINO',
  'OBSERVACION',
  'COMPONENTE',
  'CANTIDAD',
  'VALOR UNITARIO',
];

/// Centros que usa el alta de un equipo cuando no se dice otro: una compra
/// (origen) que queda atribuida al centro general de RPCI (destino). Los
/// mismos de ActivoAltaPage.
const codigoOrigenPorDefecto = 'COMPRA';
const codigoDestinoPorDefecto = 'G000002';

/// Los equipos van a la base de a este número por llamada. Medido: 100
/// equipos entran en menos de 1 segundo, y la base corta a los 8.
const tamanoLoteImport = 100;

/// Una fila de la plantilla, tal como vino (texto).
class FilaEquipoArchivo {
  /// Número de fila en el archivo (1 = el encabezado), para poder decir
  /// "fila 14" y que el usuario la encuentre en su Excel.
  final int fila;
  final String serial;
  final String referencia;
  final String marca;
  final String modelo;
  final String esKit;
  final String condicion;
  final String porcentaje;
  final String valorNuevo;
  final String bodega;
  final String centroOrigen;
  final String centroDestino;
  final String observacion;
  final String componente;
  final String cantidad;
  final String valorUnitario;

  const FilaEquipoArchivo({
    required this.fila,
    this.serial = '',
    this.referencia = '',
    this.marca = '',
    this.modelo = '',
    this.esKit = '',
    this.condicion = '',
    this.porcentaje = '',
    this.valorNuevo = '',
    this.bodega = '',
    this.centroOrigen = '',
    this.centroDestino = '',
    this.observacion = '',
    this.componente = '',
    this.cantidad = '',
    this.valorUnitario = '',
  });

  /// Una fila de componente: trae COMPONENTE y no trae REFERENCIA.
  bool get esDeComponente => componente.isNotEmpty && referencia.isEmpty;
}

/// Lee las filas de la plantilla. Lanza [FormatException] con un mensaje
/// para el usuario si no encuentra los encabezados.
List<FilaEquipoArchivo> leerPlantillaEquipos(List<List<String>> crudas) {
  final columnas = {
    for (final c in encabezadoImportEquipos) normalizarTexto(c): c,
    // Nombres que alguien escribe a mano sin pensarlo.
    'observaciones': 'OBSERVACION',
  };
  int filaEncabezado = -1;
  final indice = <String, int>{};
  for (var r = 0; r < crudas.length && filaEncabezado < 0; r++) {
    final nombres = [for (final c in crudas[r]) normalizarTexto(c)];
    if (nombres.contains('serial') &&
        (nombres.contains('referencia') || nombres.contains('componente'))) {
      filaEncabezado = r;
      for (var c = 0; c < nombres.length; c++) {
        final col = columnas[nombres[c]];
        if (col != null) indice.putIfAbsent(col, () => c);
      }
    }
  }
  if (filaEncabezado < 0) {
    throw const FormatException(
        'No encontré los encabezados de la plantilla de equipos.\n\n'
        'La primera fila debe traer al menos SERIAL y REFERENCIA. Lo más '
        'fácil es bajar la plantilla y llenarla encima.');
  }
  String celda(List<String> fila, String col) {
    final i = indice[col];
    return (i == null || i >= fila.length) ? '' : fila[i].trim();
  }

  final out = <FilaEquipoArchivo>[];
  for (var r = filaEncabezado + 1; r < crudas.length; r++) {
    final f = crudas[r];
    if (f.every((c) => c.trim().isEmpty)) continue;
    out.add(FilaEquipoArchivo(
      fila: r + 1,
      serial: celda(f, 'SERIAL'),
      referencia: celda(f, 'REFERENCIA'),
      marca: celda(f, 'MARCA'),
      modelo: celda(f, 'MODELO'),
      esKit: celda(f, 'ES KIT'),
      condicion: celda(f, 'CONDICION'),
      porcentaje: celda(f, 'PORCENTAJE'),
      valorNuevo: celda(f, 'VALOR NUEVO'),
      bodega: celda(f, 'BODEGA'),
      centroOrigen: celda(f, 'CENTRO ORIGEN'),
      centroDestino: celda(f, 'CENTRO DESTINO'),
      observacion: celda(f, 'OBSERVACION'),
      componente: celda(f, 'COMPONENTE'),
      cantidad: celda(f, 'CANTIDAD'),
      valorUnitario: celda(f, 'VALOR UNITARIO'),
    ));
  }
  return out;
}

/// Lo que hay en la base y hace falta para revisar el archivo.
class CatalogoImport {
  /// TODAS las referencias, también las desactivadas (para decir "está
  /// desactivada" en vez de crear otra igual).
  final List<ActivoReferencia> referencias;
  final List<Bodega> bodegas;
  final List<CentroCosto> centros;
  /// Seriales del archivo que ya existen en la base.
  final Set<String> serialesExistentes;
  /// Composición del último kit de cada referencia kit (plantilla_kit), para
  /// los kits que vienen sin componentes. Por id de referencia.
  final Map<String, List<ComponentePlantilla>> plantillas;

  const CatalogoImport({
    this.referencias = const [],
    this.bodegas = const [],
    this.centros = const [],
    this.serialesExistentes = const {},
    this.plantillas = const {},
  });
}

/// Una referencia que la carga va a CREAR.
class ReferenciaNuevaImport {
  final String nombre;
  final String marca;
  final String modelo;
  bool esKit;
  /// Las del catálogo que se le parecen: casi siempre ya existe escrita de
  /// otra forma, y así se ve antes de crear un duplicado.
  final List<ActivoReferencia> parecidas;
  /// Cuántos equipos del archivo la usan.
  int equipos = 0;

  ReferenciaNuevaImport(this.nombre, this.marca, this.modelo,
      {this.esKit = false, this.parecidas = const []});

  String get etiqueta =>
      [nombre, marca, modelo].where((e) => e.isNotEmpty).join(' · ');

  Map<String, dynamic> aJson() => {
        'nombre': nombre,
        if (marca.isNotEmpty) 'marca': marca,
        if (modelo.isNotEmpty) 'modelo': modelo,
        'es_kit': esKit,
      };
}

/// Un equipo del archivo, ya revisado.
class EquipoImport {
  final String serial;
  /// Fila del equipo en el archivo.
  final int fila;
  final String nombreReferencia;
  ActivoReferencia? referencia;
  ReferenciaNuevaImport? referenciaNueva;
  String? condicion;
  num porcentaje = 100;
  num? valorNuevo;
  Bodega? bodega;
  CentroCosto? centroOrigen;
  CentroCosto? centroDestino;
  String observacion = '';
  final List<ComponentePlantilla> componentes = [];
  /// Los componentes se copiaron del último kit de la referencia.
  bool componentesDeLaPlantilla = false;
  final List<String> errores = [];
  final List<String> avisos = [];
  /// Lo que dijo la columna ES KIT (null si vino vacía).
  bool? esKitArchivo;

  EquipoImport(this.serial, this.fila, this.nombreReferencia);

  bool get listo => errores.isEmpty;
  bool get esKit => referencia?.esKit ?? referenciaNueva?.esKit ?? false;

  /// Lo que valdrá a nuevo: la suma de los componentes si es kit.
  num get valorCalculado => esKit
      ? componentes.fold<num>(0, (s, c) => s + c.cantidad * c.valorUnitario)
      : (valorNuevo ?? 0);

  /// Lo que se manda a importar_equipos (schema_v70).
  Map<String, dynamic> aJson() => {
        'serial': serial,
        if (referencia != null)
          'referencia_id': referencia!.id
        else
          'referencia_nueva': referenciaNueva!.aJson(),
        'condicion': condicion,
        'porcentaje': porcentaje,
        if (!esKit) 'valor_nuevo': valorNuevo,
        'bodega_id': bodega!.id,
        'centro_origen_id': centroOrigen!.id,
        'centro_destino_id': centroDestino!.id,
        if (observacion.isNotEmpty) 'observacion': observacion,
        if (esKit)
          'componentes': [
            for (var i = 0; i < componentes.length; i++)
              {
                'nombre': componentes[i].nombre,
                'cantidad': componentes[i].cantidad,
                'valor_unitario': componentes[i].valorUnitario,
                'orden': i + 1,
              },
          ],
      };
}

/// El archivo revisado entero.
class RevisionImport {
  final List<EquipoImport> equipos;
  final List<ReferenciaNuevaImport> referenciasNuevas;
  /// Problemas que no son de un equipo (una fila de componente sin kit).
  final List<String> problemasSueltos;

  const RevisionImport(
      this.equipos, this.referenciasNuevas, this.problemasSueltos);

  List<EquipoImport> get listos => equipos.where((e) => e.listo).toList();
  int get conProblemas => equipos.length - listos.length;
}

/// Nombre, marca y modelo como los compara el índice único de la base
/// (activo_referencias_uniq): sin espacios de sobra y en mayúsculas.
String claveReferencia(String? s) =>
    (s ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

String? _condicion(String s) => switch (normalizarTexto(s)) {
      'nuevo' || 'nueva' => 'nuevo',
      'usado' || 'usada' => 'usado',
      'repuestos' || 'repuesto' || 'para repuestos' => 'repuestos',
      'baja' || 'de baja' => 'baja',
      _ => null,
    };

bool? _siNo(String s) => switch (normalizarTexto(s)) {
      'si' || 's' || 'x' || '1' || 'true' || 'verdadero' => true,
      'no' || 'n' || '0' || 'false' || 'falso' => false,
      _ => null,
    };

num? _cantidad(String s) {
  final t = s.trim().replaceAll(',', '.');
  return t.isEmpty ? null : num.tryParse(t);
}

/// Revisa el archivo contra el catálogo. No toca la base.
RevisionImport analizarImportEquipos(
  List<FilaEquipoArchivo> filas,
  CatalogoImport cat,
) {
  final equipos = <EquipoImport>[];
  final porSerial = <String, EquipoImport>{};
  final sueltos = <String>[];
  final nuevas = <String, ReferenciaNuevaImport>{};

  final origenDefecto = cat.centros
      .where((c) => c.codigo.toUpperCase() == codigoOrigenPorDefecto)
      .firstOrNull;
  final destinoDefecto = cat.centros
      .where((c) => c.codigo.toUpperCase() == codigoDestinoPorDefecto)
      .firstOrNull;

  EquipoImport? ultimo;
  for (final f in filas) {
    // ---- Fila de componente: va al kit de su serial (o al de arriba). ----
    if (f.esDeComponente) {
      final dueno = f.serial.isEmpty ? ultimo : porSerial[f.serial];
      if (dueno == null) {
        sueltos.add('Fila ${f.fila}: el componente "${f.componente}" no '
            'tiene un equipo con el serial "${f.serial}" más arriba.');
        continue;
      }
      _agregarComponente(dueno, f);
      continue;
    }

    // ---- Fila de equipo. ----
    final e = EquipoImport(f.serial, f.fila, f.referencia);
    equipos.add(e);
    ultimo = e;
    if (f.serial.isEmpty) {
      e.errores.add('Falta el SERIAL.');
    } else if (porSerial.containsKey(f.serial)) {
      final otra = porSerial[f.serial]!;
      e.errores.add('El serial está repetido en el archivo (fila ${otra.fila}).');
      otra.errores
          .add('El serial está repetido en el archivo (fila ${f.fila}).');
    } else {
      porSerial[f.serial] = e;
    }
    if (normalizarTexto(f.serial).startsWith('ejemplo')) {
      e.errores.add('Es una fila de EJEMPLO de la plantilla: bórrala o '
          'escribe el serial real.');
    } else if (cat.serialesExistentes.contains(f.serial)) {
      e.errores.add('Ya existe un equipo con ese serial.');
    }

    // La referencia.
    final esKitArchivo = _siNo(f.esKit);
    e.esKitArchivo = esKitArchivo;
    if (f.esKit.isNotEmpty && esKitArchivo == null) {
      e.errores.add('ES KIT dice "${f.esKit}": escribe SI o NO.');
    }
    if (f.referencia.isEmpty) {
      e.errores.add('Falta la REFERENCIA.');
    } else {
      _resolverReferencia(e, f, cat, nuevas, esKitArchivo);
    }

    // La condición y el valor.
    e.condicion = _condicion(f.condicion);
    if (e.condicion == null) {
      e.errores.add(f.condicion.isEmpty
          ? 'Falta la CONDICION (nuevo, usado, repuestos o baja).'
          : 'CONDICION "${f.condicion}" no existe: nuevo, usado, repuestos '
              'o baja.');
    }
    if (f.porcentaje.isNotEmpty) {
      final p = _cantidad(f.porcentaje.replaceAll('%', ''));
      if (p == null || p < 0 || p > 100) {
        e.errores.add('PORCENTAJE "${f.porcentaje}": tiene que ser un '
            'número de 0 a 100.');
      } else {
        e.porcentaje = p;
      }
    } else if (e.condicion == 'usado') {
      e.avisos.add('Usado sin PORCENTAJE: se valoriza al 100 %.');
    }
    if (f.valorNuevo.isNotEmpty) {
      // Dinero: "1.540.000" es un millón quinientos cuarenta mil.
      final v = leerPesos(f.valorNuevo);
      if (v == null || v < 0) {
        e.errores.add('VALOR NUEVO "${f.valorNuevo}" no se entiende como '
            'valor en pesos.');
      } else {
        e.valorNuevo = v;
      }
    }

    // Dónde queda.
    e.bodega = _bodega(f.bodega, cat.bodegas);
    if (e.bodega == null) {
      e.errores.add(f.bodega.isEmpty
          ? 'Falta la BODEGA.'
          : 'No reconozco la bodega "${f.bodega}" (hay: '
              '${cat.bodegas.map((b) => b.nombre).join(', ')}).');
    }
    _centros(e, f, cat.centros, origenDefecto, destinoDefecto);
    e.observacion = f.observacion;

    // Un componente en la misma fila del equipo.
    if (f.componente.isNotEmpty) _agregarComponente(e, f);
  }

  // Lo que solo se sabe con TODAS las filas leídas: una referencia nueva es
  // kit si cualquiera de sus equipos trae componentes (y nadie dijo NO). Si
  // se decidiera fila por fila, el resultado dependería del orden del Excel.
  for (final e in equipos) {
    final n = e.referenciaNueva;
    if (n != null && e.componentes.isNotEmpty && e.esKitArchivo != false) {
      n.esKit = true;
    }
  }
  for (final e in equipos) {
    _revisarKit(e, cat);
  }
  return RevisionImport(equipos, nuevas.values.toList(), sueltos);
}

void _agregarComponente(EquipoImport e, FilaEquipoArchivo f) {
  final cant = _cantidad(f.cantidad);
  final valor = f.valorUnitario.isEmpty ? null : leerPesos(f.valorUnitario);
  if (cant == null || cant <= 0) {
    e.errores.add('Fila ${f.fila}: la CANTIDAD de "${f.componente}" tiene '
        'que ser un número mayor que cero.');
    return;
  }
  if (valor == null || valor < 0) {
    e.errores.add('Fila ${f.fila}: el VALOR UNITARIO de "${f.componente}" '
        'no se entiende como valor en pesos.');
    return;
  }
  e.componentes.add(ComponentePlantilla(
      nombre: f.componente, cantidad: cant, valorUnitario: valor));
}

void _resolverReferencia(
  EquipoImport e,
  FilaEquipoArchivo f,
  CatalogoImport cat,
  Map<String, ReferenciaNuevaImport> nuevas,
  bool? esKitArchivo,
) {
  final nombre = claveReferencia(f.referencia);
  var candidatas =
      cat.referencias.where((r) => claveReferencia(r.nombre) == nombre);
  if (f.marca.isNotEmpty) {
    candidatas = candidatas
        .where((r) => claveReferencia(r.marca) == claveReferencia(f.marca));
  }
  if (f.modelo.isNotEmpty) {
    candidatas = candidatas
        .where((r) => claveReferencia(r.modelo) == claveReferencia(f.modelo));
  }
  final lista = candidatas.toList();
  if (lista.length > 1) {
    e.errores.add('Hay ${lista.length} referencias "${f.referencia}" en el '
        'catálogo: escribe la MARCA (o el MODELO) para saber cuál.');
    return;
  }
  if (lista.length == 1) {
    final r = lista.single;
    if (!r.activo) {
      e.errores.add('La referencia "${r.etiqueta}" está desactivada: '
          'actívala en Referencias o usa otra.');
      return;
    }
    if (esKitArchivo == true && !r.esKit) {
      e.errores.add('ES KIT dice SI, pero "${r.nombre}" no es un kit en el '
          'catálogo.');
    } else if (esKitArchivo == false && r.esKit) {
      e.errores.add('ES KIT dice NO, pero "${r.nombre}" es un kit en el '
          'catálogo.');
    }
    e.referencia = r;
    return;
  }
  // No existe: se CREA. Una sola vez aunque la usen cien equipos.
  final clave = '$nombre|${claveReferencia(f.marca)}|'
      '${claveReferencia(f.modelo)}';
  final n = nuevas.putIfAbsent(clave, () {
    final norm = normalizarTexto(f.referencia);
    final parecidas = [
      for (final r in cat.referencias)
        (r, similitud(norm, normalizarTexto(r.nombre))),
    ]..retainWhere((p) => p.$2 >= 0.5);
    parecidas.sort((a, b) => b.$2.compareTo(a.$2));
    return ReferenciaNuevaImport(f.referencia.trim(), f.marca, f.modelo,
        parecidas: [for (final p in parecidas.take(3)) p.$1]);
  });
  if (esKitArchivo == true) n.esKit = true;
  n.equipos++;
  e.referenciaNueva = n;
}

Bodega? _bodega(String texto, List<Bodega> bodegas) {
  if (texto.isEmpty) return null;
  final t = normalizarTexto(texto);
  final exacta =
      bodegas.where((b) => normalizarTexto(b.nombre) == t).toList();
  if (exacta.length == 1) return exacta.single;
  // "RPCI" o "PROPLAS" a secas: la bodega cuyo nombre lo contiene, si es
  // una sola.
  final contiene = bodegas
      .where((b) => normalizarTexto(b.nombre).split(' ').contains(t) ||
          normalizarTexto(b.nombre).contains(t))
      .toList();
  return contiene.length == 1 ? contiene.single : null;
}

void _centros(EquipoImport e, FilaEquipoArchivo f, List<CentroCosto> centros,
    CentroCosto? origenDefecto, CentroCosto? destinoDefecto) {
  CentroCosto? porCodigo(String c) => centros
      .where((x) => x.codigo.toUpperCase() == c.trim().toUpperCase())
      .firstOrNull;

  if (f.centroOrigen.isEmpty) {
    e.centroOrigen = origenDefecto;
    if (origenDefecto == null) {
      e.errores.add('Falta el CENTRO ORIGEN y no existe el centro '
          '"$codigoOrigenPorDefecto" para usarlo por defecto.');
    }
  } else {
    final c = porCodigo(f.centroOrigen);
    if (c == null) {
      e.errores.add('No existe el centro de costo "${f.centroOrigen}" '
          '(CENTRO ORIGEN).');
    } else if (c.esInterno) {
      e.errores.add('CENTRO ORIGEN "${c.codigo}" es interno de RPCI: el '
          'origen es de dónde viene el equipo (una compra o un cliente).');
    } else {
      e.centroOrigen = c;
    }
  }

  if (f.centroDestino.isEmpty) {
    e.centroDestino = destinoDefecto;
    if (destinoDefecto == null) {
      e.errores.add('Falta el CENTRO DESTINO y no existe el centro '
          '"$codigoDestinoPorDefecto" para usarlo por defecto.');
    }
  } else {
    final c = porCodigo(f.centroDestino);
    if (c == null) {
      e.errores.add('No existe el centro de costo "${f.centroDestino}" '
          '(CENTRO DESTINO).');
    } else if (!c.esInterno) {
      e.errores.add('CENTRO DESTINO "${c.codigo}" no es interno: el destino '
          'es a quién de RPCI queda atribuido el equipo.');
    } else {
      e.centroDestino = c;
    }
  }
}

void _revisarKit(EquipoImport e, CatalogoImport cat) {
  if (e.esKitArchivo == false && e.esKit && e.referenciaNueva != null) {
    e.errores.add('ES KIT dice NO, pero otra fila de la referencia nueva '
        '"${e.nombreReferencia}" trae componentes: decide si es un kit.');
    return;
  }
  if (!e.esKit) {
    if (e.componentes.isNotEmpty) {
      e.errores.add('Trae componentes, pero "${e.nombreReferencia}" no es un '
          'kit: solo un kit tiene componentes.');
    } else if (e.valorNuevo == null) {
      e.errores.add('Falta el VALOR NUEVO.');
    }
    return;
  }
  if (e.valorNuevo != null) {
    e.avisos.add('El VALOR NUEVO se ignora: un kit vale la suma de sus '
        'componentes.');
  }
  if (e.componentes.isEmpty) {
    final plantilla =
        e.referencia == null ? null : cat.plantillas[e.referencia!.id];
    if (plantilla == null || plantilla.isEmpty) {
      e.errores.add(e.referencia == null
          ? 'Es un kit nuevo y no trae componentes: escríbelos en las filas '
              'de abajo, con el mismo SERIAL.'
          : 'Es un kit y no trae componentes, y no hay un kit anterior de '
              'esa referencia para copiarlos.');
      return;
    }
    e.componentes.addAll(plantilla);
    e.componentesDeLaPlantilla = true;
    final de = plantilla.first.desdeSerial;
    e.avisos.add('Sin componentes en el archivo: se copian los '
        '${plantilla.length} del último kit${de == null ? '' : ' ($de)'}.');
    return;
  }
  final problema = validarComposicionKit(e.componentes);
  if (problema != null) e.errores.add(problema);
}

/// Las filas de la plantilla para descargar: el encabezado y dos equipos de
/// EJEMPLO con referencias reales del catálogo (uno sencillo y un kit con sus
/// componentes). Los seriales empiezan por EJEMPLO: si alguien deja las
/// filas, la revisión las marca y no entran.
List<List<dynamic>> filasPlantillaEquipos({
  ActivoReferencia? sencilla,
  ActivoReferencia? kit,
  List<ComponentePlantilla> componentesKit = const [],
  String bodega = '',
}) {
  List<dynamic> equipo(String serial, ActivoReferencia r, String esKit,
          String condicion, Object porcentaje, Object valor, String obs) =>
      [
        serial, r.nombre, r.marca ?? '', r.modelo ?? '', esKit, condicion,
        porcentaje, valor, bodega, codigoOrigenPorDefecto,
        codigoDestinoPorDefecto, obs, '', '', '',
      ];
  return [
    encabezadoImportEquipos,
    if (sencilla != null)
      equipo('EJEMPLO-001', sencilla, 'NO', 'nuevo', 100, 1540000,
          'Fila de ejemplo: bórrala o cámbiala por un equipo real'),
    if (kit != null) ...[
      equipo('EJEMPLO-002', kit, 'SI', 'nuevo', 100, '',
          'Los componentes van en las filas de abajo, con el mismo SERIAL'),
      for (final c in componentesKit)
        [
          'EJEMPLO-002', '', '', '', '', '', '', '', '', '', '', '',
          c.nombre, c.cantidad, c.valorUnitario.round(),
        ],
    ],
    if (sencilla == null && kit == null)
      [
        'EJEMPLO-001', 'Escribe aquí el nombre de la referencia', '', '',
        'NO', 'nuevo', 100, 1540000, bodega, codigoOrigenPorDefecto,
        codigoDestinoPorDefecto, '', '', '', '',
      ],
  ];
}

/// La ayuda del formato (el ícono (i) de la pantalla).
const String ayudaImportEquipos =
    'Una fila por equipo, con el encabezado de la plantilla en la primera '
    'fila.\n\n'
    '• SERIAL: el del equipo. No se puede repetir (ni en el archivo ni con uno '
    'que ya exista).\n'
    '• REFERENCIA: el modelo. Si no existe en el catálogo, se CREA al cargar; '
    'antes de cargar verás cuáles y a cuáles se parecen. MARCA y MODELO '
    'ayudan a encontrarla o se usan al crearla.\n'
    '• ES KIT: SI o NO.\n'
    '• CONDICION: nuevo, usado, repuestos o baja.\n'
    '• PORCENTAJE: de 0 a 100 (vacío = 100).\n'
    '• VALOR NUEVO: en pesos. En un kit no se usa: vale la suma de sus '
    'componentes.\n'
    '• BODEGA: donde queda (Bodega RPCI, Bodega PROPLAS…).\n'
    '• CENTRO ORIGEN y CENTRO DESTINO: códigos. Vacíos = COMPRA y G000002, '
    'como en el alta de un equipo.\n\n'
    'KITS: el kit en una fila, y sus componentes en las filas de abajo con el '
    'MISMO SERIAL, llenando solo COMPONENTE, CANTIDAD y VALOR UNITARIO. Si un '
    'kit no trae componentes, se copian los del último kit de esa '
    'referencia.\n\n'
    'Nada entra sin revisión: la pantalla muestra qué entra, qué se crea y '
    'qué tiene problemas. Subir el mismo archivo otra vez no duplica nada: un '
    'serial que ya existe no vuelve a entrar.';
