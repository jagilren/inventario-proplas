import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/util/movimiento_fmt.dart';

void main() {
  group('cantidadConSigno: lo que sale resta, lo que entra suma', () {
    test('salida siempre negativa', () {
      expect(cantidadConSigno('salida', 10), -10);
      // Aunque llegara ya negativa, no se debe voltear a positivo.
      expect(cantidadConSigno('salida', -10), -10);
    });

    test('entrada e inicial siempre positivas', () {
      expect(cantidadConSigno('entrada', 10), 10);
      expect(cantidadConSigno('inicial', 7), 7);
      expect(cantidadConSigno('entrada', -10), 10);
    });

    test('las devoluciones y las cargas masivas son entradas: positivas', () {
      // Para la base son 'entrada' normales; lo que las distingue es la
      // referencia, no el tipo.
      expect(cantidadConSigno('entrada', 25), 25);
    });

    test('ajuste conserva su propio signo', () {
      // Ese tipo YA viene firmado desde la base: positivo si suma, negativo
      // si resta. Forzarlo lo dañaría.
      expect(cantidadConSigno('ajuste', 5), 5);
      expect(cantidadConSigno('ajuste', -5), -5);
    });

    test('respeta los decimales', () {
      expect(cantidadConSigno('salida', 2.5), -2.5);
    });
  });
}
