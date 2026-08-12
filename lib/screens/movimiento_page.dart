import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'escaner_page.dart';
import 'devoluciones_page.dart';
import 'remision_devolucion_page.dart';
import 'salida_masiva_page.dart';
import 'entrada_masiva_page.dart';
import '../util/adjuntos_gate.dart';
import '../util/tiempo.dart';
import '../util/movimiento_fmt.dart';
import '../widgets/selector_recargable.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

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

  // Lista paginada de últimos movimientos del tipo (parte inferior).
  final List<MovLista> _recientes = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargandoMas = false;

  bool _recargandoCentros = false;
  bool _recargandoBodegas = false;

  /// Vuelve a pedir los centros de costo: sirve cuando alguien crea uno
  /// mientras esta pantalla ya estaba abierta.
  Future<void> _recargarCentros() async {
    setState(() => _recargandoCentros = true);
    final nueva = await recargarCatalogo(
        context, InventarioService.centrosCosto, _centros.length);
    if (!mounted) return;
    setState(() {
      if (nueva != null) _centros = nueva;
      _recargandoCentros = false;
    });
  }

  Future<void> _recargarBodegas() async {
    setState(() => _recargandoBodegas = true);
    final nueva = await recargarCatalogo(
        context, InventarioService.bodegas, _bodegas.length);
    if (!mounted) return;
    setState(() {
      if (nueva != null) _bodegas = nueva;
      _recargandoBodegas = false;
    });
  }

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
    _cargarRecientes(reset: true);
    // Si ocurre un movimiento (aquí o en otra parte), refrescar la lista.
    InventarioService.revision.addListener(_onRevision);
  }

  void _onRevision() {
    if (mounted) _cargarRecientes(reset: true);
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_onRevision);
    super.dispose();
  }

  Future<void> _cargarRecientes({bool reset = false}) async {
    if (_cargandoMas) return;
    setState(() => _cargandoMas = true);
    try {
      if (reset) { _offset = 0; _hayMas = true; _recientes.clear(); }
      final r = await InventarioService.movimientosPorTipo(
          widget.tipoInicial, offset: _offset, limit: 10);
      if (!mounted) return;
      setState(() {
        _recientes.addAll(r);
        _offset += r.length;
        if (r.length < 10) _hayMas = false;
      });
    } catch (_) {
      // sin red: la lista simplemente no se actualiza
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
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
              // Simétrico al de Devoluciones: en SALIDA, acceso a la carga
              // masiva desde un archivo de Excel.
              trailing: _esSalida
                  ? IconButton(
                      icon: const Icon(Icons.playlist_add_check,
                          color: Color(0xFFE65100)),
                      tooltip: 'Salida masiva desde Excel',
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SalidaMasivaPage()));
                        if (mounted) _cargarRecientes(reset: true);
                      },
                    )
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.assignment_return,
                          color: Color(0xFF1565C0)),
                      tooltip: 'Devoluciones',
                      onSelected: (v) {
                        if (v == 'crear') {
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const RemisionDevolucionPage()));
                        } else if (v == 'cargar') {
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const DevolucionesPage()));
                        } else if (v == 'compra') {
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const EntradaMasivaPage()))
                            .then((_) {
                              if (mounted) _cargarRecientes(reset: true);
                            });
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'crear',
                            child: ListTile(
                                leading: Icon(Icons.playlist_add),
                                title: Text('Crear remisión de devolución'),
                                dense: true)),
                        PopupMenuItem(value: 'cargar',
                            child: ListTile(
                                leading: Icon(Icons.upload_file),
                                title: Text('Cargar devolución (Excel/CSV)'),
                                dense: true)),
                        PopupMenuDivider(),
                        // La compra es otra cosa: entra al precio pagado, no
                        // al costo promedio, y por eso recalcula el promedio.
                        PopupMenuItem(value: 'compra',
                            child: ListTile(
                                leading: Icon(Icons.local_shipping,
                                    color: Color(0xFF00695C)),
                                title: Text('Compra masiva a proveedor'),
                                subtitle: Text('Excel con costo unitario',
                                    style: TextStyle(fontSize: 11)),
                                dense: true)),
                      ],
                    ),
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
          SelectorRecargable<Bodega>(
            etiqueta: 'Bodega',
            icono: Icons.warehouse,
            valor: _bodega,
            opciones: _bodegas,
            textoDe: (b) => b.nombre,
            recargando: _recargandoBodegas,
            onRecargar: _recargarBodegas,
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
          // El selector va en LAS DOS: antes solo aparecía en las salidas, y
          // por eso una devolución (que se registra como entrada) no tenía
          // dónde indicar de qué centro volvía. Resultado: las 16 entradas de
          // la base quedaron sin centro, y el informe "Neto por centro de
          // costo" nunca resto una sola devolución, porque su RPC exige
          // centro_costo_id no nulo.
          //
          // En salida es OBLIGATORIO (a dónde va). En entrada es OPCIONAL:
          // una compra no viene de ningún centro, una devolución sí.
          SelectorRecargable<CentroCosto>(
            // Los centros de costo SIEMPRE con buscador.
            forzarBuscador: true,
            etiqueta: _esSalida
                ? 'Centro de costo destino'
                : 'Centro de costo de origen (si es devolución)',
            valor: _cc,
            opciones: _centros,
            textoDe: (c) => c.etiqueta,
            recargando: _recargandoCentros,
            onRecargar: _recargarCentros,
            onChanged: (v) => setState(() => _cc = v),
            textoVacio: _esSalida
                ? 'No hay centros. Pulsa ↻ para volver a consultar.'
                : 'Déjalo vacío si es una compra; elígelo si es una devolución.',
          ),
          if (!_esSalida)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Si esta entrada es una DEVOLUCIÓN, elige el centro de costo '
                'que devuelve: sin eso, el informe de Neto por centro no la '
                'descuenta del consumo.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _obs,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => mostrarMensajeBillete(context),
            icon: const Icon(Icons.attach_file),
            label: const Text('Adjuntar archivo (PDF/Excel)'),
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
          const SizedBox(height: 28),
          const Divider(),
          Row(children: [
            Icon(_esSalida ? Icons.upload : Icons.download, size: 18,
                color: _esSalida ? Colors.orange : Colors.green),
            const SizedBox(width: 6),
            Text('Últimas ${_esSalida ? 'salidas' : 'entradas'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          ..._recientes.map(_filaReciente),
          if (_recientes.isEmpty && !_cargandoMas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Sin movimientos aún',
                  style: TextStyle(color: Colors.grey)),
            ),
          if (_cargandoMas)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_hayMas && _recientes.isNotEmpty && !_cargandoMas)
            Center(
              child: TextButton.icon(
                onPressed: () => _cargarRecientes(),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('Cargar más'),
              ),
            ),
          if (!_hayMas && _recientes.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Center(
                child: Text('— No hay más —',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaReciente(MovLista m) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: (_esSalida ? Colors.orange : Colors.green)
            .withValues(alpha: 0.15),
        child: Text('${m.cantidad}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      title: Text(m.elemento, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(flujoMovimiento(tipo: m.tipo, referencia: m.referencia,
              bodega: m.bodega, centroCosto: m.centroCosto),
              style: const TextStyle(fontSize: 11)),
          Text([
            _fechaHora.format(horaColombia(m.fecha)),
            if (m.usuario != null) m.usuario!,
          ].join(' · '),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      trailing: Text('${m.cantidad} ${m.unidad}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
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
