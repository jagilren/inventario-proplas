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

/// Muestra la ayuda del formato con el diálogo informativo de la app.
void mostrarAyudaFormato(BuildContext context) => mostrarInfoDialog(
      context,
      icon: Icons.table_chart,
      color: Colors.teal,
      titulo: 'Cómo armar el archivo',
      contenido: ayudaFormatoArchivo,
    );

/// Descarga una plantilla lista para llenar.
///
/// Las filas de ejemplo salen del catálogo REAL del usuario, no son inventadas:
/// así ve exactamente cómo se escriben los nombres que la app espera, y si
/// deja los ejemplos, el emparejamiento le acierta al 100%.
Future<void> descargarPlantillaImport(
  BuildContext context, {
  required String nombreArchivo,
}) async {
  try {
    final ejemplos = await InventarioService.buscar('', limit: 3);
    final filas = <List<dynamic>>[
      ['ELEMENTO', 'CANTIDAD'],
      if (ejemplos.isEmpty)
        ['Escribe aquí el nombre del artículo', 1]
      else
        for (final e in ejemplos) [e.nombre, 1],
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
