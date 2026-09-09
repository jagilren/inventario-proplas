import 'package:flutter/material.dart';

/// Pie de una lista paginada: el botón "Cargar más", el indicador mientras
/// trae la página siguiente, o el aviso de que ya no queda nada.
///
/// Para qué: una lista que trae un lote fijo y no ofrece traer el resto
/// oculta datos en silencio — el usuario no tiene forma de saber que hay
/// más. Se usa como último elemento de la lista (itemCount + 1).
class PieCargarMas extends StatelessWidget {
  final bool cargando;
  final bool hayMas;
  final VoidCallback onCargarMas;

  const PieCargarMas({
    super.key,
    required this.cargando,
    required this.hayMas,
    required this.onCargarMas,
  });

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hayMas) {
      return Center(
        child: TextButton.icon(
          onPressed: onCargarMas,
          icon: const Icon(Icons.expand_more, size: 18),
          label: const Text('Cargar más'),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text('— No hay más —',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }
}
