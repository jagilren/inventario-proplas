import 'package:flutter/material.dart';
import '../data.dart';
import '../util/busqueda.dart';
import '../widgets/campo_obligatorio.dart';

/// Maestra de materiales (schema_v35).
///
/// Antes el material era texto libre dentro de cada elemento y cada carga
/// podía inventar una variante ("Inox 304" / "INOX 304" / "inox304"). Desde
/// aquí se administra la lista única: crear, renombrar, inhabilitar y buscar.
///
/// Renombrar corrige el catálogo completo de una sola vez: los elementos
/// apuntan al material por id y la base arrastra el texto.
/// Abre el formulario de material (crear o editar) como hoja inferior.
///
/// Es público para que el formulario de elementos pueda crear un material
/// con el botón + sin mandar al usuario a otra pantalla y hacerle perder lo
/// que llevaba escrito.
///
/// Devuelve el nombre guardado, o null si se canceló.
Future<String?> mostrarFormularioMaterial(
  BuildContext context, {
  MaterialMaestro? material,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MaterialForm(material: material),
  );
}

class MaterialesPage extends StatefulWidget {
  const MaterialesPage({super.key});
  @override
  State<MaterialesPage> createState() => _MaterialesPageState();
}

class _MaterialesPageState extends State<MaterialesPage> {
  late Future<List<MaterialMaestro>> _future;
  final _buscar = TextEditingController();
  String _q = '';
  bool _verInactivos = false;

  @override
  void initState() {
    super.initState();
    _future = InventarioService.materialesConUso();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  void _recargar() =>
      setState(() => _future = InventarioService.materialesConUso());

  Future<void> _editar([MaterialMaestro? m]) async {
    final guardado = await mostrarFormularioMaterial(context, material: m);
    if (guardado != null) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materiales'),
        actions: [
          IconButton(
            tooltip: _verInactivos
                ? 'Ocultar inhabilitados'
                : 'Ver también los inhabilitados',
            icon: Icon(_verInactivos
                ? Icons.visibility
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _verInactivos = !_verInactivos),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          // Buscador. Mismo criterio que el resto de la app: sin tildes y
          // sin distinguir mayúsculas.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _buscar,
              onChanged: (v) => setState(() => _q = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar material…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscar.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MaterialMaestro>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final todos = snap.data ?? [];
                final lista = todos
                    .where((m) => _verInactivos || m.activo)
                    .where((m) => coincideBusqueda(_q, [m.nombre]))
                    .toList();

                if (lista.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _q.isEmpty
                            ? 'No hay materiales todavía.'
                            : 'Ningún material coincide con "$_q".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${lista.length} de ${todos.length} materiales',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => _recargar(),
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: lista.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = lista[i];
                            return ListTile(
                              leading: Icon(Icons.category,
                                  color: m.activo ? null : Colors.grey),
                              title: Text(
                                m.activo
                                    ? m.nombre
                                    : '${m.nombre}  (inhabilitado)',
                                style: m.activo
                                    ? null
                                    : const TextStyle(color: Colors.grey),
                              ),
                              subtitle: Text(m.usos == 0
                                  ? 'Sin elementos'
                                  : m.usos == 1
                                      ? '1 elemento'
                                      : '${m.usos} elementos'),
                              trailing: const Icon(Icons.edit, size: 20),
                              onTap: () => _editar(m),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialForm extends StatefulWidget {
  final MaterialMaestro? material;
  const _MaterialForm({this.material});
  @override
  State<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends State<_MaterialForm> {
  late final TextEditingController _nombre;
  bool _guardando = false;
  // True apenas se intenta guardar con el nombre vacío: lo sombrea en
  // rojo pálido hasta que se llene.
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.material?.nombre ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _mostrarErrores = true);
      _aviso('El nombre es obligatorio');
      return;
    }
    setState(() => _guardando = true);
    try {
      final nombre = _nombre.text.trim();
      await InventarioService.guardarMaterial(
        id: widget.material?.id,
        nombre: nombre,
      );
      // Se devuelve el nombre (no un bool) para que quien lo abrió pueda
      // dejar seleccionado el material recién creado.
      if (mounted) Navigator.pop(context, nombre);
    } catch (e) {
      if (mounted) {
        _aviso(e.toString().replaceAll('Exception: ', ''));
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.material;
    final usos = m?.usos ?? 0;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(m == null ? 'Nuevo material' : 'Editar material',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          TextField(
            controller: _nombre,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: marcarError(const InputDecoration(
              labelText: 'Nombre del material',
              border: OutlineInputBorder(),
            ), _mostrarErrores && _nombre.text.trim().isEmpty),
            onSubmitted: (_) => _guardando ? null : _guardar(),
          ),
          // Renombrar arrastra el catálogo: conviene decirlo antes, no
          // después de que el usuario vea cambiar 234 elementos.
          if (m != null && usos > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Si cambias el nombre, se actualiza en los $usos '
                      'elementos que usan este material.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ),
          if (m != null)
            TextButton.icon(
              onPressed:
                  _guardando ? null : (m.activo ? _inhabilitar : _reactivar),
              icon: Icon(m.activo ? Icons.block : Icons.check_circle,
                  color: m.activo ? Colors.red : Colors.green),
              label: Text(
                  m.activo ? 'Inhabilitar material' : 'Reactivar material',
                  style: TextStyle(
                      color: m.activo ? Colors.red : Colors.green)),
            ),
        ],
      ),
    );
  }

  Future<void> _inhabilitar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inhabilitar material'),
        content: const Text(
            'Deja de aparecer al crear o editar elementos. No se borra nada '
            'y los elementos que ya lo tengan lo conservan. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Inhabilitar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      await InventarioService.inhabilitarMaterial(widget.material!.id);
      if (mounted) Navigator.pop(context, widget.material!.nombre);
    } catch (e) {
      if (mounted) {
        _aviso(e.toString().replaceAll('Exception: ', ''));
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _reactivar() async {
    setState(() => _guardando = true);
    try {
      await InventarioService.reactivarMaterial(widget.material!.id);
      if (mounted) Navigator.pop(context, widget.material!.nombre);
    } catch (e) {
      if (mounted) {
        _aviso('Error: $e');
        setState(() => _guardando = false);
      }
    }
  }
}
