import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/util/import_archivo.dart';

/// Pruebas del emparejador de archivos de carga masiva.
///
/// El caso que motivó estas pruebas: el parecido se calcula con CONJUNTOS de
/// palabras, y `1/2"` se partía en `1` y `2` mientras que `2-1/2"` se partía
/// en `2`, `1` y `2`. Como un conjunto descarta repetidos, ambos quedaban
/// como {1,2} y dos artículos de medidas distintas daban parecido PERFECTO.
/// Se midieron 94 pares así en el catálogo real.
void main() {
  group('normalizarTexto: las medidas quedan en un solo número', () {
    test('fracción suelta', () {
      expect(normalizarTexto('Tubo 1/2"'), 'tubo 0.5');
      expect(normalizarTexto('Tubo 3/4"'), 'tubo 0.75');
    });

    test('número mixto, con guion o con espacio, da lo mismo', () {
      expect(normalizarTexto('Coraza 1-1/2"'), 'coraza 1.5');
      expect(normalizarTexto('Coraza 1 1/2"'), 'coraza 1.5');
      expect(normalizarTexto('Coraza 1- 1/2"'), 'coraza 1.5');
    });

    test('SCH 40 1/2" son DOS números, no "cuarenta y medio"', () {
      // El 40 es el schedule y el 1/2 el diámetro: no se deben fusionar.
      expect(firmaNumerica(normalizarTexto('Tapon SCH 40 1/2"')),
          {'40', '0.5'});
    });

    test('quita tildes y baja a minúsculas', () {
      expect(normalizarTexto('Codo 90° Presión'), 'codo 90 presion');
    });
  });

  group('medidas que se contradicen: no deben emparejar', () {
    void noEmpareja(String a, String b) {
      final s = similitud(normalizarTexto(a), normalizarTexto(b));
      expect(s, lessThan(0.55),
          reason: '"$a" no debería emparejar con "$b" (dio $s)');
    }

    test('tapón de 1/2" vs de 2-1/2"', () {
      noEmpareja('Tapon Liso PVC Presion SCH 40 1/2"',
          'Tapon Liso PVC Presion SCH 40 2-1/2"');
    });

    test('codo de 1/2" vs de 1-1/2"', () {
      noEmpareja('Codo 90° Inox 304 SCH 10 Soldar 1/2"',
          'Codo 90° Inox 304 SCH 10 Soldar 1-1/2"');
    });

    test('niple de 1/4" vs de 1-1/4"', () {
      noEmpareja('Niple Roscar Inox 304 SCH 40 1/4"x10 cm',
          'Niple Roscar Inox 304 SCH 40 1-1/4"x10 cm');
    });

    test('válvula 1/2x1/2 vs 1-1/2x1-1/2', () {
      noEmpareja('Valvula alivio bronce 1/2x1/2" Safety',
          'Valvula alivio bronce 1- 1/2x1-1/2" Safety');
    });
  });

  group('lo que SÍ debe seguir emparejando', () {
    void empareja(String a, String b) {
      final s = similitud(normalizarTexto(a), normalizarTexto(b));
      expect(s, greaterThanOrEqualTo(0.55),
          reason: '"$a" debería emparejar con "$b" (dio $s)');
    }

    test('solo cambia una mayúscula', () {
      empareja('Brida Lisa So Inox 304 L 1" Clase 150',
          'Brida Lisa SO Inox 304 L 1" Clase 150');
    });

    test('la misma medida escrita de dos formas', () {
      empareja('Coraza Americana Flexible 1 1/2"',
          'Coraza Americana Flexible 1-1/2"');
    });

    test('el Excel escribe el nombre casi igual', () {
      empareja('Tubo PVC Presion SCH 40 2 X Metro',
          'Tubo PVC Presion SCH 40 2" X Metro');
      empareja('abrazadera industrial inox 304 36-39 mm 1-1/2',
          'Abrazadera industrial Inox 304 36-39 mm (1-1/2")');
    });

    test('OJO: un nombre muy abreviado NO empareja solo, y está bien', () {
      // "ABRAZADERA 1 1/2" comparte muy pocas palabras con el nombre
      // completo del catálogo, así que queda "sin emparejar" y el usuario
      // lo elige a mano. Esto es de ANTES del arreglo de medidas (daba
      // 0.333) y no cambió: se deja escrito para que quede claro que es
      // comportamiento conocido y no una regresión.
      final s = similitud(normalizarTexto('ABRAZADERA 1 1/2'),
          normalizarTexto('Abrazadera industrial Inox 304 36-39 mm (1-1/2")'));
      expect(s, lessThan(0.55));
      expect(s, closeTo(0.33, 0.05));
    });

    test('tener MENOS números no debe bloquear el emparejamiento', () {
      // {2} ⊆ {2, 40}: el usuario escribió menos datos, no datos que
      // contradigan. El parecido puede quedar bajo por las palabras, pero
      // la regla de medidas no debe ser la que lo tumbe.
      expect(
        medidasCompatibles(normalizarTexto('TUBO PVC 2 PULG'),
            normalizarTexto('Tubo PVC Presion SCH 40 2" X Metro')),
        isTrue,
      );
    });

    test('el arreglo no empeora lo que ya no emparejaba', () {
      // Este caso daba 0.333 ANTES del arreglo (palabras muy distintas) y
      // debe seguir dando lo mismo: la regla de medidas no lo toca.
      final s = similitud(normalizarTexto('TUBO PVC 2 PULG'),
          normalizarTexto('Tubo PVC Presion SCH 40 2" X Metro'));
      expect(s, closeTo(0.333, 0.01));
    });

    test('sin números de por medio, manda el parecido del texto', () {
      empareja('caneca plastica 30 gl', 'Caneca plastica de 30 GL');
    });
  });

  group('EmparejadorCatalogo elige el correcto entre variantes', () {
    test('no se queda con el de otra medida', () {
      // Se arma un catálogo de mentiras con las tres variantes.
      final catalogo = [
        _elem('Tapon Liso PVC Presion SCH 40 1/2"'),
        _elem('Tapon Liso PVC Presion SCH 40 1-1/2"'),
        _elem('Tapon Liso PVC Presion SCH 40 2-1/2"'),
      ];
      final emp = EmparejadorCatalogo(catalogo);
      final (m, _) = emp.mejor('TAPON LISO PVC SCH 40 2-1/2');
      expect(m?.nombre, 'Tapon Liso PVC Presion SCH 40 2-1/2"');
    });
  });
}

/// Elemento mínimo para las pruebas (solo importa el nombre).
Elemento _elem(String nombre) => Elemento.fromMap({
      'id': nombre,
      'nombre': nombre,
      'unidad': 'UND',
      'existencia': 0,
      'costo_promedio': 0,
      'stock_minimo': 0,
      'activo': true,
    });
