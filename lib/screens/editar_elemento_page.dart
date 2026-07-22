import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data.dart';
import '../widgets/galeria_elemento.dart';
import 'escaner_page.dart';

/// Crea o edita un elemento (admin / coordinador).
/// Si [elemento] es null, es creación. Devuelve true si guardó.
class EditarElementoPage extends StatefulWidget {
  final Elemento? elemento;
  const EditarElementoPage({super.key, this.elemento});
  @override
  State<EditarElementoPage> createState() => _EditarElementoPageState();
}

class _EditarElementoPageState extends State<EditarElementoPage> {
  late final TextEditingController _nombre;
  late final TextEditingController _material;
  late final TextEditingController _sch;
  late final TextEditingController _stockMin;
  late final TextEditingController _codigoBarras;
  // solo en creación: existencia inicial y su costo
  final _cantIni = TextEditingController();
  final _costoIni = TextEditingController();
  late String _unidad;
  late bool _activo;
  bool _guardando = false;

  // Fotos elegidas antes de que el elemento exista (solo al crear).
  List<Uint8List> _fotosPendientes = [];

  static const _unidades = ['UND', 'MT', 'Par', 'KG', 'LT'];

  bool get _esNuevo => widget.elemento == null;

  @override
  void initState() {
    super.initState();
    final e = widget.elemento;
    _nombre = TextEditingController(text: e?.nombre ?? '');
    _material = TextEditingController(text: e?.material ?? '');
    _sch = TextEditingController(text: e?.sch ?? '');
    _stockMin = TextEditingController(text: (e?.stockMinimo ?? 0).toString());
    _codigoBarras = TextEditingController(text: e?.codigoBarras ?? '');
    _unidad = (e != null && _unidades.contains(e.unidad)) ? e.unidad : 'UND';
    _activo = e?.activo ?? true;
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      _msg('El nombre es obligatorio');
      return;
    }
    setState(() => _guardando = true);
    try {
      final datos = <String, dynamic>{
        'nombre': _nombre.text.trim(),
        'material': _material.text.trim().isEmpty ? null : _material.text.trim(),
        'sch': _sch.text.trim().isEmpty ? null : _sch.text.trim(),
        'unidad': _unidad,
        'stock_minimo': num.tryParse(_stockMin.text.replaceAll(',', '.')) ?? 0,
        'codigo_barras':
            _codigoBarras.text.trim().isEmpty ? null : _codigoBarras.text.trim(),
        'activo': _activo,
      };

      String? elementoId = widget.elemento?.id;

      if (_esNuevo) {
        await InventarioService.crearElemento(datos);
        // Al crear no conocemos el id: lo buscamos por su nombre (único).
        final creados = await InventarioService.buscar(_nombre.text.trim());
        final nuevo = creados.where((x) => x.nombre == _nombre.text.trim());
        if (nuevo.isNotEmpty) elementoId = nuevo.first.id;

        // Existencia inicial, si la indicó
        final cant = num.tryParse(_cantIni.text.replaceAll(',', '.'));
        final costo = num.tryParse(_costoIni.text.replaceAll(',', '.'));
        if (cant != null && cant > 0 && elementoId != null) {
          await InventarioService.registrarMovimiento(
            tipo: 'inicial',
            elementoId: elementoId,
            cantidad: cant,
            costoUnitario: costo ?? 0,
            observacion: 'Existencia inicial al crear el elemento',
          );
        }
      } else {
        await InventarioService.actualizarElemento(widget.elemento!.id, datos);
      }

      // Las fotos elegidas al crear se suben ahora, ya con el id disponible.
      if (elementoId != null && _fotosPendientes.isNotEmpty) {
        for (final bytes in _fotosPendientes) {
          await InventarioService.agregarImagen(elementoId, bytes);
        }
      }

      if (!mounted) return;
      _msg(_esNuevo ? '✓ Elemento creado' : '✓ Elemento actualizado');
      Navigator.pop(context, true);
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Escanea el código del fabricante y lo pone en el campo.
  /// Así se "aprende" el código de un artículo la primera vez que se usa.
  Future<void> _escanearCodigo() async {
    final codigo = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    setState(() => _codigoBarras.text = codigo);
    _msg('Código capturado: $codigo. Guarda para asociarlo.');
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_esNuevo ? 'Nuevo elemento' : 'Editar elemento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GaleriaElemento(
            elementoId: widget.elemento?.id,
            onPendientes: (fotos) => _fotosPendientes = fotos,
          ),
          const Divider(height: 28),
          _campo(_nombre, 'Nombre *'),
          _campo(_material, 'Material'),
          _campo(_sch, 'SCH'),
          DropdownButtonFormField<String>(
            initialValue: _unidad,
            decoration: const InputDecoration(
                labelText: 'Unidad', border: OutlineInputBorder()),
            items: _unidades
                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                .toList(),
            onChanged: (v) => setState(() => _unidad = v ?? 'UND'),
          ),
          const SizedBox(height: 14),
          _campo(_stockMin, 'Stock mínimo (para alertas)',
              teclado: const TextInputType.numberWithOptions(decimal: true)),
          Row(
            children: [
              Expanded(
                child: _campo(_codigoBarras, 'Código de barras',
                    teclado: TextInputType.text,
                    hint: 'Escanea o escribe el código'),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Escanear código',
                  onPressed: _escanearCodigo,
                ),
              ),
            ],
          ),
          if (!_esNuevo) ...[
            const Divider(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Elemento activo'),
              subtitle: Text(_activo
                  ? 'Visible en búsquedas y movimientos'
                  : 'Dado de baja: no aparece, pero conserva su kardex'),
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
            ),
          ],
          if (_esNuevo) ...[
            const Divider(height: 28),
            const Text('Existencia inicial (opcional)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Si ya tienes unidades en bodega, regístralas aquí.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            _campo(_cantIni, 'Cantidad inicial',
                teclado: const TextInputType.numberWithOptions(decimal: true)),
            _campo(_costoIni, 'Costo unitario',
                teclado: const TextInputType.numberWithOptions(decimal: true)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_esNuevo ? 'Crear elemento' : 'Guardar cambios'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label,
      {TextInputType? teclado, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: teclado,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
