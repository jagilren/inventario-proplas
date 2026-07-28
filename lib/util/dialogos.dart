import 'package:flutter/material.dart';

/// Diálogo informativo genérico: ícono + título + contenido + "Entendido".
void mostrarInfoDialog(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String titulo,
  required String contenido,
}) {
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(icon, color: color, size: 40),
      title: Text(titulo),
      content: Text(contenido),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
