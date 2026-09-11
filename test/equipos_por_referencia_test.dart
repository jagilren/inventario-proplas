import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/activos_service.dart';
import 'package:mi_app/screens/activos_de_referencia_page.dart';

// EQUIPOS POR REFERENCIA: disponibles, no disponibles y VENDIDOS
// (schema_v68). Antes "no disponibles" era total − disponibles y metía ahí
// también los vendidos, que ya ni siquiera son nuestros.

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

/// Una fila como la entrega la vista `activos_disponibilidad`.
Map<String, dynamic> _fila(String serial,
        {String estado = 'operativo',
        String condicion = 'nuevo',
        bool disponible = false}) =>
    {
      'id': serial,
      'referencia_id': 'r1',
      'serial': serial,
      'condicion': condicion,
      'estado': estado,
      'bodega_id': 'b1',
      'bodegas': {'nombre': 'Bodega RPCI'},
      'valor_actual': 1000000,
      'creado_en': '2026-09-01T12:00:00Z',
      'disponible': disponible,
    };

final _disponible = _fila('D1', disponible: true);
final _enTaller = _fila('T1', estado: 'mantenimiento_externo');
final _repuestos = _fila('R1', condicion: 'repuestos');
final _vendido = _fila('V1', estado: 'entregado');

Future<void> _montar(WidgetTester t, Widget w, {double escalaTexto = 1.0}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: _tema,
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(escalaTexto)),
      child: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('ResumenReferencia: las tres cuentas', () {
    ResumenReferencia r(int total, int disp, int? vend) =>
        ResumenReferencia.fromMap({
          'referencia_id': 'r1',
          'nombre': 'BOMBA DE DIAFRAGMA ELECTRICA',
          'total': total,
          'disponibles': disp,
          'vendidos': ?vend,
        });

    test('los vendidos ya NO cuentan como no disponibles', () {
      final x = r(6, 3, 2);
      expect(x.noDisponibles, 1);
      expect(x.disponibles + x.noDisponibles + x.vendidos, x.total);
    });

    test('la línea dice las tres, con singular y plural', () {
      expect(r(6, 3, 2).textoCuentas,
          '3 disponibles · 1 no disponible · 2 vendidas');
      expect(r(1, 0, 1).textoCuentas,
          '0 disponibles · 0 no disponibles · 1 vendida');
    });

    test('una respuesta sin "vendidos" (la base de antes) no rompe', () {
      final x = r(4, 1, null);
      expect(x.vendidos, 0);
      expect(x.noDisponibles, 3);
    });
  });

  group('FiltroEquipos: cada equipo cae en UNO solo', () {
    test('disponible, no disponible o vendido, nunca dos', () {
      for (final f in [_disponible, _enTaller, _repuestos, _vendido]) {
        final en = [
          FiltroEquipos.disponibles,
          FiltroEquipos.noDisponibles,
          FiltroEquipos.vendidos,
        ].where((x) => x.incluye(f));
        expect(en.length, 1, reason: '${f['serial']} cayó en $en');
      }
    });

    test('cada uno donde le toca', () {
      expect(FiltroEquipos.disponibles.incluye(_disponible), isTrue);
      expect(FiltroEquipos.noDisponibles.incluye(_enTaller), isTrue);
      expect(FiltroEquipos.noDisponibles.incluye(_repuestos), isTrue);
      expect(FiltroEquipos.vendidos.incluye(_vendido), isTrue);
      // El caso que motivó el cambio: un vendido NO es "no disponible".
      expect(FiltroEquipos.noDisponibles.incluye(_vendido), isFalse);
    });

    test('"Todas" trae todo', () {
      expect(
          [_disponible, _enTaller, _repuestos, _vendido]
              .every(FiltroEquipos.todas.incluye),
          isTrue);
    });
  });

  group('FiltrosEquipos (pantalla)', () {
    testWidgets('los cuatro filtros, y el tocado se avisa', (t) async {
      FiltroEquipos? elegido;
      await _montar(
          t,
          FiltrosEquipos(
              valor: FiltroEquipos.todas, onCambio: (f) => elegido = f));
      for (final f in FiltroEquipos.values) {
        expect(find.text(f.etiqueta), findsOneWidget);
      }
      await t.tap(find.text('Vendidas'));
      expect(elegido, FiltroEquipos.vendidos);
    });

    testWidgets('con las cuentas: Vendidas le QUITA a No disponibles',
        (t) async {
      // 6 unidades: 3 disponibles, 2 vendidas → 1 no disponible (antes, 3).
      final cuentas = ResumenReferencia.fromMap({
        'referencia_id': 'r1', 'nombre': 'BOMBA',
        'total': 6, 'disponibles': 3, 'vendidos': 2,
      });
      await _montar(
          t,
          FiltrosEquipos(
              valor: FiltroEquipos.todas, onCambio: (_) {}, cuentas: cuentas));
      expect(find.text('Todas (6)'), findsOneWidget);
      expect(find.text('Disponibles (3)'), findsOneWidget);
      expect(find.text('No disponibles (1)'), findsOneWidget);
      expect(find.text('Vendidas (2)'), findsOneWidget);
    });

    testWidgets('con Vendidos elegido, dice qué es un vendido', (t) async {
      await _montar(t,
          FiltrosEquipos(valor: FiltroEquipos.vendidos, onCambio: (_) {}));
      expect(find.textContaining('ya no son nuestras'), findsOneWidget);
    });

    testWidgets('todo lo que se toca mide 48 dp, tiene nombre y contraste',
        (t) async {
      final h = t.ensureSemantics();
      await _montar(t,
          FiltrosEquipos(valor: FiltroEquipos.vendidos, onCambio: (_) {}));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: los filtros bajan de línea',
        (t) async {
      await _montar(
          t,
          FiltrosEquipos(
              valor: FiltroEquipos.vendidos,
              onCambio: (_) {},
              cuentas: ResumenReferencia.fromMap({
                'referencia_id': 'r1', 'nombre': 'BOMBA',
                'total': 1234, 'disponibles': 1000, 'vendidos': 200,
              })),
          escalaTexto: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  // La explicación de cada filtro: al MANTENER PRESIONADO en el celular (no
  // hay "pasar el mouse") o al pasar el mouse en el PC. Flota, y se va sola.
  group('explicación al mantener presionado', () {
    testWidgets('cada filtro tiene su explicación', (t) async {
      await _montar(t,
          FiltrosEquipos(valor: FiltroEquipos.todas, onCambio: (_) {}));
      for (final f in FiltroEquipos.values) {
        expect(find.byTooltip(f.explicacion), findsOneWidget,
            reason: f.etiqueta);
      }
    });

    testWidgets('aparece al mantener presionado, NO filtra, y se va sola',
        (t) async {
      FiltroEquipos? elegido;
      await _montar(
          t,
          FiltrosEquipos(
              valor: FiltroEquipos.todas, onCambio: (f) => elegido = f));
      await t.longPress(find.text('Vendidas'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(FiltroEquipos.vendidos.explicacion), findsOneWidget);
      // Mantener presionado es para leer, no para filtrar.
      expect(elegido, isNull);
      // Se va sola, sin tener que tocar nada.
      await t.pump(duracionAyudaEquipos + const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text(FiltroEquipos.vendidos.explicacion), findsNothing);
    });

    testWidgets('el ícono de estado de una unidad también explica', (t) async {
      await _montar(t,
          LineaUnidad(unidad: ActivoDisponibilidad.fromMap(_vendido), onTap: () {}));
      await t.longPress(find.byIcon(Icons.sell_outlined));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(FiltroEquipos.vendidos.unidad), findsOneWidget);
    });

    test('el ícono explica el MISMO grupo en que cae la unidad', () {
      for (final f in [_disponible, _enTaller, _repuestos, _vendido]) {
        final d = ActivoDisponibilidad.fromMap(f);
        expect(d.categoria.incluye(f), isTrue, reason: '${f['serial']}');
      }
    });

    testWidgets('360 px con la letra al DOBLE: la explicación no desborda',
        (t) async {
      await _montar(
          t, FiltrosEquipos(valor: FiltroEquipos.todas, onCambio: (_) {}),
          escalaTexto: 2.0);
      await t.longPress(find.textContaining('No disponibles'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(FiltroEquipos.noDisponibles.explicacion), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('con la explicación abierta: 48 dp, nombres y contraste',
        (t) async {
      final h = t.ensureSemantics();
      await _montar(t,
          FiltrosEquipos(valor: FiltroEquipos.todas, onCambio: (_) {}));
      await t.longPress(find.text('Disponibles'));
      await t.pump(const Duration(milliseconds: 300));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });
  });

  group('LineaUnidad', () {
    testWidgets('un vendido lo DICE con texto y no muestra bodega', (t) async {
      await _montar(
          t, LineaUnidad(unidad: ActivoDisponibilidad.fromMap(_vendido)));
      expect(find.text('Vendido · Nuevo'), findsOneWidget);
      expect(find.textContaining('Bodega RPCI'), findsNothing);
      expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
    });

    testWidgets('uno disponible sí dice en qué bodega está', (t) async {
      await _montar(
          t, LineaUnidad(unidad: ActivoDisponibilidad.fromMap(_disponible)));
      expect(find.text('Operativo · Nuevo · Bodega RPCI'), findsOneWidget);
    });

    testWidgets('contraste y 360 px con la letra al doble', (t) async {
      final h = t.ensureSemantics();
      await _montar(
          t,
          Column(children: [
            LineaUnidad(unidad: ActivoDisponibilidad.fromMap(_vendido), onTap: () {}),
            LineaUnidad(unidad: ActivoDisponibilidad.fromMap(_enTaller), onTap: () {}),
          ]),
          escalaTexto: 2.0);
      expect(t.takeException(), isNull);
      await expectLater(t, meetsGuideline(textContrastGuideline));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      h.dispose();
    });
  });
}
