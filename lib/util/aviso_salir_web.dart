// ignore: deprecated_member_use
import 'dart:html' as html;

/// Pide al NAVEGADOR que confirme antes de cerrar o recargar la pestaña.
///
/// PopScope cubre la flecha de atrás (de la barra, de Android y del
/// navegador), pero no puede interceptar el cierre de la pestaña ni un F5.
/// Para eso solo sirve 'beforeunload', y es el navegador el que muestra su
/// propio mensaje: no se puede personalizar el texto ni el diseño, es una
/// medida de seguridad de los navegadores.
html.EventListener? _handler;

void avisarAntesDeCerrarPestana(bool activar) {
  if (activar) {
    if (_handler != null) return; // ya estaba puesto
    _handler = (event) {
      // Basta con cancelar el evento: el navegador muestra su aviso estándar.
      event.preventDefault();
      (event as html.BeforeUnloadEvent).returnValue = '';
    };
    html.window.addEventListener('beforeunload', _handler);
  } else {
    if (_handler == null) return;
    html.window.removeEventListener('beforeunload', _handler);
    _handler = null;
  }
}
