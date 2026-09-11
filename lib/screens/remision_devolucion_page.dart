import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../reportes.dart';
import '../util/import_archivo.dart';
import '../util/plantilla_import.dart';
import '../widgets/remision_nuevo.dart';
import 'escaner_page.dart';

final _qty = NumberFormat.decimalPattern('es_CO');
final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Un renglón de la remisión (temporal, en memoria): un artículo del
/// catálogo o uno NUEVO propuesto (docs/plan-remision-elementos-nuevos.md).
class _ItemRemision {
  final Elemento? elemento;
  num cantidad;
  // Solo en los nuevos:
  String nombreNuevo;
  String? unidad;
  num? costoEstimado;

  _ItemRemision(Elemento this.elemento, this.cantidad) : nombreNuevo = '';
  _ItemRemision.nuevo(LineaDevolucion l)
      : elemento = null,
        cantidad = l.cantidad,
        nombreNuevo = l.nombre,
        unidad = l.unidad,
        costoEstimado = l.costoEstimado;

  bool get esNuevo => elemento == null;
  String get nombre => elemento?.nombre ?? nombreNuevo;
  String get unidadTexto => elemento?.unidad ?? unidad ?? '';

  LineaDevolucion get linea => esNuevo
      ? LineaDevolucion.nueva(
          nombre: nombreNuevo,
          cantidad: cantidad,
          unidad: unidad!,
          costoEstimado: costoEstimado!)
      : LineaDevolucion.catalogo(elemento!, cantidad);
}

/// Lo que devuelve el buscador cuando el artículo no aparece.
class _PedirNuevo {
  final String texto;
  const _PedirNuevo(this.texto);
}

/// Utilidad para ARMAR una remisión de devolución: se van agregando
/// elementos (por búsqueda o escaneo) con su cantidad a una lista temporal
/// editable, y al final se genera un CSV descargable. Ese mismo CSV se puede
/// importar luego con la utilidad de "Devoluciones".
///
/// Por ahora NO se guarda en la base (lista en memoria); a futuro se podría
/// persistir en una tabla de "remisiones".
class RemisionDevolucionPage extends StatefulWidget {
  const RemisionDevolucionPage({super.key});
  @override
  State<RemisionDevolucionPage> createState() => _RemisionDevolucionPageState();
}

class _RemisionDevolucionPageState extends State<RemisionDevolucionPage> {
  final List<_ItemRemision> _items = [];
  bool _generando = false;
  bool _puedeGenerar = false; // rol admin o remisiones
  /// El catálogo, para mostrar los parecidos antes de aceptar un artículo
  /// nuevo. Null sin señal: la hoja lo dice.
  EmparejadorCatalogo? _catalogo;

  @override
  void initState() {
    super.initState();
    InventarioService.todosElementos().then((e) {
      if (mounted) setState(() => _catalogo = EmparejadorCatalogo(e));
    }).catchError((_) {});
    InventarioService.misRoles().then((r) {
      if (mounted) {
        setState(() => _puedeGenerar =
            r.contains(Roles.admin) || r.contains(Roles.remisiones));
      }
    });
  }

  Future<void> _buscar() async {
    final sel = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BuscadorElemento(),
    );
    if (sel is Elemento) _agregar(sel);
    if (sel is _PedirNuevo) _proponerNuevo(texto: sel.texto);
  }

  /// Nombres (normalizados) de las líneas nuevas, sin contar [menos].
  Set<String> _nuevosEnLista({_ItemRemision? menos}) => {
        for (final it in _items)
          if (it.esNuevo && !identical(it, menos))
            normalizarTexto(it.nombreNuevo),
      };

  /// Propone un artículo que no está en el catálogo, o edita uno ya
  /// propuesto ([editar]). Si en la hoja resulta que sí existía, se agrega
  /// ese del catálogo.
  Future<void> _proponerNuevo({String texto = '', _ItemRemision? editar}) async {
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaElementoNuevo(
        nombreInicial: texto,
        inicial: editar?.linea,
        catalogo: _catalogo,
        nuevosEnLista: _nuevosEnLista(menos: editar),
      ),
    );
    if (!mounted || r == null) return;
    if (r is Elemento) {
      if (editar != null) setState(() => _items.remove(editar));
      _agregar(r);
      return;
    }
    final l = r as LineaDevolucion;
    setState(() {
      if (editar != null) {
        editar
          ..nombreNuevo = l.nombre
          ..cantidad = l.cantidad
          ..unidad = l.unidad
          ..costoEstimado = l.costoEstimado;
      } else {
        _items.add(_ItemRemision.nuevo(l));
      }
    });
  }

  Future<void> _escanear() async {
    final codigo = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const EscanerPage()));
    if (codigo == null || !mounted) return;
    final elem = await InventarioService.porCodigoBarras(codigo);
    if (!mounted) return;
    if (elem != null) {
      _agregar(elem);
    } else {
      _msg('Código $codigo sin asociar a ningún elemento.');
    }
  }

  Future<void> _agregar(Elemento e) async {
    // Si ya está en la lista, se edita la cantidad en vez de duplicar.
    final idx = _items.indexWhere((it) => it.elemento?.id == e.id);
    if (idx >= 0) {
      _msg('Ese elemento ya está en la lista; edita su cantidad.');
      _editarCantidad(idx);
      return;
    }
    final cant = await _pedirCantidad(e, null);
    if (cant != null && mounted) {
      setState(() => _items.add(_ItemRemision(e, cant)));
    }
  }

  Future<void> _editarCantidad(int idx) async {
    final it = _items[idx];
    // Un nuevo se edita completo: nombre, unidad, cantidad y costo.
    if (it.esNuevo) return _proponerNuevo(editar: it);
    final cant = await _pedirCantidad(it.elemento!, it.cantidad);
    if (cant != null && mounted) setState(() => it.cantidad = cant);
  }

  /// Diálogo para capturar/editar la cantidad. Devuelve null si cancela.
  Future<num?> _pedirCantidad(Elemento e, num? actual) async {
    final ctrl = TextEditingController(text: actual?.toString() ?? '');
    return showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.nombre),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cantidad (${e.unidad})',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
            if (c != null && c > 0) Navigator.pop(ctx, c);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = num.tryParse(ctrl.text.replaceAll(',', '.'));
              if (c == null || c <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Cantidad inválida')));
                return;
              }
              Navigator.pop(ctx, c);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _eliminar(int idx) => setState(() => _items.removeAt(idx));

  Future<void> _generarCsv() async {
    if (_items.isEmpty) return;
    setState(() => _generando = true);
    try {
      // El costo promedio se lee AHORA del servidor: la lista se pudo armar
      // hace horas y el costo cambia con cada compra. Sin señal se usa el
      // que se tenía al agregar cada elemento, y se avisa.
      Map<String, num> costos = const {};
      var costoAlDia = true;
      try {
        costos = await InventarioService.costosPromedio([
          for (final it in _items)
            if (it.elemento case final e?) e.id,
        ]);
      } catch (_) {
        costoAlDia = false;
      }
      final filas = filasCsvDevolucion(
        [for (final it in _items) it.linea],
        costos: costos,
        // D4 del plan: la firma del estimado es el correo de quien genera.
        estimadoPor: supabase.auth.currentUser?.email,
      );
      final guardado =
          await Reportes.descargarCsv('remision_devolucion', filas);
      // En el celular se puede cancelar el diálogo de guardar: no decir
      // "✓ generado" si el archivo no quedó en ninguna parte.
      if (!guardado) {
        _msg('No se guardó el CSV: se canceló el diálogo. La lista sigue '
            'aquí; vuelve a tocar "Generar CSV".');
        return;
      }
      _msg(costoAlDia
          ? '✓ CSV generado. Puedes importarlo en "Devoluciones".'
          : '✓ CSV generado SIN conexión: el costo promedio es el de cuando '
              'agregaste cada elemento, puede no estar al día.');
    } catch (e) {
      _msg('Error al generar: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remisión de devolución')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFE3F2FD),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
                'Agrega elementos con su cantidad y genera el CSV: lleva el '
                'elemento, la cantidad y su costo promedio actual. Si algo no '
                'está en el catálogo, agrégalo como NUEVO desde "Buscar". Ese '
                'archivo se carga luego en "Devoluciones".',
                style: TextStyle(fontSize: 12, color: Color(0xFF1565C0))),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _buscar,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _escanear,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear'),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  _items.isEmpty
                      ? 'Sin elementos aún'
                      : '${_items.length} elemento${_items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Usa "Buscar" o "Escanear" para ir agregando elementos '
                        'a la remisión.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 13)),
                        ),
                        title: Text(it.nombre),
                        // Un nuevo lo DICE con texto, no solo con un color.
                        subtitle: Text(it.esNuevo
                            ? 'NUEVO · ${_qty.format(it.cantidad)} '
                                '${it.unidadTexto} · estimado '
                                '${_money.format(it.costoEstimado)} c/u'
                            : '${_qty.format(it.cantidad)} ${it.unidadTexto}'),
                        subtitleTextStyle: it.esNuevo
                            ? TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.tertiary)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: it.esNuevo
                                  ? 'Editar ${it.nombre}'
                                  : 'Editar cantidad de ${it.nombre}',
                              onPressed: () => _editarCantidad(i),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              tooltip: 'Quitar ${it.nombre}',
                              onPressed: () => _eliminar(i),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_puedeGenerar)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                    'No tienes el permiso "Remisiones de devolución" para '
                    'generar el CSV. Pídeselo a un administrador.',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                    textAlign: TextAlign.center),
              ),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_generando || _items.isEmpty || !_puedeGenerar)
                    ? null : _generarCsv,
                icon: _generando
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download),
                label: Text('Generar CSV (${_items.length})'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Buscador de elementos del inventario oficial (excluye aprovechamiento).
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
          // Siempre a la vista, no solo cuando no hay resultados: con 900
          // artículos casi toda búsqueda trae ALGO, aunque no sea lo buscado.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('¿No está? Agregarlo como NUEVO'),
                onPressed: () =>
                    Navigator.pop(context, _PedirNuevo(_ctrl.text.trim())),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(e.nombre),
                  subtitle: Text('Existencia: ${_qty.format(e.existencia)} '
                      '${e.unidad}'),
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
