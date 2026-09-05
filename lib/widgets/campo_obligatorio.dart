import 'package:flutter/material.dart';

/// Sombrea en rojo pálido un campo obligatorio que el usuario dejó vacío al
/// intentar guardar/cargar. Se usa envolviendo la InputDecoration ya armada
/// del campo. No hace falta "limpiarlo" a mano cuando se llena: como el
/// llamador recalcula [error] en cada build a partir del valor actual, la
/// próxima vez que el campo tenga algo la condición da false sola y el
/// campo vuelve a su color de siempre.
InputDecoration marcarError(InputDecoration base, bool error) => error
    ? base.copyWith(filled: true, fillColor: Colors.red.shade50)
    : base;

/// Mismo sombreado, para un widget que no es un campo de texto (una
/// tarjeta, el selector de elemento, la lista de seriales).
Widget conMarcaError({required bool error, required Widget child}) {
  if (!error) return child;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(6),
    ),
    child: child,
  );
}
