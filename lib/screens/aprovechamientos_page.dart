import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';

final _qty = NumberFormat.decimalPattern('es_CO');

/// Inventario paralelo de TROZOS/RETAZOS aprovechables, valorizados a $0.
/// No toca el inventario oficial. Reusa catálogo, bodegas y centros de costo.
class AprovechamientosPage extends StatefulWidget {
  const AprovechamientosPage({super.key});
  @override
  State<AprovechamientosPage> createState() => _AprovechamientosPageState();
}

class _AprovechamientosPageState extends State<AprovechamientosPage> {
  final _ctrl = TextEditingController();
  List<TrozoResumen> _todos = [];
  bool _cargando = false;
  bool _puedeEntrada = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    InventarioService.revision.addListener(_cargar);
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() => _puedeEntrada =
            r.contains(Roles.admin) || r.contains(Roles.operarioMas));
      }
    });
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_cargar);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await InventarioService.aprovechamientosResumen();
      if (mounted) setState(() => _todos = r);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<TrozoResumen> get _filtrados {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return _todos;
    return _todos.where((t) => t.nombre.toLowerCase().contains(q)).toList();
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
    final items = _filtrados;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.blueGrey.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: const [
            Icon(Icons.content_cut, size: 18, color: Colors.blueGrey),
            SizedBox(width: 8),
            Expanded(
              child: Text('Trozos aprovechables · valorizados a \$0 · '
                  'no afectan el inventario oficial',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar elemento con trozos…',
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
        if (_cargando) const LinearProgressIndicator(),
        Expanded(
          child: items.isEmpty && !_cargando
              ? const Center(child: Text('Sin trozos registrados'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blueGrey.shade100,
                        child: Text('${t.cantidad}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                      title: Text(t.nombre),
                      subtitle: Text('${t.cantidad} '
                          'trozo${t.cantidad == 1 ? '' : 's'} · '
                          '${_qty.format(t.total)} ${t.unidad} en total'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => TrozosElementoPage(
                                elementoId: t.elementoId,
                                nombre: t.nombre,
                                unidad: t.unidad)));
                        _cargar();
                      },
                    );
                  },
                ),
        ),
      ],
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
  List<Trozo> _trozos = [];
  bool _cargando = false;
  bool _puedeEntrada = false, _puedeSalida = false, _puedeBorrar = false;

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
      final t = await InventarioService.trozosDeElemento(widget.elementoId);
      if (mounted) setState(() => _trozos = t);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      floatingActionButton: _puedeEntrada
          ? FloatingActionButton.extended(
              onPressed: _ingresar,
              icon: const Icon(Icons.add),
              label: const Text('Ingresar trozo'))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _trozos.isEmpty
              ? const Center(child: Text('No hay trozos disponibles'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _trozos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _trozos[i];
                    return ListTile(
                      leading: const Icon(Icons.content_cut, color: Colors.blueGrey),
                      title: Text(
                          '${_qty.format(t.longitudActual)} ${widget.unidad}'
                          '${t.parcial ? '  (de ${_qty.format(t.longitud)})' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text([
                        if (t.parcial) 'usado en parte',
                        if (t.bodega != null) '📍 ${t.bodega}',
                        if (t.observacion != null && t.observacion!.isNotEmpty)
                          t.observacion!,
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_puedeSalida)
                          TextButton(onPressed: () => _usar(t),
                              child: const Text('Usar')),
                        if (_puedeBorrar)
                          IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              tooltip: 'Borrar',
                              onPressed: () => _borrar(t)),
                      ]),
                    );
                  },
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
