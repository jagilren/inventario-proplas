import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'escaner_page.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Pantalla para registrar una ENTRADA o SALIDA.
class MovimientoPage extends StatefulWidget {
  final String tipoInicial; // 'entrada' | 'salida'
  const MovimientoPage({super.key, required this.tipoInicial});
  @override
  State<MovimientoPage> createState() => _MovimientoPageState();
}

class _MovimientoPageState extends State<MovimientoPage> {
  Elemento? _elemento;
  CentroCosto? _cc;
  List<CentroCosto> _centros = [];
  Bodega? _bodega;
  List<Bodega> _bodegas = [];
  final _cantidad = TextEditingController();
  final _costo = TextEditingController();
  final _obs = TextEditingController();
  bool _guardando = false;
  // Serializados
  final _serialCtrl = TextEditingController();
  final List<String> _serialesNuevos = []; // entrada
  List<Serie> _disponibles = [];            // salida
  final Set<String> _serialSel = {};        // salida seleccionados

  bool get _esSalida => widget.tipoInicial == 'salida';
  bool get _serial => _elemento?.serializado ?? false;

  Future<void> _cargarDisponibles() async {
    if (_serial && _esSalida && _elemento != null && _bodega != null) {
      final d = await InventarioService.seriesDisponibles(_elemento!.id, _bodega!.id);
      if (mounted) setState(() { _disponibles = d; _serialSel.clear(); });
    }
  }

  void _agregarSerial() {
    final s = _serialCtrl.text.trim();
    if (s.isEmpty || _serialesNuevos.contains(s)) return;
    setState(() { _serialesNuevos.add(s); _serialCtrl.clear(); });
  }

  @override
  void initState() {
    super.initState();
    InventarioService.centrosCosto().then((c) {
      if (mounted) setState(() => _centros = c);
    });
    InventarioService.bodegas().then((b) {
      if (mounted) {
        setState(() {
          _bodegas = b;
          if (b.length == 1) _bodega = b.first; // una sola: la elige sola
        });
      }
    });
  }

  Future<void> _elegirElemento() async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) _seleccionar(sel);
  }

  void _seleccionar(Elemento sel) {
    setState(() {
      _elemento = sel;
      if (_esSalida) _costo.text = ''; // salida usa costo promedio automático
      _serialesNuevos.clear(); _serialSel.clear(); _disponibles = [];
    });
    _cargarDisponibles();
  }

  /// Escanea el código del artículo y lo selecciona directo.
  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    final elem = await InventarioService.porCodigoBarras(codigo);
    if (!mounted) return;
    if (elem != null) {
      _seleccionar(elem);
      _msg('✓ ${elem.nombre}');
    } else {
      _msg('Código $codigo sin asociar a ningún elemento.');
    }
  }

  Future<void> _guardar() async {
    final el = _elemento;
    final cant = num.tryParse(_cantidad.text.replaceAll(',', '.'));
    if (el == null) return _msg('Selecciona un elemento');
    if (_bodega == null) return _msg('Selecciona la bodega');
    if (_serial) return _guardarSerie(el);
    if (cant == null || cant <= 0) return _msg('Cantidad inválida');
    if (_esSalida && _cc == null) return _msg('Selecciona el centro de costo');
    if (!_esSalida) {
      final c = num.tryParse(_costo.text.replaceAll(',', '.'));
      if (c == null || c < 0) return _msg('Costo unitario inválido');
    }

    setState(() => _guardando = true);
    try {
      final subido = await InventarioService.registrarMovimiento(
        tipo: widget.tipoInicial,
        elementoId: el.id,
        bodegaId: _bodega!.id,
        cantidad: cant,
        centroCostoId: _cc?.id,
        costoUnitario: _esSalida
            ? null
            : num.parse(_costo.text.replaceAll(',', '.')),
        observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
      );
      if (!mounted) return;
      _msg(subido
          ? '✓ ${_esSalida ? 'Salida' : 'Entrada'} registrada'
          : '✓ Guardada sin conexión · se subirá al volver el internet');
      setState(() {
        _elemento = null; _cc = null;
        _cantidad.clear(); _costo.clear(); _obs.clear();
      });
    } catch (e) {
      _msg('Error: ${e.toString().replaceAll('PostgrestException(message: ', '')}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarSerie(Elemento el) async {
    if (_esSalida) {
      if (_serialSel.isEmpty) return _msg('Selecciona al menos un serial');
      if (_cc == null) return _msg('Selecciona el centro de costo');
    } else {
      if (_serialesNuevos.isEmpty) return _msg('Ingresa al menos un serial');
      final c = num.tryParse(_costo.text.replaceAll(',', '.'));
      if (c == null || c < 0) return _msg('Costo unitario inválido');
    }
    setState(() => _guardando = true);
    try {
      await InventarioService.moverSerie(
        tipo: widget.tipoInicial, elementoId: el.id, bodegaId: _bodega!.id,
        serials: _esSalida ? _serialSel.toList() : List.of(_serialesNuevos),
        costo: _esSalida ? null : num.parse(_costo.text.replaceAll(',', '.')),
        centroCostoId: _cc?.id,
        observacion: _obs.text.trim().isEmpty ? null : _obs.text.trim(),
      );
      if (!mounted) return;
      _msg('✓ ${_esSalida ? 'Salida' : 'Entrada'} registrada');
      setState(() {
        _elemento = null; _cc = null; _serialesNuevos.clear();
        _serialSel.clear(); _disponibles = []; _costo.clear(); _obs.clear();
      });
    } catch (e) {
      _msg('Error: ${e.toString().replaceAll('PostgrestException(message: ', '')}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _msg(String m) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final el = _elemento;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: _esSalida
                ? Colors.orange.shade50
                : Colors.green.shade50,
            child: ListTile(
              leading: Icon(_esSalida ? Icons.upload : Icons.download),
              title: Text(_esSalida ? 'Registrar SALIDA' : 'Registrar ENTRADA',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          // Selector de elemento
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2),
              title: Text(el?.nombre ?? 'Seleccionar elemento…'),
              subtitle: el == null
                  ? null
                  : Text('Existencia: ${el.existencia} ${el.unidad}  ·  '
                      'costo prom. ${_money.format(el.costoPromedio)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Escanear código',
                    onPressed: _escanear,
                  ),
                  const Icon(Icons.search),
                ],
              ),
              onTap: _elegirElemento,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Bodega>(
            initialValue: _bodega,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Bodega',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.warehouse),
            ),
            items: _bodegas
                .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b.nombre, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) { setState(() => _bodega = v); _cargarDisponibles(); },
          ),
          const SizedBox(height: 8),
          if (!_serial)
            TextField(
              controller: _cantidad,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Cantidad${el != null ? ' (${el.unidad})' : ''}',
                border: const OutlineInputBorder(),
              ),
            ),
          if (_serial && !_esSalida) ...[
            Row(children: [
              Expanded(child: TextField(
                controller: _serialCtrl,
                onSubmitted: (_) => _agregarSerial(),
                decoration: const InputDecoration(
                    labelText: 'Serial', border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag)),
              )),
              IconButton(iconSize: 32, icon: const Icon(Icons.add_circle),
                  tooltip: 'Agregar serial', onPressed: _agregarSerial),
            ]),
            if (_serialesNuevos.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 4, children: _serialesNuevos
                  .map((s) => Chip(label: Text(s),
                      onDeleted: () => setState(() => _serialesNuevos.remove(s)))).toList()),
            ),
          ],
          if (_serial && _esSalida) ...[
            const Align(alignment: Alignment.centerLeft,
                child: Text('Seriales disponibles en la bodega:',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            if (_bodega == null)
              const Text('Elige la bodega para ver los seriales.',
                  style: TextStyle(color: Colors.grey)),
            if (_bodega != null && _disponibles.isEmpty)
              const Text('No hay seriales disponibles en esta bodega.',
                  style: TextStyle(color: Colors.grey)),
            ..._disponibles.map((s) => CheckboxListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(s.serial),
              value: _serialSel.contains(s.serial),
              onChanged: (v) => setState(() => v == true
                  ? _serialSel.add(s.serial) : _serialSel.remove(s.serial)),
            )),
          ],
          const SizedBox(height: 8),
          if (!_esSalida)
            TextField(
              controller: _costo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo unitario',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
            ),
          if (_esSalida)
            DropdownButtonFormField<CentroCosto>(
              initialValue: _cc,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Centro de costo destino',
                border: OutlineInputBorder(),
              ),
              items: _centros
                  .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.etiqueta, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _cc = v),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _obs,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_esSalida ? 'Guardar salida' : 'Guardar entrada'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior con búsqueda inteligente de elementos.
class _BuscadorElemento extends StatefulWidget {
  const _BuscadorElemento();
  @override
  State<_BuscadorElemento> createState() => _BuscadorElementoState();
}

class _BuscadorElementoState extends State<_BuscadorElemento> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  Future<void> _buscar(String q) async {
    setState(() => _cargando = true);
    final r = await InventarioService.buscar(q);
    if (mounted) setState(() { _items = r; _cargando = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _buscar,
                decoration: const InputDecoration(
                  hintText: 'Buscar…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_cargando) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final e = _items[i];
                  return ListTile(
                    title: Text(e.nombre),
                    subtitle: Text('Existencia: ${e.existencia} ${e.unidad}'),
                    onTap: () => Navigator.pop(context, e),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
