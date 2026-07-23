// Huella visual (dHash) para reconocer un elemento por su foto.
// El MISMO algoritmo se usa para las fotos guardadas y para la foto de
// consulta, así se pueden comparar. dHash = compara brillos vecinos.
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class PHash {
  /// Huella de 64 bits en hex (16 caracteres). null si no se pudo leer.
  static String? dhash(Uint8List bytes) {
    final im = img.decodeImage(bytes);
    if (im == null) return null;
    // 9x8 con NEAREST (mismo que el precálculo en Python).
    final r = img.copyResize(im,
        width: 9, height: 8, interpolation: img.Interpolation.nearest);
    final sb = StringBuffer();
    int nibble = 0, count = 0;
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final l = img.getLuminance(r.getPixel(x, y));
        final rr = img.getLuminance(r.getPixel(x + 1, y));
        nibble = (nibble << 1) | (l < rr ? 1 : 0);
        if (++count == 4) { sb.write(nibble.toRadixString(16)); nibble = 0; count = 0; }
      }
    }
    return sb.toString(); // 16 caracteres hex
  }

  /// Distancia de Hamming (cuántos bits difieren). Menor = más parecidas.
  static int hamming(String a, String b) {
    if (a.length != b.length) return 64;
    int d = 0;
    for (int i = 0; i < a.length; i++) {
      var x = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
      while (x != 0) { d += x & 1; x >>= 1; }
    }
    return d;
  }
}
