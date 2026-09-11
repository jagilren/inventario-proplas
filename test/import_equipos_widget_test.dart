import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/activos_service.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/util/import_equipos.dart';
import 'package:mi_app/widgets/import_equipos_widgets.dart';

// La revisión de la carga masiva de equipos, en pantalla: cada equipo dice
// qué es y sus problemas CON TEXTO; las referencias nuevas se ven antes de
// crearlas, con sus parecidas.

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

final _bomba = ActivoReferencia.fromMap(
    {'id': 'r1', 'nombre': 'BOMBA DE DIAFRAGMA ELECTRICA', 'marca': 'GRUNDFOS'});
final _cat = CatalogoImport(
  referencias: [_bomba],
  bodegas: [Bodega.fromMap({'id': 'b1', 'nombre': 'Bodega RPCI'})],
  centros: [
    CentroCosto.fromMap({'id': 'c1', 'codigo': 'COMPRA', 'activo': true}),
    CentroCosto.fromMap(
        {'id': 'c2', 'codigo': 'G000002', 'es_interno': true, 'activo': true}),
  ],
);

RevisionImport _revision() => analizarImportEquipos([
      const FilaEquipoArchivo(
          fila: 2, serial: 'B-7788', referencia: 'BOMBA DE DIAFRAGMA ELECTRICA',
          condicion: 'nuevo', valorNuevo: '1.540.000', bodega: 'RPCI'),
      const FilaEquipoArchivo(
          fila: 3, serial: 'S-1', referencia: 'Bomba de diafragma eléctrica 2',
          condicion: 'usado', porcentaje: '70', valorNuevo: '7.474.600',
          bodega: 'RPCI'),
      const FilaEquipoArchivo(
          fila: 4, serial: 'K-1', referencia: 'Kit sellos mecánicos',
          esKit: 'SI', condicion: 'nuevo', bodega: 'Bodega Norte'),
      const FilaEquipoArchivo(
          fila: 5, serial: 'K-1', componente: 'Sello', cantidad: '2',
          valorUnitario: '10.000'),
    ], _cat);

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
  testWidgets('un equipo listo dice qué es, dónde queda y cuánto vale',
      (t) async {
    await _montar(t, TarjetaEquipoImport(equipo: _revision().equipos[0]));
    expect(find.text('B-7788'), findsOneWidget);
    expect(find.text('fila 2'), findsOneWidget);
    expect(find.textContaining('Bodega RPCI · Nuevo'), findsOneWidget);
    expect(find.textContaining('✗'), findsNothing);
  });

  testWidgets('una referencia NUEVA se marca con la palabra, y el % se ve',
      (t) async {
    await _montar(t, TarjetaEquipoImport(equipo: _revision().equipos[1]));
    expect(find.textContaining('NUEVA'), findsOneWidget);
    expect(find.textContaining('al 70 %'), findsOneWidget);
  });

  testWidgets('los problemas se leen en la fila, con texto', (t) async {
    await _montar(t, TarjetaEquipoImport(equipo: _revision().equipos[2]));
    expect(find.textContaining('✗ No reconozco la bodega "Bodega Norte"'),
        findsOneWidget);
    expect(find.textContaining('Kit · 1 componente ·'), findsOneWidget);
  });

  testWidgets('el panel dice qué referencias se crearán y a qué se parecen',
      (t) async {
    await _montar(t,
        PanelReferenciasNuevas(nuevas: _revision().referenciasNuevas));
    expect(find.text('Se crearán 2 referencias nuevas'), findsOneWidget);
    await t.tap(find.text('Se crearán 2 referencias nuevas'));
    await t.pumpAndSettle();
    expect(find.textContaining('Kit sellos mecánicos (kit)'), findsOneWidget);
    expect(find.textContaining('Se parece a: BOMBA DE DIAFRAGMA ELECTRICA'),
        findsOneWidget);
  });

  testWidgets('contraste, 48 dp y nombres, con el panel abierto', (t) async {
    final h = t.ensureSemantics();
    final r = _revision();
    await _montar(
        t,
        Column(children: [
          PanelReferenciasNuevas(nuevas: r.referenciasNuevas),
          for (final e in r.equipos) TarjetaEquipoImport(equipo: e),
        ]));
    await t.tap(find.textContaining('Se crearán'));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(textContrastGuideline));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    h.dispose();
  });

  testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
    final r = _revision();
    await _montar(
        t,
        Column(children: [
          PanelReferenciasNuevas(nuevas: r.referenciasNuevas),
          for (final e in r.equipos) TarjetaEquipoImport(equipo: e),
        ]),
        escala: 2.0);
    await t.tap(find.textContaining('Se crearán'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
