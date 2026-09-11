import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/widgets/carga_devolucion.dart';

// El resumen de una carga de Devoluciones con "Descargar lo que no se
// cargó". Lo que más importa en el celular: si se cancela el diálogo de
// guardar, la pantalla NO puede decir "guardado".

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

Future<void> _abrir(WidgetTester t, Widget dialogo,
    {double escalaTexto = 1.0}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: _tema,
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(escalaTexto)),
      child: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showDialog<void>(
                context: ctx, builder: (_) => dialogo),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

const _resumen = [
  '✓ Cargados: 12',
  '• Nuevos sin resolver (omitidos): 2',
  '• Sin emparejar (omitidos): 1',
];

void main() {
  testWidgets('con pendientes: lo dice y ofrece descargarlos', (t) async {
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen, pendientes: 3, descargarPendientes: () async => true));
    expect(find.text('✓ Cargados: 12'), findsOneWidget);
    expect(find.textContaining('Quedaron 3 línea(s) sin cargar'), findsOneWidget);
    expect(find.text('Descargar lo que no se cargó (3)'), findsOneWidget);
  });

  testWidgets('al guardar, lo confirma', (t) async {
    var llamadas = 0;
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen,
            pendientes: 3,
            descargarPendientes: () async {
              llamadas++;
              return true;
            }));
    await t.tap(find.text('Descargar lo que no se cargó (3)'));
    await t.pumpAndSettle();
    expect(llamadas, 1);
    expect(find.textContaining('✓ Guardado'), findsOneWidget);
  });

  testWidgets('si se cancela el diálogo de guardar, NO dice guardado',
      (t) async {
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen,
            pendientes: 3,
            descargarPendientes: () async => false));
    await t.tap(find.text('Descargar lo que no se cargó (3)'));
    await t.pumpAndSettle();
    expect(find.textContaining('✓ Guardado'), findsNothing);
    expect(find.textContaining('No se guardó'), findsOneWidget);
  });

  testWidgets('si falla, dice por qué y se puede reintentar', (t) async {
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen,
            pendientes: 3,
            descargarPendientes: () async => throw Exception('sin espacio')));
    await t.tap(find.text('Descargar lo que no se cargó (3)'));
    await t.pumpAndSettle();
    expect(find.textContaining('No se pudo guardar'), findsOneWidget);
    final boton = t.widget<FilledButton>(find.ancestor(
        of: find.text('Descargar lo que no se cargó (3)'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(boton.onPressed, isNotNull);
  });

  testWidgets('sin pendientes no aparece el botón', (t) async {
    await _abrir(t, const DialogoCargaTerminada(resumen: ['✓ Cargados: 12']));
    expect(find.textContaining('Descargar'), findsNothing);
  });

  testWidgets('todo lo que se toca mide 48 dp, tiene nombre y contraste',
      (t) async {
    final h = t.ensureSemantics();
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen,
            pendientes: 3,
            descargarPendientes: () async => false));
    await t.tap(find.text('Descargar lo que no se cargó (3)'));
    await t.pumpAndSettle();
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
    await _abrir(
        t,
        DialogoCargaTerminada(
            resumen: _resumen,
            pendientes: 3,
            descargarPendientes: () async => true),
        escalaTexto: 2.0);
    await t.tap(find.text('Descargar lo que no se cargó (3)'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
