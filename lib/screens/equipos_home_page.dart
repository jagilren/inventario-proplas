import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import '../activos_service.dart';
import '../util/import_archivo.dart';
import 'perfil_page.dart';
import 'activo_referencias_page.dart';
import 'activo_terceros_page.dart';
import 'activo_alta_page.dart';
import 'activo_detalle_page.dart';
import 'activo_movimiento_page.dart';
import 'activos_de_referencia_page.dart';
import 'equipos_reportes_page.dart';
import '../widgets/pie_cargar_mas.dart';
import 'centros_page.dart';
import 'bodegas_page.dart';
import 'configuracion_page.dart';
import 'gestion_usuarios_page.dart';
import 'historial_page.dart';
import 'sincronizacion_page.dart';

/// Pantalla principal del Módulo de Equipos, con las 4 pestañas de la
/// sección 7.0 del plan.
///
/// No hay botones separados "Entrada"/"Salida" como en Inventario a
/// propósito: un equipo no es fungible, así que primero se busca la unidad y
/// el tipo de movimiento lo decide su estado actual.
class EquiposHomePage extends StatefulWidget {
  const EquiposHomePage({super.key});
  @override
  State<EquiposHomePage> createState() => _EquiposHomePageState();
}

class _EquiposHomePageState extends State<EquiposHomePage> {
  int _idx = 0;
  Set<String> _roles = {};

  static const _titulos = [
    'Por referencia',
    'Movimiento',
    'Disponibles',
    'En mantenimiento',
  ];

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() => _roles = r);
    });
  }

  bool get _admin => _roles.contains(Roles.admin);
  bool get _gestiona => _admin || _roles.contains(Roles.coordinador);

  void _ir(Widget pagina) {
    Navigator.pop(context); // cerrar el menú
    Navigator.push(context, MaterialPageRoute(builder: (_) => pagina));
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text('Equipos · ${_titulos[_idx]}',
            overflow: TextOverflow.ellipsis),
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
            ListTile(
              leading: const Icon(Icons.download_for_offline),
              title: const Text('Informes'),
              subtitle: const Text('Descargar en Excel/CSV'),
              onTap: () => _ir(const EquiposReportesPage()),
            ),
            const Divider(),
            // Catálogos propios del módulo.
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Referencias'),
              subtitle: const Text('Catálogo de modelos de equipo'),
              onTap: () => _ir(const ActivoReferenciasPage()),
            ),
            ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Terceros'),
              subtitle: const Text('Talleres, clientes y proveedores'),
              onTap: () => _ir(const ActivoTercerosPage()),
            ),
            const Divider(),
            // Ítems COMPARTIDOS con el Drawer de Inventario (sección 8.3).
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
      // El alta solo se ofrece desde el Nivel 1: un equipo nuevo todavía no
      // existe, así que no tiene sentido buscarlo en las otras pestañas.
      floatingActionButton: _idx == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                final creado = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => const ActivoAltaPage()));
                if (creado == true) setState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo equipo'),
            )
          : null,
      body: IndexedStack(
        index: _idx,
        children: const [
          _PorReferencia(),
          _BuscadorMovimiento(),
          _ListaDisponibilidad(disponible: true),
          _EnMantenimiento(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.inventory_2), label: 'Referencias'),
          NavigationDestination(
              icon: Icon(Icons.swap_vert), label: 'Movimiento'),
          NavigationDestination(
              icon: Icon(Icons.check_circle), label: 'Disponibles'),
          NavigationDestination(
              icon: Icon(Icons.build), label: 'Mantenim.'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 1 — Nivel 1: resumen por referencia
// ---------------------------------------------------------------------

class _PorReferencia extends StatefulWidget {
  const _PorReferencia();
  @override
  State<_PorReferencia> createState() => _PorReferenciaState();
}

class _PorReferenciaState extends State<_PorReferencia> {
  List<ResumenReferencia> _filas = [];
  final _buscador = TextEditingController();
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Al registrar un alta o un movimiento, este contador cambia.
    ActivosService.revision.addListener(_cargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_cargar);
    _buscador.dispose();
    super.dispose();
  }

  /// Filtra sin tildes y sin importar el orden de las palabras, igual que
  /// la búsqueda de Elementos: escribir "centrifuga bomba" tiene que
  /// encontrar "BOMBA CENTRÍFUGA".
  List<ResumenReferencia> get _visibles {
    final q = normalizarTexto(_buscador.text);
    if (q.isEmpty) return _filas;
    final palabras = q.split(' ').where((p) => p.isNotEmpty);
    return _filas.where((f) {
      final texto = normalizarTexto(f.etiqueta);
      return palabras.every(texto.contains);
    }).toList();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await ActivosService.resumenPorReferencia();
      if (!mounted) return;
      setState(() { _filas = res; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _MensajeError(error: _error!, onReintentar: _cargar);
    if (_filas.isEmpty) {
      return const _Vacio(
        texto: 'Todavía no hay equipos registrados.\n'
            'Crea el primero con el botón "Nuevo equipo".',
      );
    }
    final visibles = _visibles;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _buscador,
            // Filtra mientras se escribe: la lista ya está en memoria, así
            // que no hay consulta que esperar.
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar modelo, marca…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _buscador.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Limpiar',
                      onPressed: () =>
                          setState(() => _buscador.clear()),
                    ),
            ),
          ),
        ),
        if (visibles.isEmpty)
          const Expanded(
            child: _Vacio(texto: 'Ninguna referencia coincide con la búsqueda.'),
          )
        else
          Expanded(child: _lista(visibles)),
      ],
    );
  }

  Widget _lista(List<ResumenReferencia> visibles) {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: visibles.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = visibles[i];
          return ListTile(
            title: Text(f.etiqueta),
            subtitle: Text(
                '${f.disponibles} disponibles · ${f.noDisponibles} no disponibles'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${f.total}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('unidades', style: TextStyle(fontSize: 10)),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivosDeReferenciaPage(
                  referenciaId: f.referenciaId,
                  titulo: f.etiqueta,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 2 — Movimiento: buscar el equipo y dejar que su estado decida
// ---------------------------------------------------------------------

class _BuscadorMovimiento extends StatefulWidget {
  const _BuscadorMovimiento();
  @override
  State<_BuscadorMovimiento> createState() => _BuscadorMovimientoState();
}

class _BuscadorMovimientoState extends State<_BuscadorMovimiento> {
  static const _porPagina = 50;

  final _buscador = TextEditingController();
  final List<Activo> _resultados = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargando = false;
  bool _cargandoMas = false;
  bool _buscado = false;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _buscar({bool desdeCero = true}) async {
    if (_cargandoMas) return;
    setState(() {
      _buscado = true;
      if (desdeCero) {
        _offset = 0;
        _hayMas = true;
        _resultados.clear();
        _cargando = true;
      } else {
        _cargandoMas = true;
      }
    });
    try {
      final res = await ActivosService.listar(
        serial: _buscador.text.trim().isEmpty ? null : _buscador.text.trim(),
        offset: _offset,
        limit: _porPagina,
      );
      if (!mounted) return;
      setState(() {
        _resultados.addAll(res);
        _offset += res.length;
        if (res.length < _porPagina) _hayMas = false;
        _cargando = false;
        _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _cargandoMas = false; });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo buscar: $e')));
    }
  }

  /// El estado del equipo decide a dónde lleva tocarlo (sección 7.0.1):
  /// entregado → reingreso, operativo → salida, cualquier otro → su ficha,
  /// porque ahí no aplica una entrada o salida directa.
  Future<void> _abrir(Activo a) async {
    final destino = (a.estado == 'entregado' || a.estado == 'operativo')
        ? ActivoMovimientoPage(activo: a)
        : ActivoDetallePage(activoId: a.id) as Widget;
    final hecho = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => destino));
    if (hecho == true) _buscar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _buscador,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              hintText: 'Buscar por serial…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'Buscar',
                onPressed: _buscar,
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Toca un equipo y la app decide sola si corresponde una entrada '
            'o una salida, según cómo esté.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : !_buscado
                  ? const _Vacio(
                      texto: 'Busca un equipo por su serial para registrarle '
                          'un movimiento.')
                  : _resultados.isEmpty
                      ? const _Vacio(texto: 'Ningún equipo coincide.')
                      : ListView.separated(
                          itemCount: _resultados.length + 1,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            if (i == _resultados.length) {
                              return PieCargarMas(
                                cargando: _cargandoMas,
                                hayMas: _hayMas,
                                onCargarMas: () => _buscar(desdeCero: false),
                              );
                            }
                            final a = _resultados[i];
                            return ListTile(
                              title: Text(a.serial),
                              subtitle: Text(a.referenciaNombre ?? '—'),
                              trailing: Text(a.estadoEtiqueta,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => _abrir(a),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Pestaña 3 — Nivel 3: disponibles ahora (vista global)
// ---------------------------------------------------------------------

class _ListaDisponibilidad extends StatefulWidget {
  final bool disponible;
  const _ListaDisponibilidad({required this.disponible});
  @override
  State<_ListaDisponibilidad> createState() => _ListaDisponibilidadState();
}

class _ListaDisponibilidadState extends State<_ListaDisponibilidad> {
  static const _porPagina = 50;

  final List<ActivoDisponibilidad> _filas = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    ActivosService.revision.addListener(_recargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_recargar);
    super.dispose();
  }

  void _recargar() => _cargar(desdeCero: true);

  Future<void> _cargar({bool desdeCero = false}) async {
    if (!mounted || _cargandoMas) return;
    setState(() {
      _error = null;
      if (desdeCero) {
        _offset = 0;
        _hayMas = true;
        _filas.clear();
        _cargando = true;
      } else if (_offset > 0) {
        _cargandoMas = true;
      }
    });
    try {
      final res = await ActivosService.disponibles(
          disponible: widget.disponible,
          offset: _offset,
          limit: _porPagina);
      if (!mounted) return;
      setState(() {
        _filas.addAll(res);
        _offset += res.length;
        // Una página incompleta significa que ya no queda nada detrás.
        if (res.length < _porPagina) _hayMas = false;
        _cargando = false;
        _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
        _cargandoMas = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MensajeError(error: _error!, onReintentar: _recargarAsync);
    }
    if (_filas.isEmpty) {
      return const _Vacio(texto: 'No hay equipos disponibles ahora mismo.');
    }
    return RefreshIndicator(
      onRefresh: _recargarAsync,
      child: ListView.separated(
        itemCount: _filas.length + 1, // +1: pie de "Cargar más"
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == _filas.length) {
            return PieCargarMas(
              cargando: _cargandoMas,
              hayMas: _hayMas,
              onCargarMas: _cargar,
            );
          }
          final d = _filas[i];
          return ListTile(
            title: Text(d.activo.serial),
            subtitle: Text(
                '${d.activo.referenciaNombre ?? '—'} · ${d.activo.bodegaNombre ?? '—'}'),
            trailing: Text('\$${d.activo.valorActual.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ActivoDetallePage(activoId: d.activo.id)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _recargarAsync() => _cargar(desdeCero: true);
}

// ---------------------------------------------------------------------
// Pestaña 4 — En mantenimiento
// ---------------------------------------------------------------------

class _EnMantenimiento extends StatefulWidget {
  const _EnMantenimiento();
  @override
  State<_EnMantenimiento> createState() => _EnMantenimientoState();
}

class _EnMantenimientoState extends State<_EnMantenimiento> {
  static const _porPagina = 50;

  final List<Activo> _filas = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    ActivosService.revision.addListener(_recargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_recargar);
    super.dispose();
  }

  void _recargar() => _cargar(desdeCero: true);
  Future<void> _recargarAsync() => _cargar(desdeCero: true);

  Future<void> _cargar({bool desdeCero = false}) async {
    if (!mounted || _cargandoMas) return;
    setState(() {
      _error = null;
      if (desdeCero) {
        _offset = 0;
        _hayMas = true;
        _filas.clear();
        _cargando = true;
      } else if (_offset > 0) {
        _cargandoMas = true;
      }
    });
    try {
      final res = await ActivosService.enMantenimiento(
          offset: _offset, limit: _porPagina);
      if (!mounted) return;
      setState(() {
        _filas.addAll(res);
        _offset += res.length;
        if (res.length < _porPagina) _hayMas = false;
        _cargando = false;
        _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
        _cargandoMas = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MensajeError(error: _error!, onReintentar: _recargarAsync);
    }
    if (_filas.isEmpty) {
      return const _Vacio(texto: 'Ningún equipo está en mantenimiento.');
    }
    return RefreshIndicator(
      onRefresh: _recargarAsync,
      child: ListView.separated(
        itemCount: _filas.length + 1, // +1: pie de "Cargar más"
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == _filas.length) {
            return PieCargarMas(
              cargando: _cargandoMas,
              hayMas: _hayMas,
              onCargarMas: _cargar,
            );
          }
          final a = _filas[i];
          return ListTile(
            leading: const Icon(Icons.build, color: Colors.orange),
            title: Text(a.serial),
            subtitle: Text([
              a.referenciaNombre ?? '—',
              a.estadoEtiqueta,
              if (a.mantenimientoActor != null &&
                  a.mantenimientoActor!.isNotEmpty)
                a.mantenimientoActor!,
            ].join(' · ')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ActivoDetallePage(activoId: a.id)),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Piezas compartidas por las pestañas
// ---------------------------------------------------------------------

class _Vacio extends StatelessWidget {
  final String texto;
  const _Vacio({required this.texto});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      );
}

class _MensajeError extends StatelessWidget {
  final String error;
  final Future<void> Function() onReintentar;
  const _MensajeError({required this.error, required this.onReintentar});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text('No se pudo cargar.\n$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: onReintentar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}
