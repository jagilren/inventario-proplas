import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'picker.dart';

/// Elige una imagen del dispositivo (archivo / "computador").
///
/// En WEB usa un input HTML nativo: el diálogo se abre de inmediato, sin el
/// bloqueo de "user activation" que sufre image_picker en algunos navegadores
/// (por eso no abría). Además comprime la imagen para no pasar el límite del
/// balde. En móvil usa image_picker, que ya redimensiona.
Future<Uint8List?> elegirImagenArchivo() async {
  if (kIsWeb) {
    final r = await abrirArchivoWeb('image/*');
    if (r == null) return null;
    return _comprimir(r.bytes);
  }
  final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280,
      imageQuality: 80);
  return foto == null ? null : await foto.readAsBytes();
}

/// Redimensiona a máx. 1280 px y recodifica en JPG (calidad 80) para que la
/// foto pese poco. Si algo falla, devuelve los bytes originales.
Uint8List _comprimir(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var im = decoded;
    if (decoded.width > 1280 || decoded.height > 1280) {
      im = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: 1280)
          : img.copyResize(decoded, height: 1280);
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 80));
  } catch (_) {
    return bytes;
  }
}
