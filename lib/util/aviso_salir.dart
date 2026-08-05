// Aviso de "vas a perder lo que llevas" al cerrar/recargar la pestaña.
// Solo aplica en web; en móvil/escritorio no hace nada (allá manda PopScope).
export 'aviso_salir_stub.dart' if (dart.library.html) 'aviso_salir_web.dart';
