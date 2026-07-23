import 'dart:typed_data';

/// Implementación de reserva (móvil/escritorio): en esas plataformas se usa
/// file_picker, no esta función. Nunca debería llamarse aquí.
Future<({String name, Uint8List bytes})?> abrirArchivoWeb(String accept) async {
  throw UnsupportedError('abrirArchivoWeb solo está disponible en web');
}
