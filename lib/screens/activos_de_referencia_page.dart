import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../activos_service.dart';
import '../widgets/pie_cargar_mas.dart';
import 'activo_detalle_page.dart';

// Formato de dinero de toda la app: signo peso y separador de miles.
final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

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
  static const _porPagina = 50;

  /// null = todas; true = disponibles; false = no disponibles.
  bool? _filtro;
  final _buscador = TextEditingController();
  // Espera a que el usuario deje de escribir antes de consultar. Sin esto
  // habría una consulta por cada letra; con Enter obligatorio, en un móvil
  // el usuario escribe y se queda esperando resultados que nunca llegan.
  Timer? _teclado;
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
    // Cualquier cambio de estado, condición o ubicación empuja este
    // contador; así la lista se entera aunque el cambio venga de otra
    // pantalla o de otro usuario.
    ActivosService.revision.addListener(_alCambiarAlgo);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_alCambiarAlgo);
    _teclado?.cancel();
    _buscador.dispose();
    super.dispose();
  }

  void _alCambiarAlgo() { if (mounted) _recargar(); }

  Future<void> _recargar() => _cargar(desdeCero: true);

  Future<void> _cargar({bool desdeCero = false}) async {
    if (_cargandoMas) return;
    setState(() {
      _error = null;
      if (desdeCero || _offset == 0) {
        _offset = 0;
        _hayMas = true;
        _filas.clear();
        _cargando = true;
      } else {
        _cargandoMas = true;
      }
    });
    try {
      final res = await ActivosService.disponibles(
        referenciaId: widget.referenciaId,
        disponible: _filtro,
        serial: _buscador.text,
        offset: _offset,
        limit: _porPagina,
      );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _buscador,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              // Se busca contra la BASE, no sobre lo ya descargado: con
              // miles de unidades de un mismo modelo, filtrar en memoria
              // diría "no existe" cuando el serial está más adelante.
              onSubmitted: (_) => _recargar(),
              onChanged: (_) {
                setState(() {});           // refresca el botón de limpiar
                _teclado?.cancel();
                _teclado = Timer(
                    const Duration(milliseconds: 400), _recargar);
              },
              decoration: InputDecoration(
                hintText: 'Buscar por serial…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _buscador.text.isEmpty
                    ? IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Buscar',
                        onPressed: _recargar,
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Limpiar',
                        onPressed: () {
                          _buscador.clear();
                          _recargar();
                        },
                      ),
              ),
            ),
          ),
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
                      _recargar();
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
              FilledButton(
                  onPressed: _recargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_filas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _buscador.text.trim().isEmpty
                ? 'No hay unidades que cumplan ese filtro.'
                : 'Ningún serial coincide con la búsqueda.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _recargar,
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
            trailing: Text(_money.format(a.valorActual),
                style: const TextStyle(fontSize: 12)),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ActivoDetallePage(activoId: a.id)),
              );
              // _recargar y NO _cargar: sin reiniciar, al haber una página
              // ya cargada esto se tomaba como "cargar más" y AÑADÍA las
              // filas de nuevo, duplicadas y con el estado viejo.
              await _recargar();
            },
          );
        },
      ),
    );
  }
}
