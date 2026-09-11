import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/reportes.dart';
import 'package:mi_app/util/import_archivo.dart';
import 'package:mi_app/util/plantilla_import.dart';

// El CSV de la remisión de devolución (2026-09-11): la columna COSTO
// PROMEDIO, y los artículos NUEVOS que no están en el catálogo
// (docs/plan-remision-elementos-nuevos.md). Lo que importa probar no es solo
// que salgan las columnas: es que ese MISMO archivo se lea bien en
// Devoluciones, que es para lo que existe.

Elemento _elemento(String id, String nombre, num costo) => Elemento.fromMap({
      'id': id,
      'nombre': nombre,
      'costo_promedio': costo,
    });

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

LineaDevolucion _cat(Elemento e, num c) => LineaDevolucion.catalogo(e, c);

const _valvula = LineaDevolucion.nueva(
  nombre: 'Válvula mariposa 4" wafer',
  cantidad: 2,
  unidad: 'UND',
  costoEstimado: 185000,
);

void main() {
  final tubo = _elemento('e1', 'Tubo PVC 2"', 12500);
  final codo = _elemento('e2', 'Codo 90° 1-1/2"', 3200.6);

  group('filasCsvDevolucion', () {
    test('siete columnas; las del catálogo con su costo promedio', () {
      final filas = filasCsvDevolucion([_cat(tubo, 10), _cat(codo, 4)]);
      expect(filas.first, [
        'ELEMENTO', 'CANTIDAD', 'COSTO PROMEDIO',
        'NUEVO', 'UNIDAD', 'COSTO ESTIMADO', 'ESTIMADO POR',
      ]);
      expect(filas[1], ['Tubo PVC 2"', 10, 12500, '', '', '', '']);
      // En pesos enteros, como en los informes.
      expect(filas[2], ['Codo 90° 1-1/2"', 4, 3201, '', '', '', '']);
    });

    test('un NUEVO lleva SI, unidad, costo estimado y quién lo estimó', () {
      final filas = filasCsvDevolucion([_valvula],
          estimadoPor: 'ing.perez@rpci.com.co');
      expect(filas[1], [
        'Válvula mariposa 4" wafer', 2, '', 'SI', 'UND', 185000,
        'ing.perez@rpci.com.co',
      ]);
    });

    test('el costo leído del servidor manda sobre el que traía la lista', () {
      final filas = filasCsvDevolucion([_cat(tubo, 10), _cat(codo, 4)],
          costos: {'e1': 13000});
      expect(filas[1][2], 13000);
      expect(filas[2][2], 3201);
    });

    test('un artículo en \$0 sale en 0, no vacío', () {
      final filas =
          filasCsvDevolucion([_cat(_elemento('e3', 'Brida', 0), 1)]);
      expect(filas[1][2], 0);
    });

    test('la plantilla y la remisión usan el MISMO encabezado', () {
      expect(filasCsvDevolucion([]).single, encabezadoDevolucion);
    });
  });

  group('lo que genera la remisión se lee bien en Devoluciones', () {
    List<FilaArchivoDevolucion> idaYVuelta(List<List<dynamic>> filas) =>
        leerArchivoDevolucion(Reportes.bytesCsv(filas), 'remision.csv');

    test('catálogo y nuevos llegan con todo lo suyo', () {
      final leidas = idaYVuelta(filasCsvDevolucion(
          [_cat(tubo, 10), _valvula, _cat(codo, 2.5)],
          estimadoPor: 'ing.perez@rpci.com.co'));
      expect(leidas.length, 3);
      expect(leidas[0].elemento, 'Tubo PVC 2"');
      expect(leidas[0].cantidad, 10);
      expect(leidas[0].nuevo, isFalse);
      // El costo PROMEDIO de una fila del catálogo NO es un estimado.
      expect(leidas[0].costoEstimado, isNull);
      expect(leidas[1].elemento, 'Válvula mariposa 4" wafer');
      expect(leidas[1].nuevo, isTrue);
      expect(leidas[1].unidad, 'UND');
      expect(leidas[1].cantidad, 2);
      expect(leidas[1].costoEstimado, 185000);
      expect(leidas[1].estimadoPor, 'ing.perez@rpci.com.co');
      // 2,5 con coma decimal, como lo escribe el CSV en Colombia.
      expect(leidas[2].cantidad, 2.5);
    });

    test('ninguna columna de costo se toma como la cantidad', () {
      // Un costo de 12500 leído como cantidad serían 12.500 tubos.
      final leidas = idaYVuelta(filasCsvDevolucion([_cat(tubo, 3), _valvula]));
      expect(leidas[0].cantidad, 3);
      expect(leidas[1].cantidad, 2);
    });

    test('un nombre con punto y coma o comillas no parte la fila', () {
      final raro = _elemento('e4', 'Unión; tipo "universal" 1/2"', 900);
      final leidas = idaYVuelta(filasCsvDevolucion([_cat(raro, 7)]));
      expect(leidas.single.elemento, 'Unión; tipo "universal" 1/2"');
      expect(leidas.single.cantidad, 7);
    });

    test('un archivo viejo, de dos columnas, se sigue cargando', () {
      final leidas = idaYVuelta([
        ['ELEMENTO', 'CANTIDAD'],
        ['Tubo PVC 2"', 10],
      ]);
      expect(leidas.single.elemento, 'Tubo PVC 2"');
      expect(leidas.single.cantidad, 10);
      expect(leidas.single.nuevo, isFalse);
    });

    test('y uno de tres (el de ayer, con COSTO PROMEDIO) también', () {
      final leidas = idaYVuelta([
        ['ELEMENTO', 'CANTIDAD', 'COSTO PROMEDIO'],
        ['Tubo PVC 2"', 10, 12500],
      ]);
      expect(leidas.single.cantidad, 10);
      expect(leidas.single.nuevo, isFalse);
      expect(leidas.single.costoEstimado, isNull);
    });

    test('editado a mano en Excel: "Sí", "185.000" y columnas en otro orden',
        () {
      final leidas = idaYVuelta([
        ['ESTIMADO POR', 'ELEMENTO', 'COSTO ESTIMADO', 'CANTIDAD', 'NUEVO',
            'UNIDAD'],
        ['Ing. Pérez', 'Brida ciega 6"', '185.000', '1', 'Sí', 'UND'],
      ]);
      final f = leidas.single;
      expect(f.elemento, 'Brida ciega 6"');
      expect(f.nuevo, isTrue);
      // Dinero como se escribe en Colombia: ciento ochenta y cinco mil.
      expect(f.costoEstimado, 185000);
      expect(f.cantidad, 1);
      expect(f.estimadoPor, 'Ing. Pérez');
    });

    test('NUEVO vacío o "NO" es del catálogo', () {
      final leidas = idaYVuelta([
        ['ELEMENTO', 'CANTIDAD', 'NUEVO'],
        ['Tubo PVC 2"', 1, 'NO'],
        ['Codo 90° 1"', 1, ''],
      ]);
      expect(leidas.every((f) => !f.nuevo), isTrue);
    });
  });

  group('los parecidos del catálogo', () {
    final catalogo = EmparejadorCatalogo([
      _elemento('a', 'Valvula mariposa 4" wafer', 180000),
      _elemento('b', 'Valvula mariposa 6" wafer', 260000),
      _elemento('c', 'Tubo PVC 2"', 12500),
    ]);

    test('el más parecido primero, y no trae lo que no se parece', () {
      final p = catalogo.parecidos('Válvula mariposa 4 pulgadas wafer');
      expect(p.first.$1.id, 'a');
      // La de 6" sí sale (pudo equivocarse de medida), pero después.
      expect(p.map((e) => e.$1.id).toList(), ['a', 'b']);
    });

    test('un tubo NO es parecido de una válvula, aunque ambos tengan medida',
        () {
      // Con similitud() los dos daban 0,45 (el tope de medida distinta).
      final p = catalogo.parecidos('Válvula mariposa 3" wafer');
      expect(p.map((e) => e.$1.id), isNot(contains('c')));
    });

    test('mismo nombre sin contar tildes ni mayúsculas', () {
      expect(catalogo.mismoNombre('VÁLVULA MARIPOSA 4" WAFER')?.id, 'a');
      expect(catalogo.mismoNombre('Válvula mariposa 8" wafer'), isNull);
    });
  });

  // "Descargar lo que no se cargó": el archivo vuelve a Devoluciones sin
  // repetir lo que ya entró, y cada línea dice por qué quedó por fuera.
  group('lo que no se cargó', () {
    const nuevaPendiente = PendienteDevolucion(
      elemento: 'Válvula mariposa 4" wafer',
      cantidad: 2,
      nuevo: true,
      unidad: 'UND',
      costoEstimado: 185000,
      estimadoPor: 'ing.perez@rpci.com.co',
      motivo: 'Artículo NUEVO sin resolver',
    );
    const enCero = PendienteDevolucion(
      elemento: 'Tubo PVC 2"',
      cantidad: 3,
      costoPromedio: 0,
      motivo: 'Costo en \$0 sin asignar',
    );

    test('mismo formato de la remisión, más el porqué al final', () {
      final filas = filasCsvPendientes([nuevaPendiente, enCero]);
      expect(filas.first, [...encabezadoDevolucion, 'POR QUE NO SE CARGO']);
      expect(filas[1], [
        'Válvula mariposa 4" wafer', 2, '', 'SI', 'UND', 185000,
        'ing.perez@rpci.com.co', 'Artículo NUEVO sin resolver',
      ]);
      expect(filas[2], ['Tubo PVC 2"', 3, 0, '', '', '', '', 'Costo en \$0 sin asignar']);
    });

    test('se vuelve a subir tal cual: el NUEVO conserva estimado y firma', () {
      final leidas = leerArchivoDevolucion(
          Reportes.bytesCsv(filasCsvPendientes([nuevaPendiente, enCero])),
          'devolucion_pendiente.csv');
      expect(leidas.length, 2);
      expect(leidas[0].nuevo, isTrue);
      expect(leidas[0].costoEstimado, 185000);
      expect(leidas[0].estimadoPor, 'ing.perez@rpci.com.co');
      expect(leidas[0].cantidad, 2);
      expect(leidas[1].nuevo, isFalse);
      expect(leidas[1].elemento, 'Tubo PVC 2"');
      expect(leidas[1].cantidad, 3);
    });

    test('un porqué con punto y coma, comillas o números no desordena nada',
        () {
      const raro = PendienteDevolucion(
        elemento: 'Tubo PVC 2"',
        cantidad: 4,
        motivo: 'Error al registrar: cantidad 999; costo "12500"',
      );
      final leidas = leerArchivoDevolucion(
          Reportes.bytesCsv(filasCsvPendientes([raro])), 'p.csv');
      expect(leidas.single.elemento, 'Tubo PVC 2"');
      expect(leidas.single.cantidad, 4);
      expect(leidas.single.nuevo, isFalse);
    });
  });

  group('regla 1: un NUEVO nunca se empareja solo', () {
    final catalogo = EmparejadorCatalogo([tubo, codo]);

    test('aunque tenga EXACTAMENTE el nombre de uno del catálogo', () {
      const f = FilaArchivoDevolucion(
          elemento: 'Tubo PVC 2"', cantidad: 10, nuevo: true);
      expect(emparejarFilaDevolucion(f, catalogo).$1, isNull);
    });

    test('la misma fila sin NUEVO sí se empareja, como siempre', () {
      const f = FilaArchivoDevolucion(elemento: 'Tubo PVC 2"', cantidad: 10);
      expect(emparejarFilaDevolucion(f, catalogo).$1?.id, 'e1');
    });
  });

  group('observacionArticuloNuevo: el estimado queda escrito', () {
    test('creado en el catálogo, cargado al estimado', () {
      expect(
        observacionArticuloNuevo(
          propuesto: 'Válvula mariposa 4" wafer',
          estimadoPor: 'ing.perez@rpci.com.co',
          costoEstimado: 185000,
          costoCargado: 185000,
          creado: true,
          nombreFinal: 'Válvula mariposa 4" wafer',
        ),
        // El mismo formato de pesos de toda la app (util/dinero.dart).
        'Artículo nuevo creado desde remisión · estimado por '
        'ing.perez@rpci.com.co: ${_money.format(185000)}',
      );
    });

    test('si la bodega corrige el costo, quedan los dos números', () {
      final o = observacionArticuloNuevo(
        propuesto: 'Válvula',
        estimadoPor: 'ing.perez@rpci.com.co',
        costoEstimado: 185000,
        costoCargado: 170000,
        creado: true,
        nombreFinal: 'Válvula',
      );
      expect(o, contains('185.000'));
      expect(o, contains('cargado a'));
      expect(o, contains('170.000'));
    });

    test('si ya existía, dice como qué', () {
      final o = observacionArticuloNuevo(
        propuesto: 'Valv. mariposa 4',
        costoEstimado: 185000,
        costoCargado: 180000,
        creado: false,
        nombreFinal: 'Valvula mariposa 4" wafer',
      );
      expect(o, startsWith('Propuesto como nuevo "Valv. mariposa 4"; ya '
          'existía como "Valvula mariposa 4" wafer"'));
    });
  });

  test('la ayuda dice que el costo PROMEDIO no se usa y cómo va un NUEVO', () {
    expect(ayudaFormatoDevolucion, contains('al cargar NO se usa'));
    expect(ayudaFormatoDevolucion, contains('pon SI en NUEVO'));
  });
}
