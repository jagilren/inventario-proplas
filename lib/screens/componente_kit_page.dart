import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../activos_service.dart';
import '../util/tiempo.dart';
import '../widgets/kit_componentes.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');
String _cuando(DateTime f) => _fechaHora.format(horaColombia(f));

/// La vida de UN componente de un kit (Fase 5, docs/plan-kits-equipos.md):
/// cuántos hay, su historia, registrar un movimiento y anular uno.
///
/// Pantalla completa y no una hoja: tiene una lista que crece y acciones
/// sobre cada línea, y en un celular eso necesita todo el alto y un botón de
/// volver claro.
class ComponenteKitPage extends StatefulWidget {
  final ActivoComponente componente;
  /// El serial del kit, para el título: el nombre del componente solo no dice
  /// de cuál kit es.
  final String serialKit;
  /// Un kit entregado ya no es nuestro (regla 3): no se le mueve nada.
  final bool kitEntregado;
  /// Anular: solo el admin (la base lo exige, schema_v66).
  final bool esAdmin;

  const ComponenteKitPage({
    super.key,
    required this.componente,
    required this.serialKit,
    required this.kitEntregado,
    required this.esAdmin,
  });

  @override
  State<ComponenteKitPage> createState() => _ComponenteKitPageState();
}

class _ComponenteKitPageState extends State<ComponenteKitPage> {
  late ActivoComponente _componente = widget.componente;
  List<MovimientoComponente> _movs = [];
  bool _cargando = true;
  String? _error;
  bool _anulando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    ActivosService.revision.addListener(_cargar);
  }

  @override
  void dispose() {
    ActivosService.revision.removeListener(_cargar);
    super.dispose();
  }

  /// Historial y cantidad actual. La cantidad se relee de la base: la calcula
  /// ella desde los movimientos, la app nunca la deduce.
  Future<void> _cargar() async {
    try {
      final movs =
          await ActivosService.movimientosComponente(widget.componente.id);
      final comps =
          await ActivosService.componentes(widget.componente.activoId);
      if (!mounted) return;
      setState(() {
        _movs = movs;
        for (final c in comps) {
          if (c.id == widget.componente.id) _componente = c;
        }
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  /// Los movimientos que ya tienen su anulación: no se pueden anular otra vez
  /// y se marcan "ANULADO".
  Set<String> get _anulados => {
        for (final m in _movs)
          if (m.anulaMovimientoId != null) m.anulaMovimientoId!,
      };

  Future<void> _registrar() async {
    final antes = _componente.cantidad;
    final hecho = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HojaMovimientoComponente(componente: _componente),
    );
    if (hecho != true) return;
    await _cargar();
    if (!mounted) return;
    // Confirmación explícita, con la cantidad que dice la BASE después del
    // movimiento (no la que calculó la hoja): la hoja se cierra y sin esto
    // solo cambiaba un número, fácil de no notar.
    final ahora = _componente.cantidad;
    final dif = ahora - antes;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Registrado: ${_componente.nombre} '
        '${dif >= 0 ? "+" : "−"}${textoCantidad(dif.abs())}. '
        'Ahora hay ${textoCantidad(ahora)}.',
      ),
    ));
  }

  Future<void> _anular(MovimientoComponente m) async {
    // El motivo se pide aquí mismo (schema_v67): la anulación también sale
    // en las observaciones del equipo y ahí tiene que decir por qué.
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => DialogoAnularComponente(
        descripcion: '${m.descripcionAccesible}, el ${_cuando(m.fecha)}.',
      ),
    );
    if (motivo == null || !mounted) return;
    setState(() => _anulando = true);
    try {
      await ActivosService.anularMovimientoComponente(m, observacion: motivo);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo anular: $e')));
    } finally {
      if (mounted) setState(() => _anulando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _componente;
    final esquema = Theme.of(context).colorScheme;
    final anulados = _anulados;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(c.nombre,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17)),
            Text('Kit ${widget.serialKit}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No se pudo cargar.\n$_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Cuántos hay: lo primero que se necesita saber.
                      Semantics(
                        container: true,
                        label: 'Hay ${textoCantidad(c.cantidad)}. '
                            'A ${_money.format(c.valorUnitario)} cada una. '
                            'Subtotal ${_money.format(c.subtotal)}',
                        excludeSemantics: true,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.end,
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Hay',
                                        style: TextStyle(
                                            color: esquema.onSurfaceVariant)),
                                    Text(textoCantidad(c.cantidad),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        'a ${_money.format(c.valorUnitario)} '
                                        'c/u',
                                        style: TextStyle(
                                            color: esquema.onSurfaceVariant)),
                                    Text(_money.format(c.subtotal),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.kitEntregado)
                        const Text(
                          'Este kit fue entregado y ya no nos pertenece: no se '
                          'le registran movimientos.',
                          style: TextStyle(fontSize: 12.5),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _registrar,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text('Registrar movimiento'),
                        ),
                      const SizedBox(height: 24),
                      Text('Historial',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Del más reciente al más antiguo.',
                          style: TextStyle(
                              fontSize: 12, color: esquema.onSurfaceVariant)),
                      if (_movs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('Todavía no tiene movimientos.'),
                        ),
                      for (final m in _movs)
                        LineaMovimientoComponente(
                          movimiento: m,
                          anulado: anulados.contains(m.id),
                          // Anular: admin, un movimiento normal, no anulado
                          // todavía, y el kit sigue siendo nuestro.
                          onAnular: widget.esAdmin &&
                                  !widget.kitEntregado &&
                                  !m.esAnulacion &&
                                  !anulados.contains(m.id) &&
                                  !_anulando
                              ? () => _anular(m)
                              : null,
                        ),
                    ],
                  ),
                ),
    );
  }
}
