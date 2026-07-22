import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../local_store.dart';
import '../sync_service.dart';

final _fmt = DateFormat('dd/MM/yyyy HH:mm');

/// Estado del modo sin conexión: qué hay guardado, qué falta subir,
/// y botones para descargar el catálogo o forzar la sincronización.
class SincronizacionPage extends StatefulWidget {
  const SincronizacionPage({super.key});
  @override
  State<SincronizacionPage> createState() => _SincronizacionPageState();
}

class _SincronizacionPageState extends State<SincronizacionPage> {
  int _elementosGuardados = 0;
  int _centrosGuardados = 0;
  DateTime? _ultima;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final e = await LocalStore.leerElementos();
    final c = await LocalStore.leerCentros();
    final u = await LocalStore.ultimaSincronizacion();
    await SyncService.refrescarPendientes();
    if (mounted) {
      setState(() {
        _elementosGuardados = e.length;
        _centrosGuardados = c.length;
        _ultima = u;
      });
    }
  }

  Future<void> _descargar() async {
    setState(() => _ocupado = true);
    final ok = await SyncService.refrescarCache();
    await _cargar();
    if (mounted) {
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? '✓ Catálogo descargado para usar sin señal'
              : 'No se pudo descargar: revisa la conexión')));
    }
  }

  Future<void> _subir() async {
    setState(() => _ocupado = true);
    final n = await SyncService.sincronizar();
    await _cargar();
    if (mounted) {
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n > 0
              ? '✓ $n movimiento(s) subido(s)'
              : 'No había nada por subir (o sigue sin conexión)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trabajo sin conexión')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: SyncService.enLinea,
            builder: (_, enLinea, __) => Card(
              color: enLinea ? Colors.green.shade50 : Colors.orange.shade50,
              child: ListTile(
                leading: Icon(enLinea ? Icons.cloud_done : Icons.cloud_off,
                    color: enLinea ? Colors.green : Colors.orange, size: 30),
                title: Text(enLinea ? 'Con conexión' : 'Sin conexión',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(enLinea
                    ? 'Los movimientos se guardan al instante en el servidor.'
                    : 'Los movimientos se guardan en el teléfono y subirán solos.'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: SyncService.pendientes,
            builder: (_, n, __) => Card(
              child: ListTile(
                leading: Icon(Icons.cloud_upload,
                    color: n > 0 ? Colors.blue : Colors.grey),
                title: Text('$n movimiento(s) por subir'),
                subtitle: Text(n > 0
                    ? 'Se subirán automáticamente al recuperar la señal.'
                    : 'Todo está sincronizado.'),
                trailing: n > 0
                    ? TextButton(
                        onPressed: _ocupado ? null : _subir,
                        child: const Text('Subir ya'))
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: Text('$_elementosGuardados elementos guardados'),
                  subtitle: Text('$_centrosGuardados centros de costo · '
                      'última descarga: '
                      '${_ultima == null ? 'nunca' : _fmt.format(_ultima!)}'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _ocupado ? null : _descargar,
                      icon: _ocupado
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download),
                      label: const Text('Descargar catálogo ahora'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Consejo: antes de ir a una bodega sin señal, abre esta pantalla '
              'con internet y toca "Descargar catálogo ahora". Así podrás '
              'buscar elementos y registrar movimientos sin conexión.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
