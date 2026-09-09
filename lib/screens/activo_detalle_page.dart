import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../activos_service.dart';
import '../util/tiempo.dart';
import '../widgets/campo_obligatorio.dart';
import 'activo_movimiento_page.dart';

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
  const ActivoDetallePage({super.key, required this.activoId});
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(a.serial, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Ficha'),
              Tab(text: 'Piezas'),
              Tab(text: 'Mantenimiento'),
              Tab(text: 'Movimientos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Ficha(
              activo: a,
              ubicacion: _ubicacion,
              onCambio: _cargar,
            ),
            _Piezas(activoId: a.id),
            _Mantenimientos(activoId: a.id),
            _Movimientos(activoId: a.id, esAdmin: _admin, onCambio: _cargar),
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
  final Future<void> Function() onCambio;
  const _Ficha({
    required this.activo,
    required this.ubicacion,
    required this.onCambio,
  });

  Color _colorEstado(String estado) => switch (estado) {
    'operativo' => Colors.green.shade700,
    'entregado' => Colors.blueGrey,
    'baja' => Colors.red.shade700,
    _ => Colors.orange.shade800,
  };

  /// Solo un equipo disponible o entregado puede tener un movimiento real.
  /// En mantenimiento o de baja, lo que corresponde son otras acciones.
  bool get _permiteMovimiento =>
      activo.estado == 'operativo' || activo.estado == 'entregado';

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
                      label: Text(activo.estadoEtiqueta),
                      backgroundColor:
                          _colorEstado(activo.estado).withValues(alpha: 0.15),
                      side: BorderSide(color: _colorEstado(activo.estado)),
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
          _fila('Valor a nuevo', '\$${activo.valorNuevo.toStringAsFixed(2)}'),
          _fila('Porcentaje', '${activo.porcentajeValor}%'),
          _fila('Valor actual', '\$${activo.valorActual.toStringAsFixed(2)}',
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
        const Text(
          'Cambiar la ubicación NO afecta el inventario: el equipo sigue '
          'contando como nuestro aunque esté en un taller.',
          style: TextStyle(fontSize: 11.5, color: Colors.grey),
        ),
        const SizedBox(height: 12),
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
        if (activo.estado != 'entregado')
          OutlinedButton.icon(
            onPressed: () async {
              final cambio = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _HojaEstado(activo: activo),
              );
              if (cambio == true) await onCambio();
            },
            icon: const Icon(Icons.tune),
            label: const Text('Cambiar estado o condición'),
          ),

        if (activo.observacion != null && activo.observacion!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _bloque(context, 'Observación', [Text(activo.observacion!)]),
        ],

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
class _HojaEstado extends StatefulWidget {
  final Activo activo;
  const _HojaEstado({required this.activo});
  @override
  State<_HojaEstado> createState() => _HojaEstadoState();
}

class _HojaEstadoState extends State<_HojaEstado> {
  late String _estado;
  late String _condicion;
  late final TextEditingController _actor;
  bool _guardando = false;

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
  }

  @override
  void dispose() {
    _actor.dispose();
    super.dispose();
  }

  bool get _faltaTaller =>
      _estado == 'mantenimiento_externo' && _actor.text.trim().isEmpty;

  Future<void> _guardar() async {
    if (_faltaTaller) {
      setState(() {});
      return;
    }
    setState(() => _guardando = true);
    try {
      if (_estado != widget.activo.estado ||
          _actor.text.trim() != (widget.activo.mantenimientoActor ?? '')) {
        await ActivosService.cambiarEstado(
          widget.activo.id,
          estado: _estado,
          mantenimientoActor:
              _actor.text.trim().isEmpty ? null : _actor.text.trim(),
        );
      }
      if (_condicion != widget.activo.condicion) {
        await ActivosService.cambiarCondicion(widget.activo.id, _condicion);
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
            Text('Estado y condición',
                style: Theme.of(context).textTheme.titleLarge),
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
              TextField(
                controller: _actor,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: marcarError(
                  const InputDecoration(
                    labelText: '¿En qué taller está? *',
                    hintText: 'Ej: TALLER DE LUCHO',
                    border: OutlineInputBorder(),
                  ),
                  _faltaTaller,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Si además quieres dejar registrado el movimiento físico, '
                'usa "Cambiar ubicación" en la ficha.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
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
      final t = await ActivosService.terceros(limit: 200);
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

  Future<void> _guardar() async {
    if (_enBodega && _bodega == null) return;
    if (!_enBodega && _tercero == null) return;
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
                  Text('Cambiar ubicación',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text(
                    'No afecta el inventario: el equipo sigue siendo nuestro.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
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
                  else if (_terceros.isEmpty)
                    const Text(
                      'No hay terceros registrados. Créalos desde el menú '
                      '"Terceros" del módulo.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    DropdownButtonFormField<ActivoTercero>(
                      initialValue: _tercero,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Tercero', border: OutlineInputBorder()),
                      items: _terceros
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.nombre,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _tercero = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detalle,
                    decoration: const InputDecoration(
                      labelText: 'Detalle',
                      hintText: 'Ej: en reparación del impulsor',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
            Text('Historial de ubicaciones',
                style: Theme.of(context).textTheme.titleLarge),
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
                          : Text('\$${m.costo.toStringAsFixed(2)}'),
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
        costo: num.tryParse(_costo.text.replaceAll(',', '.')) ?? 0,
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
            Text('Registrar mantenimiento',
                style: Theme.of(context).textTheme.titleLarge),
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
              decoration: const InputDecoration(
                  labelText: 'Costo',
                  prefixText: '\$ ',
                  border: OutlineInputBorder()),
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
  final bool esAdmin;
  final Future<void> Function() onCambio;
  const _Movimientos({
    required this.activoId,
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
        final etiqueta = switch (m.tipo) {
          'entrada' => 'Entrada',
          'salida' => 'Salida',
          _ => 'Anulación',
        };
        return ListTile(
          leading: Icon(switch (m.tipo) {
            'entrada' => Icons.download,
            'salida' => Icons.upload,
            _ => Icons.undo,
          }),
          title: Row(
            children: [
              Text(etiqueta),
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
          subtitle: Text([
            _cuando(m.fecha),
            if (m.centroCosto != null) m.centroCosto!,
            if (m.bodega != null) m.bodega!,
            if (m.valor != null) '\$${m.valor!.toStringAsFixed(2)}',
            if (m.usuarioEmail != null) m.usuarioEmail!,
            if (m.observacion != null && m.observacion!.isNotEmpty)
              m.observacion!,
          ].join(' · ')),
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
