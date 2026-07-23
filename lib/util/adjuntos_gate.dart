import 'package:flutter/material.dart';

/// La subida de adjuntos está deshabilitada para no gastar Storage de Supabase.
/// Muestra el aviso del "billete" (a cualquier usuario, incluidos admins) y no
/// sube nada. El backend queda listo por si algún día se habilita.
void mostrarMensajeBillete(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.savings, color: Colors.orange, size: 40),
      title: const Text('Función de pago'),
      content: const Text(
          'Te hacen falta créditos en SUPABASE para adjuntar archivos. '
          'Transfiere el billete para darte los permisos 💸'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d),
            child: const Text('Entendido')),
      ],
    ),
  );
}
