import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/util/carrito_salida.dart';
import 'package:mi_app/widgets/carrito_salida_widgets.dart';

// "Armar salida": el carrito que despacha sin archivo. Usa las mismas
// funciones de la base que la salida masiva por Excel, así que lo que se
// prueba aquí es lo que la pantalla decide ANTES de llamarlas.

Elemento _el(String id, String nombre,
        {num existencia = 100, num costo = 12500, bool serializado = false,
        String unidad = 'UND'}) =>
    Elemento.fromMap({
      'id': id,
      'nombre': nombre,
      'unidad': unidad,
      'existencia': existencia,
      'costo_promedio': costo,
      'serializado': serializado,
    });

ValidacionSalida _saldo(String id,
        {num pedido = 5, num disponible = 10, bool alcanza = true,
        num enOtras = 0, String? otras}) =>
    ValidacionSalida.fromMap({
      'elemento_id': id,
      'nombre': 'x',
      'unidad': 'UND',
      'pedido': pedido,
      'disponible': disponible,
      'alcanza': alcanza,
      'en_otras': enOtras,
      'otras_detalle': otras,
    });

final _tubo = _el('e1', 'Tubo PVC 2"');
final _codo = _el('e2', 'Codo 90° 1/2"', costo: 3200);

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

Future<void> _montar(WidgetTester t, Widget w, {double escala = 1.0}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: _tema,
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 800), textScaler: TextScaler.linear(escala)),
      child: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('el carrito', () {
    test('el mismo artículo se reconoce, no se duplica', () {
      final lineas = [LineaSalida(_tubo, 5)];
      expect(indiceEnCarrito(lineas, 'e1'), 0);
      expect(indiceEnCarrito(lineas, 'e2'), -1);
    });

    test('totales y resumen, con singular y plural', () {
      final lineas = [LineaSalida(_tubo, 5), LineaSalida(_codo, 2)];
      expect(totalCarrito(lineas), 5 * 12500 + 2 * 3200);
      expect(resumenCarrito(lineas), '2 artículos · 7 unidades');
      expect(resumenCarrito([LineaSalida(_tubo, 1)]), '1 artículo · 1 unidad');
    });

    test('lo que se le manda a la base es lo que espera', () {
      expect(itemsSalida([LineaSalida(_tubo, 2.5)]),
          [{'elemento_id': 'e1', 'cantidad': 2.5}]);
    });

    test('las cantidades se escriben como en Colombia', () {
      expect(textoCantidadSalida(7), '7');
      expect(textoCantidadSalida(7.0), '7');
      expect(textoCantidadSalida(2.5), '2,5');
    });
  });

  group('qué línea NO se puede despachar', () {
    test('cantidad en cero', () {
      expect(problemaLinea(LineaSalida(_tubo, 0), null),
          contains('mayor que cero'));
    });

    test('un serializado se despacha por serial, y lo dice', () {
      final l = LineaSalida(_el('e9', 'Blower', serializado: true), 1);
      expect(problemaLinea(l, null), contains('seriales'));
    });

    test('no alcanza: dice cuánto hay, y en qué otra bodega', () {
      final l = LineaSalida(_tubo, 20);
      expect(problemaLinea(l, _saldo('e1', disponible: 3, alcanza: false)),
          'Solo hay 3 y se piden 20.');
      expect(
          problemaLinea(
              l,
              _saldo('e1',
                  disponible: 3, alcanza: false, enOtras: 40,
                  otras: 'Bodega PROPLAS: 40')),
          contains('En otras bodegas: Bodega PROPLAS: 40'));
    });

    test('sin señal (sin saldo) no se bloquea: la base revisa al despachar',
        () {
      expect(problemaLinea(LineaSalida(_tubo, 999), null), isNull);
    });

    test('solo se despacha lo que está listo', () {
      final lineas = [
        LineaSalida(_tubo, 5),
        LineaSalida(_codo, 50),
        LineaSalida(_el('e9', 'Blower', serializado: true), 1),
      ];
      final saldos = {'e2': _saldo('e2', disponible: 2, alcanza: false)};
      expect(lineasListas(lineas, saldos).map((l) => l.elemento.id), ['e1']);
    });
  });

  test('el CSV de lo despachado lleva la bodega, el centro y el total', () {
    final filas = filasCsvSalida([LineaSalida(_tubo, 5), LineaSalida(_codo, 2)],
        bodega: 'Bodega RPCI', centro: 'NP00039 · TINTEXA');
    expect(filas.first, ['BODEGA', 'Bodega RPCI', 'CENTRO DE COSTO',
        'NP00039 · TINTEXA']);
    expect(filas[1], ['ELEMENTO', 'CANTIDAD', 'UNIDAD', 'COSTO PROMEDIO',
        'VALOR']);
    expect(filas[2], ['Tubo PVC 2"', 5, 'UND', 12500, 62500]);
    expect(filas.last, ['TOTAL', '', '', '', 62500 + 6400]);
  });

  group('en pantalla', () {
    testWidgets('una línea dice cuánto sale, cuánto vale y cuánto hay',
        (t) async {
      await _montar(
          t,
          TarjetaLineaSalida(
              linea: LineaSalida(_tubo, 5), saldo: _saldo('e1', disponible: 9)));
      expect(find.textContaining('5 UND · '), findsOneWidget);
      expect(find.text('Hay 9 UND en la bodega'), findsOneWidget);
    });

    testWidgets('el problema se lee en la línea, con texto', (t) async {
      await _montar(
          t,
          TarjetaLineaSalida(
              linea: LineaSalida(_tubo, 20),
              saldo: _saldo('e1', disponible: 3, alcanza: false)));
      expect(find.textContaining('✗ Solo hay 3'), findsOneWidget);
      expect(find.text('Hay 3 UND en la bodega'), findsNothing);
    });

    testWidgets('el pie dice cuántos artículos y cuánto suma', (t) async {
      final h = t.ensureSemantics();
      await _montar(t,
          PieCarritoSalida(lineas: [LineaSalida(_tubo, 5), LineaSalida(_codo, 2)]));
      expect(find.text('2 artículos · 7 unidades'), findsOneWidget);
      // Una sola frase para el lector de pantalla.
      expect(find.bySemanticsLabel(RegExp(r'^2 artículos · 7 unidades\. Total estimado')),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('48 dp, nombres y contraste', (t) async {
      final h = t.ensureSemantics();
      await _montar(
          t,
          Column(children: [
            TarjetaLineaSalida(
                linea: LineaSalida(_tubo, 20),
                saldo: _saldo('e1', disponible: 3, alcanza: false),
                onEditar: () {},
                onQuitar: () {}),
            PieCarritoSalida(lineas: [LineaSalida(_tubo, 20)]),
          ]));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await _montar(
          t,
          Column(children: [
            TarjetaLineaSalida(
                linea: LineaSalida(
                    _el('e5', 'Tornillo Cabeza Hexagonal Rosca Continua Inox '
                        '304 9/16x3-1/2"'),
                    20),
                saldo: _saldo('e5', disponible: 3, alcanza: false,
                    enOtras: 40, otras: 'Bodega PROPLAS: 40'),
                onEditar: () {},
                onQuitar: () {}),
            PieCarritoSalida(lineas: [LineaSalida(_tubo, 20)]),
          ]),
          escala: 2.0);
      expect(t.takeException(), isNull);
    });
  });
}
