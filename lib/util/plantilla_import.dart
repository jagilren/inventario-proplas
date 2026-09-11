import 'package:flutter/material.dart';
import '../data.dart';
import '../reportes.dart';
import 'dialogos.dart';

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
const List<String> encabezadoDevolucion = [
  'ELEMENTO',
  'CANTIDAD',
  'COSTO PROMEDIO',
];

/// Las filas de un archivo de devolución: nombre, cantidad y el costo
/// promedio del artículo. El costo sale de [costos] (leído del servidor en
/// ese momento) y, si un elemento no está ahí, del que trae el propio
/// elemento. Va en pesos enteros, como en los informes.
///
/// Esa tercera columna es INFORMATIVA: la carga de Devoluciones la ignora y
/// valoriza siempre al costo promedio que tenga el artículo al cargarla.
List<List<dynamic>> filasCsvDevolucion(
  List<(Elemento, num)> lineas, {
  Map<String, num> costos = const {},
}) =>
    [
      encabezadoDevolucion,
      for (final (e, cantidad) in lineas)
        [e.nombre, cantidad, (costos[e.id] ?? e.costoPromedio).round()],
    ];

/// Ayuda del formato de una DEVOLUCIÓN: las dos columnas de siempre y la
/// del costo promedio, que es solo para mirar.
const String ayudaFormatoDevolucion =
    'El archivo lleva tres columnas, con encabezado en la primera fila:\n\n'
    '   ELEMENTO      CANTIDAD   COSTO PROMEDIO\n'
    '   Tubo PVC 2"   10         12500\n'
    '   Codo 90° 1"   4          3200\n\n'
    '• ELEMENTO: el nombre del artículo. No tiene que ser idéntico al del '
    'catálogo: la app busca el más parecido y te muestra con qué lo emparejó '
    'para que lo revises antes de cargar.\n'
    '• CANTIDAD: solo el número.\n'
    '• COSTO PROMEDIO: el costo promedio del artículo cuando se generó el '
    'archivo. Es para consultarlo; al cargar NO se usa: la devolución '
    'siempre entra al costo promedio que tenga el artículo en ese momento. '
    'Si falta esta columna, el archivo sirve igual.\n\n'
    'Antes de cargar, elige arriba la bodega y los centros de costo Origen y '
    'Destino: aplican a todo el archivo.\n\n'
    'Si el archivo trae columnas de más, se ignoran. Sirve Excel (.xlsx) o '
    'CSV.\n\n'
    'Lo más fácil es pulsar "Plantilla": baja un archivo de ejemplo ya armado '
    'con artículos de tu propio catálogo, para que lo llenes encima. O arma '
    'la lista en "Remisión de devolución" y genera el CSV desde ahí.';

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
                ['Escribe aquí el nombre del artículo', 1, 0],
              ]
            : filasCsvDevolucion([for (final e in ejemplos) (e, 1)]))
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
    await Reportes.descargarCsv(nombreArchivo, filas);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Plantilla descargada. Llénala y vuelve a subirla.'),
        duration: Duration(seconds: 3),
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
