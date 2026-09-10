import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mi_app/activos_service.dart';
import 'package:mi_app/widgets/kit_componentes.dart';

// Accesibilidad y visibilidad de las pantallas de KITS (Fase 3,
// docs/plan-kits-equipos.md). No es "se ve bien en mi pantalla": son las
// pruebas de accesibilidad de Flutter —área táctil de 48 dp, que todo lo que
// se toca tenga nombre para el lector de pantalla, contraste del texto— y que
// nada se desborde en un celular de 360 px con la letra al DOBLE.

// El mismo tema de la app (lib/main.dart): el contraste depende del color.
final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Un celular angosto (360 px) y, si se pide, la letra agrandada como la
/// pone alguien que ve poco (Ajustes > Tamaño de fuente).
Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  double escalaTexto = 1.0,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: _tema,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(escalaTexto),
        ),
        child: Scaffold(body: SingleChildScrollView(child: hijo)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ActivoComponente _componente({
  String nombre = 'Tela filtros de los medios',
  num cantidad = 24,
  num valor = 45000,
}) =>
    ActivoComponente.fromMap({
      'id': 'c1',
      'activo_id': 'a1',
      'nombre': nombre,
      'valor_unitario': valor,
      'cantidad': cantidad,
      'subtotal': cantidad * valor,
      'orden': 1,
    });

void main() {
  group('TarjetaComponente', () {
    testWidgets('el lector de pantalla oye UNA frase completa', (t) async {
      final h = t.ensureSemantics();
      await _montar(
          t, TarjetaComponente(componente: _componente(), porcentaje: 70));
      final frase =
          TarjetaComponente(componente: _componente(), porcentaje: 70)
              .fraseAccesible;
      expect(find.bySemanticsLabel(frase), findsOneWidget);
      // En palabras: qué es cada cifra, y sin el "×".
      expect(frase, contains('24 unidades a'));
      expect(frase, contains('subtotal ${_money.format(1080000)}'));
      expect(frase, contains('al 70 por ciento, ${_money.format(756000)}'));
      expect(frase, isNot(contains('×')));
      h.dispose();
    });

    testWidgets('al 100% no muestra una línea ponderada que no aporta',
        (t) async {
      await _montar(
          t, TarjetaComponente(componente: _componente(), porcentaje: 100));
      expect(find.textContaining('al 100%'), findsNothing);
    });

    testWidgets('un agotado lo DICE con texto, no solo con color', (t) async {
      await _montar(
          t,
          TarjetaComponente(
              componente: _componente(cantidad: 0), porcentaje: 100));
      expect(find.text('Agotado'), findsOneWidget);
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await _montar(
          t,
          TarjetaComponente(
              componente: _componente(
                  nombre: 'Tela filtros de los extremos del tanque principal',
                  cantidad: 1250,
                  valor: 1845000),
              porcentaje: 70),
          escalaTexto: 2.0);
      // Un desborde en Flutter es una excepción de dibujo: si la hubiera,
      // aquí aparecería.
      expect(t.takeException(), isNull);
    });

    testWidgets('contraste suficiente, también en uno agotado', (t) async {
      await _montar(
          t,
          Column(children: [
            TarjetaComponente(componente: _componente(), porcentaje: 70),
            TarjetaComponente(
                componente: _componente(nombre: 'Guías', cantidad: 0),
                porcentaje: 70),
          ]));
      await expectLater(t, meetsGuideline(textContrastGuideline));
    });
  });

  group('PieTotalKit', () {
    testWidgets('dice el valor del kit y el ponderado, en una frase',
        (t) async {
      final h = t.ensureSemantics();
      await _montar(t, const PieTotalKit(total: 1540000, porcentaje: 70));
      expect(
          find.bySemanticsLabel(
              'Valor del kit a nuevo, ${_money.format(1540000)}. '
              'al 70 por ciento, ${_money.format(1078000)}'),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await _montar(t, const PieTotalKit(total: 154000000, porcentaje: 70),
          escalaTexto: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('MarcaKit', () {
    testWidgets('el lector de pantalla dice "Es un kit"', (t) async {
      final h = t.ensureSemantics();
      await _montar(t, const MarcaKit());
      expect(find.bySemanticsLabel('Es un kit'), findsOneWidget);
      h.dispose();
    });
  });

  group('HojaComponente', () {
    Widget hoja() => const HojaComponente(activoId: 'a1', orden: 1);

    testWidgets('todo lo que se toca mide 48 dp y tiene nombre', (t) async {
      final h = t.ensureSemantics();
      await _montar(t, hoja());
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('sin datos no guarda: dice qué falta en cada campo', (t) async {
      await _montar(t, hoja());
      await t.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await t.pumpAndSettle();
      expect(find.text('Escribe el nombre del componente'), findsOneWidget);
      expect(find.text('Escribe cuántos hay'), findsOneWidget);
      expect(find.text('Escribe el valor de cada uno'), findsOneWidget);
    });

    testWidgets('"45.000" como se escribe en Colombia NO se vuelve 45',
        (t) async {
      await _montar(t, hoja());
      await t.enterText(find.widgetWithText(TextField, 'Valor unitario *'),
          '45.000');
      await t.pump();
      // El campo solo acepta dígitos: queda 45000, y lo muestra entendido.
      expect(find.text('45000'), findsOneWidget);
      expect(find.text('= ${_money.format(45000)} cada uno'), findsOneWidget);
    });

    testWidgets('cantidad con coma decimal y subtotal en vivo', (t) async {
      await _montar(t, hoja());
      await t.enterText(
          find.widgetWithText(TextField, 'Cantidad *'), '2,5');
      await t.enterText(
          find.widgetWithText(TextField, 'Valor unitario *'), '45000');
      await t.pump();
      expect(
          find.text('Subtotal: 2,5 × ${_money.format(45000)} = '
              '${_money.format(112500)}'),
          findsOneWidget);
    });

    testWidgets('cantidad cero o negativa: lo dice', (t) async {
      await _montar(t, hoja());
      await t.enterText(find.widgetWithText(TextField, 'Nombre *'), 'Guías');
      await t.enterText(find.widgetWithText(TextField, 'Cantidad *'), '0');
      await t.enterText(
          find.widgetWithText(TextField, 'Valor unitario *'), '15000');
      await t.tap(find.widgetWithText(FilledButton, 'Agregar'));
      await t.pumpAndSettle();
      expect(find.text('Tiene que ser mayor que cero'), findsOneWidget);
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await _montar(t, hoja(), escalaTexto: 2.0);
      await t.enterText(
          find.widgetWithText(TextField, 'Cantidad *'), '24');
      await t.enterText(
          find.widgetWithText(TextField, 'Valor unitario *'), '45000');
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  test('textoCantidad: sin ".0" y con coma decimal', () {
    expect(textoCantidad(24), '24');
    expect(textoCantidad(24.0), '24');
    expect(textoCantidad(2.5), '2,5');
  });
}
