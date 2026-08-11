import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../reportes.dart';

final _f = DateFormat('dd/MM/yyyy');

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});
  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  late DateTime _desde;
  late DateTime _hasta;
  String? _generando;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde = DateTime(hoy.year, hoy.month, 1); // inicio de mes
    _hasta = hoy;
  }

  /// Cambia el rango. Es UNO solo para toda la pantalla: se muestra dentro de
  /// cada informe que lo usa, así que tocarlo en cualquiera de ellos lo cambia
  /// para todos. Es a propósito: normalmente uno quiere comparar el mismo mes
  /// en varios informes, no llevar tres rangos distintos.
  Future<void> _pickRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
      helpText: 'Rango de fechas del informe',
    );
    if (r != null) setState(() { _desde = r.start; _hasta = r.end; });
  }

  Future<void> _descargar(String id, Future<void> Function() fn) async {
    setState(() => _generando = id);
    try {
      await fn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Informe descargado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _generando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informes'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2), text: 'Inventario'),
              Tab(icon: Icon(Icons.recycling), text: 'Aprovechamientos'),
            ],
          ),
        ),
        // El rango de fechas ya NO va aquí arriba: antes se veía como si
        // aplicara a los cinco informes, cuando solo tres lo usan. Ahora cada
        // informe muestra en su propia tarjeta si trabaja con fechas o si es
        // una foto del momento.
        body: TabBarView(
          children: [
            _tabInventario(),
            _tabAprovechamientos(),
          ],
        ),
      ),
    );
  }

  /// Fila del rango, dentro de la tarjeta de un informe que SÍ usa fechas.
  /// Se toca para cambiarlo, aparte del botón de descargar.
  Widget _filaRango() {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _generando != null ? null : _pickRango,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.06),
          border: Border(top: BorderSide(color: c.outlineVariant)),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_f.format(_desde)}  →  ${_f.format(_hasta)}',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: c.primary),
              ),
            ),
            Icon(Icons.edit_calendar, size: 18, color: c.primary),
          ],
        ),
      ),
    );
  }

  /// Fila para los informes que NO usan fechas: dice que son una foto de
  /// ahora, para que nadie se quede esperando que el rango los afecte.
  Widget _filaSinFechas() {
    final gris = Theme.of(context).colorScheme.outline;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.photo_camera_outlined, size: 18, color: gris),
          const SizedBox(width: 8),
          Text('Foto de ahora · no usa fechas',
              style: TextStyle(color: gris, fontSize: 13)),
        ],
      ),
    );
  }

  /// Pestaña 1: informes del inventario oficial.
  Widget _tabInventario() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _reporte('existencias', 'Existencias valorizadas',
              'Inventario actual por elemento y bodega, con valorización.',
              Icons.inventory_2, () => Reportes.existenciasValorizadas(),
              usaFechas: false),
          _reporte('movimientos', 'Movimientos por fecha',
              'Entradas, salidas, traslados y ajustes del rango elegido.',
              Icons.swap_vert, () => Reportes.movimientos(_desde, _hasta),
              usaFechas: true),
          _reporte('consumo', 'Consumo por centro de costo',
              'Solo las salidas del rango, sin restar devoluciones.',
              Icons.account_tree, () => Reportes.consumoPorCentro(_desde, _hasta),
              usaFechas: true),
          _reporte('netos', 'Neto por centro de costo',
              'Lo que se llevó MENOS lo que devolvió, valorizado al costo '
              'de cada movimiento. Es el consumo real.',
              Icons.balance, () => Reportes.netosPorCentro(_desde, _hasta),
              usaFechas: true),
          _reporte('minimo', 'Elementos bajo mínimo',
              'Lo que hay que reponer (existencia bajo el mínimo).',
              Icons.warning_amber, () => Reportes.bajoMinimo(),
              usaFechas: false),
        ],
      );

  /// Pestaña 2: informes de aprovechamientos (trozos/tramos a $0).
  Widget _tabAprovechamientos() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _reporte('aprov_existencias', 'Existencias actuales',
              'Tramos disponibles ahora (con saldo), por elemento y bodega.',
              Icons.inventory_2, () => Reportes.existenciasAprovechamientos(),
              usaFechas: false),
          _reporte('aprov_movimientos', 'Movimientos por fecha',
              'Entradas (tramos creados) y salidas (consumo) del rango elegido.',
              Icons.swap_vert,
              () => Reportes.movimientosAprovechamientos(_desde, _hasta),
              usaFechas: true),
        ],
      );

  /// [usaFechas] decide qué se muestra al pie de la tarjeta: el rango
  /// editable, o el aviso de que el informe es una foto del momento.
  Widget _reporte(String id, String titulo, String desc, IconData icono,
      Future<void> Function() fn, {required bool usaFechas}) {
    final generando = _generando == id;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(icono, color: Theme.of(context).colorScheme.primary),
            title:
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(desc),
            trailing: generando
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            onTap: _generando != null ? null : () => _descargar(id, fn),
          ),
          if (usaFechas) _filaRango() else _filaSinFechas(),
        ],
      ),
    );
  }
}
