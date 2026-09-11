import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

/// Guarda un archivo en móvil/escritorio abriendo el diálogo del sistema.
///
/// Se usa `file_picker` —que ya era dependencia y NO aplica Kotlin Gradle
/// Plugin— en vez de `file_saver`. Desde la versión 8 escribe los bytes
/// directamente en Android e iOS, así que no hace falta ningún paso extra.
///
/// Si el usuario cancela el diálogo, no se guarda nada y no es un error:
/// devuelve false, para que quien llama no diga "✓ guardado" cuando no lo
/// está (en el celular es fácil tocar "atrás" en el diálogo sin notarlo).
Future<bool> guardarArchivo({
  required String nombre,
  required String extension,
  required Uint8List bytes,
  required String mimeType,
}) async {
  // file_picker 12: saveFile devuelve la Uri del archivo guardado, o null
  // si se canceló el diálogo.
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar $nombre.$extension',
    fileName: '$nombre.$extension',
    bytes: bytes,
    mimeType: mimeType,
  );
  return uri != null;
}

String comoTexto(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
