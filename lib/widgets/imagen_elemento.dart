import 'package:flutter/material.dart';

/// Muestra la foto de un elemento con marcador de posición y manejo de errores.
/// La app depende de la red, así que una imagen que no cargue nunca debe
/// romper la pantalla: siempre cae a un ícono neutro.
class ImagenElemento extends StatelessWidget {
  final String? url;
  final double tamano;
  final double radio;
  final BoxFit ajuste;

  const ImagenElemento({
    super.key,
    required this.url,
    this.tamano = 48,
    this.radio = 8,
    this.ajuste = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final vacio = _marcador(context);
    if (url == null || url!.isEmpty) return vacio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: Image.network(
        url!,
        width: tamano,
        height: tamano,
        fit: ajuste,
        errorBuilder: (_, __, ___) => vacio,
        loadingBuilder: (context, child, progreso) {
          if (progreso == null) return child;
          return SizedBox(
            width: tamano,
            height: tamano,
            child: Center(
              child: SizedBox(
                width: tamano * 0.35,
                height: tamano * 0.35,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _marcador(BuildContext context) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radio),
        ),
        child: Icon(Icons.inventory_2_outlined,
            size: tamano * 0.5, color: Colors.grey.shade500),
      );
}

/// Abre la imagen a pantalla completa, con zoom.
class ImagenCompleta extends StatelessWidget {
  final String url;
  final String titulo;
  const ImagenCompleta({super.key, required this.url, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(titulo, style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            url,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se pudo cargar la imagen',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
