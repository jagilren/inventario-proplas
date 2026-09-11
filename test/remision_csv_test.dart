import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/reportes.dart';
import 'package:mi_app/util/import_archivo.dart';
import 'package:mi_app/util/plantilla_import.dart';

// El CSV de la remisión de devolución lleva una tercera columna, COSTO
// PROMEDIO (2026-09-11). Lo que importa probar no es solo que salga la
// columna: es que ese MISMO archivo se siga cargando bien en Devoluciones,
// que es para lo que existe.

Elemento _elemento(String id, String nombre, num costo) => Elemento.fromMap({
      'id': id,
      'nombre': nombre,
      'costo_promedio': costo,
    });

void main() {
  final tubo = _elemento('e1', 'Tubo PVC 2"', 12500);
  final codo = _elemento('e2', 'Codo 90° 1-1/2"', 3200.6);

  group('filasCsvDevolucion', () {
    test('tres columnas: elemento, cantidad y costo promedio', () {
      final filas = filasCsvDevolucion([(tubo, 10), (codo, 4)]);
      expect(filas.first, ['ELEMENTO', 'CANTIDAD', 'COSTO PROMEDIO']);
      expect(filas[1], ['Tubo PVC 2"', 10, 12500]);
      // En pesos enteros, como en los informes.
      expect(filas[2], ['Codo 90° 1-1/2"', 4, 3201]);
    });

    test('el costo leído del servidor manda sobre el que traía la lista', () {
      // La lista se armó cuando el tubo valía 12.500; hoy vale 13.000.
      final filas =
          filasCsvDevolucion([(tubo, 10), (codo, 4)], costos: {'e1': 13000});
      expect(filas[1][2], 13000);
      // El que no vino del servidor se queda con el suyo.
      expect(filas[2][2], 3201);
    });

    test('un artículo en \$0 sale en 0, no vacío', () {
      final filas = filasCsvDevolucion([(_elemento('e3', 'Brida', 0), 1)]);
      expect(filas[1], ['Brida', 1, 0]);
    });

    test('la plantilla y la remisión usan el MISMO encabezado', () {
      expect(filasCsvDevolucion([]).single, encabezadoDevolucion);
    });
  });

  group('lo que genera la remisión se carga bien en Devoluciones', () {
    List<List<dynamic>> idaYVuelta(List<List<dynamic>> filas) =>
        leerArchivoImport(Reportes.bytesCsv(filas), 'remision.csv');

    test('elemento y cantidad llegan intactos; el costo no se confunde', () {
      final leidas =
          idaYVuelta(filasCsvDevolucion([(tubo, 10), (codo, 2.5)]));
      expect(leidas.length, 2);
      expect(leidas[0][0], 'Tubo PVC 2"');
      expect(parseCantidad(leidas[0][1].toString()), 10);
      expect(leidas[1][0], 'Codo 90° 1-1/2"');
      // 2,5 con coma decimal, como lo escribe el CSV en Colombia.
      expect(parseCantidad(leidas[1][1].toString()), 2.5);
    });

    test('la columna nueva NO se toma como la cantidad', () {
      // El peligro de agregar una columna: que el lector la tome por otra.
      // Un costo de 12500 leído como cantidad serían 12.500 tubos.
      final leidas = idaYVuelta(filasCsvDevolucion([(tubo, 3)]));
      expect(parseCantidad(leidas.single[1].toString()), 3);
    });

    test('un nombre con punto y coma o comillas no parte la fila', () {
      final raro = _elemento('e4', 'Unión; tipo "universal" 1/2"', 900);
      final leidas = idaYVuelta(filasCsvDevolucion([(raro, 7)]));
      expect(leidas.single[0], 'Unión; tipo "universal" 1/2"');
      expect(parseCantidad(leidas.single[1].toString()), 7);
    });

    test('un archivo viejo, de dos columnas, se sigue cargando', () {
      final leidas = idaYVuelta([
        ['ELEMENTO', 'CANTIDAD'],
        ['Tubo PVC 2"', 10],
      ]);
      expect(leidas.single[0], 'Tubo PVC 2"');
      expect(parseCantidad(leidas.single[1].toString()), 10);
    });
  });

  test('la ayuda de devolución dice que el costo NO se usa al cargar', () {
    expect(ayudaFormatoDevolucion, contains('COSTO PROMEDIO'));
    expect(ayudaFormatoDevolucion, contains('al cargar NO se usa'));
  });
}
