import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/widgets/avatar_referencia.dart';

// El adorno de la lista "Por referencia": un ícono según el tipo de equipo,
// o la inicial. Sale del nombre, sin consultar la base.

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
}

void main() {
  test('las referencias de hoy: bombas y kits con su ícono', () {
    expect(
        aspectoReferencia('(97721138) Bomba dosificadora DDE 15 -4 B-PVC')
            .icono,
        Icons.water_drop_outlined);
    expect(aspectoReferencia('BOMBA DE DIAFRAGMA ELECTRICA').icono,
        Icons.water_drop_outlined);
    expect(
        aspectoReferencia('KIT 1 . REPUESTOS Screw Type Sludge Dehydrator')
            .icono,
        Icons.inventory_2_outlined);
    expect(aspectoReferencia('KIT DE PRUEBA01').icono,
        Icons.inventory_2_outlined);
  });

  test('sin tildes ni mayúsculas, y el plural también', () {
    expect(aspectoReferencia('Válvula mariposa 4"').icono, Icons.plumbing);
    expect(aspectoReferencia('CENTRÍFUGA DECANTER').icono, Icons.cyclone);
    expect(aspectoReferencia('Bombas de vacío').icono,
        Icons.water_drop_outlined);
  });

  test('un kit de bomba es un kit: gana el primero de la lista', () {
    expect(aspectoReferencia('Kit de sellos para bomba').icono,
        Icons.inventory_2_outlined);
  });

  test('si no reconoce el tipo: la primera LETRA, siempre del mismo color', () {
    final a = aspectoReferencia('(123) Escalera de aluminio');
    expect(a.icono, isNull);
    expect(a.inicial, 'E');
    expect(aspectoReferencia('(123) Escalera de aluminio').color, a.color);
  });

  testWidgets('la letra blanca se lee sobre TODOS los colores', (t) async {
    final h = t.ensureSemantics();
    // Un avatar con inicial por cada color de la paleta: la prueba de
    // contraste de Flutter mide cada uno.
    final nombres = <String>[];
    for (var i = 0; nombres.length < paletaAvatarReferencia.length; i++) {
      final n = 'Equipo raro $i';
      final c = aspectoReferencia(n).color;
      if (!nombres.map((x) => aspectoReferencia(x).color).contains(c)) {
        nombres.add(n);
      }
    }
    await _montar(
        t,
        Wrap(children: [
          for (final n in nombres)
            // Sin ExcludeSemantics para que la prueba vea la letra.
            CircleAvatar(
              radius: 20,
              backgroundColor: aspectoReferencia(n).color,
              child: Text(aspectoReferencia(n).inicial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ),
        ]));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    h.dispose();
  });

  testWidgets('es decorativo: el lector de pantalla no lo lee', (t) async {
    final h = t.ensureSemantics();
    // Como en la app: la fila se puede tocar, y el lector la lee entera.
    await _montar(
        t,
        ListTile(
            leading: const AvatarReferencia(nombre: 'Escalera de aluminio'),
            title: const Text('Escalera de aluminio'),
            onTap: () {}));
    // Lo que se oye es SOLO el nombre, no "E, Escalera de aluminio".
    expect(t.getSemantics(find.byType(ListTile)).label,
        'Escalera de aluminio');
    h.dispose();
  });

  testWidgets('360 px con la letra al DOBLE: la fila no se desborda',
      (t) async {
    await _montar(
        t,
        const ListTile(
          leading: AvatarReferencia(nombre: 'BOMBA DE DIAFRAGMA ELECTRICA'),
          title: Text('BOMBA DE DIAFRAGMA ELECTRICA · GRUNDFOS'),
          subtitle: Text('3 disponibles · 1 no disponible · 2 vendidas'),
          trailing: Text('6'),
        ),
        escala: 2.0);
    expect(t.takeException(), isNull);
  });

  testWidgets('en "Disponibles": fila de una unidad, sin nombre de referencia',
      (t) async {
    // Sin señal y con el caché viejo podría llegar sin nombre: no debe
    // romper ni dejar el círculo vacío.
    expect(aspectoReferencia('').inicial, '#');
    await _montar(
        t,
        const ListTile(
          leading: AvatarReferencia(nombre: ''),
          title: Text('A9772113810000036'),
          subtitle: Text('BOMBA DE DIAFRAGMA ELECTRICA · Bodega RPCI'),
          trailing: Text('\$ 1.540.000'),
        ),
        escala: 2.0);
    expect(t.takeException(), isNull);
  });
}
