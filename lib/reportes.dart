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
          'elementos!inner(nombre), bodegas(nombre), '
          'centros_costo!movimientos_centro_costo_id_fkey(codigo), '
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
        // Dice si el centro de la columna anterior es el ORIGEN (de dónde
        // vuelve) o el DESTINO (a dónde va), sin tener que cruzarlo con
        // Tipo — sale vacío si la fila no tiene centro.
        'Rol',
        'Usuario',
        'Referencia',
        'Observación',
      ],
    ];
    for (final r in (res as List)) {
      final tipo = (r['tipo'] ?? '') as String;
      final cant = (r['cantidad'] ?? 0) as num;
      final centro = (r['centros_costo'] as Map?)?['codigo'] as String?;
      filas.add([
        _fecha(r['fecha']),
        tipo,
        (r['elementos'] as Map?)?['nombre'] ?? '',
        (r['bodegas'] as Map?)?['nombre'] ?? '',
        // Con signo: lo que sale resta, lo que entra suma. Así la columna
        // se puede sumar directo en Excel y da el movimiento neto.
        cantidadConSigno(tipo, cant),
        r['costo_unitario'] != null ? (r['costo_unitario'] as num).round() : '',
        centro ?? '',
        rolCentro(tipo, cant, centro != null),
        (r['profiles'] as Map?)?['email'] ?? '',
        r['referencia'] ?? '',
        r['observacion'] ?? '',
      ]);
    }
    await _descargar('movimientos', filas);
  }

  /// 3) Consumo por centro de costo: una fila POR MOVIMIENTO (cada una con
  /// su propia fecha, a diferencia de "Neto" que agrupa por elemento), pero
  /// con salidas Y devoluciones — para que el TOTAL final coincida con el
  /// de "Neto por centro de costo" en vez de mostrar solo lo bruto que
  /// salió. Salida en negativo, devolución en positivo (mismo criterio de
  /// signo que el resto de los informes de centro).
  /// [centroId] null = TODOS los centros de costo.
  static Future<void> consumoPorCentro(
    DateTime desde,
    DateTime hasta, {
    String? centroId,
  }) async {
    // Movimientos ya anulados: no fueron consumo ni devolución real,
    // aunque la fila siga en la tabla (nunca se borra). Se piden aparte,
    // sin filtro de fecha, porque la anulación puede haber ocurrido
    // después del rango que se está consultando.
    final anuladas = await supabase
        .from('movimientos')
        .select('anula_movimiento_id')
        .not('anula_movimiento_id', 'is', null);
    final idsAnulados = (anuladas as List)
        .map((r) => r['anula_movimiento_id'] as String)
        .toSet();

    Future<List> pedir(String tipo) async {
      var q = supabase
          .from('movimientos')
          .select(
            'id, fecha, cantidad, costo_unitario, '
            'elementos!inner(nombre, costo_promedio), '
            'centros_costo!movimientos_centro_costo_id_fkey(codigo, descripcion), '
            'profiles(email)',
          )
          .eq('elementos.es_aprovechamiento', false)
          .eq('tipo', tipo)
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.add(const Duration(days: 1)).toIso8601String());
      if (centroId != null) q = q.eq('centro_costo_id', centroId);
      return (await q.order('fecha'))
          .where((r) => !idsAnulados.contains(r['id']))
          .toList();
    }

    // Salidas y devoluciones por separado (son dos consultas: 'entrada'
    // aquí SIEMPRE es "quien devuelve", nunca una compra sin centro —
    // esas quedan fuera porque no tienen centro_costo_id). Cada fila se
    // etiqueta con su tipo ANTES de mezclarlas, para no tener que
    // adivinar de cuál lista vino después.
    final salidas = (await pedir('salida'))
        .map((r) => {...r, '_esSalida': true});
    final devoluciones = (await pedir('entrada'))
        .map((r) => {...r, '_esSalida': false});
    // Mezcladas y ordenadas por fecha, como si fuera un solo kardex del
    // centro: así cada movimiento queda en su propia fila, sin agrupar.
    final res = [...salidas, ...devoluciones]
      ..sort((a, b) =>
          (a['fecha'] as String).compareTo(b['fecha'] as String));

    final filas = <List<dynamic>>[
      [
        'Fecha',
        'Centro de costo',
        'Descripción',
        'Elemento',
        'Tipo',
        // El mismo dato que Tipo, en el vocabulario de "de dónde viene /
        // a dónde va" — para que se lea igual que en los otros informes
        // sin tener que traducir mentalmente Salida=Destino/Devolución=Origen.
        'Rol',
        'Cantidad',
        'Costo unitario',
        'Valor estimado',
        'Usuario',
      ],
    ];
    int total = 0;
    for (final r in res) {
      final esSalida = r['_esSalida'] as bool;
      final cc = r['centros_costo'] as Map?;
      final el = r['elementos'] as Map?;
      final cant = (r['cantidad'] ?? 0) as num;
      // El costo con el que SALIÓ de verdad, no el promedio de hoy: cuando
      // un artículo se agota, su promedio queda en 0 y esta salida pasaba a
      // valer $0 retroactivamente. Medido sobre los datos reales, así se
      // subvaloraba el 57% del consumo (20 salidas aparecían en cero). En
      // una devolución el costo_unitario siempre viene lleno (obligatorio
      // al registrar la entrada), así que el fallback no hace falta ahí.
      final costo =
          (r['costo_unitario'] ?? el?['costo_promedio'] ?? 0) as num;
      final val = (cant * costo).round() * (esSalida ? -1 : 1);
      total += val;
      filas.add([
        _fecha(r['fecha']),
        cc?['codigo'] ?? '(sin centro)',
        cc?['descripcion'] ?? '',
        el?['nombre'] ?? '',
        esSalida ? 'Salida' : 'Devolución',
        esSalida ? 'Destino' : 'Origen',
        esSalida ? -cant : cant,
        costo.round(),
        val,
        (r['profiles'] as Map?)?['email'] ?? '',
      ]);
    }
    filas.add(['', '', '', '', '', '', 'TOTAL', '', total, '']);
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
  /// [centroId] null = TODOS los centros de costo.
  static Future<void> netosPorCentro(
    DateTime desde,
    DateTime hasta, {
    String? centroId,
  }) async {
    final res = await supabase.rpc(
      'netos_por_centro',
      params: {
        'p_desde': desde.toUtc().toIso8601String(),
        'p_hasta': hasta
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'p_centro': centroId,
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
        // Cada fila resume MUCHOS movimientos, así que no hay una fecha ni un
        // usuario únicos: se da la ventana real y quiénes participaron.
        'Primera fecha',
        'Última fecha',
        'Usuarios',
      ],
    ];
    num totalSal = 0, totalDev = 0, totalNeto = 0;
    for (final r in (res as List)) {
      final m = r as Map<String, dynamic>;
      // Con el mismo signo que su columna de cantidad vecina: "Valor
      // salidas" en negativo (como "Salidas") y "Valor neto" en el
      // signo que corresponda (como "Neto"). Antes solo "Devoluciones"
      // tenía el mismo signo en cantidad y en plata por casualidad (las
      // dos ya eran positivas); "Salidas" y "Neto" podían mostrar un
      // signo en unidades y el contrario en dinero para el mismo
      // centro. De paso, sumar "Valor salidas" + "Valor devoluciones"
      // en Excel ahora también da "Valor neto" directo, igual que ya
      // pasaba con las columnas de cantidad.
      final vSal = -((m['valor_salidas'] ?? 0) as num);
      final vDev = (m['valor_devoluciones'] ?? 0) as num;
      final vNeto = -((m['valor_neto'] ?? 0) as num);
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
        _fecha(m['primera_fecha']),
        _fecha(m['ultima_fecha']),
        m['usuarios'] ?? '',
      ]);
    }
    filas.add([
      '', '', '', '', '', '', 'TOTAL',
      totalSal.round(), totalDev.round(), totalNeto.round(),
      '', '', '',
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
