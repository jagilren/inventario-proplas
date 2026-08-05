import 'dart:async';
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

  /// Señal para limpiar el buscador cuando se vuelve a esta vista desde otra
  /// pestaña (el home la incrementa al seleccionar Existencias).
  static final ValueNotifier<int> limpiarBusqueda = ValueNotifier(0);

  @override
  State<ElementosPage> createState() => _ElementosPageState();
}

class _ElementosPageState extends State<ElementosPage> {
  final _ctrl = TextEditingController();
  final List<Elemento> _items = [];
  bool _cargando = false;
  bool _puedeCrear = false;
  String? _error;

  /// La lista se pide de a poco. El filtro sí se evalúa contra TODO el
  /// catálogo en el servidor: el tamaño de página solo decide cuántas filas
  /// viajan por vez, nunca cuántas se revisan.
  static const _porPagina = 10;
  int _offset = 0;
  bool _hayMas = true;
  bool _cargandoMas = false;

  /// Total de coincidencias en el servidor (null mientras llega o sin señal).
  int? _total;

  /// Espera a que el usuario termine de escribir antes de consultar. Sin
  /// esto, cada tecla disparaba una búsqueda: escribir "valvula" eran 7
  /// viajes al servidor (14 contando el total). Con la espera son 2.
  static const _esperaTecleo = Duration(milliseconds: 350);
  Timer? _debounce;

  /// Cada búsqueda lleva número. Si llega la respuesta de una anterior
  /// (porque se demoró más que la siguiente), se descarta: así la lista
  /// nunca muestra el resultado de algo que el usuario ya dejó de escribir.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _buscar('');
    // Recargar la lista cuando haya un movimiento (salida/entrada/anulación),
    // aunque esta pantalla quede viva en segundo plano (IndexedStack).
    InventarioService.revision.addListener(_onCambioInventario);
    // Al volver a Existencias desde otra pestaña, limpiar el buscador.
    ElementosPage.limpiarBusqueda.addListener(_limpiarBusqueda);
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

  void _limpiarBusqueda() {
    if (mounted && _ctrl.text.isNotEmpty) {
      _ctrl.clear();
      _buscar('');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    InventarioService.revision.removeListener(_onCambioInventario);
    ElementosPage.limpiarBusqueda.removeListener(_limpiarBusqueda);
    _ctrl.dispose();
    super.dispose();
  }

  /// Lo que dispara el campo de texto: espera a que el usuario deje de
  /// escribir. La barra de progreso se enciende de una, para que se note
  /// que la app sí reaccionó a la tecla.
  void _alEscribir(String q) {
    _debounce?.cancel();
    setState(() => _cargando = true);
    _debounce = Timer(_esperaTecleo, () => _buscar(q));
  }

  /// Búsqueda nueva: vuelve a empezar por la primera página.
  /// Se llama directo (sin espera) cuando el disparo no es del teclado:
  /// al abrir la pantalla, al limpiar el buscador o tras editar un elemento.
  Future<void> _buscar(String q) async {
    _debounce?.cancel();
    final mio = ++_seq;
    setState(() {
      _cargando = true;
      _error = null;
      _items.clear();
      _offset = 0;
      _hayMas = true;
      _total = null;
    });

    // El total viaja aparte y NO frena la lista: apenas llegan los 10
    // primeros se pintan, y el contador se completa cuando esté listo.
    InventarioService.contarElementos(q).then((t) {
      if (mounted && mio == _seq) setState(() => _total = t);
    });

    try {
      final primera =
          await InventarioService.buscar(q, offset: 0, limit: _porPagina);
      // Llegó tarde: el usuario ya va en otra búsqueda. Se descarta.
      if (!mounted || mio != _seq) return;
      setState(() {
        _items.addAll(primera);
        _offset = primera.length;
        _hayMas = primera.length == _porPagina;
      });
    } catch (e) {
      if (mounted && mio == _seq) setState(() => _error = '$e');
    } finally {
      if (mounted && mio == _seq) setState(() => _cargando = false);
    }
  }

  /// Trae la siguiente página y la agrega al final de la lista.
  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;
    setState(() => _cargandoMas = true);
    try {
      final r = await InventarioService.buscar(
        _ctrl.text,
        offset: _offset,
        limit: _porPagina,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(r);
        _offset += r.length;
        if (r.length < _porPagina) _hayMas = false;
      });
    } catch (_) {
      // Sin red: la lista se queda como está, sin romper nada.
      if (mounted) setState(() => _hayMas = false);
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
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
              onChanged: _alEscribir,
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
                    // La fila extra del final es el pie con "Cargar más".
                    itemCount: _items.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      if (i == _items.length) return _pieDeLista();
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

  /// Pie de la lista: cuántos se ven de cuántos hay, y el botón para traer
  /// la siguiente tanda. El total sale del servidor, así queda claro que
  /// buscar sigue mirando el catálogo completo aunque se muestren de a 10.
  Widget _pieDeLista() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            // El total llega un instante después que la lista; mientras
            // tanto se muestra solo lo que ya se ve, sin números falsos.
            _total == null
                ? 'Mostrando ${_items.length}'
                : 'Mostrando ${_items.length} de $_total',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (_cargandoMas)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          if (_hayMas && !_cargandoMas)
            TextButton.icon(
              onPressed: _cargarMas,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('Cargar más'),
            ),
          if (!_hayMas)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('— No hay más —',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
