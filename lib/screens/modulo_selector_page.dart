import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data.dart';
import '../activos_service.dart';
import '../ajustes.dart';
import '../sync_service.dart';
import '../realtime_service.dart';
import 'home_page.dart';
import 'equipos_home_page.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Primera pantalla tras el login: deja elegir entre Inventario (Piping) y
/// Equipos. Ver docs/plan-modulo-equipos.md sección 8.0.
///
/// Regla clave: quien NO tiene acceso a Equipos no ve esta pantalla en
/// absoluto — pasa derecho a Inventario, exactamente como funcionaba antes.
/// Una pantalla para "elegir" entre una sola opción sería un estorbo.
class ModuloSelectorPage extends StatefulWidget {
  const ModuloSelectorPage({super.key});
  @override
  State<ModuloSelectorPage> createState() => _ModuloSelectorPageState();
}

class _ModuloSelectorPageState extends State<ModuloSelectorPage> {
  Set<String> _roles = {};
  bool _cargado = false;
  List<ValorizadoBodega> _valorizado = [];

  @override
  void initState() {
    super.initState();
    InventarioService.misRoles().then((r) {
      if (mounted) setState(() { _roles = r; _cargado = true; });
      if (r.contains(Roles.admin) ||
          r.contains(Roles.coordinador) ||
          r.contains(Roles.equipos)) {
        _cargarValorizado();
      }
    });
    // Arranque de sesión: vivía en HomePage.initState(), se movió aquí para
    // que corra una sola vez sin importar a qué módulo se entre.
    SyncService.alSesionIniciada();
    RealtimeService.iniciar();
    Ajustes.cargar();
  }

  /// El resumen es un vistazo útil, no un requisito para entrar: si no se
  /// puede traer (sin señal, por ejemplo) la pantalla funciona igual y
  /// simplemente no se muestra.
  Future<void> _cargarValorizado() async {
    try {
      final v = await ActivosService.valorizadoPorBodega();
      if (mounted) setState(() => _valorizado = v);
    } catch (_) {
      // Se queda sin resumen, a propósito.
    }
  }

  bool get _puedeEquipos =>
      _roles.contains(Roles.admin) ||
      _roles.contains(Roles.coordinador) ||
      _roles.contains(Roles.equipos);

  @override
  Widget build(BuildContext context) {
    if (!_cargado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Sin acceso a Equipos: la app se comporta igual que siempre.
    if (!_puedeEquipos) return const HomePage();

    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/rpci_letras.png', height: 30),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Elegir módulo', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Hola, $email',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text('¿Con qué quieres trabajar?',
                style: Theme.of(context).textTheme.titleLarge),
            if (_valorizado.isNotEmpty) ...[
              const SizedBox(height: 14),
              _ResumenValorizado(filas: _valorizado),
            ],
            const SizedBox(height: 20),
            _FichaModulo(
              icono: Icons.inventory_2,
              titulo: 'Inventario (Piping)',
              detalle: 'Existencias, entradas, salidas, aprovechamientos',
              color: Theme.of(context).colorScheme.primary,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HomePage())),
            ),
            const SizedBox(height: 14),
            _FichaModulo(
              icono: Icons.precision_manufacturing,
              titulo: 'Equipos',
              detalle: 'Bombas, motores y herramienta: estado y ubicación',
              color: Colors.teal.shade700,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EquiposHomePage())),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vistazo ejecutivo antes de elegir módulo: cuánto vale lo guardado en cada
/// bodega, sumando inventario y equipos (sección 8.0 del plan).
class _ResumenValorizado extends StatelessWidget {
  final List<ValorizadoBodega> filas;
  const _ResumenValorizado({required this.filas});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Valorizado en bodega',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final f in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    // Expanded: un nombre de bodega largo recorta en vez de
                    // desbordar la fila en un teléfono angosto.
                    Expanded(
                      child: Text(f.bodega,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(_money.format(f.total),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Text('Inventario de piping + equipos.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// Ficha grande y tocable. Alto mínimo generoso: la condición de móvil de la
/// sección 0 del plan pide área táctil cómoda y que no se apriete a 360px.
class _FichaModulo extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final Color color;
  final VoidCallback onTap;

  const _FichaModulo({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color,
                child: Icon(icono, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              // Expanded: el texto reacomoda en pantalla angosta en vez de
              // desbordarse (condición de móvil, sección 0 del plan).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(detalle,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
