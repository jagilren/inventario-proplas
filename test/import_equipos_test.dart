import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/activos_service.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/reportes.dart';
import 'package:mi_app/util/import_archivo.dart';
import 'package:mi_app/util/import_equipos.dart';

// Carga masiva de EQUIPOS (schema_v70): la lógica pura. Lo que se prueba
// son las reglas que deciden qué entra y qué no, antes de tocar la base.

ActivoReferencia _ref(String id, String nombre,
        {String? marca, bool kit = false, bool activo = true}) =>
    ActivoReferencia.fromMap({
      'id': id,
      'nombre': nombre,
      'marca': marca,
      'es_kit': kit,
      'activo': activo,
    });

final _bomba = _ref('r1', 'BOMBA DE DIAFRAGMA ELECTRICA', marca: 'GRUNDFOS');
final _kit = _ref('r2', 'KIT FILTROS 636', marca: 'GENEBRE', kit: true);
final _rpci = Bodega.fromMap({'id': 'b1', 'nombre': 'Bodega RPCI'});
final _proplas = Bodega.fromMap({'id': 'b2', 'nombre': 'Bodega PROPLAS'});
CentroCosto _cc(String id, String codigo, {bool interno = false}) =>
    CentroCosto.fromMap(
        {'id': id, 'codigo': codigo, 'es_interno': interno, 'activo': true});
final _compra = _cc('c1', 'COMPRA');
final _g2 = _cc('c2', 'G000002', interno: true);
final _cliente = _cc('c3', 'NP00039');

const _plantillaKit = [
  ComponentePlantilla(
      nombre: 'Tela Mesh 100', cantidad: 24, valorUnitario: 45000,
      desdeSerial: 'K-0001'),
  ComponentePlantilla(
      nombre: 'Guías filtro', cantidad: 12, valorUnitario: 15000,
      desdeSerial: 'K-0001'),
];

CatalogoImport _cat({
  Set<String> existentes = const {},
  List<ActivoReferencia>? referencias,
}) =>
    CatalogoImport(
      referencias: referencias ?? [_bomba, _kit],
      bodegas: [_rpci, _proplas],
      centros: [_compra, _g2, _cliente],
      serialesExistentes: existentes,
      plantillas: {'r2': _plantillaKit},
    );

/// Una fila de equipo con todo lo necesario, para cambiarle solo lo que se
/// prueba.
FilaEquipoArchivo _eq(
  int fila,
  String serial, {
  String referencia = 'BOMBA DE DIAFRAGMA ELECTRICA',
  String marca = '',
  String esKit = '',
  String condicion = 'nuevo',
  String porcentaje = '',
  String valor = '1.540.000',
  String bodega = 'Bodega RPCI',
  String origen = '',
  String destino = '',
  String componente = '',
  String cantidad = '',
  String valorUnitario = '',
}) =>
    FilaEquipoArchivo(
      fila: fila,
      serial: serial,
      referencia: referencia,
      marca: marca,
      esKit: esKit,
      condicion: condicion,
      porcentaje: porcentaje,
      valorNuevo: valor,
      bodega: bodega,
      centroOrigen: origen,
      centroDestino: destino,
      componente: componente,
      cantidad: cantidad,
      valorUnitario: valorUnitario,
    );

FilaEquipoArchivo _comp(int fila, String serial, String nombre, String cant,
        String valor) =>
    FilaEquipoArchivo(
        fila: fila,
        serial: serial,
        componente: nombre,
        cantidad: cant,
        valorUnitario: valor);

EquipoImport _uno(List<FilaEquipoArchivo> filas, [CatalogoImport? cat]) =>
    analizarImportEquipos(filas, cat ?? _cat()).equipos.single;

void main() {
  group('leer la plantilla', () {
    test('encuentra el encabezado aunque haya títulos encima', () {
      final filas = leerPlantillaEquipos([
        ['LISTADO DE EQUIPOS', '', ''],
        ['', '', ''],
        ['SERIAL', 'REFERENCIA', 'CONDICIÓN', 'Observaciones'],
        ['A-1', 'Bomba', 'nuevo', 'llegó bien'],
        ['', '', '', ''],
      ]);
      expect(filas.length, 1);
      expect(filas.single.fila, 4);
      expect(filas.single.condicion, 'nuevo');
      // "Observaciones" (plural) también se reconoce.
      expect(filas.single.observacion, 'llegó bien');
    });

    test('columnas en otro orden: se ubican por su nombre', () {
      final f = leerPlantillaEquipos([
        ['VALOR NUEVO', 'REFERENCIA', 'VALOR UNITARIO', 'SERIAL'],
        ['1.000', 'Bomba', '5', 'A-1'],
      ]).single;
      expect(f.serial, 'A-1');
      expect(f.valorNuevo, '1.000');
      expect(f.valorUnitario, '5');
    });

    test('sin encabezados: lo dice, no inventa', () {
      expect(() => leerPlantillaEquipos([['a', 'b'], ['1', '2']]),
          throwsA(isA<FormatException>()));
    });
  });

  group('un equipo sencillo', () {
    test('completo: listo, con los centros de siempre', () {
      final e = _uno([_eq(2, 'B-7788')]);
      expect(e.errores, isEmpty);
      expect(e.referencia?.id, 'r1');
      expect(e.valorNuevo, 1540000);
      expect(e.porcentaje, 100);
      expect(e.bodega?.id, 'b1');
      expect(e.centroOrigen?.codigo, 'COMPRA');
      expect(e.centroDestino?.codigo, 'G000002');
      expect(e.aJson(), {
        'serial': 'B-7788',
        'referencia_id': 'r1',
        'condicion': 'nuevo',
        'porcentaje': 100,
        'valor_nuevo': 1540000,
        'bodega_id': 'b1',
        'centro_origen_id': 'c1',
        'centro_destino_id': 'c2',
      });
    });

    test('"1.540.000" es un millón quinientos cuarenta mil, no 1,54', () {
      expect(_uno([_eq(2, 'A', valor: '1.540.000')]).valorNuevo, 1540000);
    });

    test('sin valor nuevo no entra', () {
      expect(_uno([_eq(2, 'A', valor: '')]).errores,
          contains('Falta el VALOR NUEVO.'));
    });

    test('condición: acepta como se escribe, y la vacía no entra', () {
      expect(_uno([_eq(2, 'A', condicion: 'Para repuestos')]).condicion,
          'repuestos');
      expect(_uno([_eq(2, 'A', condicion: 'USADA', porcentaje: '70')]).condicion,
          'usado');
      expect(_uno([_eq(2, 'A', condicion: '')]).listo, isFalse);
      expect(_uno([_eq(2, 'A', condicion: 'dañado')]).listo, isFalse);
    });

    test('porcentaje: "70%" sirve; 150 no; usado sin porcentaje avisa', () {
      expect(_uno([_eq(2, 'A', porcentaje: '70%')]).porcentaje, 70);
      expect(_uno([_eq(2, 'A', porcentaje: '150')]).listo, isFalse);
      final u = _uno([_eq(2, 'A', condicion: 'usado')]);
      expect(u.listo, isTrue);
      expect(u.avisos.single, contains('100 %'));
    });

    test('bodega: "RPCI" a secas basta; una que no existe lo dice', () {
      expect(_uno([_eq(2, 'A', bodega: 'rpci')]).bodega?.id, 'b1');
      final e = _uno([_eq(2, 'A', bodega: 'Bodega Norte')]);
      // Dice cuáles hay, para que se pueda corregir sin preguntar.
      expect(e.errores.single, allOf(contains('Bodega Norte'),
          contains('Bodega PROPLAS'), contains('Bodega RPCI')));
    });

    test('centros: origen interno no; destino externo no; código raro no', () {
      expect(_uno([_eq(2, 'A', origen: 'G000002')]).listo, isFalse);
      expect(_uno([_eq(2, 'A', destino: 'NP00039')]).listo, isFalse);
      expect(_uno([_eq(2, 'A', origen: 'NP99999')]).listo, isFalse);
      final ok = _uno([_eq(2, 'A', origen: 'np00039')]);
      expect(ok.centroOrigen?.codigo, 'NP00039');
    });
  });

  group('seriales', () {
    test('repetido en el archivo: las DOS filas lo dicen', () {
      final r = analizarImportEquipos(
          [_eq(2, 'A-1'), _eq(3, 'B-2'), _eq(4, 'A-1')], _cat());
      expect(r.equipos[0].errores.single, contains('fila 4'));
      expect(r.equipos[2].errores.single, contains('fila 2'));
      expect(r.equipos[1].listo, isTrue);
    });

    test('uno que ya existe en la base no vuelve a entrar', () {
      final e = _uno([_eq(2, 'A-1')], _cat(existentes: {'A-1'}));
      expect(e.errores.single, 'Ya existe un equipo con ese serial.');
    });

    test('las filas de EJEMPLO de la plantilla no entran', () {
      expect(_uno([_eq(2, 'EJEMPLO-001')]).errores.single,
          contains('EJEMPLO'));
    });
  });

  group('referencias', () {
    test('una que no existe se crea UNA vez, aunque la usen tres equipos',
        () {
      final r = analizarImportEquipos([
        _eq(2, 'S-1', referencia: 'Soplador FPZ SCL R40', marca: 'FPZ'),
        _eq(3, 'S-2', referencia: 'soplador  fpz scl r40', marca: 'fpz'),
        _eq(4, 'S-3', referencia: 'Soplador FPZ SCL R40', marca: 'FPZ'),
      ], _cat());
      expect(r.referenciasNuevas.length, 1);
      expect(r.referenciasNuevas.single.equipos, 3);
      expect(r.listos.length, 3);
      expect(r.equipos.first.aJson()['referencia_nueva'],
          {'nombre': 'Soplador FPZ SCL R40', 'marca': 'FPZ', 'es_kit': false});
    });

    test('muestra a cuáles del catálogo se parece la nueva', () {
      final r = analizarImportEquipos(
          [_eq(2, 'X', referencia: 'Bomba de diafragma eléctrica 2')], _cat());
      expect(r.referenciasNuevas.single.parecidas.first.id, 'r1');
    });

    test('dos con el mismo nombre: pide la MARCA', () {
      final dos = [
        _bomba,
        _ref('r9', 'BOMBA DE DIAFRAGMA ELECTRICA', marca: 'GRACO'),
      ];
      final sin = _uno([_eq(2, 'A')], _cat(referencias: dos));
      expect(sin.errores.single, contains('escribe la MARCA'));
      final con = _uno([_eq(2, 'A', marca: 'graco')], _cat(referencias: dos));
      expect(con.referencia?.id, 'r9');
    });

    test('una desactivada no se usa ni se duplica: lo dice', () {
      final e = _uno([_eq(2, 'A')],
          _cat(referencias: [_ref('r1', 'BOMBA DE DIAFRAGMA ELECTRICA',
              activo: false)]));
      expect(e.errores.single, contains('desactivada'));
    });

    test('ES KIT que contradice al catálogo no entra', () {
      expect(_uno([_eq(2, 'A', esKit: 'SI')]).listo, isFalse);
      expect(_uno([_eq(2, 'K', referencia: 'KIT FILTROS 636', esKit: 'NO')])
          .listo, isFalse);
    });
  });

  group('kits', () {
    test('los componentes van en las filas de abajo, con el mismo SERIAL', () {
      final e = _uno([
        _eq(2, 'K-9', referencia: 'KIT FILTROS 636', valor: ''),
        _comp(3, 'K-9', 'Tela Mesh 100', '24', '45.000'),
        _comp(4, 'K-9', 'Guías filtro', '12', '15.000'),
      ]);
      expect(e.errores, isEmpty);
      expect(e.componentes.map((c) => c.nombre),
          ['Tela Mesh 100', 'Guías filtro']);
      expect(e.valorCalculado, 24 * 45000 + 12 * 15000);
      final j = e.aJson();
      expect(j.containsKey('valor_nuevo'), isFalse);
      expect((j['componentes'] as List).first,
          {'nombre': 'Tela Mesh 100', 'cantidad': 24,
           'valor_unitario': 45000, 'orden': 1});
    });

    test('un componente con el SERIAL vacío es del kit de arriba', () {
      final e = _uno([
        _eq(2, 'K-9', referencia: 'KIT FILTROS 636', valor: ''),
        _comp(3, '', 'Tela Mesh 100', '24', '45000'),
      ]);
      expect(e.componentes.single.nombre, 'Tela Mesh 100');
    });

    test('un componente sin equipo arriba queda como problema suelto', () {
      final r = analizarImportEquipos(
          [_comp(2, 'NADIE', 'Tela', '1', '1')], _cat());
      expect(r.equipos, isEmpty);
      expect(r.problemasSueltos.single, contains('Fila 2'));
    });

    test('kit sin componentes: copia los del último kit, y lo avisa', () {
      final e = _uno([_eq(2, 'K-9', referencia: 'KIT FILTROS 636', valor: '')]);
      expect(e.listo, isTrue);
      expect(e.componentesDeLaPlantilla, isTrue);
      expect(e.componentes.length, 2);
      expect(e.avisos.single, contains('K-0001'));
    });

    test('kit NUEVO sin componentes no entra', () {
      final e = _uno([_eq(2, 'K', referencia: 'Kit sellos', esKit: 'SI',
          valor: '')]);
      expect(e.errores.single, contains('kit nuevo'));
    });

    test('una referencia nueva con componentes es kit aunque ES KIT esté '
        'vacío, sin importar el orden de las filas', () {
      final r = analizarImportEquipos([
        // Este va PRIMERO y no trae componentes…
        _eq(2, 'K-1', referencia: 'Kit sellos', valor: ''),
        // …y este, después, sí.
        _eq(3, 'K-2', referencia: 'Kit sellos', valor: ''),
        _comp(4, 'K-2', 'Sello', '2', '10000'),
      ], _cat());
      expect(r.referenciasNuevas.single.esKit, isTrue);
      expect(r.equipos[1].listo, isTrue);
      // El primero se trata como kit (sin componentes), no como sencillo.
      expect(r.equipos[0].errores.single, contains('kit nuevo'));
    });

    test('componentes en un equipo que NO es kit: no entra', () {
      final e = _uno([
        _eq(2, 'B-1'),
        _comp(3, 'B-1', 'Tela', '1', '1'),
      ]);
      expect(e.errores.single, contains('no es un kit'));
    });

    test('cantidad cero o componente repetido: no entra', () {
      expect(
          _uno([
            _eq(2, 'K', referencia: 'KIT FILTROS 636', valor: ''),
            _comp(3, 'K', 'Tela', '0', '1'),
          ]).listo,
          isFalse);
      expect(
          _uno([
            _eq(2, 'K', referencia: 'KIT FILTROS 636', valor: ''),
            _comp(3, 'K', 'Tela', '1', '1'),
            _comp(4, 'K', 'tela', '2', '1'),
          ]).errores.single,
          contains('repetido'));
    });

    test('valor nuevo en un kit se ignora, y lo avisa', () {
      final e = _uno([
        _eq(2, 'K', referencia: 'KIT FILTROS 636', valor: '999'),
        _comp(3, 'K', 'Tela', '1', '10'),
      ]);
      expect(e.listo, isTrue);
      expect(e.avisos.single, contains('se ignora'));
    });
  });

  test('la plantilla que baja la app se lee entera, y sus EJEMPLOS no entran',
      () {
    final filas = filasPlantillaEquipos(
      sencilla: _bomba,
      kit: _kit,
      componentesKit: _plantillaKit,
      bodega: 'Bodega RPCI',
    );
    final crudas =
        leerFilasCrudas(Reportes.bytesCsv(filas), 'plantilla_equipos.csv');
    final r = analizarImportEquipos(leerPlantillaEquipos(crudas), _cat());
    expect(r.equipos.map((e) => e.serial), ['EJEMPLO-001', 'EJEMPLO-002']);
    // El kit de ejemplo trae sus 2 componentes en las filas de abajo.
    expect(r.equipos[1].componentes.length, 2);
    expect(r.equipos[1].componentesDeLaPlantilla, isFalse);
    // Y ninguno entra por ser de ejemplo.
    expect(r.listos, isEmpty);
    for (final e in r.equipos) {
      expect(e.errores.join(), contains('EJEMPLO'));
    }
  });
}
