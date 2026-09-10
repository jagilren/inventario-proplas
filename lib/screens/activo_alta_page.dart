import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../activos_service.dart';
import '../widgets/selector_recargable.dart';
import '../widgets/campo_obligatorio.dart';
import 'activo_detalle_page.dart';
import 'activo_referencias_page.dart';

// Formato de dinero de toda la app: signo peso y separador de miles.
final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Alta de un equipo nuevo. Cubre los dos escenarios de entrada de la
/// sección 4 del plan:
///
/// - **Compra**: viene directo del proveedor. El Centro de Costo Origen es
///   fijo (`COMPRA · DIRECTO PROVEEDOR`), no se elige.
/// - **Devolución**: el equipo llega desde un centro de costo externo, que sí
///   se elige.
///
/// En ambos casos el Centro de Costo Destino es uno interno de RPCI y la
/// condición decide si el equipo queda disponible o entra a mantenimiento
/// (esa regla la aplica el trigger de la base, no esta pantalla).
class ActivoAltaPage extends StatefulWidget {
  const ActivoAltaPage({super.key});
  @override
  State<ActivoAltaPage> createState() => _ActivoAltaPageState();
}

class _ActivoAltaPageState extends State<ActivoAltaPage> {
  static const _codigoCompra = 'COMPRA';
  static const _codigoDestinoPorDefecto = 'G000002';

  bool _esCompra = true;

  final _serial = TextEditingController();
  final _valorNuevo = TextEditingController();
  final _porcentaje = TextEditingController(text: '100');
  final _observacion = TextEditingController();

  List<ActivoReferencia> _referencias = [];
  List<CentroCosto> _centros = [];
  List<Bodega> _bodegas = [];

  ActivoReferencia? _referencia;
  CentroCosto? _centroOrigen;
  CentroCosto? _centroDestino;
  Bodega? _bodega;
  String _condicion = 'nuevo';
  bool _usable = true;

  bool _cargandoCatalogos = true;
  bool _recargandoReferencias = false;
  bool _recargandoCentros = false;
  bool _recargandoBodegas = false;
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  @override
  void dispose() {
    _serial.dispose();
    _valorNuevo.dispose();
    _porcentaje.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final refs = await ActivosService.todasLasReferencias();
      final centros = await InventarioService.centrosCosto();
      final bodegas = await InventarioService.bodegas();
      if (!mounted) return;
      setState(() {
        _referencias = refs;
        _centros = centros;
        _bodegas = bodegas;
        _centroDestino = _porCodigo(_codigoDestinoPorDefecto);
        _cargandoCatalogos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoCatalogos = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los catálogos: $e')),
      );
    }
  }

  CentroCosto? _porCodigo(String codigo) {
    for (final c in _centros) {
      if (c.codigo == codigo) return c;
    }
    return null;
  }

  // Internos de RPCI: a quién queda atribuido el equipo.
  List<CentroCosto> get _centrosInternos =>
      _centros.where((c) => c.esInterno).toList();

  // Externos: de dónde vuelve el equipo en una devolución.
  List<CentroCosto> get _centrosExternos =>
      _centros.where((c) => !c.esInterno).toList();

  /// En una compra el origen es fijo; en una devolución, el que se eligió.
  CentroCosto? get _origenEfectivo =>
      _esCompra ? _porCodigo(_codigoCompra) : _centroOrigen;

  num get _valorNuevoNum => num.tryParse(_valorNuevo.text.replaceAll(',', '.')) ?? 0;
  num get _porcentajeNum =>
      num.tryParse(_porcentaje.text.replaceAll(',', '.')) ?? 0;
  num get _valorActual => _valorNuevoNum * _porcentajeNum / 100;

  bool get _porcentajeValido => _porcentajeNum >= 0 && _porcentajeNum <= 100;

  /// Porcentaje sugerido al cambiar la condición. Solo es una sugerencia:
  /// el usuario decide el número final para ESE equipo.
  void _sugerirPorcentaje(String condicion) {
    _porcentaje.text = switch (condicion) {
      'nuevo' => '100',
      'usado' => '70',
      'baja' => '0',
      _ => _porcentaje.text,
    };
  }

  Future<void> _recargarReferencias() async {
    setState(() => _recargandoReferencias = true);
    final nueva = await recargarCatalogo(
        context, ActivosService.todasLasReferencias, _referencias.length);
    if (!mounted) return;
    setState(() {
      if (nueva != null) _referencias = nueva;
      _recargandoReferencias = false;
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

  /// Crear una referencia sin abandonar el formulario: se abre el catálogo y
  /// al volver se recarga la lista, conservando lo ya escrito.
  Future<void> _agregarReferencia() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ActivoReferenciasPage()));
    if (!mounted) return;
    await _recargarReferencias();
  }

  /// La referencia elegida es un kit: su valor lo calcula la base sumando los
  /// componentes (schema_v64) y cualquier número que se escriba aquí lo
  /// reemplazaría por $0. Por eso el campo se bloquea y lo dice, en vez de
  /// dejar escribir un valor que va a desaparecer en silencio.
  bool get _esKit => _referencia?.esKit ?? false;

  bool get _formularioValido =>
      _referencia != null &&
      _serial.text.trim().isNotEmpty &&
      _origenEfectivo != null &&
      _centroDestino != null &&
      _bodega != null &&
      _porcentajeValido;

  Future<void> _guardar() async {
    if (!_formularioValido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final creado = await ActivosService.alta(
        referenciaId: _referencia!.id,
        serial: _serial.text.trim(),
        condicion: _condicion,
        bodegaId: _bodega!.id,
        valorNuevo: _esKit ? 0 : _valorNuevoNum,
        porcentajeValor: _porcentajeNum,
        observacion: _observacion.text.trim().isEmpty
            ? null
            : _observacion.text.trim(),
        centroCostoId: _origenEfectivo!.id,
        centroCostoDestinoId: _centroDestino!.id,
        usable: _condicion == 'usado' ? _usable : null,
      );
      if (!mounted) return;
      if (_esKit) {
        // Un kit recién creado vale $0 hasta que se le agreguen componentes:
        // se lleva al usuario directo a esa pestaña. result: true para que
        // la pantalla de origen sepa que se creó y se refresque.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ActivoDetallePage(activoId: creado.id, abrirComponentes: true),
          ),
          result: true,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      final texto = '$e'.contains('activos_serial_key')
          ? 'Ya existe un equipo con ese serial.'
          : 'No se pudo guardar: $e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo equipo')),
      body: _cargandoCatalogos
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true,
                        label: Text('Compra'),
                        icon: Icon(Icons.shopping_cart)),
                    ButtonSegment(
                        value: false,
                        label: Text('Devolución'),
                        icon: Icon(Icons.assignment_return)),
                  ],
                  selected: {_esCompra},
                  onSelectionChanged: (s) => setState(() {
                    _esCompra = s.first;
                    if (_esCompra) {
                      _condicion = 'nuevo';
                      _sugerirPorcentaje('nuevo');
                    }
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _esCompra
                      ? 'Equipo comprado directo al proveedor.'
                      : 'Equipo que llega desde un centro de costo.',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const Divider(height: 28),

                SelectorRecargable<ActivoReferencia>(
                  // Siempre con buscador, no atado al umbral de 12: el
                  // catálogo de modelos va a crecer a cientos, y un
                  // desplegable de ese tamaño es inservible. Mismo criterio
                  // que ya se aplicó a los centros de costo.
                  forzarBuscador: true,
                  etiqueta: 'Referencia (modelo) *',
                  icono: Icons.precision_manufacturing,
                  valor: _referencia,
                  opciones: _referencias,
                  textoDe: (r) => r.etiqueta,
                  recargando: _recargandoReferencias,
                  onRecargar: _recargarReferencias,
                  onChanged: (v) => setState(() => _referencia = v),
                  onAgregar: _agregarReferencia,
                  tooltipAgregar: 'Crear una referencia nueva',
                  textoVacio:
                      'No hay referencias. Crea una con el botón +.',
                  error: _mostrarErrores && _referencia == null,
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _serial,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: marcarError(
                    const InputDecoration(
                      labelText: 'Serial *',
                      hintText: 'Identificador único de esta unidad',
                      border: OutlineInputBorder(),
                    ),
                    _mostrarErrores && _serial.text.trim().isEmpty,
                  ),
                ),
                const SizedBox(height: 16),

                Text('Condición', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                // Wrap y no Row: en un teléfono angosto las opciones bajan de
                // línea en vez de apretarse (condición de móvil del plan).
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
                        onSelected: (_) => setState(() {
                          _condicion = c;
                          _sugerirPorcentaje(c);
                        }),
                      ),
                  ],
                ),
                if (_condicion == 'usado') ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('¿Está usable?'),
                    subtitle: Text(_usable
                        ? 'Queda disponible para entregar'
                        : 'Entra a mantenimiento interno'),
                    value: _usable,
                    onChanged: (v) => setState(() => _usable = v),
                  ),
                ],
                if (_condicion == 'baja')
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Un equipo de baja nunca queda disponible.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ),
                const Divider(height: 28),

                if (_esCompra)
                  // Origen fijo: se muestra para que quede claro qué se va a
                  // guardar, pero no es editable.
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Centro de Costo Origen',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(_porCodigo(_codigoCompra)?.etiqueta ??
                        'No se encontró el centro "$_codigoCompra"'),
                  )
                else
                  SelectorRecargable<CentroCosto>(
                    forzarBuscador: true,
                    etiqueta: 'Centro de Costo Origen *',
                    valor: _centroOrigen,
                    opciones: _centrosExternos,
                    textoDe: (c) => c.etiqueta,
                    recargando: _recargandoCentros,
                    onRecargar: _recargarCentros,
                    onChanged: (v) => setState(() => _centroOrigen = v),
                    error: _mostrarErrores && _centroOrigen == null,
                  ),
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
                  etiqueta: 'Bodega *',
                  icono: Icons.warehouse,
                  valor: _bodega,
                  opciones: _bodegas,
                  textoDe: (b) => b.nombre,
                  recargando: _recargandoBodegas,
                  onRecargar: _recargarBodegas,
                  onChanged: (v) => setState(() => _bodega = v),
                  error: _mostrarErrores && _bodega == null,
                ),
                const Divider(height: 28),

                TextField(
                  controller: _valorNuevo,
                  // Deshabilitado en un kit: el lector de pantalla lo anuncia
                  // como "deshabilitado" y el helperText dice por qué.
                  enabled: !_esKit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Valor a nuevo',
                    prefixText: _esKit ? null : '\$ ',
                    hintText: _esKit ? 'Se calcula solo' : null,
                    helperText: _esKit
                        ? 'Es un kit: su valor es la suma de sus componentes. '
                            'Al guardar te llevo a agregárselos.'
                        : null,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _porcentaje,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: marcarError(
                    const InputDecoration(
                      labelText: '% del valor según su estado',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    _mostrarErrores && !_porcentajeValido,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    _esKit
                        ? 'Valorizado: se calcula cuando le agregues sus '
                            'componentes.'
                        : 'Valorizado de este equipo: ${_money.format(_valorActual)}',
                    style: Theme.of(context).textTheme.titleSmall),
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
                      : const Icon(Icons.save),
                  label: const Text('Guardar equipo'),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
