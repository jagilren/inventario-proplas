import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'editar_elemento_page.dart';
import 'historial_page.dart';
import '../widgets/imagen_elemento.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _fecha = DateFormat('dd/MM/yyyy');

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
  List<ImagenElem> _fotos = [];
  late Future<List<MovKardex>> _future;

  @override
  void initState() {
    super.initState();
    _elemento = widget.elemento;
    _future = InventarioService.kardex(_elemento.id);
    _cargarFotos();
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

  Future<void> _recargar() async {
    // vuelve a leer existencia/costo actualizados
    final actualizado = await InventarioService.buscar(_elemento.nombre);
    final match = actualizado.where((e) => e.id == _elemento.id);
    setState(() {
      if (match.isNotEmpty) _elemento = match.first;
      _future = InventarioService.kardex(_elemento.id);
    });
    await _cargarFotos();
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
                ],
              ),
            ),
          ),
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
                      subtitle: Text([
                        _fecha.format(m.fecha),
                        if (m.costoUnitario != null) _money.format(m.costoUnitario),
                        if (m.centroCosto != null) m.centroCosto!,
                        if (m.referencia != null) m.referencia!,
                      ].join(' · ')),
                      trailing: (_esAdmin && !m.esAnulacion)
                          ? IconButton(
                              icon: const Icon(Icons.block, size: 20, color: Colors.red),
                              tooltip: 'Anular',
                              onPressed: () => _anular(m),
                            )
                          : null,
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
