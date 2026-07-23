// Selector de archivo multiplataforma: en web usa un input HTML nativo;
// en móvil/escritorio se usa file_picker directamente (ver devoluciones_page).
export 'picker_stub.dart' if (dart.library.html) 'picker_web.dart';
