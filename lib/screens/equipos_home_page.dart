import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import '../activos_service.dart';
import 'perfil_page.dart';
import 'centros_page.dart';
import 'bodegas_page.dart';
import 'configuracion_page.dart';
import 'gestion_usuarios_page.dart';
import 'historial_page.dart';
import 'sincronizacion_page.dart';

/// Pantalla principal del Módulo de Equipos.
///
/// Fase 3 (navegación): entra con el listado real de equipos y el Drawer del
/// módulo. La estructura de 4 pestañas de la sección 7.0 del plan y los
/// formularios de alta/entrada/salida son la Fase 4.
class EquiposHomePage extends StatefulWidget {
  const EquiposHomePage({super.key});
  @override
  State<EquiposHomePage> createState() => _EquiposHomePageState();
}

class _EquiposHomePageState extends State<EquiposHomePage> {
  static const _porPagina = 50;

  final _buscador = TextEditingController();
  List<Activo> _equipos = [];
  Set<String> _roles = {};
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() => _roles = r);
    });
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  bool get _admin => _roles.contains(Roles.admin);
  bool get _gestiona => _admin || _roles.contains(Roles.coordinador);

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await ActivosService.listar(
        limit: _porPagina,
        serial: _buscador.text.trim().isEmpty ? null : _buscador.text.trim(),
      );
      if (!mounted) return;
      setState(() { _equipos = res; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  void _ir(Widget pagina) {
    Navigator.pop(context); // cerrar el menú
    Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Cambiar de módulo',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.teal.shade700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.precision_manufacturing,
                      color: Colors.white, size: 34),
                  const SizedBox(height: 8),
                  const Text('Módulo de Equipos',
                      style: TextStyle(color: Colors.white, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  Text(email,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            // Ítems COMPARTIDOS con el Drawer de Inventario (sección 8.3 del
            // plan): administran catálogos que usan los dos módulos.
            if (_gestiona) ...[
              ListTile(
                leading: const Icon(Icons.warehouse),
                title: const Text('Bodegas'),
                subtitle: const Text('Crear y editar'),
                onTap: () => _ir(const BodegasPage()),
              ),
              ListTile(
                leading: const Icon(Icons.account_tree),
                title: const Text('Centros de costo'),
                subtitle: const Text('Crear y editar'),
                onTap: () => _ir(const CentrosPage()),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Auditoría de cambios'),
                subtitle: const Text('Quién cambió qué y cuándo'),
                onTap: () =>
                    _ir(const HistorialPage(titulo: 'Auditoría de cambios')),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Configuración'),
                subtitle: const Text('Formato de exportaciones (por usuario)'),
                onTap: () => _ir(const ConfiguracionPage()),
              ),
            ],
            if (_admin)
              ListTile(
                leading: const Icon(Icons.group),
                title: const Text('Usuarios y roles'),
                subtitle: const Text('Crear usuarios, asignar permisos'),
                onTap: () => _ir(const GestionUsuariosPage()),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('Trabajo sin conexión'),
              subtitle: const Text('Descargar catálogo y subir pendientes'),
              onTap: () => _ir(const SincronizacionPage()),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Mi perfil'),
              onTap: () => _ir(const PerfilPage()),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _buscador,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _cargar(),
              decoration: InputDecoration(
                hintText: 'Buscar por serial…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: 'Buscar',
                  onPressed: _cargar,
                ),
              ),
            ),
          ),
          Expanded(child: _lista()),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text('No se pudo cargar la lista de equipos.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_equipos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay equipos registrados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _equipos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _equipos[i];
          return ListTile(
            title: Text(e.serial),
            subtitle: Text(
              '${e.referenciaNombre ?? '—'} · ${e.condicionEtiqueta}'
              '${e.bodegaNombre == null ? '' : ' · ${e.bodegaNombre}'}',
            ),
            trailing: Text(e.estadoEtiqueta,
                style: const TextStyle(fontSize: 12)),
          );
        },
      ),
    );
  }
}
