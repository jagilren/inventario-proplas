import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/activos_service.dart';
import 'package:mi_app/widgets/observacion_reingreso.dart';

// Un REINGRESO también es un elemento del listado de observaciones del
// equipo (schema_v69), no solo un movimiento. Pedido del usuario: "no
// olvides esto nunca".

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

ActivoObservacion _reingreso({String texto = '', bool anulado = false}) =>
    ActivoObservacion.fromMap({
      'id': 'm1',
      'fecha': '2026-09-11T19:57:16Z',
      'texto': texto,
      'origen': 'reingreso',
      'contexto': null,
      'usuario_email': 'jagilren@gmail.com',
      'editada': false,
      'mov_centro': 'NP00038',
      'mov_centro_destino': 'G000002',
      'mov_bodega': 'Bodega PROPLAS',
      'mov_condicion': 'usado',
      'mov_anulado': anulado,
    });

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
}

void main() {
  group('el modelo', () {
    test('se reconoce, y dice lo mismo que la pestaña Movimientos', () {
      final o = _reingreso();
      expect(o.esReingreso, isTrue);
      expect(o.esDeComponente, isFalse);
      expect(o.etiquetaOrigen, ActivoMovimiento.etiquetaTipo('entrada', true));
      expect(o.etiquetaOrigen, 'Entrada · REINGRESO');
    });

    test('sin texto también se oye completo', () {
      expect(
          _reingreso().descripcionAccesible,
          'Entrada · REINGRESO. Desde NP00038 a Bodega PROPLAS. '
          'Condición Usado. Sin observación');
    });

    test('con texto y anulado', () {
      expect(
          _reingreso(texto: 'No cumplió con el caudal', anulado: true)
              .descripcionAccesible,
          'Entrada · REINGRESO. Desde NP00038 a Bodega PROPLAS. '
          'Condición Usado. Anulado después. '
          'Observación: No cumplió con el caudal');
    });

    test('las observaciones de antes (sin columnas mov_) no cambian', () {
      final o = ActivoObservacion.fromMap({
        'id': 'o1',
        'fecha': '2026-09-10T12:00:00Z',
        'texto': 'Llegó con un golpe',
        'origen': 'manual',
        'contexto': null,
        'usuario_email': 'kuribe@rpci.com.co',
        'editada': false,
      });
      expect(o.esReingreso, isFalse);
      expect(o.movAnulado, isFalse);
      expect(o.descripcionAccesible, 'Llegó con un golpe');
    });
  });

  group('LineaObservacionReingreso', () {
    testWidgets('dice qué fue, de dónde a dónde y cómo volvió', (t) async {
      await _montar(t, LineaObservacionReingreso(observacion: _reingreso()));
      expect(find.text('Entrada · REINGRESO'), findsOneWidget);
      expect(find.text('🎯 NP00038 ➡️ 🎯 G000002'), findsOneWidget);
      expect(find.text('Volvió usado'), findsOneWidget);
    });

    testWidgets('sin texto sale igual, y lo dice', (t) async {
      await _montar(t, LineaObservacionReingreso(observacion: _reingreso()));
      expect(find.text('Sin observación'), findsOneWidget);
    });

    testWidgets('con texto, el texto', (t) async {
      await _montar(
          t,
          LineaObservacionReingreso(
              observacion: _reingreso(texto: 'No cumplió con el caudal')));
      expect(find.text('No cumplió con el caudal'), findsOneWidget);
      expect(find.text('Sin observación'), findsNothing);
    });

    testWidgets('anulado: lo DICE con texto', (t) async {
      await _montar(t,
          LineaObservacionReingreso(observacion: _reingreso(anulado: true)));
      expect(find.text('Anulado después'), findsOneWidget);
    });

    testWidgets('el lector de pantalla oye UNA frase, y hay contraste',
        (t) async {
      final h = t.ensureSemantics();
      await _montar(t,
          LineaObservacionReingreso(observacion: _reingreso(anulado: true)));
      expect(find.bySemanticsLabel(_reingreso(anulado: true).descripcionAccesible),
          findsOneWidget);
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await _montar(
          t,
          LineaObservacionReingreso(
              observacion: _reingreso(
                  texto: 'Regresa por cambio a una referencia más grande. '
                      'No cumplió con el caudal',
                  anulado: true)),
          escala: 2.0);
      expect(t.takeException(), isNull);
    });
  });
}
