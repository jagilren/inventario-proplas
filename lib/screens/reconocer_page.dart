import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data.dart';
import '../widgets/imagen_elemento.dart';
import 'kardex_page.dart';

/// Reconoce un elemento tomándole una foto (compara huellas visuales).
class ReconocerPage extends StatefulWidget {
  const ReconocerPage({super.key});
  @override
  State<ReconocerPage> createState() => _ReconocerPageState();
}

class _ReconocerPageState extends State<ReconocerPage> {
  Uint8List? _foto;
  List<Elemento> _matches = [];
  bool _buscando = false;
  String? _msg;

  Future<void> _tomar(ImageSource src) async {
    final x = await ImagePicker()
        .pickImage(source: src, maxWidth: 1024, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() { _foto = bytes; _buscando = true; _matches = []; _msg = null; });
    try {
      final r = await InventarioService.reconocerPorFoto(bytes);
      if (mounted) {
        setState(() {
          _matches = r;
          if (r.isEmpty) {
            _msg = 'No hay elementos con foto para comparar. Sube fotos a los '
                'elementos primero (y consistentes: fondo claro, pieza centrada).';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _msg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reconocer por foto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: FilledButton.icon(
                onPressed: () => _tomar(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tomar foto'),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _tomar(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galería'),
              )),
            ],
          ),
          const SizedBox(height: 16),
          if (_foto != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_foto!, height: 180, fit: BoxFit.cover,
                  width: double.infinity),
            ),
          if (_buscando) const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Column(children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Buscando parecidos…'),
            ])),
          ),
          if (_msg != null) Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_msg!, style: const TextStyle(color: Colors.grey)),
          ),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Parecidos (el más probable primero):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ..._matches.asMap().entries.map((e) {
              final i = e.key;
              final el = e.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  leading: ImagenElemento(url: el.imagenUrl, tamano: 52, radio: 8),
                  title: Text(el.nombre),
                  subtitle: Text('Existencia: ${el.existencia} ${el.unidad}'),
                  trailing: i == 0
                      ? const Chip(label: Text('Mejor'), visualDensity: VisualDensity.compact)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => KardexPage(elemento: el))),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
