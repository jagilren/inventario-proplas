import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../util/tiempo.dart';

final _fmt = DateFormat('dd/MM/yyyy HH:mm');

Color _color(String accion) => switch (accion) {
      'INSERT' => Colors.green,
      'DELETE' => Colors.red,
      _ => Colors.blue,
    };

IconData _icono(String accion) => switch (accion) {
      'INSERT' => Icons.add_circle_outline,
      'DELETE' => Icons.delete_outline,
      _ => Icons.edit_outlined,
    };

/// Etiqueta amable del tipo de registro auditado.
String _tablaLabel(String? t) => switch (t) {
      'movimientos' => 'Movimiento',
      'elementos' => 'Elemento',
      'bodegas' => 'Bodega',
      'centros_costo' => 'Centro de costo',
      'usuario_roles' => 'Usuario',
      'aprovechamiento_trozos' => 'Aprovechamiento',
      'aprovechamiento_salidas' => 'Aprovechamiento',
      'categorias' => 'Categoría',
      'elemento_imagenes' => 'Foto',
      _ => t ?? '',
    };

Widget _auditoriaTile(Auditoria a, {bool mostrarTabla = false}) {
  final titulo = (a.afectado != null && a.afectado!.isNotEmpty)
      ? a.afectado!
      : a.descripcion;
  return ListTile(
    dense: true,
    leading: CircleAvatar(
      radius: 16,
      backgroundColor: _color(a.accion).withValues(alpha: 0.15),
      child: Icon(_icono(a.accion), color: _color(a.accion), size: 18),
    ),
    title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text([
      if (a.afectado != null && a.afectado!.isNotEmpty) a.descripcion,
      _fmt.format(horaColombia(a.fecha)),
      if (a.usuarioEmail != null) a.usuarioEmail!,
      if (mostrarTabla) _tablaLabel(a.tabla),
    ].where((s) => s.isNotEmpty).join('  ·  '),
        style: const TextStyle(fontSize: 11)),
  );
}

/// Historial de cambios.
/// - Con [registroId]: historial de ESE registro (desde el kardex). Simple.
/// - Sin él: auditoría GLOBAL con sub-pestañas (admin/coordinador).
class HistorialPage extends StatefulWidget {
  final String? tabla;
  final String? registroId;
  final String titulo;
  const HistorialPage({super.key, this.tabla, this.registroId,
      this.titulo = 'Auditoría de cambios'});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  bool get _global => widget.registroId == null;

  // Pestañas de la auditoría global.
  static const _tabs = [
    ('Recientes', null),
    ('Entradas', 'entradas'),
    ('Salidas', 'salidas'),
    ('Bodegas', 'bodegas'),
    ('Centros', 'centros'),
    ('Usuarios', 'usuarios'),
    ('Aprovech.', 'aprovechamientos'),
  ];

  Future<List<Auditoria>>? _futurePorRegistro;

  @override
  void initState() {
    super.initState();
    if (!_global) {
      _futurePorRegistro = InventarioService.historialRegistro(
          widget.tabla!, widget.registroId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_global) return _vistaPorRegistro();
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.titulo),
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs
              .map((t) => _AuditoriaTab(categoria: t.$2,
                  esRecientes: t.$2 == null))
              .toList(),
        ),
      ),
    );
  }

  Widget _vistaPorRegistro() {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: FutureBuilder<List<Auditoria>>(
        future: _futurePorRegistro,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center)));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return const _Vacio();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _auditoriaTile(items[i]),
          );
        },
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history, size: 44, color: Colors.grey),
            SizedBox(height: 10),
            Text('Sin cambios registrados', textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text('Los cambios que se hagan de ahora en adelante aparecerán aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
      );
}

/// Una sub-pestaña de auditoría: buscador + lista paginada (10 + "Mostrar más").
class _AuditoriaTab extends StatefulWidget {
  final String? categoria;
  final bool esRecientes;
  const _AuditoriaTab({required this.categoria, this.esRecientes = false});
  @override
  State<_AuditoriaTab> createState() => _AuditoriaTabState();
}

class _AuditoriaTabState extends State<_AuditoriaTab>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  final List<Auditoria> _items = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar(reset: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool reset = false}) async {
    if (_cargando) return;
    setState(() { _cargando = true; _error = null; });
    try {
      if (reset) { _offset = 0; _hayMas = true; _items.clear(); }
      final r = await InventarioService.auditoriaClasificada(
          widget.categoria, q: _ctrl.text, offset: _offset, limit: 10);
      if (!mounted) return;
      setState(() {
        _items.addAll(r);
        _offset += r.length;
        if (r.length < 10) _hayMas = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _ctrl,
            onSubmitted: (_) => _cargar(reset: true),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar (afectado o usuario)…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(icon: const Icon(Icons.clear),
                      onPressed: () { _ctrl.clear(); _cargar(reset: true); }),
                IconButton(icon: const Icon(Icons.arrow_forward),
                    tooltip: 'Buscar', onPressed: () => _cargar(reset: true)),
              ]),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12),
              child: Text('Error: $_error',
                  style: const TextStyle(color: Colors.red))),
        Expanded(
          child: _items.isEmpty && !_cargando
              ? const _Vacio()
              : ListView.separated(
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == _items.length) {
                      // Pie: "Mostrar más" / cargando / no hay más.
                      if (_cargando) {
                        return const Padding(padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()));
                      }
                      if (_hayMas && _items.isNotEmpty) {
                        return Center(child: TextButton.icon(
                          onPressed: () => _cargar(),
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('Mostrar más'),
                        ));
                      }
                      if (!_hayMas && _items.isNotEmpty) {
                        return const Padding(padding: EdgeInsets.all(10),
                            child: Center(child: Text('— No hay más —',
                                style: TextStyle(fontSize: 12, color: Colors.grey))));
                      }
                      return const SizedBox.shrink();
                    }
                    return _auditoriaTile(_items[i],
                        mostrarTabla: widget.esRecientes);
                  },
                ),
        ),
      ],
    );
  }
}
