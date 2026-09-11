import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../activos_service.dart';
import '../widgets/pie_cargar_mas.dart';
import 'activo_detalle_page.dart';

// Formato de dinero de toda la app: signo peso y separador de miles.
final _money = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Cuánto se queda a la vista la explicación de un filtro o de un estado.
/// En el celular no hay "pasar el mouse": aparece al MANTENER PRESIONADO y se
/// va sola; flota encima, así que no corre nada de la pantalla.
const duracionAyudaEquipos = Duration(seconds: 4);

final _temaAyuda = TooltipThemeData(
  showDuration: duracionAyudaEquipos,
  // En el PC, al pasar el mouse: sin esperar tanto que parezca que no hay.
  waitDuration: Duration(milliseconds: 400),
  // Que no tape el dedo: sale debajo y con margen.
  preferBelow: true,
  verticalOffset: 24,
  textStyle: TextStyle(fontSize: 13, color: Colors.white),
);

/// Nivel 2 del módulo: las unidades individuales de una referencia, con los
/// filtros rápidos Todas / Disponibles / No disponibles / Vendidos.
///
/// "Disponible" se lee de la vista `activos_disponibilidad`, donde es una
/// regla derivada (operativo + ubicado en bodega propia), no un campo suelto.
/// "Vendido" es un equipo entregado a un centro de costo (estado
/// `entregado`): ya no es nuestro, y antes se contaba como "no disponible"
/// junto con los que están en el taller (schema_v68).
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

  FiltroEquipos _filtro = FiltroEquipos.todas;
  /// Cuántas unidades hay en cada filtro, para mostrarlo en los chips. Null
  /// sin señal: los chips salen sin número.
  ResumenReferencia? _cuentas;
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
    _cargarCuentas();
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

  void _alCambiarAlgo() {
    if (!mounted) return;
    _recargar();
    _cargarCuentas();
  }

  Future<void> _recargar() => _cargar(desdeCero: true);

  /// Las cuentas salen de la MISMA función que la lista de referencias
  /// (activos_resumen_por_referencia): así los números de los chips y los de
  /// la pantalla anterior no se pueden contradecir.
  Future<void> _cargarCuentas() async {
    try {
      final todas = await ActivosService.resumenPorReferencia();
      if (!mounted) return;
      setState(() {
        _cuentas = todas
            .where((r) => r.referenciaId == widget.referenciaId)
            .firstOrNull;
      });
    } catch (_) {
      // Sin señal: los chips se quedan sin número; la lista funciona igual.
    }
  }

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
        filtro: _filtro,
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
            child: FiltrosEquipos(
              valor: _filtro,
              cuentas: _cuentas,
              onCambio: (f) {
                setState(() => _filtro = f);
                _recargar();
              },
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
                ? switch (_filtro) {
                    FiltroEquipos.vendidos =>
                      'De esta referencia no se ha vendido ninguna unidad.',
                    FiltroEquipos.disponibles =>
                      'No hay unidades disponibles de esta referencia.',
                    FiltroEquipos.noDisponibles =>
                      'No hay unidades no disponibles: ninguna está en '
                          'taller, de baja ni para repuestos.',
                    FiltroEquipos.todas => 'No hay unidades de esta referencia.',
                  }
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
          return LineaUnidad(
            unidad: d,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ActivoDetallePage(activoId: d.activo.id)),
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

/// Los cuatro filtros de EQUIPOS POR REFERENCIA. En un Wrap: en un teléfono
/// angosto bajan de línea en vez de apretarse. Con "Vendidos" elegido, una
/// línea dice qué es un vendido: la palabra sola no dice que ya no es nuestro.
class FiltrosEquipos extends StatelessWidget {
  final FiltroEquipos valor;
  final ValueChanged<FiltroEquipos> onCambio;
  /// Si se da, cada chip dice cuántas: "No disponibles (1)", "Vendidas (2)".
  /// Así se ve que las vendidas ya no cuentan como no disponibles.
  final ResumenReferencia? cuentas;

  const FiltrosEquipos({
    super.key,
    required this.valor,
    required this.onCambio,
    this.cuentas,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TooltipTheme(
          data: _temaAyuda,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in FiltroEquipos.values)
                ChoiceChip(
                  label: Text(cuentas == null
                      ? f.etiqueta
                      : '${f.etiqueta} (${cuentas!.cuantas(f)})'),
                  // Mantener presionado (celular) o pasar el mouse (PC).
                  // El lector de pantalla lo lee junto con el nombre.
                  tooltip: f.explicacion,
                  selected: valor == f,
                  onSelected: (_) => onCambio(f),
                ),
            ],
          ),
        ),
        if (valor == FiltroEquipos.vendidos)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Entregadas a un centro de costo: ya no son nuestras, salieron '
              'del inventario.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Una unidad de la referencia. Un VENDIDO lo dice con texto y con su propio
/// ícono (no solo con un color), y no muestra bodega: ya no está en ninguna.
class LineaUnidad extends StatelessWidget {
  final ActivoDisponibilidad unidad;
  final VoidCallback? onTap;

  const LineaUnidad({super.key, required this.unidad, this.onTap});

  bool get vendido => unidad.activo.estado == 'entregado';

  @override
  Widget build(BuildContext context) {
    final a = unidad.activo;
    final esquema = Theme.of(context).colorScheme;
    return ListTile(
      // El ícono explica qué significa al mantenerlo presionado; tocar la
      // fila sigue abriendo el equipo.
      leading: TooltipTheme(
        data: _temaAyuda,
        child: Tooltip(
          message: unidad.categoria.unidad,
          child: Icon(
            vendido
                ? Icons.sell_outlined
                : (unidad.disponible
                    ? Icons.check_circle
                    : Icons.remove_circle_outline),
            color: vendido
                ? esquema.tertiary
                : (unidad.disponible ? Colors.green : Colors.grey),
          ),
        ),
      ),
      title: Text(a.serial),
      subtitle: Text([
        if (vendido) 'Vendido' else a.estadoEtiqueta,
        a.condicionEtiqueta,
        if (!vendido && a.bodegaNombre != null) a.bodegaNombre!,
      ].join(' · ')),
      trailing: Text(_money.format(a.valorActual),
          style: const TextStyle(fontSize: 12)),
      onTap: onTap,
    );
  }
}
