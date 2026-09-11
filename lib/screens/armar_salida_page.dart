import 'dart:async';
import 'package:flutter/material.dart';
import '../data.dart';
import '../reportes.dart';
import '../util/carrito_salida.dart';
import '../widgets/carrito_salida_widgets.dart';
import '../widgets/confirmar_descarte.dart';
import '../widgets/selector_recargable.dart';
import 'escaner_page.dart';

/// ARMAR SALIDA: despachar sin archivo, buscando o escaneando los artículos
/// (docs/plan-armar-salida.md).
///
/// Usa las MISMAS funciones de la base que la salida masiva por Excel
/// (`validar_salida_masiva` para ver si alcanza, `registrar_salida_masiva`
/// para despachar en una sola transacción): dos caminos distintos para el
/// usuario, un solo comportamiento.
class ArmarSalidaPage extends StatefulWidget {
  const ArmarSalidaPage({super.key});
  @override
  State<ArmarSalidaPage> createState() => _ArmarSalidaPageState();
}

class _ArmarSalidaPageState extends State<ArmarSalidaPage> {
  List<Bodega> _bodegas = [];
  List<CentroCosto> _centros = [];
  Bodega? _bodega;
  CentroCosto? _centro;
  bool _recargandoBodegas = false;
  bool _recargandoCentros = false;

  final List<LineaSalida> _lineas = [];
  /// Lo que respondió la base por cada artículo, por id de elemento.
  Map<String, ValidacionSalida> _saldos = {};
  Timer? _esperaSaldos;
  bool _revisando = false;
  bool _despachando = false;
  bool _mostrarErrores = false;

  // Los centros de costo de una salida son los EXTERNOS: a un centro
  // interno de RPCI no se le despacha, es la propia bodega.
  List<CentroCosto> get _centrosSalida =>
      _centros.where((c) => !c.esInterno).toList();

  @override
  void initState() {
    super.initState();
    InventarioService.bodegas().then((b) {
      if (mounted) {
        setState(() {
          _bodegas = b;
          if (b.length == 1) _bodega = b.first;
        });
      }
    });
    InventarioService.centrosCosto().then((c) {
      if (mounted) setState(() => _centros = c);
    });
  }

  @override
  void dispose() {
    _esperaSaldos?.cancel();
    super.dispose();
  }

  // ---- Armar el carrito ----
  Future<void> _buscar() async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) await _agregar(sel);
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    final e = await InventarioService.porCodigoBarras(codigo);
    if (!mounted) return;
    if (e == null) return _msg('Código $codigo sin asociar a ningún artículo.');
    await _agregar(e);
  }

  Future<void> _agregar(Elemento e) async {
    final i = indiceEnCarrito(_lineas, e.id);
    if (i >= 0) {
      _msg('"${e.nombre}" ya está en la lista: cambia su cantidad.');
      return _editar(i);
    }
    final cant = await _pedirCantidad(e, null);
    if (cant == null || !mounted) return;
    setState(() => _lineas.add(LineaSalida(e, cant)));
    _revisarSaldosPronto();
  }

  Future<void> _editar(int i) async {
    final l = _lineas[i];
    final cant = await _pedirCantidad(l.elemento, l.cantidad);
    if (cant == null || !mounted) return;
    setState(() => l.cantidad = cant);
    _revisarSaldosPronto();
  }

  void _quitar(int i) {
    setState(() => _lineas.removeAt(i));
    _revisarSaldosPronto();
  }

  Future<num?> _pedirCantidad(Elemento e, num? actual) {
    final ctrl = TextEditingController(
        text: actual == null ? '' : textoCantidadSalida(actual));
    num? leer() => num.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    return showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.nombre),
        content: StatefulBuilder(
          builder: (ctx, redibujar) => TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => redibujar(() {}),
            onSubmitted: (_) {
              final c = leer();
              if (c != null && c > 0) Navigator.pop(ctx, c);
            },
            decoration: InputDecoration(
              labelText: 'Cantidad (${e.unidad})',
              // La existencia general, para no pedir a ciegas. La de la
              // bodega elegida la confirma la base al revisar saldos.
              helperText: 'En total hay ${textoCantidadSalida(e.existencia)} '
                  '${e.unidad}',
              errorText: (ctrl.text.isNotEmpty &&
                      (leer() == null || leer()! <= 0))
                  ? 'Escribe un número mayor que cero'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = leer();
              if (c == null || c <= 0) return;
              Navigator.pop(ctx, c);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  // ---- Saldos: los dice la BASE, no el caché ----
  void _revisarSaldosPronto() {
    _esperaSaldos?.cancel();
    _esperaSaldos = Timer(const Duration(milliseconds: 400), _revisarSaldos);
  }

  Future<void> _revisarSaldos() async {
    if (_bodega == null || _lineas.isEmpty) {
      if (mounted) setState(() => _saldos = {});
      return;
    }
    setState(() => _revisando = true);
    try {
      final r = await InventarioService.validarSalidaMasiva(
          bodegaId: _bodega!.id, items: itemsSalida(_lineas));
      if (!mounted) return;
      setState(() => _saldos = {for (final v in r) v.elementoId: v});
    } catch (_) {
      // Sin señal no se bloquea nada: la base vuelve a revisar al despachar.
      if (mounted) setState(() => _saldos = {});
    } finally {
      if (mounted) setState(() => _revisando = false);
    }
  }

  // ---- Despachar ----
  Future<void> _despachar() async {
    if (_bodega == null || _centro == null) {
      setState(() => _mostrarErrores = true);
    }
    if (_bodega == null) return _msg('Elige la bodega de donde sale');
    if (_centro == null) return _msg('Elige el centro de costo destino');
    final listas = lineasListas(_lineas, _saldos);
    if (listas.isEmpty) return _msg('No hay líneas listas para despachar');
    final quedan = _lineas.length - listas.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar salida'),
        content: SingleChildScrollView(
          child: Text(
            'Se despacharán ${listas.length} línea(s) desde '
            '"${_bodega!.nombre}" hacia ${_centro!.etiqueta}.'
            '${quedan > 0 ? '\n\n$quedan línea(s) con problemas NO salen.' : ''}'
            '\n\nEntran todas o ninguna: si una no alcanza, no sale nada.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Despachar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _despachando = true);
    try {
      final n = await InventarioService.registrarSalidaMasiva(
        bodegaId: _bodega!.id,
        centroCostoId: _centro!.id,
        items: itemsSalida(listas),
        observacion: 'Salida armada en la app ➜ ${_centro!.codigo}',
      );
      if (!mounted) return;
      final despachadas = [...listas];
      final bodega = _bodega!.nombre;
      final centro = _centro!.etiqueta;
      setState(() {
        _despachando = false;
        _lineas.removeWhere(listas.contains);
        _saldos = {};
      });
      await _dialogoListo(n, despachadas, bodega, centro);
      if (mounted && _lineas.isNotEmpty) _revisarSaldos();
    } catch (e) {
      if (!mounted) return;
      setState(() => _despachando = false);
      _msg('No se pudo despachar: $e');
    }
  }

  Future<void> _dialogoListo(int n, List<LineaSalida> lineas, String bodega,
      String centro) async {
    var estado = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redibujar) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Salida registrada'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Se despacharon $n línea(s) desde "$bodega" hacia '
                    '$centro.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar la lista (CSV)'),
                  onPressed: () async {
                    try {
                      final guardado = await Reportes.descargarCsv(
                          'salida_despachada',
                          filasCsvSalida(lineas,
                              bodega: bodega, centro: centro));
                      redibujar(() => estado = guardado
                          ? '✓ Guardada.'
                          : 'No se guardó: se canceló el diálogo.');
                    } catch (e) {
                      redibujar(() => estado = 'No se pudo guardar: $e');
                    }
                  },
                ),
                if (estado.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(estado,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo')),
          ],
        ),
      ),
    );
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
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

  @override
  Widget build(BuildContext context) {
    final listas = lineasListas(_lineas, _saldos).length;
    return ConfirmarDescarte(
      hayTrabajoSinGuardar: _lineas.isNotEmpty && !_despachando,
      queSePierde: '${_lineas.length} artículo(s) en la lista',
      child: Scaffold(
        appBar: AppBar(title: const Text('Armar salida')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SelectorRecargable<Bodega>(
                etiqueta: 'Bodega de donde sale',
                icono: Icons.warehouse,
                valor: _bodega,
                opciones: _bodegas,
                textoDe: (b) => b.nombre,
                recargando: _recargandoBodegas,
                onRecargar: _recargarBodegas,
                onChanged: (v) {
                  setState(() => _bodega = v);
                  _revisarSaldos();
                },
                error: _mostrarErrores && _bodega == null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SelectorRecargable<CentroCosto>(
                forzarBuscador: true,
                etiqueta: 'Centro de costo destino',
                icono: Icons.account_tree,
                valor: _centro,
                opciones: _centrosSalida,
                textoDe: (c) => c.etiqueta,
                recargando: _recargandoCentros,
                onRecargar: _recargarCentros,
                onChanged: (v) => setState(() => _centro = v),
                error: _mostrarErrores && _centro == null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _despachando ? null : _buscar,
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _despachando ? null : _escanear,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear'),
                  ),
                ),
              ]),
            ),
            if (_revisando) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _cuerpo()),
          ],
        ),
        bottomNavigationBar: _lineas.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PieCarritoSalida(lineas: _lineas),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              (_despachando || listas == 0) ? null : _despachar,
                          icon: _despachando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.upload),
                          label: Text('DESPACHAR ($listas)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_lineas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Arma la salida aquí mismo: busca o escanea cada artículo y dile '
            'cuánto sale.\n\nCuando esté completa, se despacha todo junto: '
            'entran todas las líneas o ninguna.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _lineas.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => TarjetaLineaSalida(
        linea: _lineas[i],
        saldo: _saldos[_lineas[i].elemento.id],
        onEditar: () => _editar(i),
        onQuitar: () => _quitar(i),
      ),
    );
  }
}

/// Buscador del catálogo oficial (el mismo patrón de las demás pantallas).
class _BuscadorElemento extends StatefulWidget {
  const _BuscadorElemento();
  @override
  State<_BuscadorElemento> createState() => _BuscadorElementoState();
}

class _BuscadorElementoState extends State<_BuscadorElemento> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String q) async {
    final r = await InventarioService.buscar(q);
    if (mounted) setState(() => _items = r);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar artículo…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text(
                      'Existencia: ${textoCantidadSalida(e.existencia)} '
                      '${e.unidad}${e.serializado ? ' · serializado' : ''}'),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
