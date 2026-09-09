import 'package:flutter/material.dart';
import '../activos_service.dart';
import '../widgets/campo_obligatorio.dart';

/// Catálogo de terceros: talleres, clientes y proveedores donde puede estar
/// físicamente un equipo que sigue siendo nuestro.
///
/// OJO: un tercero NO es un usuario de la app. "Taller de Lucho" nunca inicia
/// sesión aquí; es un dato de catálogo que usamos para registrar dónde está
/// un equipo.
class ActivoTercerosPage extends StatefulWidget {
  const ActivoTercerosPage({super.key});
  @override
  State<ActivoTercerosPage> createState() => _ActivoTercerosPageState();
}

class _ActivoTercerosPageState extends State<ActivoTercerosPage> {
  List<ActivoTercero> _terceros = [];
  bool _cargando = true;
  bool _mostrarInactivos = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await ActivosService.terceros(
          soloActivos: !_mostrarInactivos, limit: 200);
      if (!mounted) return;
      setState(() { _terceros = res; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  Future<void> _abrirFormulario({ActivoTercero? tercero}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioTercero(tercero: tercero),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terceros'),
        actions: [
          IconButton(
            icon: Icon(_mostrarInactivos
                ? Icons.visibility
                : Icons.visibility_off),
            tooltip: _mostrarInactivos
                ? 'Ocultar los inactivos'
                : 'Mostrar también los inactivos',
            onPressed: () {
              setState(() => _mostrarInactivos = !_mostrarInactivos);
              _cargar();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
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
    if (_terceros.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay terceros.\nCrea el primero con el botón "Nuevo".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _terceros.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final t = _terceros[i];
          final detalle = [_etiquetaTipo(t.tipo), t.contacto]
              .where((e) => e != null && e.isNotEmpty)
              .join(' · ');
          return ListTile(
            leading: Icon(_iconoTipo(t.tipo)),
            title: Text(t.nombre),
            subtitle: detalle.isEmpty ? null : Text(detalle),
            trailing: t.activo
                ? const Icon(Icons.chevron_right)
                : const Text('Inactivo', style: TextStyle(fontSize: 12)),
            onTap: () => _abrirFormulario(tercero: t),
          );
        },
      ),
    );
  }
}

String? _etiquetaTipo(String? tipo) => switch (tipo) {
  'taller' => 'Taller',
  'cliente' => 'Cliente',
  'proveedor' => 'Proveedor',
  'otro' => 'Otro',
  _ => null,
};

IconData _iconoTipo(String? tipo) => switch (tipo) {
  'taller' => Icons.build,
  'cliente' => Icons.business,
  'proveedor' => Icons.local_shipping,
  _ => Icons.place,
};

class _FormularioTercero extends StatefulWidget {
  final ActivoTercero? tercero;
  const _FormularioTercero({this.tercero});
  @override
  State<_FormularioTercero> createState() => _FormularioTerceroState();
}

class _FormularioTerceroState extends State<_FormularioTercero> {
  late final TextEditingController _nombre;
  late final TextEditingController _contacto;
  late String _tipo;
  late bool _activo;
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    final t = widget.tercero;
    _nombre = TextEditingController(text: t?.nombre ?? '');
    _contacto = TextEditingController(text: t?.contacto ?? '');
    _tipo = t?.tipo ?? 'taller';
    _activo = t?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _contacto.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final t = widget.tercero;
      if (t == null) {
        await ActivosService.crearTercero(
          nombre: _nombre.text.trim(),
          tipo: _tipo,
          contacto: _contacto.text.trim().isEmpty
              ? null : _contacto.text.trim(),
        );
      } else {
        await ActivosService.editarTercero(
          t.id,
          nombre: _nombre.text.trim(),
          tipo: _tipo,
          contacto: _contacto.text.trim(),
          activo: _activo,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      final txt = '$e';
      final duplicado = txt.contains('activo_terceros_uniq') ||
          txt.contains('23505') ||
          txt.contains('duplicate key');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(duplicado
              ? 'Ya existe un tercero con ese nombre. Búscalo en la lista '
                  '(puede estar inactivo).'
              : 'No se pudo guardar: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.tercero != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editando ? 'Editar tercero' : 'Nuevo tercero',
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
                  hintText: 'Ej: TALLER DE LUCHO',
                  border: OutlineInputBorder(),
                ),
                _mostrarErrores && _nombre.text.trim().isEmpty,
              ),
            ),
            const SizedBox(height: 14),
            Text('Tipo', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            // Wrap: en pantalla angosta las opciones bajan de línea.
            Wrap(
              spacing: 8,
              children: [
                for (final t in ['taller', 'cliente', 'proveedor', 'otro'])
                  ChoiceChip(
                    label: Text(_etiquetaTipo(t)!),
                    selected: _tipo == t,
                    onSelected: (_) => setState(() => _tipo = t),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contacto,
              decoration: const InputDecoration(
                labelText: 'Contacto',
                hintText: 'Teléfono, dirección o persona',
                border: OutlineInputBorder(),
              ),
            ),
            if (editando) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activo'),
                subtitle: const Text(
                    'Un tercero inactivo no se ofrece al cambiar ubicación'),
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
