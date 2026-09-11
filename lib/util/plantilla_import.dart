import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../reportes.dart';
import 'dialogos.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Ayuda del formato de los archivos de carga masiva (devoluciones, salidas).
///
/// Antes esta explicación solo salía cuando el archivo fallaba, o sea que el
/// usuario se enteraba del formato DESPUÉS de equivocarse. Ahora está a la
/// mano desde el principio, con el ícono (i) al lado del botón de subir.
const String ayudaFormatoArchivo =
    'El archivo necesita solo dos columnas, con encabezado en la primera fila:\n\n'
    '   ELEMENTO      CANTIDAD\n'
    '   Tubo PVC 2"   10\n'
    '   Codo 90° 1"   4\n\n'
    '• ELEMENTO: el nombre del artículo. No tiene que ser idéntico al del '
    'catálogo: la app busca el más parecido y te muestra con qué lo emparejó '
    'para que lo revises antes de cargar.\n'
    '• CANTIDAD: solo el número.\n\n'
    'Si el archivo trae columnas de más, se ignoran sin problema. '
    'Sirve Excel (.xlsx) o CSV.\n\n'
    'Lo más fácil es pulsar "Plantilla": baja un archivo de ejemplo ya armado '
    'con artículos de tu propio catálogo, para que lo llenes encima.';

/// Encabezado del archivo de DEVOLUCIÓN. Uno solo para la remisión de
/// devolución (que lo genera) y la plantilla de Devoluciones (que lo
/// ejemplifica): si cada una tuviera el suyo, a la primera corrección
/// dirían cosas distintas.
///
/// Cada columna significa UNA cosa: COSTO PROMEDIO es informativo (del
/// catálogo, no se usa al cargar); COSTO ESTIMADO es el que propone el
/// ingeniero para un artículo NUEVO, y ese sí se usa.
const List<String> encabezadoDevolucion = [
  'ELEMENTO',
  'CANTIDAD',
  'COSTO PROMEDIO',
  'NUEVO',
  'UNIDAD',
  'COSTO ESTIMADO',
  'ESTIMADO POR',
];

/// Una línea de la remisión: un artículo del catálogo, o uno NUEVO que no
/// existe en la base y propone el ingeniero.
class LineaDevolucion {
  /// Del catálogo; null si es nuevo.
  final Elemento? elemento;
  final String nombre;
  final num cantidad;
  // Solo en las nuevas:
  final String? unidad;
  final num? costoEstimado;

  LineaDevolucion.catalogo(Elemento e, this.cantidad)
      : elemento = e,
        nombre = e.nombre,
        unidad = null,
        costoEstimado = null;

  const LineaDevolucion.nueva({
    required this.nombre,
    required this.cantidad,
    required String this.unidad,
    required num this.costoEstimado,
  }) : elemento = null;

  bool get esNueva => elemento == null;
}

/// Las filas de un archivo de devolución.
///
/// Del catálogo: nombre, cantidad y su costo promedio — de [costos] (leído
/// del servidor en ese momento) o, si no está ahí, el que trae el elemento.
/// Nuevas: nombre, cantidad, "SI", unidad, costo estimado y [estimadoPor]
/// (el correo de quien genera la remisión). Dinero en pesos enteros, como
/// en los informes.
List<List<dynamic>> filasCsvDevolucion(
  List<LineaDevolucion> lineas, {
  Map<String, num> costos = const {},
  String? estimadoPor,
}) =>
    [
      encabezadoDevolucion,
      for (final l in lineas)
        if (l.elemento case final e?)
          [
            e.nombre, l.cantidad,
            (costos[e.id] ?? e.costoPromedio).round(), '', '', '', '',
          ]
        else
          [
            l.nombre, l.cantidad, '', 'SI', l.unidad,
            l.costoEstimado!.round(), estimadoPor ?? '',
          ],
    ];

/// Una línea que NO se cargó en Devoluciones, para bajarla y cargarla
/// después sin repetir las que ya entraron.
class PendienteDevolucion {
  final String elemento;
  final num cantidad;
  /// Informativo, como en la remisión. Null si no se sabe.
  final num? costoPromedio;
  // Si llegó como NUEVO: lo que propuso el ingeniero, tal cual.
  final bool nuevo;
  final String? unidad;
  final num? costoEstimado;
  final String? estimadoPor;
  /// Por qué no se cargó, en palabras.
  final String motivo;

  const PendienteDevolucion({
    required this.elemento,
    required this.cantidad,
    this.costoPromedio,
    this.nuevo = false,
    this.unidad,
    this.costoEstimado,
    this.estimadoPor,
    required this.motivo,
  });
}

/// El archivo de lo que no se cargó: el MISMO formato de la remisión, para
/// subirlo otra vez a Devoluciones tal cual, más una columna final que dice
/// por qué no entró cada línea. El lector la ignora: busca sus columnas por
/// nombre, y "POR QUE NO SE CARGO" no se confunde con ninguna.
List<List<dynamic>> filasCsvPendientes(List<PendienteDevolucion> lineas) => [
      [...encabezadoDevolucion, 'POR QUE NO SE CARGO'],
      for (final p in lineas)
        [
          p.elemento,
          p.cantidad,
          p.nuevo ? '' : (p.costoPromedio?.round() ?? ''),
          p.nuevo ? 'SI' : '',
          p.nuevo ? (p.unidad ?? '') : '',
          p.nuevo ? (p.costoEstimado?.round() ?? '') : '',
          p.nuevo ? (p.estimadoPor ?? '') : '',
          p.motivo,
        ],
    ];

/// Lo que queda escrito en la observación del movimiento de una fila que
/// llegó como NUEVO: quién propuso qué y a cuánto, y en qué terminó. Así el
/// costo estimado se puede auditar después (plan-remision-elementos-nuevos,
/// regla 3).
String observacionArticuloNuevo({
  required String propuesto,
  String? estimadoPor,
  num? costoEstimado,
  required num costoCargado,
  required bool creado,
  required String nombreFinal,
}) {
  String pesos(num v) => _money.format(v);
  final quien = estimadoPor ?? 'quien armó la remisión';
  final partes = <String>[
    creado
        ? 'Artículo nuevo creado desde remisión'
        : 'Propuesto como nuevo "$propuesto"; ya existía como "$nombreFinal"',
    if (costoEstimado != null) 'estimado por $quien: ${pesos(costoEstimado)}',
    if (costoEstimado == null || costoEstimado.round() != costoCargado.round())
      'cargado a ${pesos(costoCargado)}',
  ];
  return partes.join(' · ');
}

/// Ayuda del formato de una DEVOLUCIÓN.
const String ayudaFormatoDevolucion =
    'El archivo lleva estas columnas, con encabezado en la primera fila:\n\n'
    '   ELEMENTO | CANTIDAD | COSTO PROMEDIO | NUEVO | UNIDAD | '
    'COSTO ESTIMADO | ESTIMADO POR\n\n'
    '• ELEMENTO: el nombre del artículo. No tiene que ser idéntico al del '
    'catálogo: la app busca el más parecido y te muestra con qué lo emparejó '
    'para que lo revises antes de cargar.\n'
    '• CANTIDAD: solo el número.\n'
    '• COSTO PROMEDIO: el del artículo cuando se generó el archivo. Es para '
    'consultarlo; al cargar NO se usa: la devolución entra al costo promedio '
    'que tenga el artículo en ese momento.\n\n'
    'Artículos que NO están en el catálogo: pon SI en NUEVO, y llena UNIDAD '
    '(UND, MT, Par, KG o LT), COSTO ESTIMADO (lo que vale UNA unidad) y '
    'ESTIMADO POR (quién lo estimó). Al cargar, la bodega los revisa: si ya '
    'existían con otro nombre, los elige; si no, un coordinador los crea en '
    'el catálogo y entran a ese costo estimado, que se puede corregir.\n\n'
    'Solo ELEMENTO y CANTIDAD son obligatorias: un archivo de dos columnas '
    'sirve igual. Antes de cargar, elige arriba la bodega y los centros de '
    'costo Origen y Destino: aplican a todo el archivo.\n\n'
    'Sirve Excel (.xlsx) o CSV. Lo más fácil es armar la lista en "Remisión '
    'de devolución" y generar el CSV desde ahí, o pulsar "Plantilla".';

/// Ayuda del formato para una COMPRA a proveedor: lleva una columna más.
const String ayudaFormatoCompra =
    'El archivo necesita TRES columnas, con encabezado en la primera fila:\n\n'
    '   ELEMENTO      CANTIDAD   COSTO UNITARIO\n'
    '   Tubo PVC 2"   10         12500\n'
    '   Codo 90° 1"   4          3200\n\n'
    '• ELEMENTO: el nombre del artículo. No tiene que ser idéntico al del '
    'catálogo: la app busca el más parecido y te muestra con qué lo emparejó '
    'para que lo revises antes de cargar.\n'
    '• CANTIDAD: solo el número.\n'
    '• COSTO UNITARIO: lo que pagaste por UNA unidad, SIN IVA. No el total '
    'de la línea.\n\n'
    'El costo es obligatorio y no es un dato de adorno: es el que recalcula '
    'el costo promedio del artículo. Si entra mal, la valorización de todo '
    'tu inventario queda mal.\n\n'
    'Si el archivo trae columnas de más, se ignoran. Sirve Excel (.xlsx) o CSV.\n\n'
    'Lo más fácil es pulsar "Plantilla": baja un archivo de ejemplo ya armado '
    'con artículos de tu propio catálogo, para que lo llenes encima.';

/// Muestra la ayuda del formato con el diálogo informativo de la app.
/// Con [compra] en true explica también la columna del costo unitario; con
/// [devolucion], la del costo promedio.
void mostrarAyudaFormato(BuildContext context,
        {bool compra = false, bool devolucion = false}) =>
    mostrarInfoDialog(
      context,
      icon: Icons.table_chart,
      color: Colors.teal,
      titulo: compra
          ? 'Cómo armar el archivo de compra'
          : devolucion
              ? 'Cómo armar el archivo de devolución'
              : 'Cómo armar el archivo',
      contenido: compra
          ? ayudaFormatoCompra
          : devolucion
              ? ayudaFormatoDevolucion
              : ayudaFormatoArchivo,
    );

/// Descarga una plantilla lista para llenar.
///
/// Las filas de ejemplo salen del catálogo REAL del usuario, no son inventadas:
/// así ve exactamente cómo se escriben los nombres que la app espera, y si
/// deja los ejemplos, el emparejamiento le acierta al 100%.
/// Con [compra] en true agrega la columna COSTO UNITARIO, y precarga el
/// costo promedio actual de cada ejemplo como punto de partida (el usuario
/// lo reemplaza por lo que realmente pagó).
/// Con [devolucion] en true sale con el formato de la remisión de
/// devolución: agrega la columna COSTO PROMEDIO (informativa).
Future<void> descargarPlantillaImport(
  BuildContext context, {
  required String nombreArchivo,
  bool compra = false,
  bool devolucion = false,
}) async {
  try {
    final ejemplos = await InventarioService.buscar('', limit: 3);
    final filas = devolucion
        ? (ejemplos.isEmpty
            ? <List<dynamic>>[
                encabezadoDevolucion,
                ['Escribe aquí el nombre del artículo', 1, 0, '', '', '', ''],
              ]
            : filasCsvDevolucion(
                [for (final e in ejemplos) LineaDevolucion.catalogo(e, 1)]))
        : <List<dynamic>>[
      if (compra)
        ['ELEMENTO', 'CANTIDAD', 'COSTO UNITARIO']
      else
        ['ELEMENTO', 'CANTIDAD'],
      if (ejemplos.isEmpty)
        if (compra)
          ['Escribe aquí el nombre del artículo', 1, 0]
        else
          ['Escribe aquí el nombre del artículo', 1]
      else
        for (final e in ejemplos)
          if (compra)
            [e.nombre, 1, e.costoPromedio]
          else
            [e.nombre, 1],
    ];
    final guardado = await Reportes.descargarCsv(nombreArchivo, filas);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(guardado
            ? '✓ Plantilla descargada. Llénala y vuelve a subirla.'
            : 'No se guardó la plantilla: se canceló el diálogo.'),
        duration: const Duration(seconds: 3),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la plantilla: $e')),
      );
    }
  }
}
