import 'package:flutter/material.dart';
import '../util/aviso_salir.dart';

/// Avisa antes de abandonar una pantalla donde hay trabajo sin guardar.
///
/// Para qué: en las cargas masivas el usuario puede llevar decenas de líneas
/// emparejadas y corregidas a mano. Si se sale sin registrar el movimiento,
/// todo ese trabajo se pierde — y hasta ahora se perdía en silencio, con un
/// simple toque en la flecha de atrás.
///
/// Cubre dos caminos distintos:
/// - **Dentro de la app** (flecha de la barra, botón de atrás de Android,
///   botón "atrás" del navegador): diálogo propio, con nuestro texto.
/// - **Cerrar o recargar la pestaña en web**: el aviso estándar del
///   navegador. Ahí el texto no se puede personalizar — los navegadores no
///   lo permiten, para que ninguna página pueda engañar al usuario.
class ConfirmarDescarte extends StatefulWidget {
  /// Si es false, la pantalla se cierra sin preguntar nada.
  final bool hayTrabajoSinGuardar;

  /// Qué se va a perder, en palabras del usuario.
  /// Ej: '18 líneas emparejadas'.
  final String queSePierde;

  final Widget child;

  const ConfirmarDescarte({
    super.key,
    required this.hayTrabajoSinGuardar,
    required this.queSePierde,
    required this.child,
  });

  @override
  State<ConfirmarDescarte> createState() => _ConfirmarDescarteState();
}

class _ConfirmarDescarteState extends State<ConfirmarDescarte> {
  @override
  void didUpdateWidget(ConfirmarDescarte old) {
    super.didUpdateWidget(old);
    // El aviso del navegador se prende y se apaga solo, según haya trabajo.
    if (old.hayTrabajoSinGuardar != widget.hayTrabajoSinGuardar) {
      avisarAntesDeCerrarPestana(widget.hayTrabajoSinGuardar);
    }
  }

  @override
  void dispose() {
    // Al salir de la pantalla se quita SIEMPRE: si no, el navegador seguiría
    // preguntando en el resto de la app.
    avisarAntesDeCerrarPestana(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hayTrabajoSinGuardar = widget.hayTrabajoSinGuardar;
    final queSePierde = widget.queSePierde;
    return PopScope(
      canPop: !hayTrabajoSinGuardar,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return; // ya se cerró: no había nada que perder
        final salir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber, color: Colors.orange,
                size: 40),
            title: const Text('¿Salir sin registrar?'),
            content: Text(
              'Tienes $queSePierde sin registrar.\n\n'
              'Si sales ahora se pierde ese trabajo y toca volver a subir '
              'el archivo y corregir los emparejamientos otra vez.',
            ),
            actions: [
              // El botón seguro es el que se queda: es el de la derecha y el
              // resaltado, para que el toque por inercia no borre nada.
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salir y perder',
                    style: TextStyle(color: Colors.red)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Seguir aquí'),
              ),
            ],
          ),
        );
        if (salir == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: widget.child,
    );
  }
}
