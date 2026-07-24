import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data.dart';
import '../reportes.dart';
import '../util/tiempo.dart';

final _qty = NumberFormat.decimalPattern('es_CO');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

/// Fondo amarillo MUY tenue: distingue visualmente el módulo de
/// Aprovechamientos del inventario oficial. Un toque más fuerte para barras.
const _fondoAprov = Color(0xFFFFFDF2);
final _barraAprov = Colors.amber.shade50;

/// Orden paramétrico de las listas de aprovechamientos (se recuerda por usuario).
enum _OrdenAprov { reciente, antiguo, nombre, saldo }

const _ordenLabels = {
  _OrdenAprov.reciente: 'Más reciente',
  _OrdenAprov.antiguo: 'Más antiguo',
  _OrdenAprov.nombre: 'Nombre (A–Z)',
  _OrdenAprov.saldo: 'Mayor saldo',
};
const _ordenPrefKey = 'aprov_orden';

/// Inventario paralelo de TROZOS/RETAZOS aprovechables, valorizados a $0.
/// No toca el inventario oficial. Reusa catálogo, bodegas y centros de costo.
class AprovechamientosPage extends StatefulWidget {
  const AprovechamientosPage({super.key});
  @override
  State<AprovechamientosPage> createState() => _AprovechamientosPageState();
}

class _AprovechamientosPageState extends State<AprovechamientosPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  late final TabController _tab;
  List<TrozoResumen> _resumen = [];
  List<Trozo> _historico = [];
  bool _cargando = false;
  bool _puedeEntrada = false;
  bool _puedeExportar = false;
  bool _mostrarSaldoCero = false; // en "Por elemento", ocultar saldo 0 por defecto
  String? _trozoExpandido; // id del trozo desplegado inline en la pestaña Histórico
  _OrdenAprov _orden = _OrdenAprov.reciente;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      // Al cambiar de pestaña, limpiar el buscador (cada pestaña arranca fresca).
      if (_tab.indexIsChanging && _ctrl.text.isNotEmpty) {
        setState(() => _ctrl.clear());
      }
    });
    _cargar();
    InventarioService.revision.addListener(_cargar);
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() {
          _puedeEntrada = r.contains(Roles.admin) || r.contains(Roles.operarioMas);
          _puedeExportar = r.contains(Roles.admin) ||
              r.contains(Roles.coordinador) || r.contains(Roles.exportar);
        });
      }
    });
    // Recupera el orden que el usuario dejó guardado.
    SharedPreferences.getInstance().then((p) {
      final s = p.getString(_ordenPrefKey);
      if (s != null && mounted) {
        setState(() => _orden = _OrdenAprov.values
            .firstWhere((e) => e.name == s, orElse: () => _OrdenAprov.reciente));
      }
    });
  }

  Future<void> _setOrden(_OrdenAprov o) async {
    setState(() => _orden = o);
    final p = await SharedPreferences.getInstance();
    await p.setString(_ordenPrefKey, o.name);
  }

  List<TrozoResumen> _ordenarResumen(List<TrozoResumen> l) {
    final out = [...l];
    final cero = DateTime.fromMillisecondsSinceEpoch(0);
    switch (_orden) {
      case _OrdenAprov.reciente:
        out.sort((a, b) =>
            (b.ultimaCreacion ?? cero).compareTo(a.ultimaCreacion ?? cero));
      case _OrdenAprov.antiguo:
        out.sort((a, b) =>
            (a.ultimaCreacion ?? cero).compareTo(b.ultimaCreacion ?? cero));
      case _OrdenAprov.nombre:
        out.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      case _OrdenAprov.saldo:
        out.sort((a, b) => b.totalDisp.compareTo(a.totalDisp));
    }
    return out;
  }

  List<Trozo> _ordenarTrozos(List<Trozo> l) {
    final out = [...l];
    final cero = DateTime.fromMillisecondsSinceEpoch(0);
    switch (_orden) {
      case _OrdenAprov.reciente:
        out.sort((a, b) => (b.creadoEn ?? cero).compareTo(a.creadoEn ?? cero));
      case _OrdenAprov.antiguo:
        out.sort((a, b) => (a.creadoEn ?? cero).compareTo(b.creadoEn ?? cero));
      case _OrdenAprov.nombre:
        out.sort((a, b) =>
            a.elementoNombre.toLowerCase().compareTo(b.elementoNombre.toLowerCase()));
      case _OrdenAprov.saldo:
        out.sort((a, b) => b.longitudActual.compareTo(a.longitudActual));
    }
    return out;
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_cargar);
    _tab.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await InventarioService.aprovechamientosResumen();
      final h = await InventarioService.todosLosTrozos();
      if (mounted) setState(() { _resumen = r; _historico = h; });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<TrozoResumen> get _resumenFiltrado {
    final q = _ctrl.text.trim().toLowerCase();
    final base = q.isEmpty
        ? _resumen
        : _resumen.where((t) => t.nombre.toLowerCase().contains(q)).toList();
    return _ordenarResumen(base);
  }

  List<Trozo> get _historicoFiltrado {
    final q = _ctrl.text.trim().toLowerCase();
    final base = q.isEmpty
        ? _historico
        : _historico.where((t) => t.elementoNombre.toLowerCase().contains(q)).toList();
    return _ordenarTrozos(base);
  }

  Future<void> _exportar() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: ahora.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
          start: ahora.subtract(const Duration(days: 30)), end: ahora),
      helpText: 'Movimientos de aprovechamientos: rango de fechas',
    );
    if (rango == null) return;
    try {
      await Reportes.movimientosAprovechamientos(rango.start, rango.end);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✓ Exportado (revisa tus descargas)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }

  Future<void> _ingresar([TrozoResumen? pre]) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IngresarTrozoSheet(
        elementoId: pre?.elementoId,
        nombre: pre?.nombre,
        unidad: pre?.unidad,
      ),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _fondoAprov,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: _barraAprov,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.content_cut, size: 18, color: Colors.brown.shade400),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Trozos aprovechables · valorizados a \$0 · '
                    'no afectan el inventario oficial',
                    style: TextStyle(fontSize: 12, color: Colors.brown.shade400)),
              ),
              if (_puedeExportar)
                IconButton(
                  icon: Icon(Icons.file_download, size: 20,
                      color: Colors.brown.shade400),
                  tooltip: 'Exportar movimientos por fecha',
                  visualDensity: VisualDensity.compact,
                  onPressed: _exportar,
                ),
            ]),
          ),
          TabBar(controller: _tab, tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Por elemento'),
            Tab(icon: Icon(Icons.history), text: 'Histórico'),
          ]),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar elemento…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _puedeEntrada
                    ? IconButton(
                        icon: const Icon(Icons.add_box, color: Colors.teal),
                        tooltip: 'Ingresar trozo',
                        onPressed: () => _ingresar(),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
            child: Row(children: [
              Icon(Icons.sort, size: 18, color: Colors.brown.shade400),
              const SizedBox(width: 6),
              const Text('Ordenar por:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<_OrdenAprov>(
                value: _orden,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: _OrdenAprov.values
                    .map((o) => DropdownMenuItem(value: o,
                        child: Text(_ordenLabels[o]!,
                            style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (o) { if (o != null) _setOrden(o); },
              ),
            ]),
          ),
          if (_cargando) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              _porElemento(),
              _historicoLista(),
            ]),
          ),
        ],
      ),
    );
  }

  /// Pestaña "Por elemento": elementos con sus trozos disponibles.
  Widget _porElemento() {
    // Por defecto solo con saldo; el check muestra también los de saldo 0.
    final items = _resumenFiltrado
        .where((t) => _mostrarSaldoCero || t.disponibles > 0)
        .toList();
    return Column(children: [
      CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        value: _mostrarSaldoCero,
        onChanged: (v) => setState(() => _mostrarSaldoCero = v ?? false),
        title: const Text('Mostrar los que tienen saldo 0',
            style: TextStyle(fontSize: 13)),
      ),
      const Divider(height: 1),
      Expanded(
        child: items.isEmpty && !_cargando
            ? Center(child: Text(_mostrarSaldoCero
                ? 'Sin trozos registrados'
                : 'Sin trozos con saldo disponible'))
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = items[i];
        final hayDisp = t.disponibles > 0;
        final consumidos = t.totalTrozos - t.disponibles;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                hayDisp ? Colors.blueGrey.shade100 : Colors.grey.shade300,
            child: Text('${t.disponibles}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                    color: hayDisp ? Colors.black : Colors.grey)),
          ),
          title: Text(t.nombre,
              style: TextStyle(color: hayDisp ? null : Colors.grey)),
          subtitle: Text(hayDisp
              ? '${t.disponibles} trozo${t.disponibles == 1 ? '' : 's'} · '
                  '${_qty.format(t.totalDisp)} ${t.unidad} disponibles'
                  '${consumidos > 0 ? '  ·  $consumidos en histórico' : ''}'
              : 'Sin saldo · ${t.totalTrozos} en histórico'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => TrozosElementoPage(
                    elementoId: t.elementoId, nombre: t.nombre,
                    unidad: t.unidad)));
            _cargar();
          },
        );
                },
              ),
      ),
    ]);
  }

  /// Pestaña "Histórico": TODOS los trozos (incluidos saldo 0), planos.
  /// Cada trozo se despliega/contrae en el sitio (Expand/Collapse): así se ve
  /// la trazabilidad sin salir del módulo ni perder la posición en la lista.
  Widget _historicoLista() {
    final items = _historicoFiltrado;
    if (items.isEmpty && !_cargando) {
      return const Center(child: Text('Aún no hay trozos registrados'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = items[i];
        final abierto = _trozoExpandido == t.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(Icons.content_cut,
                  color: t.disponible ? Colors.blueGrey : Colors.grey),
              title: Text(t.elementoNombre,
                  style: TextStyle(color: t.disponible ? null : Colors.grey)),
              subtitle: Text([
                t.disponible
                    ? 'Disponible: ${_qty.format(t.longitudActual)} ${t.unidad}'
                        '${t.parcial ? ' (de ${_qty.format(t.longitud)})' : ''}'
                    : 'Consumido · era de ${_qty.format(t.longitud)} ${t.unidad}',
                if (t.bodega != null) '📍 ${t.bodega}',
                if (t.creadoEn != null) _fechaHora.format(horaColombia(t.creadoEn!)),
              ].join(' · '), style: const TextStyle(fontSize: 12)),
              trailing: Icon(abierto ? Icons.expand_less : Icons.expand_more,
                  color: Colors.brown.shade400),
              onTap: () =>
                  setState(() => _trozoExpandido = abierto ? null : t.id),
            ),
            if (abierto)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _barraAprov,
                  border: Border(
                      left: BorderSide(color: Colors.brown.shade200, width: 3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TrozoTrazaView(trozo: t, unidad: t.unidad),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _trozoExpandido = null),
                          icon: const Icon(Icons.unfold_less, size: 18),
                          label: const Text('Contraer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Trozos de un elemento: ver, usar (consumir completo) e ingresar.
class TrozosElementoPage extends StatefulWidget {
  final String elementoId;
  final String nombre;
  final String unidad;
  const TrozosElementoPage(
      {super.key, required this.elementoId, required this.nombre,
      required this.unidad});
  @override
  State<TrozosElementoPage> createState() => _TrozosElementoPageState();
}

class _TrozosElementoPageState extends State<TrozosElementoPage> {
  List<Trozo> _todos = [];
  bool _cargando = false;
  bool _puedeEntrada = false, _puedeSalida = false, _puedeBorrar = false;

  List<Trozo> get _disponibles => _todos.where((t) => t.disponible).toList();

  @override
  void initState() {
    super.initState();
    _cargar();
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() {
          _puedeEntrada = r.contains(Roles.admin) || r.contains(Roles.operarioMas);
          _puedeSalida = r.contains(Roles.admin) || r.contains(Roles.operarioMenos);
          _puedeBorrar = r.contains(Roles.admin) || r.contains(Roles.coordinador);
        });
      }
    });
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      // Trae TODOS (incluye consumidos) para la pestaña de histórico.
      final t = await InventarioService.trozosDeElemento(
          widget.elementoId, soloDisponibles: false);
      if (mounted) setState(() => _todos = t);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _verHistorial(Trozo t) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => TrozoHistorialPage(trozo: t, unidad: widget.unidad)));
  }

  Future<void> _usar(Trozo t) async {
    final centros = await InventarioService.centrosCosto();
    if (!mounted) return;
    CentroCosto? cc;
    final obs = TextEditingController();
    final cant = TextEditingController(text: t.longitudActual.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text('Usar del trozo · quedan '
            '${_qty.format(t.longitudActual)} ${widget.unidad}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: cant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Cantidad a usar (${widget.unidad})',
                helperText: 'Puede ser parcial; el resto queda disponible',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<CentroCosto>(
            initialValue: cc,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Centro de costo', border: OutlineInputBorder()),
            items: centros.map((c) => DropdownMenuItem(value: c,
                child: Text(c.etiqueta, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setD(() => cc = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: obs, decoration: const InputDecoration(
              labelText: 'Observación (opcional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Usar')),
        ],
      )),
    );
    if (ok != true) return;
    final c = num.tryParse(cant.text.replaceAll(',', '.'));
    if (c == null || c <= 0) {
      _snack('Cantidad inválida');
      return;
    }
    if (c > t.longitudActual) {
      _snack('No puedes usar más de lo que queda '
          '(${_qty.format(t.longitudActual)} ${widget.unidad})');
      return;
    }
    try {
      await InventarioService.sacarDeTrozo(t.id,
          cantidad: c, centroCostoId: cc?.id, observacion: obs.text);
      final resto = t.longitudActual - c;
      _snack(resto > 0
          ? '✓ Usaste ${_qty.format(c)} ${widget.unidad}; '
              'quedan ${_qty.format(resto)}'
          : '✓ Trozo consumido por completo');
      _cargar();
    } catch (e) {
      _snack('Error: ${e.toString().replaceAll('PostgrestException(message: ', '')}');
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _borrar(Trozo t) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Borrar trozo'),
      content: Text('¿Borrar este trozo de ${_qty.format(t.longitud)} '
          '${widget.unidad}? (corrección, no queda historial)'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
      ],
    ));
    if (ok != true) return;
    await InventarioService.borrarTrozo(t.id);
    _cargar();
  }

  Future<void> _ingresar() async {
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      builder: (_) => _IngresarTrozoSheet(
          elementoId: widget.elementoId, nombre: widget.nombre,
          unidad: widget.unidad),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _fondoAprov,
        appBar: AppBar(
          backgroundColor: _barraAprov,
          title: Text(widget.nombre),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.content_cut), text: 'Disponibles'),
            Tab(icon: Icon(Icons.history), text: 'Histórico'),
          ]),
        ),
        floatingActionButton: _puedeEntrada
            ? FloatingActionButton.extended(
                onPressed: _ingresar,
                icon: const Icon(Icons.add),
                label: const Text('Ingresar trozo'))
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _lista(_disponibles, historico: false),
                _lista(_todos, historico: true),
              ]),
      ),
    );
  }

  Widget _lista(List<Trozo> items, {required bool historico}) {
    if (items.isEmpty) {
      return Center(child: Text(historico
          ? 'Aún no hay trozos registrados'
          : 'No hay trozos disponibles'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = items[i];
        final consumido = !t.disponible;
        return ListTile(
          leading: Icon(Icons.content_cut,
              color: consumido ? Colors.grey : Colors.blueGrey),
          title: Text(
              historico && consumido
                  ? 'Consumido · era de ${_qty.format(t.longitud)} ${widget.unidad}'
                  : '${_qty.format(t.longitudActual)} ${widget.unidad}'
                      '${t.parcial ? '  (de ${_qty.format(t.longitud)})' : ''}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: consumido ? Colors.grey : null)),
          subtitle: Text([
            if (!consumido && t.parcial) 'usado en parte',
            if (t.bodega != null) '📍 ${t.bodega}',
            if (t.observacion != null && t.observacion!.isNotEmpty) t.observacion!,
            'ver historial ⟶',
          ].join(' · '), style: const TextStyle(fontSize: 12)),
          trailing: (!historico && (_puedeSalida || _puedeBorrar))
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_puedeSalida)
                    TextButton(onPressed: () => _usar(t), child: const Text('Usar')),
                  if (_puedeBorrar)
                    IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: Colors.red),
                        tooltip: 'Borrar',
                        onPressed: () => _borrar(t)),
                ])
              : const Icon(Icons.chevron_right),
          onTap: () => _verHistorial(t),
        );
      },
    );
  }
}

/// Contenido de trazabilidad de un trozo (Card + línea de tiempo con saldo
/// corriente). Reutilizable: como página propia (TrozoHistorialPage) o
/// desplegado inline dentro de la lista de Histórico (Expand/Collapse).
class _TrozoTrazaView extends StatefulWidget {
  final Trozo trozo;
  final String unidad;
  const _TrozoTrazaView({required this.trozo, required this.unidad});
  @override
  State<_TrozoTrazaView> createState() => _TrozoTrazaViewState();
}

class _TrozoTrazaViewState extends State<_TrozoTrazaView> {
  late Future<List<SalidaTrozo>> _future;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.salidasDeTrozo(widget.trozo.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trozo;
    final u = widget.unidad;
    return FutureBuilder<List<SalidaTrozo>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final salidas = snap.data ?? [];
        // Saldo corriendo: arranca en la longitud inicial y va bajando.
        num saldo = t.longitud;
        final pasos = <Widget>[];
        pasos.add(_eventoTrozo(
          icono: Icons.add_circle, color: Colors.green,
          titulo: 'Ingreso · +${_qty.format(t.longitud)} $u',
          detalle: [
            if (t.creadoEmail != null) 'por ${t.creadoEmail}',
            if (t.creadoEn != null) _fechaHora.format(horaColombia(t.creadoEn!)),
            if (t.bodega != null) '📍 ${t.bodega}',
          ].join(' · '),
          saldo: 'Saldo: ${_qty.format(saldo)} $u',
        ));
        for (final s in salidas) {
          saldo -= s.cantidad;
          pasos.add(_eventoTrozo(
            icono: Icons.remove_circle, color: Colors.orange,
            titulo: 'Salida · −${_qty.format(s.cantidad)} $u  →  '
                '${s.centroCosto ?? 'sin centro de costo'}',
            detalle: [
              if (s.usuarioEmail != null) 'por ${s.usuarioEmail}',
              _fechaHora.format(horaColombia(s.fecha)),
              if (s.observacion != null && s.observacion!.isNotEmpty) s.observacion!,
            ].join(' · '),
            saldo: 'Saldo: ${_qty.format(saldo < 0 ? 0 : saldo)} $u',
          ));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.elementoNombre,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('Longitud inicial: ${_qty.format(t.longitud)} $u'),
                    Text('Disponible ahora: ${_qty.format(t.longitudActual)} $u'
                        '${t.disponible ? '' : '  ·  CONSUMIDO'}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.disponible ? Colors.teal : Colors.grey)),
                    Text('Salidas registradas: ${salidas.length}'),
                  ]),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Trazabilidad (más reciente primero)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            // El saldo de cada línea se calcula en orden cronológico, pero se
            // muestra invertido: primero lo más reciente, al final el ingreso.
            ...pasos.reversed,
          ],
        );
      },
    );
  }
}

Widget _eventoTrozo({required IconData icono, required Color color,
    required String titulo, required String detalle, required String saldo}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icono, color: color, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (detalle.isNotEmpty)
            Text(detalle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(saldo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
    ]),
  );
}

/// Trazabilidad de un trozo como página propia: se abre al entrar desde la
/// lista de un elemento (TrozosElementoPage). En la pestaña Histórico del
/// módulo la misma trazabilidad se muestra embebida (Expand/Collapse).
class TrozoHistorialPage extends StatelessWidget {
  final Trozo trozo;
  final String unidad;
  const TrozoHistorialPage({super.key, required this.trozo, required this.unidad});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondoAprov,
      appBar: AppBar(
          backgroundColor: _barraAprov,
          title: const Text('Historial del trozo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _TrozoTrazaView(trozo: trozo, unidad: unidad),
      ),
    );
  }
}

/// Hoja para ingresar un trozo (entrada). Si no viene elemento, permite elegirlo.
class _IngresarTrozoSheet extends StatefulWidget {
  final String? elementoId;
  final String? nombre;
  final String? unidad;
  const _IngresarTrozoSheet({this.elementoId, this.nombre, this.unidad});
  @override
  State<_IngresarTrozoSheet> createState() => _IngresarTrozoSheetState();
}

class _IngresarTrozoSheetState extends State<_IngresarTrozoSheet> {
  String? _elementoId;
  String? _nombre;
  String _unidad = 'UND';
  final _longitud = TextEditingController();
  final _obs = TextEditingController();
  List<Bodega> _bodegas = [];
  Bodega? _bodega;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _elementoId = widget.elementoId;
    _nombre = widget.nombre;
    _unidad = widget.unidad ?? 'UND';
    InventarioService.bodegas().then((b) {
      if (mounted) setState(() { _bodegas = b; if (b.length == 1) _bodega = b.first; });
    });
  }

  Future<void> _elegirElemento() async {
    final sel = await showModalBottomSheet<Elemento>(
      context: context, isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel != null) {
      setState(() { _elementoId = sel.id; _nombre = sel.nombre; _unidad = sel.unidad; });
    }
  }

  Future<void> _guardar() async {
    final l = num.tryParse(_longitud.text.replaceAll(',', '.'));
    if (_elementoId == null) return _msg('Elige el elemento');
    if (l == null || l <= 0) return _msg('Longitud inválida');
    setState(() => _guardando = true);
    try {
      await InventarioService.ingresarTrozo(
        elementoId: _elementoId!,
        longitud: l,
        bodegaId: _bodega?.id,
        observacion: _obs.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _msg('Error: $e');
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ingresar trozo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2),
              title: Text(_nombre ?? 'Elegir elemento…'),
              subtitle: _nombre == null ? null : Text('Unidad: $_unidad'),
              trailing: const Icon(Icons.search),
              onTap: _elegirElemento,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _longitud,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Longitud del trozo ($_unidad)',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Bodega>(
            initialValue: _bodega,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Ubicación (rack/bodega)',
                border: OutlineInputBorder(), prefixIcon: Icon(Icons.warehouse)),
            items: _bodegas.map((b) => DropdownMenuItem(value: b,
                child: Text(b.nombre, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _bodega = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _obs, decoration: const InputDecoration(
              labelText: 'Observación (opcional)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Guardar trozo'),
          )),
        ]),
    );
  }
}

/// Buscador de elementos reutilizable.
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
              controller: _ctrl, autofocus: true, onChanged: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar elemento…',
                  prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text('Unidad: ${e.unidad}'),
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
