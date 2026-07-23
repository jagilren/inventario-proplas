import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Abre el diálogo de archivo en WEB con un input HTML nativo.
/// El input.click() se dispara de inmediato (sin trabajo previo) para no
/// perder el "user activation" del navegador (clave en Safari/iPhone).
Future<({String name, Uint8List bytes})?> abrirArchivoWeb(String accept) async {
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = false;
  input.click();

  // Espera a que el usuario elija (change) o cancele. Sin selección → null.
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  final result = reader.result;
  final Uint8List bytes;
  if (result is ByteBuffer) {
    bytes = result.asUint8List();
  } else if (result is Uint8List) {
    bytes = result;
  } else {
    bytes = Uint8List.fromList(result as List<int>);
  }
  return (name: file.name, bytes: bytes);
}
