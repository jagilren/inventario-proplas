import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import 'kardex_page.dart';
import 'reconocer_page.dart';
import 'editar_elemento_page.dart';
import 'escaner_page.dart';
import '../widgets/imagen_elemento.dart';

final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _qty = NumberFormat.decimalPattern('es_CO');

class ElementosPage extends StatefulWidget {
  const ElementosPage({super.key});
  @override
  State<ElementosPage> createState() => _ElementosPageState();
}

class _ElementosPageState extends State<ElementosPage> {
  final _ctrl = TextEditingController();
  List<Elemento> _items = [];
  bool _cargando = false;
  bool _puedeCrear = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _buscar('');
    // Recargar la lista cuando haya un movimiento (salida/entrada/anulación),
    // aunque esta pantalla quede viva en segundo plano (IndexedStack).
    InventarioService.revision.addListener(_onCambioInventario);
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() => _puedeCrear =
            r.contains(Roles.admin) || r.contains(Roles.coordinador));
      }
    });
  }

  void _onCambioInventario() {
    if (mounted) _buscar(_ctrl.text);
  }

  @override
  void dispose() {
    InventarioService.revision.removeListener(_onCambioInventario);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String q) async {
    setState(() { _cargando = true; _error = null; });
    try {
      final r = await InventarioService.buscar(q);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoElemento() async {
    final creado = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => const EditarElementoPage()));
    if (creado == true) _buscar(_ctrl.text);
  }

  /// Escanea un código y abre directo el elemento asociado.
  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    final elem = await InventarioService.porCodigoBarras(codigo);
    if (!mounted) return;
    if (elem != null) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => KardexPage(elemento: elem)));
      if (mounted) _buscar(_ctrl.text);
    } else {
      // Código aún no asociado: se muestra el código para buscarlo/asignarlo.
      _ctrl.text = codigo;
      _buscar(codigo);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Código $codigo sin asociar. '
              'Ábrelo y guárdalo en un elemento (lápiz → Código de barras).'),
          duration: const Duration(seconds: 5)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _puedeCrear
          ? FloatingActionButton.extended(
              onPressed: _nuevoElemento,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo elemento'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: 'Buscar elemento (palabras en cualquier orden)…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_ctrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _ctrl.clear(); _buscar(''); },
                      ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Escanear código',
                      onPressed: _escanear,
                    ),
                    IconButton(
                      icon: const Icon(Icons.center_focus_strong),
                      tooltip: 'Reconocer por foto',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const ReconocerPage())),
                    ),
                    if (_puedeCrear)
                      IconButton(
                        icon: const Icon(Icons.add_box, color: Colors.teal),
                        tooltip: 'Nuevo elemento',
                        onPressed: _nuevoElemento,
                      ),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_cargando) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Expanded(
            child: _items.isEmpty && !_cargando
                ? const Center(child: Text('Sin resultados'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      return ListTile(
                        // La existencia ya va en el subtítulo, así que este
                        // espacio se aprovecha para la foto del elemento.
                        leading: Container(
                          decoration: e.bajoMinimo
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.orange, width: 2))
                              : null,
                          child: ImagenElemento(url: e.imagenUrl, tamano: 46),
                        ),
                        title: Text(e.nombre),
                        subtitle: Text(
                            '${_qty.format(e.existencia)} ${e.unidad}  ·  '
                            'costo prom. ${_money.format(e.costoPromedio)}'
                            '${e.material != null ? '  ·  ${e.material}' : ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (e.bajoMinimo)
                              const Icon(Icons.warning_amber, color: Colors.orange),
                            if (_puedeCrear)
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Editar elemento',
                                onPressed: () async {
                                  final cambio = await Navigator.push<bool>(
                                      context, MaterialPageRoute(
                                          builder: (_) =>
                                              EditarElementoPage(elemento: e)));
                                  if (cambio == true && mounted) _buscar(_ctrl.text);
                                },
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => KardexPage(elemento: e)));
                          if (mounted) _buscar(_ctrl.text);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
