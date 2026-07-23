// Generación y descarga de informes en CSV (se abren en Excel).
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'ajustes.dart';
import 'data.dart';

class Reportes {
  /// Convierte las filas a CSV y dispara la descarga (web y móvil).
  static Future<void> _descargar(String nombre, List<List<dynamic>> filas) async {
    // Configuración regional: separador de decimales en los números.
    final dec = Ajustes.decSep;
    final fmt = filas
        .map((row) => row.map((c) =>
            c is num ? c.toString().replaceAll('.', dec) : c).toList())
        .toList();
    final csv = ListToCsvConverter(fieldDelimiter: Ajustes.csvSep).convert(fmt);
    // BOM UTF-8 para que Excel muestre bien las tildes.
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    final fecha = DateTime.now().toIso8601String().substring(0, 10);
    await FileSaver.instance.saveFile(
      name: '${nombre}_$fecha',
      bytes: bytes,
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  static String _fecha(dynamic iso) =>
      iso == null ? '' : iso.toString().substring(0, 10);

  /// 1) Existencias valorizadas (por elemento y bodega).
  static Future<void> existenciasValorizadas() async {
    final res = await supabase.from('existencias')
        .select('existencia, costo_promedio, elementos(nombre, unidad), bodegas(nombre)')
        .neq('existencia', 0);
    final filas = <List<dynamic>>[
      ['Elemento', 'Bodega', 'Cantidad', 'Unidad', 'Costo promedio', 'Valorización'],
    ];
    int total = 0;
    for (final r in (res as List)) {
      final el = r['elementos'] as Map?;
      final bo = r['bodegas'] as Map?;
      final exist = (r['existencia'] ?? 0) as num;
      final costo = (r['costo_promedio'] ?? 0) as num;
      final val = (exist * costo).round(); // dinero como entero (COP)
      total += val;
      filas.add([el?['nombre'] ?? '', bo?['nombre'] ?? '', exist,
          el?['unidad'] ?? '', costo.round(), val]);
    }
    filas.add(['', '', '', '', 'TOTAL', total]);
    await _descargar('existencias_valorizadas', filas);
  }

  /// 2) Movimientos por rango de fechas.
  static Future<void> movimientos(DateTime desde, DateTime hasta) async {
    final res = await supabase.from('movimientos')
        .select('fecha, tipo, cantidad, costo_unitario, referencia, observacion, '
            'elementos(nombre), bodegas(nombre), centros_costo(codigo)')
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.add(const Duration(days: 1)).toIso8601String())
        .order('fecha');
    final filas = <List<dynamic>>[
      ['Fecha', 'Tipo', 'Elemento', 'Bodega', 'Cantidad', 'Costo unitario',
        'Centro de costo', 'Referencia', 'Observación'],
    ];
    for (final r in (res as List)) {
      filas.add([
        _fecha(r['fecha']), r['tipo'],
        (r['elementos'] as Map?)?['nombre'] ?? '',
        (r['bodegas'] as Map?)?['nombre'] ?? '',
        r['cantidad'] ?? '',
        r['costo_unitario'] != null ? (r['costo_unitario'] as num).round() : '',
        (r['centros_costo'] as Map?)?['codigo'] ?? '',
        r['referencia'] ?? '', r['observacion'] ?? '',
      ]);
    }
    await _descargar('movimientos', filas);
  }

  /// 3) Consumo por centro de costo (salidas del período).
  /// El valor se estima al costo promedio ACTUAL del elemento.
  static Future<void> consumoPorCentro(DateTime desde, DateTime hasta) async {
    final res = await supabase.from('movimientos')
        .select('cantidad, elementos(nombre, costo_promedio), '
            'centros_costo(codigo, descripcion)')
        .eq('tipo', 'salida')
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.add(const Duration(days: 1)).toIso8601String());
    final filas = <List<dynamic>>[
      ['Centro de costo', 'Descripción', 'Elemento', 'Cantidad', 'Valor estimado'],
    ];
    int total = 0;
    for (final r in (res as List)) {
      final cc = r['centros_costo'] as Map?;
      final el = r['elementos'] as Map?;
      final cant = (r['cantidad'] ?? 0) as num;
      final costo = (el?['costo_promedio'] ?? 0) as num;
      final val = (cant * costo).round(); // dinero como entero (COP)
      total += val;
      filas.add([cc?['codigo'] ?? '(sin centro)', cc?['descripcion'] ?? '',
          el?['nombre'] ?? '', cant, val]);
    }
    filas.add(['', '', '', 'TOTAL', total]);
    await _descargar('consumo_por_centro', filas);
  }

  /// 4) Elementos bajo el mínimo (para reponer).
  static Future<void> bajoMinimo() async {
    final items = await InventarioService.bajoMinimo();
    final filas = <List<dynamic>>[
      ['Elemento', 'Unidad', 'Existencia', 'Stock mínimo', 'Faltante'],
    ];
    for (final e in items) {
      filas.add([e.nombre, e.unidad, e.existencia, e.stockMinimo,
          e.stockMinimo - e.existencia]);
    }
    await _descargar('bajo_minimo', filas);
  }
}
