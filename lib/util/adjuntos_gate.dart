import 'package:flutter/material.dart';
import 'dialogos.dart';

/// La subida de adjuntos está deshabilitada para no gastar Storage de Supabase.
/// Muestra el aviso del "billete" (a cualquier usuario, incluidos admins) y no
/// sube nada. El backend queda listo por si algún día se habilita.
void mostrarMensajeBillete(BuildContext context) {
  mostrarInfoDialog(
    context,
    icon: Icons.savings,
    color: Colors.orange,
    titulo: 'Función de pago',
    contenido:
        'Te hacen falta créditos en SUPABASE para adjuntar archivos. '
        'Transfiere el billete para darte los permisos 💸',
  );
}
