// Generación y descarga de informes en CSV (se abren en Excel).
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'ajustes.dart';
import 'data.dart';
import 'util/tiempo.dart';
import 'util/movimiento_fmt.dart';

class Reportes {
  /// Convierte las filas a CSV y dispara la descarga (web y móvil).
  static Future<void> _descargar(
    String nombre,
    List<List<dynamic>> filas,
  ) async {
    // Configuración regional: separador de decimales en los números.
    final dec = Ajustes.decSep;
    final fmt = filas
        .map(
          (row) => row
              .map((c) => c is num ? c.toString().replaceAll('.', dec) : c)
              .toList(),
        )
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

  /// Descarga un CSV genérico (reusa el mismo mecanismo: separadores
  /// regionales + BOM). Útil para la remisión de devolución.
  static Future<void> descargarCsv(String nombre, List<List<dynamic>> filas) =>
      _descargar(nombre, filas);

  static String _fecha(dynamic iso) {
    if (iso == null) return '';
    final f = horaColombia(DateTime.parse(iso.toString()));
    return '${f.year}-${f.month.toString().padLeft(2, '0')}-'
        '${f.day.toString().padLeft(2, '0')}';
  }

  /// 1) Existencias valorizadas (por elemento y bodega).
  static Future<void> existenciasValorizadas() async {
    final res = await supabase
        .from('existencias')
        .select(
          'existencia, costo_promedio, '
          'elementos!inner(nombre, unidad), bodegas(nombre)',
        )
        .neq('existencia', 0)
        .eq('elementos.es_aprovechamiento', false);
    final filas = <List<dynamic>>[
      [
        'Elemento',
        'Bodega',
        'Cantidad',
        'Unidad',
        'Costo promedio',
        'Valorización',
      ],
    ];
    int total = 0;
    for (final r in (res as List)) {
      final el = r['elementos'] as Map?;
      final bo = r['bodegas'] as Map?;
      final exist = (r['existencia'] ?? 0) as num;
      final costo = (r['costo_promedio'] ?? 0) as num;
      final val = (exist * costo).round(); // dinero como entero (COP)
      total += val;
      filas.add([
        el?['nombre'] ?? '',
        bo?['nombre'] ?? '',
        exist,
        el?['unidad'] ?? '',
        costo.round(),
        val,
      ]);
    }
    filas.add(['', '', '', '', 'TOTAL', total]);
    await _descargar('existencias_valorizadas', filas);
  }

  /// 2) Movimientos por rango de fechas.
  static Future<void> movimientos(DateTime desde, DateTime hasta) async {
    final res = await supabase
        .from('movimientos')
        .select(
          'fecha, tipo, cantidad, costo_unitario, referencia, observacion, '
          'elementos!inner(nombre), bodegas(nombre), centros_costo(codigo), '
          'profiles(email)',
        )
        .eq('elementos.es_aprovechamiento', false)
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.add(const Duration(days: 1)).toIso8601String())
        .order('fecha');
    final filas = <List<dynamic>>[
      [
        'Fecha',
        'Tipo',
        'Elemento',
        'Bodega',
        'Cantidad',
        'Costo unitario',
        'Centro de costo',
        'Usuario',
        'Referencia',
        'Observación',
      ],
    ];
    for (final r in (res as List)) {
      filas.add([
        _fecha(r['fecha']),
        r['tipo'],
        (r['elementos'] as Map?)?['nombre'] ?? '',
        (r['bodegas'] as Map?)?['nombre'] ?? '',
        // Con signo: lo que sale resta, lo que entra suma. Así la columna
        // se puede sumar directo en Excel y da el movimiento neto.
        cantidadConSigno(
            (r['tipo'] ?? '') as String, (r['cantidad'] ?? 0) as num),
        r['costo_unitario'] != null ? (r['costo_unitario'] as num).round() : '',
        (r['centros_costo'] as Map?)?['codigo'] ?? '',
        (r['profiles'] as Map?)?['email'] ?? '',
        r['referencia'] ?? '',
        r['observacion'] ?? '',
      ]);
    }
    await _descargar('movimientos', filas);
  }

  /// 3) Consumo por centro de costo (salidas del período).
  /// El valor se estima al costo promedio ACTUAL del elemento.
  static Future<void> consumoPorCentro(DateTime desde, DateTime hasta) async {
    final res = await supabase
        .from('movimientos')
        .select(
          'fecha, cantidad, costo_unitario, '
          'elementos!inner(nombre, costo_promedio), '
          'centros_costo(codigo, descripcion), profiles(email)',
        )
        .eq('elementos.es_aprovechamiento', false)
        .eq('tipo', 'salida')
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.add(const Duration(days: 1)).toIso8601String())
        .order('fecha');
    // Cada fila es UNA salida, así que lleva su fecha y quién la hizo: sin
    // eso no se puede rastrear un consumo raro hasta el movimiento que lo
    // originó ni saber a quién preguntarle.
    final filas = <List<dynamic>>[
      [
        'Fecha',
        'Centro de costo',
        'Descripción',
        'Elemento',
        'Cantidad',
        'Valor estimado',
        'Usuario',
      ],
    ];
    int total = 0;
    for (final r in (res as List)) {
      final cc = r['centros_costo'] as Map?;
      final el = r['elementos'] as Map?;
      final cant = (r['cantidad'] ?? 0) as num;
      // El costo con el que SALIÓ de verdad, no el promedio de hoy: cuando
      // un artículo se agota, su promedio queda en 0 y esta salida pasaba a
      // valer $0 retroactivamente. Medido sobre los datos reales, así se
      // subvaloraba el 57% del consumo (20 salidas aparecían en cero).
      final costo =
          (r['costo_unitario'] ?? el?['costo_promedio'] ?? 0) as num;
      final val = (cant * costo).round(); // dinero como entero (COP)
      total += val;
      filas.add([
        _fecha(r['fecha']),
        cc?['codigo'] ?? '(sin centro)',
        cc?['descripcion'] ?? '',
        el?['nombre'] ?? '',
        cant,
        val,
        (r['profiles'] as Map?)?['email'] ?? '',
      ]);
    }
    filas.add(['', '', '', '', 'TOTAL', total, '']);
    await _descargar('consumo_por_centro', filas);
  }

  /// 3b) NETO por centro de costo: lo que se llevó MENOS lo que devolvió.
  ///
  /// El informe de "Consumo" solo mira las salidas, así que un centro que se
  /// lleva 100 y devuelve 30 aparece consumiendo 100. Este resta.
  ///
  /// Además valoriza al costo que el artículo tenía EN CADA MOVIMIENTO
  /// (`costo_unitario`), no al promedio de hoy: cuando un artículo se agota
  /// su promedio queda en 0, y con el método viejo esas salidas aparecían
  /// costando $0 (medido: subvaloraba el 57% del total).
  static Future<void> netosPorCentro(DateTime desde, DateTime hasta) async {
    final res = await supabase.rpc(
      'netos_por_centro',
      params: {
        'p_desde': desde.toUtc().toIso8601String(),
        'p_hasta': hasta
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      },
    );
    final filas = <List<dynamic>>[
      [
        'Centro de costo',
        'Descripción',
        'Elemento',
        'Unidad',
        'Salidas',
        'Devoluciones',
        'Neto',
        'Valor salidas',
        'Valor devoluciones',
        'Valor neto',
      ],
    ];
    num totalSal = 0, totalDev = 0, totalNeto = 0;
    for (final r in (res as List)) {
      final m = r as Map<String, dynamic>;
      final vSal = (m['valor_salidas'] ?? 0) as num;
      final vDev = (m['valor_devoluciones'] ?? 0) as num;
      final vNeto = (m['valor_neto'] ?? 0) as num;
      totalSal += vSal;
      totalDev += vDev;
      totalNeto += vNeto;
      filas.add([
        m['centro'] ?? '',
        m['descripcion'] ?? '',
        m['elemento'] ?? '',
        m['unidad'] ?? '',
        // Las salidas van en negativo y las devoluciones en positivo, para
        // que las columnas se puedan sumar directo en Excel.
        -((m['salidas'] ?? 0) as num),
        (m['devoluciones'] ?? 0) as num,
        -((m['neto'] ?? 0) as num),
        vSal.round(),
        vDev.round(),
        vNeto.round(),
      ]);
    }
    filas.add([
      '', '', '', '', '', '', 'TOTAL',
      totalSal.round(), totalDev.round(), totalNeto.round(),
    ]);
    await _descargar('netos_por_centro', filas);
  }

  /// 4) Elementos bajo el mínimo (para reponer).
  static Future<void> bajoMinimo() async {
    final items = await InventarioService.bajoMinimo();
    final filas = <List<dynamic>>[
      ['Elemento', 'Unidad', 'Existencia', 'Stock mínimo', 'Faltante'],
    ];
    for (final e in items) {
      filas.add([
        e.nombre,
        e.unidad,
        e.existencia,
        e.stockMinimo,
        e.stockMinimo - e.existencia,
      ]);
    }
    await _descargar('bajo_minimo', filas);
  }

  /// 5) Movimientos de APROVECHAMIENTOS por rango de fechas (entradas =
  /// trozos creados; salidas = segmentos usados). Ordenado del más reciente
  /// al más antiguo.
  static Future<void> movimientosAprovechamientos(
    DateTime desde,
    DateTime hasta,
  ) async {
    final d = desde.toUtc().toIso8601String();
    final h = hasta.add(const Duration(days: 1)).toUtc().toIso8601String();

    final ent = await supabase
        .from('aprovechamiento_trozos')
        .select(
          'creado_en, longitud, creado_email, observacion, '
          'elementos(nombre, unidad), bodegas(nombre)',
        )
        .gte('creado_en', d)
        .lt('creado_en', h);

    final sal = await supabase
        .from('aprovechamiento_salidas')
        .select(
          'fecha, cantidad, usuario_email, observacion, '
          'centros_costo(codigo, descripcion), '
          'aprovechamiento_trozos(elementos(nombre, unidad), bodegas(nombre))',
        )
        .gte('fecha', d)
        .lt('fecha', h);

    final filas = <List<dynamic>>[
      [
        'Fecha',
        'Tipo',
        'Elemento',
        'Unidad',
        'Cantidad',
        'Centro de costo',
        'Bodega',
        'Usuario',
        'Observación',
      ],
    ];
    // Cada mov lleva su fecha ISO al final como clave de orden (se quita luego).
    final movs = <List<dynamic>>[];

    for (final r in (ent as List)) {
      final m = r as Map<String, dynamic>;
      final el = m['elementos'] as Map?;
      movs.add([
        _fecha(m['creado_en']),
        'ENTRADA',
        el?['nombre'] ?? '',
        el?['unidad'] ?? '',
        (m['longitud'] ?? 0) as num,
        '',
        (m['bodegas'] as Map?)?['nombre'] ?? '',
        m['creado_email'] ?? '',
        m['observacion'] ?? '',
        m['creado_en'] ?? '',
      ]);
    }
    for (final r in (sal as List)) {
      final m = r as Map<String, dynamic>;
      final tr = m['aprovechamiento_trozos'] as Map?;
      final el = tr?['elementos'] as Map?;
      final cc = m['centros_costo'] as Map?;
      final ccLabel = cc == null
          ? ''
          : [cc['codigo'], cc['descripcion']]
                .where((x) => x != null && (x as String).trim().isNotEmpty)
                .join(' · ');
      movs.add([
        _fecha(m['fecha']),
        'SALIDA',
        el?['nombre'] ?? '',
        el?['unidad'] ?? '',
        // Negativo: en este informe conviven entradas y salidas de tramos.
        -((m['cantidad'] ?? 0) as num).abs(),
        ccLabel,
        (tr?['bodegas'] as Map?)?['nombre'] ?? '',
        m['usuario_email'] ?? '',
        m['observacion'] ?? '',
        m['fecha'] ?? '',
      ]);
    }
    // Más reciente primero.
    movs.sort((a, b) => (b.last as String).compareTo(a.last as String));
    for (final mv in movs) {
      mv.removeLast();
      filas.add(mv);
    }

    await _descargar('aprovechamientos_movimientos', filas);
  }

  /// 6) Existencias ACTUALES de aprovechamientos: trozos/tramos con saldo
  /// disponible (longitud_actual > 0). Inventario paralelo a $0, sin
  /// valorización. Ordenado alfabéticamente (es una foto del stock, no un
  /// histórico).
  static Future<void> existenciasAprovechamientos() async {
    final res = await supabase
        .from('aprovechamiento_trozos')
        .select(
          'longitud, longitud_actual, creado_en, creado_email, '
          'observacion, elementos(nombre, unidad), bodegas(nombre)',
        )
        .gt('longitud_actual', 0)
        .order('nombre', referencedTable: 'elementos');
    final filas = <List<dynamic>>[
      [
        'Elemento',
        'Unidad',
        'Bodega',
        'Saldo disponible',
        'Longitud inicial',
        'Ingresado',
        'Usuario',
        'Observación',
      ],
    ];
    for (final r in (res as List)) {
      final m = r as Map<String, dynamic>;
      final el = m['elementos'] as Map?;
      filas.add([
        el?['nombre'] ?? '',
        el?['unidad'] ?? '',
        (m['bodegas'] as Map?)?['nombre'] ?? '',
        (m['longitud_actual'] ?? 0) as num,
        (m['longitud'] ?? 0) as num,
        _fecha(m['creado_en']),
        m['creado_email'] ?? '',
        m['observacion'] ?? '',
      ]);
    }
    await _descargar('aprovechamientos_existencias', filas);
  }
}
