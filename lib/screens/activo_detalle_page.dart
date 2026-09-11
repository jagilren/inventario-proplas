import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../activos_service.dart';
import '../util/movimiento_fmt.dart';
import '../util/tiempo.dart';
import '../widgets/kit_componentes.dart';
import '../widgets/selector_recargable.dart';
import 'activo_movimiento_page.dart';
import 'componente_kit_page.dart';
import '../util/dinero.dart';

// Formato de dinero de toda la app: signo peso y separador de miles.
final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

// Mismo formato y misma conversión a hora de Colombia que el resto de la app.
final _fecha = DateFormat('dd/MM/yyyy');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
String _cuando(DateTime f) => _fechaHora.format(horaColombia(f));

/// Ficha completa de un equipo: datos, ubicación física, piezas, hoja de
/// mantenimientos e historial de entradas/salidas.
///
/// La distinción clave del módulo (sección 6 del plan) se refleja aquí:
/// "Cambiar ubicación" mueve el equipo físicamente SIN tocar el inventario;
/// "Registrar movimiento" sí lo suma o lo resta.
class ActivoDetallePage extends StatefulWidget {
  final String activoId;
  /// Abrir directo en la pestaña Componentes. Lo usa el alta de un kit: el
  /// equipo recién creado vale $0 hasta que se le agreguen, así que se lleva
  /// al usuario justo ahí en vez de dejarlo buscando dónde.
  final bool abrirComponentes;
  const ActivoDetallePage({
    super.key,
    required this.activoId,
    this.abrirComponentes = false,
  });
  @override
  State<ActivoDetallePage> createState() => _ActivoDetallePageState();
}

class _ActivoDetallePageState extends State<ActivoDetallePage> {
  Activo? _activo;
  ActivoUbicacion? _ubicacion;
  Set<String> _roles = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() => _roles = r);
    });
    _cargar();
  }

  bool get _admin => _roles.contains(Roles.admin);

  /// Solo admin y coordinador modifican una observación ya escrita; el rol
  /// `equipos` solo agrega. La base lo hace cumplir (schema_v62): esto solo
  /// evita mostrar un lápiz que le iba a fallar al usuario.
  bool get _editaObservaciones =>
      _admin || _roles.contains(Roles.coordinador);

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final a = await ActivosService.detalle(widget.activoId);
      final u = await ActivosService.ubicacionVigente(widget.activoId);
      if (!mounted) return;
      setState(() { _activo = a; _ubicacion = u; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _activo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipo')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                const SizedBox(height: 12),
                Text('No se pudo cargar el equipo.\n$_error',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _cargar, child: const Text('Reintentar')),
              ],
            ),
          ),
        ),
      );
    }

    final a = _activo!;
    // "Piezas" solo aplica cuando el equipo se está desarmando para
    // aprovechar partes: dado de baja, o reclasificado a repuestos. En un
    // equipo operativo o entregado la lista de piezas buenas/malas no
    // significa nada, y una pestaña vacía solo estorba.
    final muestraPiezas = a.estado == 'baja' || a.condicion == 'repuestos';
    // "Componentes" en todo equipo cuya referencia es un kit, SIEMPRE: es lo
    // que define su valor, también si está de baja o para repuestos (el plan
    // decía que ahí ganaba "Piezas"; se cambió porque ocultarla escondería
    // de dónde sale el valor que se sigue sumando al valorizado).
    final muestraComponentes = a.referenciaEsKit;
    final pestanas = 3 + (muestraPiezas ? 1 : 0) + (muestraComponentes ? 1 : 0);
    return DefaultTabController(
      length: pestanas,
      // Componentes va justo después de Ficha, así que es la pestaña 1.
      initialIndex: widget.abrirComponentes && muestraComponentes ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          // Serial arriba y modelo debajo: el serial solo no dice de qué
          // equipo se trata, y el modelo solo no distingue una unidad de
          // otra. En un teléfono angosto los dos recortan con puntos
          // suspensivos en vez de desbordarse.
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a.serial,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17)),
              Text(
                a.referenciaNombre ?? 'Sin referencia',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Ficha'),
              if (muestraComponentes) const Tab(text: 'Componentes'),
              if (muestraPiezas) const Tab(text: 'Piezas'),
              const Tab(text: 'Mantenimiento'),
              const Tab(text: 'Movimientos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Ficha(
              activo: a,
              ubicacion: _ubicacion,
              editaObservaciones: _editaObservaciones,
              onCambio: _cargar,
            ),
            if (muestraComponentes)
              _Componentes(activo: a, esAdmin: _admin, onCambio: _cargar),
            if (muestraPiezas) _Piezas(activoId: a.id),
            _Mantenimientos(activoId: a.id),
            _Movimientos(
                activoId: a.id,
                bodegaNombre: a.bodegaNombre,
                esAdmin: _admin,
                onCambio: _cargar),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 1 — Ficha
// ---------------------------------------------------------------------

class _Ficha extends StatelessWidget {
  final Activo activo;
  final ActivoUbicacion? ubicacion;
  final bool editaObservaciones;
  final Future<void> Function() onCambio;
  const _Ficha({
    required this.activo,
    required this.ubicacion,
    required this.editaObservaciones,
    required this.onCambio,
  });

  /// Operativo pero físicamente en un tercero (un préstamo a un cliente, por
  /// ejemplo). La vista activos_disponibilidad ya lo marca no disponible;
  /// la ficha tiene que decir lo mismo y no un "Operativo" en verde.
  bool get _fueraDeBodega => ubicacion?.terceroId != null;

  /// "Operativo" en verde solo si de verdad se puede entregar: misma regla
  /// que la vista (schema_v55). Si no, "No disponible" en gris.
  bool get _operativoNoDisponible =>
      activo.estado == 'operativo' && (activo.noEntregable || _fueraDeBodega);

  String get _etiquetaEstado =>
      _operativoNoDisponible ? 'No disponible' : activo.estadoEtiqueta;

  Color get _colorEstado => switch (activo.estado) {
    'operativo' when _operativoNoDisponible => Colors.grey.shade700,
    'operativo' => Colors.green.shade700,
    'entregado' => Colors.blueGrey,
    'baja' => Colors.red.shade700,
    _ => Colors.orange.shade800,
  };

  /// Solo un equipo disponible o entregado puede tener un movimiento real.
  /// En mantenimiento o de baja, lo que corresponde son otras acciones. Uno
  /// operativo pero no disponible (para repuestos, o fuera de la bodega)
  /// tampoco se entrega.
  bool get _permiteMovimiento =>
      (activo.estado == 'operativo' && !_operativoNoDisponible) ||
      activo.estado == 'entregado';

  /// Entregado a un centro de costo: salió del inventario y ya no es
  /// nuestro. No se le cambia ni la ubicación ni el estado a mano; lo único
  /// que cabe es registrar su regreso con una entrada.
  bool get _entregado => activo.estado == 'entregado';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activo.referenciaNombre ?? '—',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      label: Text(_etiquetaEstado),
                      backgroundColor: _colorEstado.withValues(alpha: 0.15),
                      side: BorderSide(color: _colorEstado),
                    ),
                    Chip(label: Text(activo.condicionEtiqueta)),
                  ],
                ),
                if (activo.mantenimientoActor != null &&
                    activo.mantenimientoActor!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('En: ${activo.mantenimientoActor}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        _bloque(context, 'Valorización', [
          // En un kit el valor no lo escribió nadie: es la suma de sus
          // componentes. La etiqueta lo dice para que no parezca un error.
          _fila(activo.referenciaEsKit
                  ? 'Valor a nuevo (suma de componentes)'
                  : 'Valor a nuevo',
              _money.format(activo.valorNuevo)),
          _fila('Porcentaje', '${activo.porcentajeValor}%'),
          _fila('Valor actual', _money.format(activo.valorActual),
              destacado: true),
        ]),
        const SizedBox(height: 12),

        _bloque(context, 'Ubicación física', [
          _fila('Está en', ubicacion?.lugar ?? 'Sin ubicación registrada'),
          if (ubicacion?.detalle != null && ubicacion!.detalle!.isNotEmpty)
            _fila('Detalle', ubicacion!.detalle!),
          if (ubicacion != null)
            _fila('Desde', _cuando(ubicacion!.fechaDesde)),
          _fila('Bodega dueña', activo.bodegaNombre ?? '—'),
        ]),
        const SizedBox(height: 6),
        // Un equipo entregado ya NO es nuestro. Ni se le cambia la ubicación
        // ni el estado a mano: la única forma de volver a tocarlo es
        // registrando su regreso con una entrada.
        if (_entregado)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.logout, size: 18),
                const SizedBox(width: 10),
                // Expanded: sin esto el texto desborda en 360 px.
                const Expanded(
                  child: Text(
                    'Este equipo fue entregado y ya no nos pertenece: no suma '
                    'al inventario. Para volver a moverlo hay que registrar su '
                    'regreso con una entrada.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          )
        else
          const Text(
            'Cambiar la ubicación NO afecta el inventario: el equipo sigue '
            'contando como nuestro aunque esté en un taller.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        const SizedBox(height: 12),
        if (!_entregado) ...[
          OutlinedButton.icon(
            onPressed: () async {
              final cambio = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _HojaCambiarUbicacion(activo: activo),
              );
              if (cambio == true) await onCambio();
            },
            icon: const Icon(Icons.place),
            label: const Text('Cambiar ubicación'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () async {
            final historial =
                await ActivosService.historialUbicacion(activo.id, limit: 50);
            if (!context.mounted) return;
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _HojaHistorialUbicacion(historial: historial),
            );
          },
          icon: const Icon(Icons.history),
          label: const Text('Ver historial de ubicaciones'),
        ),

        const SizedBox(height: 12),
        // Un equipo entregado está fuera del inventario: su estado solo
        // cambia registrando su regreso, no a mano.
        if (!_entregado)
          OutlinedButton.icon(
            onPressed: () async {
              final cambio = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    _HojaEstado(activo: activo, ubicacion: ubicacion),
              );
              if (cambio == true) await onCambio();
            },
            icon: const Icon(Icons.tune),
            label: const Text('Cambiar estado o condición'),
          ),

        const SizedBox(height: 12),
        _Observaciones(
            activoId: activo.id, puedeEditar: editaObservaciones),

        const SizedBox(height: 24),
        if (_permiteMovimiento)
          FilledButton.icon(
            onPressed: () async {
              final hecho = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => ActivoMovimientoPage(activo: activo)),
              );
              if (hecho == true) await onCambio();
            },
            icon: Icon(activo.estado == 'entregado'
                ? Icons.download
                : Icons.upload),
            label: Text(activo.estado == 'entregado'
                ? 'Registrar reingreso'
                : 'Registrar salida'),
          )
        else
          Card(
            color: Colors.orange.shade50,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Este equipo no admite entrada ni salida en su estado actual. '
                'Registra primero el mantenimiento o cámbiale la ubicación.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _bloque(BuildContext context, String titulo, List<Widget> hijos) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ...hijos,
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(etiqueta,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
          ),
          // Expanded: un nombre largo baja de línea en vez de desbordarse.
          Expanded(
            child: Text(valor,
                style: TextStyle(
                    fontWeight:
                        destacado ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }
}

/// Cambia a mano el estado operativo y la condición de un equipo.
///
/// Existe porque el trigger de la base solo mueve el estado cuando hay una
/// entrada o una salida. Sin esta pantalla, un equipo que entra a
/// mantenimiento se queda atrapado ahí para siempre: no hay movimiento que
/// lo saque, porque nunca salió de la bodega.
// ---------------------------------------------------------------------
// Pestaña — Componentes de un KIT (Fase 3, docs/plan-kits-equipos.md)
// ---------------------------------------------------------------------

/// De qué está hecho un kit y cuánto vale cada parte. El valor del equipo es
/// la suma de estos subtotales: lo calcula la base (schema_v64), aquí solo se
/// muestra y se le agregan componentes. Mover uno (vender, dañar, garantía)
/// llega en la Fase 5.
class _Componentes extends StatefulWidget {
  final Activo activo;
  /// Anular un movimiento de componente: solo el admin (schema_v66).
  final bool esAdmin;
  final Future<void> Function() onCambio;
  const _Componentes({
    required this.activo,
    required this.esAdmin,
    required this.onCambio,
  });
  @override
  State<_Componentes> createState() => _ComponentesState();
}

class _ComponentesState extends State<_Componentes> {
  List<ActivoComponente> _lista = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    ActivosService.revision.addListener(_cargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final l = await ActivosService.componentes(widget.activo.id);
      if (!mounted) return;
      setState(() { _lista = l; _cargando = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  /// Un kit entregado ya no es nuestro (regla 3): la base rechaza agregarle
  /// componentes, así que ni se ofrece el botón.
  bool get _entregado => widget.activo.estado == 'entregado';
  num get _porcentaje => widget.activo.porcentajeValor;
  num get _total => _lista.fold<num>(0, (s, c) => s + c.subtotal);

  Future<void> _agregar() async {
    final agregado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaComponente(
        activoId: widget.activo.id,
        orden: _lista.length + 1,
        // Para avisar un nombre repetido al escribirlo, no al guardar.
        nombresExistentes: [for (final c in _lista) c.nombre],
      ),
    );
    // Recargar el equipo: su valor a nuevo cambió, y la Ficha lo muestra.
    if (agregado == true) await widget.onCambio();
  }

  /// La vida de un componente: su historia y registrar movimientos (Fase 5).
  Future<void> _abrir(ActivoComponente c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComponenteKitPage(
          componente: c,
          serialKit: widget.activo.serial,
          kitEntregado: _entregado,
          esAdmin: widget.esAdmin,
        ),
      ),
    );
    // Lo que se haya movido allá cambia el valor del kit: se recarga el
    // equipo para que la Ficha no quede mostrando el viejo.
    await widget.onCambio();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudieron cargar los componentes.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    // Los que siguen en el kit primero; los agotados al final, pero se
    // muestran: su historia no desaparece porque se hayan acabado.
    final vivos = _lista.where((c) => !c.agotado).toList();
    final agotados = _lista.where((c) => c.agotado).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vivos.length == 1
                          ? '1 componente'
                          : '${vivos.length} componentes',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!_entregado)
                    FilledButton.tonalIcon(
                      onPressed: _agregar,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                ],
              ),
              if (_entregado)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Este kit fue entregado y ya no nos pertenece: no se le '
                    'agregan componentes.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              if (_lista.isEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 12),
                        // Expanded: sin esto el texto desborda en 360 px.
                        Expanded(
                          child: Text(
                            _entregado
                                ? 'Este kit no tiene componentes registrados.'
                                : 'Este kit todavía no tiene componentes, así '
                                    'que vale \$0. Agrégale sus partes con el '
                                    'botón "Agregar": su valor será la suma de '
                                    'todas.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final c in vivos)
                TarjetaComponente(
                    componente: c,
                    porcentaje: _porcentaje,
                    onTap: () => _abrir(c)),
              if (agotados.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Agotados',
                    style: Theme.of(context).textTheme.labelLarge),
                // Un agotado también se abre: su historia sigue ahí, y un
                // "Agregar" lo puede devolver al kit.
                for (final c in agotados)
                  TarjetaComponente(
                      componente: c,
                      porcentaje: _porcentaje,
                      onTap: () => _abrir(c)),
              ],
            ],
          ),
        ),
        // El total, fijo al pie: se ve siempre, aunque la lista sea larga.
        if (_lista.isNotEmpty)
          PieTotalKit(total: _total, porcentaje: _porcentaje),
      ],
    );
  }
}

/// Listado cronológico de observaciones del equipo, del más reciente al más
/// antiguo (regla de históricos del proyecto).
///
/// Antes la ficha mostraba UNA sola observación, la del alta, y los
/// comentarios de cada cambio de estado o de ubicación no se veían por
/// ninguna parte. Ahora las tres fuentes salen juntas de la vista
/// `activo_observaciones_todas`.
class _Observaciones extends StatefulWidget {
  final String activoId;
  /// Admin o coordinador. El rol `equipos` agrega pero no edita (v62).
  final bool puedeEditar;
  const _Observaciones({required this.activoId, required this.puedeEditar});
  @override
  State<_Observaciones> createState() => _ObservacionesState();
}

class _ObservacionesState extends State<_Observaciones> {
  List<ActivoObservacion> _lista = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
    ActivosService.revision.addListener(_cargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final l = await ActivosService.observaciones(widget.activoId);
      if (!mounted) return;
      setState(() { _lista = l; _cargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  static IconData _icono(String origen) => switch (origen) {
    'alta' => Icons.add_circle_outline,
    'ubicacion' => Icons.place_outlined,
    'estado' => Icons.tune,
    _ => Icons.notes,
  };

  /// Edita el texto en su tabla de origen. El historial lo guarda solo el
  /// trigger de auditoría; aquí no hay que hacer nada más.
  Future<void> _editar(ActivoObservacion o) async {
    final texto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaNota(
        titulo: 'Editar observación',
        inicial: o.texto,
        aviso: 'El cambio queda registrado: fecha, tu nombre y lo que decía '
            'antes.',
      ),
    );
    if (texto == null || texto.trim() == o.texto.trim()) return;
    if (texto.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La observación no puede quedar vacía.')));
      return;
    }
    try {
      await ActivosService.editarObservacion(
          origen: o.origen, id: o.id, texto: texto);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  Future<void> _verCambios(ActivoObservacion o) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaCambiosObservacion(observacion: o),
    );
  }

  Future<void> _agregar() async {
    final texto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HojaNota(),
    );
    if (texto == null || texto.trim().isEmpty) return;
    try {
      await ActivosService.agregarObservacion(
        activoId: widget.activoId,
        texto: texto,
        origen: 'manual',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Observaciones',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined),
                  tooltip: 'Agregar una observación',
                  onPressed: _agregar,
                ),
              ],
            ),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_lista.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Todavía no hay observaciones.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              for (final o in _lista) ...[
                const Divider(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icono(o.origen), size: 18, color: Colors.grey),
                    const SizedBox(width: 10),
                    // Expanded: en 360 px un texto largo sin esto desborda
                    // la fila y Flutter pinta la franja amarilla y negra.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.texto),
                          const SizedBox(height: 2),
                          Text(
                            [
                              o.etiquetaOrigen,
                              if (o.contexto != null && o.contexto!.isNotEmpty)
                                o.contexto!,
                              _cuando(o.fecha),
                              if (o.usuarioEmail != null) o.usuarioEmail!,
                            ].join(' · '),
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey),
                          ),
                          // Una observación editada lo dice, y deja ver qué
                          // decía antes. Sin esto, editar sería reescribir
                          // la historia en silencio.
                          if (o.editada)
                            InkWell(
                              onTap: () => _verCambios(o),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history,
                                        size: 15,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    const SizedBox(width: 4),
                                    Text('Editada · ver cambios',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 48 dp de área táctil: es un botón que se usa con el
                    // dedo en una tablet, no con un mouse. Solo admin y
                    // coordinador: al rol `equipos` la base se lo rechaza.
                    if (widget.puedeEditar)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Editar esta observación',
                        onPressed: () => _editar(o),
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// Hoja mínima para escribir una observación suelta.
/// Hoja para escribir una observación nueva o editar una existente. La
/// misma para las dos cosas: si se ven distinto, el usuario duda de si está
/// haciendo lo mismo.
class _HojaNota extends StatefulWidget {
  final String titulo;
  final String inicial;
  /// Una línea gris bajo el campo. Al editar, avisa que el cambio queda
  /// registrado: editar no es borrar lo que se dijo.
  final String? aviso;
  const _HojaNota({
    this.titulo = 'Nueva observación',
    this.inicial = '',
    this.aviso,
  });
  @override
  State<_HojaNota> createState() => _HojaNotaState();
}

class _HojaNotaState extends State<_HojaNota> {
  late final _texto = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.titulo,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar sin guardar',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _texto,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observación',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.aviso != null) ...[
            const SizedBox(height: 6),
            Text(widget.aviso!,
                style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context, _texto.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Lo que ha cambiado el texto de una observación: fecha, quién, antes y
/// después. En tarjetas y no en tabla: en 360 px una tabla de cuatro
/// columnas con textos largos es ilegible.
class _HojaCambiosObservacion extends StatelessWidget {
  final ActivoObservacion observacion;
  const _HojaCambiosObservacion({required this.observacion});

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: alto),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Cambios de la observación',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Del más reciente al más antiguo.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<CambioObservacion>>(
                future: ActivosService.historialObservacion(
                    origen: observacion.origen, id: observacion.id),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Text('No se pudo cargar: ${snap.error}');
                  }
                  final cambios = snap.data ?? const [];
                  if (cambios.isEmpty) {
                    return const Text('Esta observación no tiene cambios.');
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: cambios.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _TarjetaCambio(cambio: cambios[i]),
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

class _TarjetaCambio extends StatelessWidget {
  final CambioObservacion cambio;
  const _TarjetaCambio({required this.cambio});

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                _cuando(cambio.fecha),
                if (cambio.usuarioEmail != null) cambio.usuarioEmail!,
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: gris),
            ),
            const SizedBox(height: 8),
            Text('ANTES', style: TextStyle(fontSize: 10.5, color: gris,
                fontWeight: FontWeight.w600, letterSpacing: 0.6)),
            // Tachado: se lee de un vistazo que es lo que ya no dice.
            Text(cambio.antes ?? '(vacío)',
                style: TextStyle(
                    color: gris, decoration: TextDecoration.lineThrough)),
            const SizedBox(height: 8),
            Text('DESPUÉS', style: TextStyle(fontSize: 10.5, color: gris,
                fontWeight: FontWeight.w600, letterSpacing: 0.6)),
            Text(cambio.despues ?? '(vacío)'),
          ],
        ),
      ),
    );
  }
}

class _HojaEstado extends StatefulWidget {
  final Activo activo;
  /// La ubicación vigente. Es la fuente de verdad de dónde está el equipo;
  /// `mantenimiento_actor` es solo texto para mostrar.
  final ActivoUbicacion? ubicacion;
  const _HojaEstado({required this.activo, required this.ubicacion});
  @override
  State<_HojaEstado> createState() => _HojaEstadoState();
}

class _HojaEstadoState extends State<_HojaEstado> {
  late String _estado;
  late String _condicion;
  late final TextEditingController _actor;
  final _observacion = TextEditingController();
  bool _guardando = false;
  // Mandar un equipo a un taller externo es, para el usuario, UNA sola
  // acción. Antes eran dos pantallas distintas que no se hablaban: el
  // estado guardaba el nombre del taller como texto y el historial de
  // ubicaciones nunca se enteraba. Ahora se elige el taller del catálogo y
  // se registra la ubicación en el mismo paso.
  List<ActivoTercero> _terceros = [];
  ActivoTercero? _taller;
  /// El taller con el que se abrió la hoja, para saber si de verdad cambió.
  ActivoTercero? _tallerOriginal;
  bool _cargandoTerceros = true;

  static const _etiquetasEstado = {
    'operativo': 'Operativo (listo para entregar)',
    'mantenimiento_interno': 'En mantenimiento interno',
    'mantenimiento_externo': 'En un taller externo',
    'baja': 'De baja',
  };

  static const _etiquetasCondicion = {
    'nuevo': 'Nuevo',
    'usado': 'Usado',
    'repuestos': 'Para repuestos',
    'baja': 'De baja',
  };

  @override
  void initState() {
    super.initState();
    _estado = widget.activo.estado;
    _condicion = widget.activo.condicion;
    _actor = TextEditingController(text: widget.activo.mantenimientoActor ?? '');
    _cargarTerceros();
  }

  Future<void> _cargarTerceros() async {
    try {
      final t = await ActivosService.todosLosTerceros();
      if (!mounted) return;
      setState(() {
        _terceros = t;
        _cargandoTerceros = false;
        _preseleccionarTaller();
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoTerceros = false);
    }
  }

  /// El equipo pudo llegar aquí ya estando en un taller. Se preselecciona el
  /// taller donde está para que cambiar solo la condición no exija volver a
  /// elegirlo, y para no anteponer su nombre por segunda vez al guardar.
  ///
  /// Primero se mira la ubicación vigente, que es el dato duro. Solo si no
  /// hay ubicación con tercero se cae al texto de `mantenimiento_actor`, que
  /// es lo que existía antes de unificar estado y ubicación.
  void _preseleccionarTaller() {
    if (_estado != 'mantenimiento_externo') return;
    final terceroId = widget.ubicacion?.terceroId;
    if (terceroId != null) {
      for (final t in _terceros) {
        if (t.id == terceroId) {
          _taller = t;
          _tallerOriginal = t;
          final actor = widget.activo.mantenimientoActor ?? '';
          _actor.text = actor.startsWith('${t.nombre} · ')
              ? actor.substring(t.nombre.length + 3)
              : (actor == t.nombre ? '' : actor);
          return;
        }
      }
    }
    final actor = widget.activo.mantenimientoActor ?? '';
    if (actor.isEmpty) return;
    for (final t in _terceros) {
      if (actor == t.nombre) {
        _taller = t;
        _tallerOriginal = t;
        _actor.text = '';
        return;
      }
      if (actor.startsWith('${t.nombre} · ')) {
        _taller = t;
        _tallerOriginal = t;
        _actor.text = actor.substring(t.nombre.length + 3);
        return;
      }
    }
    // Si no coincide con ningún tercero es texto libre de antes de unificar
    // estado y ubicación. Se deja tal cual y NO se exige elegir taller.
  }

  /// Crea un taller sin salir de aquí: si el catálogo está vacío, obligar a
  /// ir a otra pantalla y volver a empezar sería absurdo.
  Future<void> _crearTaller() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Nuevo taller'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Nombre del taller',
                hintText: 'Ej: TALLER METALANDES'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Crear')),
          ],
        );
      },
    );
    if (nombre == null || nombre.isEmpty) return;
    try {
      final nuevo =
          await ActivosService.crearTercero(nombre: nombre, tipo: 'taller');
      if (!mounted) return;
      setState(() { _terceros = [..._terceros, nuevo]; _taller = nuevo; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
    }
  }

  @override
  void dispose() {
    _actor.dispose();
    _observacion.dispose();
    super.dispose();
  }

  /// Solo se exige taller cuando el equipo ENTRA a un taller ahora. Si ya
  /// estaba en mantenimiento externo y solo se viene a cambiar la condición,
  /// pedirlo bloquearía un cambio que no tiene nada que ver con la ubicación.
  bool get _entraATaller =>
      _estado == 'mantenimiento_externo' &&
      widget.activo.estado != 'mantenimiento_externo';

  bool get _faltaTaller => _entraATaller && _taller == null;

  /// El equipo estaba en un taller externo y deja de estarlo: vuelve a su
  /// bodega. Se registra solo si el historial no dice ya que está ahí, para
  /// no duplicar la fila cuando los datos venían descuadrados de antes.
  bool get _vuelveDeTaller =>
      widget.activo.estado == 'mantenimiento_externo' &&
      _estado != 'mantenimiento_externo' &&
      widget.ubicacion?.bodegaId != widget.activo.bodegaId;

  /// Misma fórmula que la vista `activos_disponibilidad` (schema_v55). Sirve
  /// solo para AVISAR aquí lo que va a pasar; la verdad la calcula la base.
  bool get _quedaraDisponible =>
      _estado == 'operativo' &&
      _condicion != 'repuestos' &&
      _condicion != 'baja' &&
      // Vuelve a la bodega, o ya estaba en una.
      (_vuelveDeTaller ||
          (_estado != 'mantenimiento_externo' &&
              widget.ubicacion?.bodegaId != null));

  /// Lo que va a pasar al guardar, en frases que el usuario reconozca. La
  /// ambigüedad entre esta pantalla y "Cambiar ubicación" fue lo que hizo
  /// que un regreso a bodega no quedara en el historial (SDD, error 9.6).
  List<String> get _consecuencias => [
    if (_vuelveDeTaller)
      'Vuelve a ${widget.activo.bodegaNombre ?? "su bodega"} y queda en el '
          'historial de ubicaciones.',
    if (_quedaraDisponible)
      'Queda DISPONIBLE para entregar.'
    else if (_condicion == 'repuestos')
      'NO queda disponible: está marcado para repuestos.'
    else if (_condicion == 'baja' || _estado == 'baja')
      'NO queda disponible: está dado de baja.'
    else if (_estado == 'mantenimiento_externo')
      'NO queda disponible: está en un taller externo.'
    else if (_estado == 'mantenimiento_interno')
      'NO queda disponible: está en mantenimiento.',
  ];

  Future<void> _guardar() async {
    if (_faltaTaller) {
      // Nunca fallar en silencio: antes solo se repintaba y el usuario
      // oprimía Guardar sin que pasara nada visible.
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Elige a qué taller se va el equipo.')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      // El nombre del taller se guarda junto al detalle, para que la ficha
      // muestre de un vistazo dónde está y por qué. Si no se eligió taller
      // (texto libre de antes), se respeta lo que ya estaba en vez de
      // borrarlo.
      final String? actor;
      if (_estado != 'mantenimiento_externo') {
        actor = null;
      } else if (_taller != null) {
        actor = [_taller!.nombre, _actor.text.trim()]
            .where((e) => e.isNotEmpty)
            .join(' · ');
      } else {
        actor = widget.activo.mantenimientoActor;
      }
      if (_estado != widget.activo.estado ||
          (actor ?? '') != (widget.activo.mantenimientoActor ?? '')) {
        await ActivosService.cambiarEstado(
          widget.activo.id,
          estado: _estado,
          mantenimientoActor: actor,
        );
      }
      // El estado y la ubicación tienen que contar la MISMA historia, en las
      // dos direcciones. Antes solo estaba programada la de ida: mandar un
      // equipo al taller registraba la ubicación, pero traerlo de vuelta no
      // registraba nada y el historial se quedaba diciendo que seguía allá.
      if (_estado == 'mantenimiento_externo') {
        // IDA. Solo si el taller CAMBIÓ: desde que se precarga, guardar un
        // cambio de condición repetiría la misma ubicación una y otra vez.
        if (_taller != null && _taller!.id != _tallerOriginal?.id) {
          await ActivosService.cambiarUbicacion(
            activoId: widget.activo.id,
            terceroId: _taller!.id,
            detalle: _actor.text.trim().isEmpty ? null : _actor.text.trim(),
          );
        }
      } else if (_vuelveDeTaller) {
        // REGRESO. Dejar de estar en un taller externo significa que el
        // equipo volvió a su bodega. Es un movimiento físico real y va al
        // historial con su fecha y su responsable, como cualquier otro.
        await ActivosService.cambiarUbicacion(
          activoId: widget.activo.id,
          bodegaId: widget.activo.bodegaId,
          detalle: _tallerOriginal != null
              ? 'Regresa de ${_tallerOriginal!.nombre}'
              : 'Regresa a la bodega',
        );
      }
      if (_condicion != widget.activo.condicion) {
        await ActivosService.cambiarCondicion(widget.activo.id, _condicion);
      }
      // La observación se guarda de últimas, con el contexto de lo que
      // acabó de cambiar, para que dentro de un año se entienda sola.
      if (_observacion.text.trim().isNotEmpty) {
        final cambios = <String>[
          if (_estado != widget.activo.estado)
            'Estado: ${_etiquetasEstado[_estado] ?? _estado}',
          if (_condicion != widget.activo.condicion)
            'Condición: ${_etiquetasCondicion[_condicion] ?? _condicion}',
        ];
        await ActivosService.agregarObservacion(
          activoId: widget.activo.id,
          texto: _observacion.text,
          contexto: cambios.isEmpty ? null : cambios.join(' · '),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Estado y condición',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                // Salida clara sin guardar: sin esto, la única forma de
                // cancelar era arrastrar la hoja hacia abajo, que no todo el
                // mundo descubre.
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Para cuando el equipo cambia sin entrar ni salir de la bodega: '
              'se reparó, se mandó al taller o se dio de baja.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text('Estado operativo',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            // Lista y no chips: las etiquetas son frases, y en un teléfono
            // angosto unos chips con este texto quedarían ilegibles.
            for (final e in ActivosService.estadosManuales)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(_estado == e
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(_etiquetasEstado[e] ?? e),
                onTap: () => setState(() => _estado = e),
              ),
            if (_estado == 'mantenimiento_externo') ...[
              const SizedBox(height: 8),
              if (_cargandoTerceros)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                // Con buscador SIEMPRE, no atado a un umbral: la lista de
                // talleres va a crecer, y un desplegable de cientos de
                // opciones es inservible. Mismo criterio que ya se aplicó a
                // los centros de costo y a las referencias.
                SelectorRecargable<ActivoTercero>(
                  forzarBuscador: true,
                  etiqueta:
                      _entraATaller ? '¿A qué taller se va? *' : '¿En qué taller está?',
                  icono: Icons.build,
                  valor: _taller,
                  opciones: _terceros,
                  textoDe: (t) => t.nombre,
                  onRecargar: _cargarTerceros,
                  onChanged: (v) => setState(() => _taller = v),
                  onAgregar: _crearTaller,
                  tooltipAgregar: 'Crear un taller nuevo',
                  textoVacio: 'No hay talleres. Crea uno con el botón +.',
                  error: _faltaTaller,
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _actor,
                decoration: const InputDecoration(
                  labelText: '¿Qué le están haciendo?',
                  hintText: 'Ej: cambio de carcaza',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Esto queda también en el historial de ubicaciones, con la '
                'fecha y tu nombre. No hace falta usar "Cambiar ubicación" '
                'aparte.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
            // Que la ventana DIGA qué va a pasar, antes de guardar. La
            // ambigüedad entre esta pantalla y "Cambiar ubicación" es lo que
            // hizo que un regreso a bodega no quedara en el historial.
            if (_consecuencias.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_quedaraDisponible ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Al guardar:',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    for (final c in _consecuencias)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• '),
                            // Expanded: sin esto el texto desborda en 360 px.
                            Expanded(
                              child: Text(c,
                                  style: const TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const Divider(height: 28),
            Text('Condición', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in _etiquetasCondicion.keys)
                  ChoiceChip(
                    label: Text(_etiquetasCondicion[c]!),
                    selected: _condicion == c,
                    onSelected: (_) => setState(() => _condicion = c),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'La condición es la clasificación comercial (cuánto vale). El '
              'estado es si se puede usar ahora. Son cosas distintas.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const Divider(height: 28),
            TextField(
              controller: _observacion,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observación',
                hintText: '¿Por qué cambia? Ej: se quemó el devanado',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Queda en el listado de observaciones de la ficha, con la fecha '
              'y tu nombre.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HojaCambiarUbicacion extends StatefulWidget {
  final Activo activo;
  const _HojaCambiarUbicacion({required this.activo});
  @override
  State<_HojaCambiarUbicacion> createState() => _HojaCambiarUbicacionState();
}

class _HojaCambiarUbicacionState extends State<_HojaCambiarUbicacion> {
  bool _enBodega = true;
  final _detalle = TextEditingController();
  List<Bodega> _bodegas = [];
  List<ActivoTercero> _terceros = [];
  Bodega? _bodega;
  ActivoTercero? _tercero;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final b = await InventarioService.bodegas();
      final t = await ActivosService.todosLosTerceros();
      if (!mounted) return;
      setState(() {
        _bodegas = b;
        _terceros = t;
        for (final x in b) {
          if (x.id == widget.activo.bodegaId) _bodega = x;
        }
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  /// Crear un tercero sin salir de aquí: si falta justo el que se necesita,
  /// obligar a ir al catálogo y volver a empezar es una pérdida de tiempo.
  Future<void> _crearTercero() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Nuevo tercero'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Nombre', hintText: 'Ej: TALLER METALANDES'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Crear')),
          ],
        );
      },
    );
    if (nombre == null || nombre.isEmpty) return;
    try {
      final nuevo =
          await ActivosService.crearTercero(nombre: nombre, tipo: 'taller');
      if (!mounted) return;
      setState(() { _terceros = [..._terceros, nuevo]; _tercero = nuevo; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
    }
  }

  /// Qué le pasa al estado con este cambio de ubicación, y si queda
  /// disponible. Predice lo que hace `cambiar_ubicacion_activo` (schema_v61);
  /// la que manda es la base.
  (String, bool)? get _consecuencia {
    final a = widget.activo;
    if (!_enBodega && _tercero != null) {
      if (_tercero!.tipo == 'taller') {
        return ('pasa a "En mantenimiento (externo)" en ${_tercero!.nombre}. '
            'NO queda disponible mientras esté allá.', false);
      }
      return ('queda fuera de la bodega, en ${_tercero!.nombre}. NO queda '
          'disponible mientras esté allá.', false);
    }
    if (_enBodega && _bodega != null && a.estado == 'mantenimiento_externo') {
      final disponible = !a.noEntregable;
      return ('vuelve del taller y pasa a "Operativo". '
          '${disponible ? "Queda DISPONIBLE para entregar." : "NO queda disponible: ${a.condicionEtiqueta.toLowerCase()}."}',
          disponible);
    }
    return null;
  }

  Future<void> _guardar() async {
    // Mismo criterio que la hoja de estado: nunca devolverse en silencio.
    // Un botón que no hace nada es peor que un error.
    if ((_enBodega && _bodega == null) || (!_enBodega && _tercero == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_enBodega
              ? 'Elige a qué bodega se va el equipo.'
              : 'Elige a qué tercero se va el equipo.'),
        ),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await ActivosService.cambiarUbicacion(
        activoId: widget.activo.id,
        bodegaId: _enBodega ? _bodega!.id : null,
        terceroId: _enBodega ? null : _tercero!.id,
        detalle: _detalle.text.trim().isEmpty ? null : _detalle.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cambiar la ubicación: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: _cargando
          ? const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Cambiar ubicación',
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Cerrar sin guardar',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'No afecta el inventario: el equipo sigue siendo nuestro.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  // La consecuencia de mandarlo a un tercero no era obvia:
                  // el equipo deja de contar como disponible. Se dice ANTES
                  // de guardar, no después de que el usuario se pregunte por
                  // qué desapareció de la lista de disponibles.
                  if (!_enBodega)
                    Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      color: Colors.orange.shade50,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Mientras esté donde un tercero, el equipo NO contará '
                          'como disponible para entregar. Sigue siendo tuyo y '
                          'sigue valorizado en tu bodega; solo deja de estar a '
                          'la mano.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          label: Text('Bodega propia'),
                          icon: Icon(Icons.warehouse)),
                      ButtonSegment(
                          value: false,
                          label: Text('Tercero'),
                          icon: Icon(Icons.place)),
                    ],
                    selected: {_enBodega},
                    onSelectionChanged: (s) =>
                        setState(() => _enBodega = s.first),
                  ),
                  const SizedBox(height: 16),
                  if (_enBodega)
                    DropdownButtonFormField<Bodega>(
                      initialValue: _bodega,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Bodega', border: OutlineInputBorder()),
                      items: _bodegas
                          .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(b.nombre,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _bodega = v),
                    )
                  else
                    // Con buscador siempre: la lista de terceros crece, y
                    // un desplegable largo no se puede recorrer. El "+"
                    // evita tener que salir a otra pantalla si falta uno.
                    SelectorRecargable<ActivoTercero>(
                      forzarBuscador: true,
                      etiqueta: 'Tercero',
                      icono: Icons.store,
                      valor: _tercero,
                      opciones: _terceros,
                      textoDe: (t) => t.nombre,
                      onRecargar: _cargar,
                      onChanged: (v) => setState(() => _tercero = v),
                      onAgregar: _crearTercero,
                      tooltipAgregar: 'Crear un tercero nuevo',
                      textoVacio: 'No hay terceros. Crea uno con el botón +.',
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detalle,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Observación',
                      hintText: 'Ej: en reparación del impulsor',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Queda en el listado de observaciones de la ficha, con la '
                    'fecha y tu nombre.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  // Lo mismo que en la ventana de Estado: decir ANTES de
                  // guardar qué le pasa al estado. Mover a un taller cambia
                  // el estado (schema_v61), y el usuario tiene que verlo.
                  if (_consecuencia != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_consecuencia!.$2 ? Colors.green : Colors.orange)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Al guardar: ${_consecuencia!.$1}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar ubicación'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HojaHistorialUbicacion extends StatelessWidget {
  final List<ActivoUbicacion> historial;
  const _HojaHistorialUbicacion({required this.historial});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Historial de ubicaciones',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (historial.isEmpty)
              const Text('Todavía no hay ubicaciones registradas.')
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: historial.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = historial[i];
                    return ListTile(
                      leading: Icon(u.vigente
                          ? Icons.place
                          : Icons.history_toggle_off),
                      title: Text(u.lugar),
                      subtitle: Text(
                        '${_cuando(u.fechaDesde)}'
                        '${u.fechaHasta == null
                            ? ' · actual'
                            : ' → ${_cuando(u.fechaHasta!)}'}'
                        '${u.detalle == null || u.detalle!.isEmpty
                            ? ''
                            : '\n${u.detalle}'}',
                      ),
                      isThreeLine:
                          u.detalle != null && u.detalle!.isNotEmpty,
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

// ---------------------------------------------------------------------
// Pestaña 2 — Piezas
// ---------------------------------------------------------------------

class _Piezas extends StatefulWidget {
  final String activoId;
  const _Piezas({required this.activoId});
  @override
  State<_Piezas> createState() => _PiezasState();
}

class _PiezasState extends State<_Piezas> {
  List<ActivoPieza> _piezas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final res = await ActivosService.piezas(widget.activoId);
      if (!mounted) return;
      setState(() { _piezas = res; _cargando = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _agregar() async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Nueva pieza'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Nombre de la pieza',
                hintText: 'Ej: IMPULSOR'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Agregar')),
          ],
        );
      },
    );
    if (nombre == null || nombre.isEmpty) return;
    await ActivosService.agregarPieza(
        activoId: widget.activoId, nombre: nombre);
    await _cargar();
  }

  Future<void> _cambiarEstado(ActivoPieza p, String estado) async {
    await ActivosService.editarPieza(p.id, estado: estado);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        icon: const Icon(Icons.add),
        label: const Text('Pieza'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _piezas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay piezas registradas para este equipo.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _piezas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = _piezas[i];
                    return ListTile(
                      leading: Icon(
                        switch (p.estado) {
                          'buena' => Icons.check_circle,
                          'mala' => Icons.cancel,
                          _ => Icons.help_outline,
                        },
                        color: switch (p.estado) {
                          'buena' => Colors.green,
                          'mala' => Colors.red,
                          _ => Colors.grey,
                        },
                      ),
                      title: Text(p.nombre),
                      subtitle: p.actualizadoEmail == null
                          ? null
                          : Text(p.actualizadoEmail!,
                              style: const TextStyle(fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => _cambiarEstado(p, v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'buena', child: Text('Marcar buena')),
                          PopupMenuItem(
                              value: 'mala', child: Text('Marcar mala')),
                          PopupMenuItem(
                              value: 'desconocido',
                              child: Text('Sin revisar')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 3 — Mantenimientos
// ---------------------------------------------------------------------

class _Mantenimientos extends StatefulWidget {
  final String activoId;
  const _Mantenimientos({required this.activoId});
  @override
  State<_Mantenimientos> createState() => _MantenimientosState();
}

class _MantenimientosState extends State<_Mantenimientos> {
  List<ActivoMantenimiento> _lista = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final res =
          await ActivosService.mantenimientos(widget.activoId, limit: 50);
      if (!mounted) return;
      setState(() { _lista = res; _cargando = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _agregar() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaMantenimiento(activoId: widget.activoId),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregar,
        icon: const Icon(Icons.add),
        label: const Text('Registrar'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _lista.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Sin mantenimientos registrados.',
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _lista.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _lista[i];
                    return ListTile(
                      title: Text(m.descripcion),
                      subtitle: Text([
                        _fecha.format(m.fecha),
                        if (m.tipo != null && m.tipo!.isNotEmpty) m.tipo!,
                        if (m.responsable != null &&
                            m.responsable!.isNotEmpty)
                          m.responsable!,
                        if (m.usuarioEmail != null) m.usuarioEmail!,
                      ].join(' · ')),
                      trailing: m.costo == 0
                          ? null
                          : Text(_money.format(m.costo)),
                    );
                  },
                ),
    );
  }
}

class _HojaMantenimiento extends StatefulWidget {
  final String activoId;
  const _HojaMantenimiento({required this.activoId});
  @override
  State<_HojaMantenimiento> createState() => _HojaMantenimientoState();
}

class _HojaMantenimientoState extends State<_HojaMantenimiento> {
  final _descripcion = TextEditingController();
  final _tipo = TextEditingController();
  final _responsable = TextEditingController();
  final _costo = TextEditingController();
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _tipo.dispose();
    _responsable.dispose();
    _costo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_descripcion.text.trim().isEmpty) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await ActivosService.registrarMantenimiento(
        activoId: widget.activoId,
        descripcion: _descripcion.text.trim(),
        tipo: _tipo.text.trim().isEmpty ? null : _tipo.text.trim(),
        responsable: _responsable.text.trim().isEmpty
            ? null : _responsable.text.trim(),
        costo: leerPesos(_costo.text) ?? 0,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Registrar mantenimiento',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descripcion,
              autofocus: true,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Qué se hizo *',
                border: const OutlineInputBorder(),
                filled: _mostrarErrores && _descripcion.text.trim().isEmpty,
                fillColor: Colors.red.shade50,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tipo,
              decoration: const InputDecoration(
                  labelText: 'Tipo',
                  hintText: 'Preventivo, correctivo…',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _responsable,
              decoration: const InputDecoration(
                  labelText: 'Responsable', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costo,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText: 'Costo',
                  prefixText: '\$ ',
                  helperText: pesosEntendidos(_costo.text),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 4 — Movimientos
// ---------------------------------------------------------------------

class _Movimientos extends StatefulWidget {
  final String activoId;
  /// La bodega dueña del equipo. Las salidas no guardan bodega en el
  /// movimiento, y sin esto el flujo diría "🏬 — ➡️ 🎯 NP00034".
  final String? bodegaNombre;
  final bool esAdmin;
  final Future<void> Function() onCambio;
  const _Movimientos({
    required this.activoId,
    required this.bodegaNombre,
    required this.esAdmin,
    required this.onCambio,
  });
  @override
  State<_Movimientos> createState() => _MovimientosState();
}

class _MovimientosState extends State<_Movimientos> {
  List<ActivoMovimiento> _movs = [];
  Set<String> _anulados = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final movs = await ActivosService.movimientos(widget.activoId, limit: 50);
      final anulados =
          await ActivosService.idsAnuladosDeActivo(widget.activoId);
      if (!mounted) return;
      setState(() { _movs = movs; _anulados = anulados; _cargando = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _anular(ActivoMovimiento m) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular este movimiento?'),
        content: const Text(
            'No se borra nada: se registra un ajuste que lo revierte y queda '
            'en el historial.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anular')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await ActivosService.anularMovimiento(m.id);
      await _cargar();
      await widget.onCambio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo anular: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_movs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sin movimientos registrados.'),
        ),
      );
    }
    return ListView.separated(
      itemCount: _movs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = _movs[i];
        final anulado = _anulados.contains(m.id);
        // La etiqueta sale del modelo, no se arma aquí: así el listado y los
        // informes dicen exactamente lo mismo ("Entrada · REINGRESO").
        final etiqueta = m.tipoEtiqueta;
        return ListTile(
          // El reingreso con su propio ícono y color: un equipo que vuelve de
          // un centro de costo se tiene que distinguir de un alta sin leer.
          leading: Icon(
            switch (m.tipo) {
              'entrada' when m.esReingreso => Icons.assignment_return,
              'entrada' => Icons.download,
              'salida' => Icons.upload,
              _ => Icons.undo,
            },
            color: m.esReingreso ? Colors.deepPurple : null,
          ),
          title: Row(
            children: [
              // Flexible: "Entrada · REINGRESO" + "ANULADO" no cabe en 360 px
              // sin dejar que el texto se ajuste.
              Flexible(
                child: Text(etiqueta,
                    style: m.esReingreso
                        ? const TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w600)
                        : null),
              ),
              if (anulado) ...[
                const SizedBox(width: 8),
                const Text('ANULADO',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.bold)),
              ],
            ],
          ),
          // El flujo "🎯 origen ➡️ 🎯 destino" es el MISMO que usa el Kardex
          // de Inventario (util/movimiento_fmt.dart). Antes aquí solo salía
          // el centro de origen y el destino no aparecía por ninguna parte.
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                flujoMovimiento(
                  tipo: m.tipo,
                  bodega: m.bodega ?? widget.bodegaNombre,
                  centroCosto: m.centroCosto,
                  centroCostoDestino: m.centroCostoDestino,
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                [
                  _cuando(m.fecha),
                  if (m.valor != null) _money.format(m.valor!),
                  if (m.usuarioEmail != null) m.usuarioEmail!,
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              if (m.observacion != null && m.observacion!.isNotEmpty)
                Text('📝 ${m.observacion!}',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, fontSize: 11.5)),
            ],
          ),
          isThreeLine: true,
          trailing: (widget.esAdmin && !anulado && !m.esAnulacion)
              ? IconButton(
                  icon: const Icon(Icons.block),
                  tooltip: 'Anular',
                  onPressed: () => _anular(m),
                )
              : null,
        );
      },
    );
  }
}
