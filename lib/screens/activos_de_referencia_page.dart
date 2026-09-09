import 'package:flutter/material.dart';
import '../activos_service.dart';
import 'activo_detalle_page.dart';

/// Nivel 2 del módulo: las unidades individuales de una referencia, con los
/// filtros rápidos Todas / Disponibles / No disponibles.
///
/// "Disponible" se lee de la vista `activos_disponibilidad`, donde es una
/// regla derivada (operativo + ubicado en bodega propia), no un campo suelto.
class ActivosDeReferenciaPage extends StatefulWidget {
  final String referenciaId;
  final String titulo;
  const ActivosDeReferenciaPage({
    super.key,
    required this.referenciaId,
    required this.titulo,
  });
  @override
  State<ActivosDeReferenciaPage> createState() =>
      _ActivosDeReferenciaPageState();
}

class _ActivosDeReferenciaPageState extends State<ActivosDeReferenciaPage> {
  /// null = todas; true = disponibles; false = no disponibles.
  bool? _filtro;
  List<ActivoDisponibilidad> _filas = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final res = await ActivosService.disponibles(
        referenciaId: widget.referenciaId,
        disponible: _filtro,
        limit: 200,
      );
      if (!mounted) return;
      setState(() { _filas = res; _cargando = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            // Wrap: en un teléfono angosto los filtros bajan de línea en vez
            // de apretarse.
            child: Wrap(
              spacing: 8,
              children: [
                for (final opcion in [null, true, false])
                  ChoiceChip(
                    label: Text(switch (opcion) {
                      null => 'Todas',
                      true => 'Disponibles',
                      _ => 'No disponibles',
                    }),
                    selected: _filtro == opcion,
                    onSelected: (_) {
                      setState(() => _filtro = opcion);
                      _cargar();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
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
              Text('No se pudo cargar.\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_filas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay unidades que cumplan ese filtro.',
              textAlign: TextAlign.center),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _filas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final d = _filas[i];
          final a = d.activo;
          return ListTile(
            leading: Icon(
              d.disponible ? Icons.check_circle : Icons.remove_circle_outline,
              color: d.disponible ? Colors.green : Colors.grey,
            ),
            title: Text(a.serial),
            subtitle: Text([
              a.estadoEtiqueta,
              a.condicionEtiqueta,
              if (a.bodegaNombre != null) a.bodegaNombre!,
            ].join(' · ')),
            trailing: Text('\$${a.valorActual.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12)),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ActivoDetallePage(activoId: a.id)),
              );
              await _cargar();
            },
          );
        },
      ),
    );
  }
}
