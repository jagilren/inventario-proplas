import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'editar_elemento_page.dart';
import 'serializar_page.dart';
import 'historial_page.dart';
import '../widgets/imagen_elemento.dart';
import '../util/tiempo.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _fecha = DateFormat('dd/MM/yyyy');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

class KardexPage extends StatefulWidget {
  final Elemento elemento;
  const KardexPage({super.key, required this.elemento});
  @override
  State<KardexPage> createState() => _KardexPageState();
}

class _KardexPageState extends State<KardexPage> {
  late Elemento _elemento;
  bool _esAdmin = false;
  bool _puedeEditar = false;
  final String? _uid = InventarioService.miUid;
  List<ImagenElem> _fotos = [];
  List<ExistenciaBodega> _porBodega = [];
  List<Serie> _series = [];
  late Future<List<MovKardex>> _future;

  @override
  void initState() {
    super.initState();
    _elemento = widget.elemento;
    _future = InventarioService.kardex(_elemento.id);
    _cargarFotos();
    _cargarBodegas();
    if (_elemento.serializado) _cargarSeries();
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() {
          _esAdmin = r.contains(Roles.admin);
          _puedeEditar = _esAdmin || r.contains(Roles.coordinador);
        });
      }
    });
  }

  Future<void> _cargarFotos() async {
    try {
      final f = await InventarioService.imagenesElemento(_elemento.id);
      if (mounted) setState(() => _fotos = f);
    } catch (_) {
      // sin fotos o sin red: la pantalla sigue funcionando igual
    }
  }

  Future<void> _cargarBodegas() async {
    try {
      final b = await InventarioService.existenciasPorBodega(_elemento.id);
      if (mounted) setState(() => _porBodega = b);
    } catch (_) {
      // sin red: se muestra solo el total
    }
  }

  Future<void> _cargarSeries() async {
    try {
      final s = await InventarioService.seriesDeElemento(_elemento.id);
      if (mounted) setState(() => _series = s);
    } catch (_) {}
  }

  Future<void> _recargar() async {
    // vuelve a leer existencia/costo actualizados
    final actualizado = await InventarioService.buscar(_elemento.nombre);
    final match = actualizado.where((e) => e.id == _elemento.id);
    setState(() {
      if (match.isNotEmpty) _elemento = match.first;
      _future = InventarioService.kardex(_elemento.id);
    });
    await _cargarFotos();
    await _cargarBodegas();
    if (_elemento.serializado) await _cargarSeries();
  }

  Color _color(String tipo) => switch (tipo) {
        'salida' => Colors.orange,
        'inicial' => Colors.blue,
        'ajuste' => Colors.purple,
        _ => Colors.green,
      };

  Future<void> _anular(MovKardex m) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular movimiento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${m.tipo.toUpperCase()} · ${m.cantidad} ${_elemento.unidad}\n'
              'Se creará una reversa que compensa este movimiento. '
              'Nada se borra; queda en el historial.'),
          const SizedBox(height: 12),
          TextField(
            controller: motivoCtrl,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true || m.id == null) return;
    try {
      await InventarioService.anularMovimiento(m.id!, motivoCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✓ Movimiento anulado')));
      _recargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Detalle de un movimiento: ver/editar la observación y (a futuro) adjuntar.
  Future<void> _verDetalle(MovKardex m) async {
    final canEdit = m.id != null &&
        (_puedeEditar || (m.usuarioId != null && m.usuarioId == _uid));
    final ctrl = TextEditingController(text: m.observacion ?? '');
    bool guardando = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${m.tipo.toUpperCase()} · ${m.cantidad} ${_elemento.unidad}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text([
                _fechaHora.format(horaColombia(m.fecha)),
                if (m.bodega != null) m.bodega!,
                if (m.costoUnitario != null) _money.format(m.costoUnitario),
                if (m.centroCosto != null) m.centroCosto!,
              ].join(' · '), style: const TextStyle(color: Colors.grey)),
              const Divider(height: 24),
              TextField(
                controller: ctrl,
                enabled: canEdit,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Observación',
                  border: const OutlineInputBorder(),
                  helperText: canEdit
                      ? 'Puedes corregir la observación'
                      : 'Solo lectura (no eres admin, coordinador ni el autor)',
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: guardando ? null : () async {
                      setSheet(() => guardando = true);
                      try {
                        await InventarioService.editarObservacion(m.id!, ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _recargar();
                      } catch (e) {
                        setSheet(() => guardando = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                    icon: guardando
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Guardar observación'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _mensajeCreditos(ctx),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Adjuntar archivo (PDF/Excel)'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// La subida de adjuntos está deshabilitada para no gastar Storage.
  void _mensajeCreditos(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.savings, color: Colors.orange, size: 40),
        title: const Text('Función de pago'),
        content: const Text(
            'Te hacen falta créditos en SUPABASE para adjuntar archivos. '
            'Transfiere el billete para darte los permisos 💸'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _elemento;
    return Scaffold(
      appBar: AppBar(
        title: Text(e.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historial de cambios',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => HistorialPage(
                    tabla: 'elementos', registroId: e.id,
                    titulo: 'Historial · ${e.nombre}'))),
          ),
          if (_puedeEditar)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar elemento',
              onPressed: () async {
                final cambio = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => EditarElementoPage(elemento: e)));
                if (cambio == true) _recargar();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_fotos.isNotEmpty) ...[
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        itemCount: _fotos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => InkWell(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ImagenCompleta(
                                  url: _fotos[i].url, titulo: e.nombre))),
                          child: ImagenElemento(
                              url: _fotos[i].url, tamano: 140, radio: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('Existencia', '${e.existencia} ${e.unidad}'),
                      _stat('Costo prom.', _money.format(e.costoPromedio)),
                      _stat('Valorización',
                          _money.format(e.existencia * e.costoPromedio)),
                    ],
                  ),
                  if (_porBodega.isNotEmpty) ...[
                    const Divider(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Existencia por bodega',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8, runSpacing: 6,
                        children: _porBodega.map((x) => Chip(
                          avatar: const Icon(Icons.warehouse, size: 16),
                          label: Text('${x.bodega}: ${x.existencia} ${e.unidad}'),
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_elemento.serializado && _puedeEditar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(context, MaterialPageRoute(
                      builder: (_) => SerializarPage(elemento: _elemento)));
                  if (ok == true) _recargar();
                },
                icon: const Icon(Icons.tag),
                label: const Text('Convertir a serializado'),
              ),
            ),
          if (_elemento.serializado) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(alignment: Alignment.centerLeft,
                  child: Text('Seriales', style: TextStyle(fontWeight: FontWeight.bold))),
            ),
            SizedBox(
              height: 130,
              child: _series.isEmpty
                  ? const Center(child: Text('Sin seriales'))
                  : ListView(padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: _series.map((s) => ListTile(
                        dense: true,
                        leading: Icon(Icons.tag,
                            color: s.disponible ? Colors.green : Colors.grey),
                        title: Text(s.serial),
                        subtitle: Text('${s.bodega ?? '—'} · ${s.estado}'),
                        trailing: Text(_money.format(s.costo)),
                      )).toList()),
            ),
            const Divider(height: 1),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Kardex (movimientos)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MovKardex>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final movs = snap.data ?? [];
                if (movs.isEmpty) {
                  return const Center(child: Text('Sin movimientos'));
                }
                return ListView.separated(
                  itemCount: movs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = movs[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _color(m.tipo).withValues(alpha: 0.15),
                        child: Icon(
                          m.tipo == 'salida' ? Icons.upload : Icons.download,
                          color: _color(m.tipo), size: 20,
                        ),
                      ),
                      title: Text('${m.tipo.toUpperCase()} · '
                          '${m.cantidad} ${e.unidad}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text([
                            _fecha.format(horaColombia(m.fecha)),
                            if (m.bodega != null) m.bodega!,
                            if (m.costoUnitario != null) _money.format(m.costoUnitario),
                            if (m.centroCosto != null) m.centroCosto!,
                            if (m.referencia != null) m.referencia!,
                          ].join(' · ')),
                          if (m.observacion != null && m.observacion!.isNotEmpty)
                            Text('📝 ${m.observacion!}',
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic, fontSize: 12)),
                        ],
                      ),
                      trailing: (_esAdmin && !m.esAnulacion)
                          ? IconButton(
                              icon: const Icon(Icons.block, size: 20, color: Colors.red),
                              tooltip: 'Anular',
                              onPressed: () => _anular(m),
                            )
                          : const Icon(Icons.chevron_right, size: 18),
                      onTap: () => _verDetalle(m),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value, style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      );
}
