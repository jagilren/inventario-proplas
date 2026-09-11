import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mi_app/util/dinero.dart';

// Cómo escribe un valor en pesos una persona en Colombia (SDD §9.9).

void main() {
  group('lo que antes se leía mal, EN SILENCIO', () {
    test('"45.000" es cuarenta y cinco mil, no 45', () {
      expect(leerPesos('45.000'), 45000);
    });
    test('"1.540.000" es un millón quinientos cuarenta mil, no \$0', () {
      expect(leerPesos('1.540.000'), 1540000);
    });
    test('miles escritos a la inglesa también', () {
      expect(leerPesos('1,540,000'), 1540000);
      expect(leerPesos('45,000'), 45000);
    });
    test('miles y decimales juntos, en los dos estilos', () {
      expect(leerPesos('1.234,5'), 1234.5);
      expect(leerPesos('1,234.5'), 1234.5);
      expect(leerPesos('1.540.000,25'), 1540000.25);
    });
  });

  group('lo que ya se leía bien, sigue igual', () {
    test('sin separadores', () {
      expect(leerPesos('45000'), 45000);
      expect(leerPesos('0'), 0);
    });
    test('decimal con coma o con punto (1 o 2 dígitos)', () {
      expect(leerPesos('45,5'), 45.5);
      expect(leerPesos('45.5'), 45.5);
      expect(leerPesos('12.75'), 12.75);
      expect(leerPesos(',5'), 0.5);
    });
  });

  group('lo que se ignora', () {
    test('signo de pesos, COP y espacios', () {
      expect(leerPesos(r'$ 1.540.000'), 1540000);
      expect(leerPesos('1.540.000 COP'), 1540000);
      expect(leerPesos('  45000  '), 45000);
      // El formato que produce la propia app al copiar un valor.
      final hecho = NumberFormat.currency(
              locale: 'es_CO', symbol: r'$', decimalDigits: 0)
          .format(1540000);
      expect(leerPesos(hecho), 1540000);
    });
  });

  group('lo que no es un número: null, nunca un valor inventado', () {
    test('vacío o texto', () {
      expect(leerPesos(''), isNull);
      expect(leerPesos('   '), isNull);
      expect(leerPesos('abc'), isNull);
      expect(leerPesos(r'$'), isNull);
    });
    test('miles mal agrupados', () {
      expect(leerPesos('1.54.000'), isNull);
      expect(leerPesos('12.34.567'), isNull);
      expect(leerPesos('12.34,5'), isNull);
    });
  });

  group('pesosEntendidos: lo que se VE debajo del campo', () {
    final fmt =
        NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
    test('muestra cómo quedó entendido', () {
      expect(pesosEntendidos('1.540.000'), '= ${fmt.format(1540000)}');
      expect(pesosEntendidos('45.000'), '= ${fmt.format(45000)}');
    });
    test('vacío no dice nada; ilegible lo avisa', () {
      expect(pesosEntendidos(''), isNull);
      expect(pesosEntendidos('1.54.000'), 'No se entiende como valor en pesos');
    });
  });
}
