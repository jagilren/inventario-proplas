import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:image_picker/image_picker.dart';
import '../data.dart';
import 'imagen_elemento.dart';

/// Galería editable de fotos de un elemento (máximo 3).
///
/// Se usa de dos formas:
/// - Elemento existente ([elementoId] != null): sube y borra contra el servidor.
/// - Elemento nuevo (aún sin id): guarda las fotos en memoria y avisa al
///   formulario con [onPendientes] para que las suba después de crearlo.
class GaleriaElemento extends StatefulWidget {
  final String? elementoId;
  final ValueChanged<List<Uint8List>>? onPendientes;
  const GaleriaElemento({super.key, this.elementoId, this.onPendientes});

  @override
  State<GaleriaElemento> createState() => _GaleriaElementoState();
}

class _GaleriaElementoState extends State<GaleriaElemento> {
  List<ImagenElem> _fotos = [];
  final List<Uint8List> _pendientes = [];
  bool _cargando = false;

  bool get _esNuevo => widget.elementoId == null;
  int get _total => _esNuevo ? _pendientes.length : _fotos.length;
  bool get _hayCupo => _total < InventarioService.maxImagenes;

  @override
  void initState() {
    super.initState();
    if (!_esNuevo) _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final f = await InventarioService.imagenesElemento(widget.elementoId!);
      if (mounted) setState(() => _fotos = f);
    } catch (_) {
      // una galería que no cargue no debe romper el formulario
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _agregar(ImageSource origen) async {
    try {
      final foto = await ImagePicker().pickImage(
        source: origen, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (foto == null) return; // el usuario canceló
      final bytes = await foto.readAsBytes();
      if (!mounted) return;

      if (_esNuevo) {
        setState(() => _pendientes.add(bytes));
        widget.onPendientes?.call(_pendientes);
      } else {
        setState(() => _cargando = true);
        await InventarioService.agregarImagen(widget.elementoId!, bytes);
        await _cargar();
      }
    } on MissingPluginException {
      // El navegador tiene guardada una versión vieja de la app.
      _msg('Recarga la página con Ctrl+Shift+R para activar la cámara.');
      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      final t = e.toString().toLowerCase();
      String mensaje;
      // Distinguir "no hay cámara" de "no dieron permiso" o error real,
      // para que el usuario sepa qué hacer.
      if (origen == ImageSource.camera &&
          (t.contains('no camera') || t.contains('notfound') ||
           t.contains('no cameras available') || t.contains('camera_access_denied'))) {
        mensaje = 'Este equipo no tiene cámara disponible. '
            'Usa "Elegir imagen" en su lugar.';
      } else if (t.contains('denied') || t.contains('permission')) {
        mensaje = 'Debes permitir el acceso a la cámara para tomar la foto.';
      } else {
        mensaje = 'No se pudo agregar la foto: $e';
      }
      _msg(mensaje);
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _menuAgregar() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // En el navegador la cámara depende del equipo; el archivo siempre
          // funciona, así que se ofrece de primero.
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tomar foto'),
              onTap: () { Navigator.pop(ctx); _agregar(ImageSource.camera); },
            ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(kIsWeb ? 'Elegir imagen del computador'
                               : 'Elegir de la galería'),
            onTap: () { Navigator.pop(ctx); _agregar(ImageSource.gallery); },
          ),
          if (kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Usar la cámara'),
              subtitle: const Text('Requiere cámara y dar permiso al navegador'),
              onTap: () { Navigator.pop(ctx); _agregar(ImageSource.camera); },
            ),
        ]),
      ),
    );
  }

  Future<void> _accionesFoto(ImagenElem img) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!img.principal)
            ListTile(
              leading: const Icon(Icons.star),
              title: const Text('Usar como foto principal'),
              subtitle: const Text('Es la que aparece en la lista'),
              onTap: () async {
                Navigator.pop(ctx);
                await InventarioService.marcarPrincipal(img.id);
                await _cargar();
              },
            ),
          ListTile(
            leading: const Icon(Icons.open_in_full),
            title: const Text('Ver en grande'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImagenCompleta(url: img.url, titulo: 'Foto')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Borrar foto', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              setState(() => _cargando = true);
              await InventarioService.borrarImagen(img);
              await _cargar();
            },
          ),
        ]),
      ),
    );
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text('$_total de ${InventarioService.maxImagenes}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (_cargando) ...[
              const SizedBox(width: 10),
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // fotos ya guardadas
              ..._fotos.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        InkWell(
                          onTap: () => _accionesFoto(f),
                          child: ImagenElemento(url: f.url, tamano: 104, radio: 10),
                        ),
                        if (f.principal)
                          const Positioned(
                            top: 4, left: 4,
                            child: Icon(Icons.star, size: 18, color: Colors.amber),
                          ),
                      ],
                    ),
                  )),
              // fotos pendientes de subir (elemento nuevo)
              ..._pendientes.map((b) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(b, width: 104, height: 104,
                          fit: BoxFit.cover),
                    ),
                  )),
              // botón agregar
              if (_hayCupo)
                InkWell(
                  onTap: _cargando ? null : _menuAgregar,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 104, height: 104,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('Agregar', style: TextStyle(fontSize: 11,
                            color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_esNuevo && _pendientes.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Las fotos se subirán al guardar el elemento.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        if (!_hayCupo)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Límite alcanzado (${InventarioService.maxImagenes} fotos). '
                'Borra una para agregar otra.',
                style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ),
      ],
    );
  }
}
