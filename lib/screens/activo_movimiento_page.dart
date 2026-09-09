import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../activos_service.dart';
import '../widgets/selector_recargable.dart';
import '../widgets/campo_obligatorio.dart';

// Formato de dinero de toda la app: signo peso y separador de miles.
final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Registra una entrada (reingreso) o una salida de un equipo.
///
/// El usuario NO elige el tipo de movimiento: lo decide el estado actual del
/// equipo (sección 7.0.1 del plan). Un equipo entregado solo puede reingresar;
/// uno operativo solo puede salir. Por eso hay una sola pantalla y no dos
/// botones "Entrada"/"Salida" como en Inventario: un equipo no es fungible.
class ActivoMovimientoPage extends StatefulWidget {
  final Activo activo;
  const ActivoMovimientoPage({super.key, required this.activo});
  @override
  State<ActivoMovimientoPage> createState() => _ActivoMovimientoPageState();
}

class _ActivoMovimientoPageState extends State<ActivoMovimientoPage> {
  static const _codigoDestinoPorDefecto = 'G000002';

  final _valor = TextEditingController();
  final _porcentaje = TextEditingController();
  final _observacion = TextEditingController();

  List<CentroCosto> _centros = [];
  List<Bodega> _bodegas = [];

  CentroCosto? _centroOrigen;
  CentroCosto? _centroDestino;
  Bodega? _bodega;
  String _condicion = 'usado';
  bool _usable = true;

  bool _cargando = true;
  bool _recargandoCentros = false;
  bool _recargandoBodegas = false;
  bool _guardando = false;
  bool _mostrarErrores = false;

  /// Un equipo entregado vuelve (entrada); uno disponible sale.
  bool get _esEntrada => widget.activo.estado == 'entregado';

  @override
  void initState() {
    super.initState();
    _porcentaje.text = '${widget.activo.porcentajeValor}';
    _valor.text = '${widget.activo.valorActual}';
    _cargar();
  }

  @override
  void dispose() {
    _valor.dispose();
    _porcentaje.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final centros = await InventarioService.centrosCosto();
      final bodegas = await InventarioService.bodegas();
      // En un reingreso se pre-sugiere el centro al que había salido, pero
      // queda editable: puede volver de otro lado.
      String? centroSalidaId;
      if (_esEntrada) {
        final movs = await ActivosService.movimientos(widget.activo.id, limit: 20);
        for (final m in movs) {
          if (m.tipo == 'salida') { centroSalidaId = m.centroCostoId; break; }
        }
      }
      if (!mounted) return;
      setState(() {
        _centros = centros;
        _bodegas = bodegas;
        _centroDestino = _porCodigo(_codigoDestinoPorDefecto);
        _bodega = _bodegaPorId(widget.activo.bodegaId);
        if (centroSalidaId != null) {
          _centroOrigen = _porId(centroSalidaId);
        }
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los catálogos: $e')),
      );
    }
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

  CentroCosto? _porCodigo(String codigo) {
    for (final c in _centros) {
      if (c.codigo == codigo) return c;
    }
    return null;
  }

  CentroCosto? _porId(String id) {
    for (final c in _centros) {
      if (c.id == id) return c;
    }
    return null;
  }

  Bodega? _bodegaPorId(String id) {
    for (final b in _bodegas) {
      if (b.id == id) return b;
    }
    return null;
  }

  List<CentroCosto> get _centrosInternos =>
      _centros.where((c) => c.esInterno).toList();
  List<CentroCosto> get _centrosExternos =>
      _centros.where((c) => !c.esInterno).toList();

  num? get _valorNum =>
      _valor.text.trim().isEmpty
          ? null
          : num.tryParse(_valor.text.replaceAll(',', '.'));
  num get _porcentajeNum =>
      num.tryParse(_porcentaje.text.replaceAll(',', '.')) ?? 0;
  bool get _porcentajeValido => _porcentajeNum >= 0 && _porcentajeNum <= 100;

  bool get _valido => _esEntrada
      ? (_centroOrigen != null &&
          _centroDestino != null &&
          _bodega != null &&
          _porcentajeValido)
      : _centroOrigen != null;

  Future<void> _guardar() async {
    if (!_valido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final obs = _observacion.text.trim().isEmpty
          ? null
          : _observacion.text.trim();
      if (_esEntrada) {
        // El valorizado puede cambiar al regresar (viene más gastado).
        if (_porcentajeNum != widget.activo.porcentajeValor) {
          await ActivosService.actualizarValor(widget.activo.id,
              porcentajeValor: _porcentajeNum);
        }
        await ActivosService.registrarEntrada(
          activoId: widget.activo.id,
          centroCostoId: _centroOrigen!.id,
          centroCostoDestinoId: _centroDestino!.id,
          bodegaId: _bodega!.id,
          condicion: _condicion,
          usable: _condicion == 'usado' ? _usable : null,
          observacion: obs,
        );
      } else {
        await ActivosService.registrarSalida(
          activoId: widget.activo.id,
          centroCostoId: _centroOrigen!.id,
          valor: _valorNum,
          observacion: obs,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activo;
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEntrada ? 'Reingreso de equipo' : 'Salida de equipo'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.precision_manufacturing),
                    title: Text(a.serial),
                    subtitle: Text(
                        '${a.referenciaNombre ?? '—'} · ${a.estadoEtiqueta}'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _esEntrada
                      ? 'El equipo estaba entregado: se registra su regreso.'
                      : 'El equipo está disponible: se registra su entrega a '
                          'un centro de costo.',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const Divider(height: 28),

                SelectorRecargable<CentroCosto>(
                  forzarBuscador: true,
                  etiqueta: _esEntrada
                      ? 'Centro de Costo Origen *'
                      : 'Centro de Costo (a quién se entrega) *',
                  valor: _centroOrigen,
                  opciones: _centrosExternos,
                  textoDe: (c) => c.etiqueta,
                  recargando: _recargandoCentros,
                  onRecargar: _recargarCentros,
                  onChanged: (v) => setState(() => _centroOrigen = v),
                  error: _mostrarErrores && _centroOrigen == null,
                ),

                if (_esEntrada) ...[
                  const SizedBox(height: 12),
                  SelectorRecargable<CentroCosto>(
                    etiqueta: 'Centro de Costo Destino *',
                    valor: _centroDestino,
                    opciones: _centrosInternos,
                    textoDe: (c) => c.etiqueta,
                    recargando: _recargandoCentros,
                    onRecargar: _recargarCentros,
                    onChanged: (v) => setState(() => _centroDestino = v),
                    error: _mostrarErrores && _centroDestino == null,
                  ),
                  const SizedBox(height: 12),
                  SelectorRecargable<Bodega>(
                    etiqueta: 'Bodega a la que entra *',
                    icono: Icons.warehouse,
                    valor: _bodega,
                    opciones: _bodegas,
                    textoDe: (b) => b.nombre,
                    recargando: _recargandoBodegas,
                    onRecargar: _recargarBodegas,
                    onChanged: (v) => setState(() => _bodega = v),
                    error: _mostrarErrores && _bodega == null,
                  ),
                  const SizedBox(height: 16),
                  Text('¿En qué condición regresa?',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in ['nuevo', 'usado', 'baja'])
                        ChoiceChip(
                          label: Text(switch (c) {
                            'nuevo' => 'Nuevo',
                            'usado' => 'Usado',
                            _ => 'De baja',
                          }),
                          selected: _condicion == c,
                          onSelected: (_) => setState(() => _condicion = c),
                        ),
                    ],
                  ),
                  if (_condicion == 'usado')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('¿Está usable?'),
                      subtitle: Text(_usable
                          ? 'Queda disponible para entregar'
                          : 'Entra a mantenimiento interno'),
                      value: _usable,
                      onChanged: (v) => setState(() => _usable = v),
                    ),
                  if (_condicion == 'baja')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Un equipo de baja nunca queda disponible.',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                    ),
                  const Divider(height: 28),
                  TextField(
                    controller: _porcentaje,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: marcarError(
                      const InputDecoration(
                        labelText: '% del valor tras el regreso',
                        suffixText: '%',
                        helperText: 'Si el equipo volvió más gastado, bájalo.',
                        border: OutlineInputBorder(),
                      ),
                      _mostrarErrores && !_porcentajeValido,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quedará valorizado en '
                    '${_money.format(a.valorNuevo * _porcentajeNum / 100)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _valor,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Valor de la salida',
                      prefixText: '\$ ',
                      helperText:
                          'Si lo dejas vacío se toma el valorizado actual.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                TextField(
                  controller: _observacion,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observación',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_esEntrada ? Icons.download : Icons.upload),
                  label: Text(_esEntrada
                      ? 'Registrar reingreso'
                      : 'Registrar salida'),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
