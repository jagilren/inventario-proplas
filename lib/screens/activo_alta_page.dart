import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../activos_service.dart';
import '../widgets/selector_recargable.dart';
import '../widgets/campo_obligatorio.dart';
import '../widgets/kit_componentes.dart';
import 'activo_detalle_page.dart';
import 'activo_referencias_page.dart';
import '../util/dinero.dart';

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
  /// Abrir con esta referencia ya elegida (por ejemplo desde "Crear un equipo
  /// de este kit"): si es un kit, la sección de componentes sale de una vez.
  final ActivoReferencia? referenciaInicial;
  const ActivoAltaPage({super.key, this.referenciaInicial});
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

  // --- Kit (Fase 4, docs/plan-kits-equipos.md) ---
  /// La composición del kit que se está creando. Llega precargada con la del
  /// kit MÁS RECIENTE de la misma referencia (plantilla_kit) y se puede
  /// cambiar: es una sugerencia, no un vínculo con el anterior.
  List<ComponentePlantilla> _composicion = [];
  /// De qué kit se copió; null si es el primero de su referencia.
  String? _composicionDesde;
  bool _cargandoPlantilla = false;
  bool _plantillaFallo = false;

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
      final inicial = widget.referenciaInicial;
      if (inicial != null) _elegirReferencia(_fresca(inicial));
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

  num get _valorNuevoNum => leerPesos(_valorNuevo.text) ?? 0;
  num get _porcentajeNum =>
      num.tryParse(_porcentaje.text.replaceAll(',', '.')) ?? 0;
  num get _totalComposicion =>
      _composicion.fold<num>(0, (s, c) => s + c.subtotal);
  /// En un kit, lo que valdrá según su composición; si no, lo escrito.
  num get _valorActual =>
      (_esKit ? _totalComposicion : _valorNuevoNum) * _porcentajeNum / 100;

  /// El problema de la composición, solo después de intentar guardar.
  String? get _errorComposicion =>
      _mostrarErrores && _esKit ? validarComposicionKit(_composicion) : null;

  /// Elegir la referencia. Si es un kit, se trae la composición del kit más
  /// reciente de esa referencia: el kit 2 de 50 no se vuelve a digitar.
  void _elegirReferencia(ActivoReferencia? v) {
    final cambio = v?.id != _referencia?.id;
    setState(() {
      _referencia = v;
      if (cambio) {
        _composicion = [];
        _composicionDesde = null;
        _plantillaFallo = false;
      }
    });
    if (cambio && v != null && v.esKit) _cargarPlantilla(v);
  }

  Future<void> _cargarPlantilla(ActivoReferencia ref) async {
    setState(() => _cargandoPlantilla = true);
    try {
      final p = await ActivosService.plantillaKit(ref.id);
      // Si el usuario cambió de referencia mientras esto cargaba, esta
      // respuesta ya no es la suya: no se aplica.
      if (!mounted || _referencia?.id != ref.id) return;
      setState(() {
        _composicion = List.of(p);
        _composicionDesde = p.isEmpty ? null : p.first.desdeSerial;
        _cargandoPlantilla = false;
      });
    } catch (_) {
      if (!mounted || _referencia?.id != ref.id) return;
      setState(() {
        _cargandoPlantilla = false;
        _plantillaFallo = true;
      });
    }
  }

  List<String> get _nombresComposicion => [for (final c in _composicion) c.nombre];

  Future<void> _agregarComponente() async {
    final nuevo = await showModalBottomSheet<ComponentePlantilla>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaComponente.borrador(
        orden: _composicion.length + 1,
        nombresExistentes: _nombresComposicion,
      ),
    );
    if (nuevo != null) setState(() => _composicion = [..._composicion, nuevo]);
  }

  Future<void> _editarComponente(int i) async {
    final editado = await showModalBottomSheet<ComponentePlantilla>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaComponente.borrador(
        inicial: _composicion[i],
        nombresExistentes: _nombresComposicion,
      ),
    );
    if (editado != null) {
      setState(() => _composicion = [..._composicion]..[i] = editado);
    }
  }

  /// Quitar con opción de deshacer: en un celular es fácil tocar la basura
  /// equivocada, y volver a escribir un componente es justo lo que la
  /// plantilla vino a evitar.
  void _quitarComponente(int i) {
    final quitado = _composicion[i];
    setState(() => _composicion = [..._composicion]..removeAt(i));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Se quitó "${quitado.nombre}".'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            if (!mounted) return;
            setState(() => _composicion = [..._composicion]
              ..insert(i.clamp(0, _composicion.length), quitado));
          },
        ),
      ));
  }

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
    // La referencia elegida se relee de la lista nueva: si en el catálogo se
    // marcó como kit (o se le quitó), la vieja en memoria diría otra cosa.
    final elegida = _referencia;
    if (nueva != null && elegida != null) {
      ActivoReferencia? fresca;
      for (final r in nueva) {
        if (r.id == elegida.id) fresca = r;
      }
      if (fresca != null && fresca.esKit != elegida.esKit) {
        setState(() => _referencia = null);
        _elegirReferencia(fresca);
      } else if (fresca != null) {
        setState(() => _referencia = fresca);
      }
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

  /// La versión de la lista cargada (la más reciente) de una referencia.
  ActivoReferencia _fresca(ActivoReferencia r) {
    for (final x in _referencias) {
      if (x.id == r.id) return x;
    }
    return r;
  }

  /// Crear una referencia sin abandonar el formulario: se abre el catálogo y
  /// al volver se recarga la lista, conservando lo ya escrito. Si allí se
  /// creó una, vuelve YA ELEGIDA: antes había que buscarla en el selector, y
  /// quien creaba un kit no veía por dónde agregarle los componentes.
  Future<void> _agregarReferencia() async {
    final creada = await Navigator.push<ActivoReferencia>(
        context,
        MaterialPageRoute(
            builder: (_) => const ActivoReferenciasPage(elegirAlCrear: true)));
    if (!mounted) return;
    await _recargarReferencias();
    if (!mounted || creada == null) return;
    _elegirReferencia(_fresca(creada));
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
      _porcentajeValido &&
      !_cargandoPlantilla &&
      (!_esKit || validarComposicionKit(_composicion) == null);

  Future<void> _guardar() async {
    if (!_formularioValido) {
      setState(() => _mostrarErrores = true);
      // El problema de la composición se marca arriba, en su sección; el
      // botón Guardar está abajo. Sin este aviso, tocar Guardar parecería no
      // hacer nada (SDD 9.5: nada puede fallar en silencio).
      final problema =
          _esKit ? validarComposicionKit(_composicion) : null;
      if (problema != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(problema)));
      }
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
        // Los componentes, TODOS en una operación (agregar_componentes,
        // schema_v65): entran todos o ninguno, nunca un kit a medias.
        String? aviso;
        try {
          await ActivosService.agregarComponentes(creado.id, _composicion);
        } catch (e) {
          // El equipo YA existe. No se oculta: se dice qué pasó y dónde
          // arreglarlo (la pestaña muestra que vale $0 y deja agregarlos).
          aviso = 'El equipo se creó, pero sus componentes no se pudieron '
              'guardar: $e. Agrégalos en esta pestaña.';
        }
        if (!mounted) return;
        // El aviso va por el ScaffoldMessenger de la app, que sobrevive al
        // cambio de pantalla; se toma ANTES de navegar.
        final mensajero = ScaffoldMessenger.of(context);
        // A la pestaña Componentes, para ver cómo quedó. result: true para
        // que la pantalla de origen sepa que se creó y se refresque.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ActivoDetallePage(activoId: creado.id, abrirComponentes: true),
          ),
          result: true,
        );
        if (aviso != null) {
          mensajero.showSnackBar(SnackBar(
            content: Text(aviso),
            duration: const Duration(seconds: 10),
          ));
        }
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
                  // _elegirReferencia y no un setState: si es un kit, trae
                  // la composición del kit anterior.
                  onChanged: _elegirReferencia,
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
                        ? 'Es un kit: su valor es la suma de los componentes '
                            'de abajo.'
                        // Cómo quedó entendido: "1.540.000" = $1.540.000,
                        // no $0 (util/dinero.dart).
                        : pesosEntendidos(_valorNuevo.text),
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_esKit) ...[
                  const SizedBox(height: 16),
                  if (_cargandoPlantilla)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'Trayendo la composición del kit anterior…')),
                        ],
                      ),
                    )
                  else ...[
                    if (_plantillaFallo)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No se pudo traer la composición del kit anterior. '
                          'Puedes escribirla aquí.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ComposicionBorrador(
                      componentes: _composicion,
                      desdeSerial: _composicionDesde,
                      porcentaje: _porcentajeValido ? _porcentajeNum : 100,
                      onAgregar: _agregarComponente,
                      onEditar: _editarComponente,
                      onQuitar: _quitarComponente,
                      error: _errorComposicion,
                    ),
                  ],
                ],
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
                        ? 'Valorizado de este kit: ${_money.format(_valorActual)}'
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
