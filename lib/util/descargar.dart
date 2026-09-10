/// Guardar un archivo generado por la app (informes CSV, plantillas).
///
/// Reemplaza a `file_saver`, que aplicaba Kotlin Gradle Plugin: Flutter avisa
/// que las versiones futuras FALLARÁN al compilar si un plugin lo aplica, y su
/// última versión publicada seguía haciéndolo.
///
/// En su lugar, cada plataforma usa lo que ya tenía a mano:
///  · Web   → descarga del navegador, SIN plugin (mismo patrón que `picker`).
///  · Móvil → `file_picker`, que ya era dependencia del proyecto y está libre
///            de KGP; abre el diálogo del sistema para elegir dónde guardar.
library;

export 'descargar_stub.dart' if (dart.library.html) 'descargar_web.dart';
