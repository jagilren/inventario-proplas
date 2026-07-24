import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import '../ajustes.dart';
import '../sync_service.dart';
import 'dashboard_page.dart';
import 'elementos_page.dart';
import 'movimiento_page.dart';
import 'alertas_page.dart';
import 'aprovechamientos_page.dart';
import 'perfil_page.dart';
import 'centros_page.dart';
import 'bodegas_page.dart';
import 'traslados_page.dart';
import 'reportes_page.dart';
import 'configuracion_page.dart';
import 'gestion_usuarios_page.dart';
import 'historial_page.dart';
import 'sincronizacion_page.dart';
import '../widgets/barra_sync.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _Seccion {
  final String titulo;
  final IconData icono;
  final Widget pagina;
  const _Seccion(this.titulo, this.icono, this.pagina);
}

class _HomePageState extends State<HomePage> {
  int _idx = 0;
  Set<String> _roles = {};
  bool _cargado = false;

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() { _roles = r; _cargado = true; });
    });
    // Ya hay sesión: descargar el catálogo para poder trabajar sin señal
    // y subir lo que hubiera quedado pendiente de una sesión anterior.
    SyncService.alSesionIniciada();
    Ajustes.cargar(); // config regional de exportaciones del usuario
  }

  bool get _admin => _roles.contains(Roles.admin);
  bool get _coord => _roles.contains(Roles.coordinador);
  bool get _gestiona => _admin || _coord;
  bool get _puedeExportar => _admin || _roles.contains(Roles.exportar);

  List<_Seccion> get _secciones {
    final puedeSalida = _admin || _roles.contains(Roles.operarioMenos);
    final puedeEntrada = _admin || _roles.contains(Roles.operarioMas);
    return [
      const _Seccion('Inicio', Icons.dashboard, DashboardPage()),
      const _Seccion('Existencias', Icons.search, ElementosPage()),
      if (puedeSalida)
        const _Seccion('Salida', Icons.upload, MovimientoPage(tipoInicial: 'salida')),
      if (puedeEntrada)
        const _Seccion('Entrada', Icons.download, MovimientoPage(tipoInicial: 'entrada')),
      const _Seccion('Alertas', Icons.warning_amber, AlertasPage()),
      const _Seccion('Aprovech.', Icons.content_cut, AprovechamientosPage()),
    ];
  }

  void _ir(Widget pagina) {
    Navigator.pop(context); // cerrar el menú
    Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    if (!_cargado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final secciones = _secciones;
    if (_idx >= secciones.length) _idx = 0;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/rpci_letras.png', height: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Inventario · ${secciones[_idx].titulo}',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white, size: 34),
                  const SizedBox(height: 8),
                  const Text('Inventario PROPLAS',
                      style: TextStyle(color: Colors.white, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  Text(email,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(
                      _roles.isEmpty
                          ? 'Sin roles'
                          : _roles.map(Roles.etiqueta).join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            if (_gestiona) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('GESTIÓN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                        letterSpacing: 1, color: Colors.grey)),
              ),
              ListTile(
                leading: const Icon(Icons.warehouse),
                title: const Text('Bodegas'),
                subtitle: const Text('Crear y editar'),
                onTap: () => _ir(const BodegasPage()),
              ),
              if (_admin)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: const Text('Traslados'),
                  subtitle: const Text('Mover stock entre bodegas'),
                  onTap: () => _ir(const TrasladosPage()),
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
                onTap: () => _ir(const HistorialPage(titulo: 'Auditoría de cambios')),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Configuración'),
                subtitle: const Text('Formato de exportaciones (por usuario)'),
                onTap: () => _ir(const ConfiguracionPage()),
              ),
            ],
            // Informes: visible para quien tenga el permiso de exportar.
            if (_puedeExportar)
              ListTile(
                leading: const Icon(Icons.download_for_offline),
                title: const Text('Informes'),
                subtitle: const Text('Descargar en Excel/CSV'),
                onTap: () => _ir(const ReportesPage()),
              ),
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
          const BarraSync(),
          Expanded(
            child: IndexedStack(
              index: _idx,
              children: secciones.map((s) => s.pagina).toList(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: secciones
            .map((s) => NavigationDestination(icon: Icon(s.icono), label: s.titulo))
            .toList(),
      ),
    );
  }
}
