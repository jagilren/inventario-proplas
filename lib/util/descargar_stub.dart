import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

/// Guarda un archivo en móvil/escritorio abriendo el diálogo del sistema.
///
/// Se usa `file_picker` —que ya era dependencia y NO aplica Kotlin Gradle
/// Plugin— en vez de `file_saver`. Desde la versión 8 escribe los bytes
/// directamente en Android e iOS, así que no hace falta ningún paso extra.
///
/// Si el usuario cancela el diálogo, no se guarda nada y no es un error.
Future<void> guardarArchivo({
  required String nombre,
  required String extension,
  required Uint8List bytes,
  required String mimeType,
}) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Guardar $nombre.$extension',
    fileName: '$nombre.$extension',
    bytes: bytes,
  );
}

String comoTexto(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
