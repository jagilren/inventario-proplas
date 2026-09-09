import 'package:flutter/material.dart';
import '../activos_service.dart';
import '../widgets/campo_obligatorio.dart';

/// Catálogo de referencias de equipos (los modelos: "Bomba Grundfos DNA30").
///
/// Es la maestra que evita que el mismo modelo quede escrito de tres formas
/// distintas, igual que `materiales` para el catálogo de elementos. Un equipo
/// individual (`activos`) siempre apunta a una de estas.
///
/// Siguiendo la regla del proyecto: una referencia con equipos asociados no se
/// borra, se inactiva.
class ActivoReferenciasPage extends StatefulWidget {
  const ActivoReferenciasPage({super.key});
  @override
  State<ActivoReferenciasPage> createState() => _ActivoReferenciasPageState();
}

class _ActivoReferenciasPageState extends State<ActivoReferenciasPage> {
  List<ActivoReferencia> _refs = [];
  bool _cargando = true;
  bool _mostrarInactivas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await ActivosService.referencias(
        soloActivas: !_mostrarInactivas,
        limit: 200,
      );
      if (!mounted) return;
      setState(() { _refs = res; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  Future<void> _abrirFormulario({ActivoReferencia? ref}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true, // el teclado no debe tapar los campos
      builder: (_) => _FormularioReferencia(referencia: ref),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referencias de equipos'),
        actions: [
          IconButton(
            icon: Icon(_mostrarInactivas
                ? Icons.visibility
                : Icons.visibility_off),
            tooltip: _mostrarInactivas
                ? 'Ocultar las inactivas'
                : 'Mostrar también las inactivas',
            onPressed: () {
              setState(() => _mostrarInactivas = !_mostrarInactivas);
              _cargar();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text('No se pudo cargar el catálogo.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_refs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay referencias.\nCrea la primera con el botón "Nueva".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        // Espacio al final para que el FAB no tape la última fila.
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _refs.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _refs[i];
          final detalle = [r.marca, r.modelo, r.tipo]
              .where((e) => e != null && e.isNotEmpty)
              .join(' · ');
          return ListTile(
            title: Text(r.nombre),
            subtitle: detalle.isEmpty ? null : Text(detalle),
            trailing: r.activo
                ? const Icon(Icons.chevron_right)
                : const Text('Inactiva', style: TextStyle(fontSize: 12)),
            onTap: () => _abrirFormulario(ref: r),
          );
        },
      ),
    );
  }
}

class _FormularioReferencia extends StatefulWidget {
  final ActivoReferencia? referencia;
  const _FormularioReferencia({this.referencia});
  @override
  State<_FormularioReferencia> createState() => _FormularioReferenciaState();
}

class _FormularioReferenciaState extends State<_FormularioReferencia> {
  late final TextEditingController _nombre;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _tipo;
  late bool _activo;
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    final r = widget.referencia;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _marca = TextEditingController(text: r?.marca ?? '');
    _modelo = TextEditingController(text: r?.modelo ?? '');
    _tipo = TextEditingController(text: r?.tipo ?? '');
    _activo = r?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _marca.dispose();
    _modelo.dispose();
    _tipo.dispose();
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = widget.referencia;
      if (r == null) {
        await ActivosService.crearReferencia(
          nombre: _nombre.text.trim(),
          marca: _t(_marca),
          modelo: _t(_modelo),
          tipo: _t(_tipo),
        );
      } else {
        await ActivosService.editarReferencia(
          r.id,
          nombre: _nombre.text.trim(),
          // Cadena vacía y no null: null significaría "no cambiar", y así
          // se puede borrar un dato que ya estaba escrito.
          marca: _marca.text.trim(),
          modelo: _modelo.text.trim(),
          tipo: _tipo.text.trim(),
          activo: _activo,
        );
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
    final editando = widget.referencia != null;
    return Padding(
      // viewInsets: el formulario sube con el teclado en vez de quedar tapado.
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editando ? 'Editar referencia' : 'Nueva referencia',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nombre,
              autofocus: !editando,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: marcarError(
                const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej: BOMBA CENTRÍFUGA',
                  border: OutlineInputBorder(),
                ),
                _mostrarErrores && _nombre.text.trim().isEmpty,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _marca,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Marca', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Modelo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tipo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                hintText: 'Ej: BOMBA, MOTOR, HERRAMIENTA',
                border: OutlineInputBorder()),
            ),
            if (editando) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                subtitle: const Text(
                    'Una referencia inactiva no se ofrece al crear equipos'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
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
