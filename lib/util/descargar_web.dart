import 'dart:convert';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

/// Descarga un archivo en el navegador, sin ningún plugin.
///
/// Se crea un enlace temporal apuntando a los bytes y se "pulsa" solo. Es el
/// mismo mecanismo que usa cualquier página para ofrecer una descarga.
Future<void> guardarArchivo({
  required String nombre,
  required String extension,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob(<Object>[bytes], mimeType),
  );
  html.AnchorElement(href: url)
    ..setAttribute('download', '$nombre.$extension')
    ..click();
  // Liberar la referencia: si no, el navegador guarda los bytes en memoria
  // hasta que se recargue la página.
  html.Url.revokeObjectUrl(url);
}

/// Se conserva por si algún día hace falta el contenido como texto.
String comoTexto(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
