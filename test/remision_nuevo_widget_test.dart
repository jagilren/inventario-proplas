import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/data.dart';
import 'package:mi_app/util/import_archivo.dart';
import 'package:mi_app/util/plantilla_import.dart';
import 'package:mi_app/widgets/remision_nuevo.dart';

// Las dos hojas de los artículos NUEVOS en la devolución
// (docs/plan-remision-elementos-nuevos.md): la del ingeniero en la remisión
// y la de la bodega en Devoluciones. Accesibilidad medida con las pruebas de
// Flutter (48 dp, nombre para el lector de pantalla, contraste) y 360 px con
// la letra al doble, como las de los kits.

final _tema = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
  useMaterial3: true,
);

Elemento _e(String id, String nombre, {num costo = 180000}) =>
    Elemento.fromMap({'id': id, 'nombre': nombre, 'costo_promedio': costo});

final _catalogo = EmparejadorCatalogo([
  _e('a', 'Valvula mariposa 4" wafer'),
  _e('b', 'Tubo PVC 2"', costo: 12500),
]);

/// Abre [hoja] en una hoja inferior de un celular de 360 px y guarda lo
/// que devuelve en [resultado].
Future<void> _abrir(WidgetTester t, Widget hoja,
    {double escalaTexto = 1.0, required void Function(Object?) resultado}) async {
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
            onPressed: () async => resultado(await showModalBottomSheet<Object>(
                context: ctx, isScrollControlled: true, builder: (_) => hoja)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

void main() {
  group('HojaElementoNuevo (el ingeniero, en la remisión)', () {
    late Object? devuelto;
    late bool cerro;
    Future<void> abrir(WidgetTester t,
        {String nombre = '', Set<String> enLista = const {},
        EmparejadorCatalogo? catalogo, double escalaTexto = 1.0}) {
      devuelto = null;
      cerro = false;
      return _abrir(
          t,
          HojaElementoNuevo(
              nombreInicial: nombre,
              catalogo: catalogo ?? _catalogo,
              nuevosEnLista: enLista),
          escalaTexto: escalaTexto,
          resultado: (r) {
            devuelto = r;
            cerro = true;
          });
    }

    Future<void> llenar(WidgetTester t,
        {String cant = '2', String costo = '185.000'}) async {
      await t.tap(find.text('UND'));
      await t.enterText(find.widgetWithText(TextField, 'Cantidad *'), cant);
      await t.enterText(
          find.widgetWithText(TextField, 'Costo estimado por unidad *'), costo);
      await t.pump();
    }

    Future<void> agregar(WidgetTester t) async {
      await t.ensureVisible(
          find.widgetWithText(FilledButton, 'Agregar a la remisión'));
      await t.tap(find.widgetWithText(FilledButton, 'Agregar a la remisión'));
      await t.pumpAndSettle();
    }

    testWidgets('completo, devuelve la línea nueva con el costo en pesos',
        (t) async {
      await abrir(t, nombre: 'Filtro de canasta 2"');
      await llenar(t);
      // Cómo quedó entendido: "185.000" son ciento ochenta y cinco mil.
      expect(find.textContaining('185.000'), findsWidgets);
      await agregar(t);
      expect(cerro, isTrue);
      final l = devuelto as LineaDevolucion;
      expect(l.esNueva, isTrue);
      expect(l.nombre, 'Filtro de canasta 2"');
      expect(l.unidad, 'UND');
      expect(l.cantidad, 2);
      expect(l.costoEstimado, 185000);
    });

    testWidgets('sin datos no agrega: dice qué falta en cada campo',
        (t) async {
      await abrir(t, nombre: 'Filtro de canasta 2"');
      await agregar(t);
      expect(cerro, isFalse);
      expect(find.text('Elige la unidad'), findsOneWidget);
      expect(find.text('Escribe cuántos'), findsOneWidget);
      expect(find.text('Escribe cuánto vale UNA unidad'), findsOneWidget);
    });

    testWidgets('muestra los parecidos, y tocar uno devuelve ESE artículo',
        (t) async {
      await abrir(t, nombre: 'Válvula mariposa 4 pulgadas wafer');
      expect(find.text('¿Es alguno de estos?'), findsOneWidget);
      await t.tap(find.text('Valvula mariposa 4" wafer'));
      await t.pumpAndSettle();
      expect((devuelto as Elemento).id, 'a');
    });

    testWidgets('con el MISMO nombre de uno del catálogo no deja agregarlo',
        (t) async {
      // La base no deja crear dos con el mismo nombre: se ataja aquí.
      await abrir(t, nombre: 'VÁLVULA MARIPOSA 4" WAFER');
      expect(find.textContaining('Ya existe en el catálogo'), findsOneWidget);
      await llenar(t);
      await agregar(t);
      expect(cerro, isFalse);
    });

    testWidgets('repetido entre los nuevos de la misma remisión: lo dice',
        (t) async {
      await abrir(t,
          nombre: 'Filtro de canasta 2"',
          enLista: {normalizarTexto('filtro de canasta 2"')});
      expect(find.textContaining('Ya está en la remisión'), findsOneWidget);
    });

    testWidgets('sin catálogo (sin señal) lo dice y deja agregar igual',
        (t) async {
      devuelto = null;
      cerro = false;
      await _abrir(t, const HojaElementoNuevo(nombreInicial: 'Filtro'),
          resultado: (r) {
        devuelto = r;
        cerro = true;
      });
      expect(find.textContaining('Sin conexión no pude revisar'),
          findsOneWidget);
      await llenar(t);
      await agregar(t);
      expect(devuelto, isA<LineaDevolucion>());
    });

    testWidgets('todo lo que se toca mide 48 dp, tiene nombre y contraste',
        (t) async {
      final h = t.ensureSemantics();
      await abrir(t, nombre: 'Válvula mariposa 4 pulgadas wafer');
      await agregar(t); // con los errores a la vista
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await abrir(t,
          nombre: 'Válvula mariposa 4 pulgadas wafer', escalaTexto: 2.0);
      await agregar(t);
      expect(t.takeException(), isNull);
    });
  });

  group('HojaResolverNuevo (la bodega, en Devoluciones)', () {
    late Object? devuelto;
    Future<void> abrir(WidgetTester t,
        {bool puedeCrear = true, double escalaTexto = 1.0}) {
      devuelto = null;
      return _abrir(
          t,
          HojaResolverNuevo(
            propuesto: 'Válvula mariposa 4 pulgadas wafer',
            cantidad: 2,
            unidad: 'UND',
            costoEstimado: 185000,
            estimadoPor: 'ing.perez@rpci.com.co',
            parecidos: [_catalogo.catalogo.first],
            puedeCrear: puedeCrear,
          ),
          escalaTexto: escalaTexto,
          resultado: (r) => devuelto = r);
    }

    testWidgets('muestra lo que propuso el ingeniero', (t) async {
      await abrir(t);
      expect(find.text('"Válvula mariposa 4 pulgadas wafer"'), findsOneWidget);
      expect(find.textContaining('por ing.perez@rpci.com.co'), findsOneWidget);
      expect(find.textContaining('185.000'), findsOneWidget);
    });

    testWidgets('tocar un parecido lo devuelve', (t) async {
      await abrir(t);
      await t.tap(find.text('Valvula mariposa 4" wafer'));
      await t.pumpAndSettle();
      expect((devuelto as Elemento).id, 'a');
    });

    testWidgets('crear y dejar por fuera devuelven su acción', (t) async {
      await abrir(t);
      await t.tap(find.text('Crear en el catálogo'));
      await t.pumpAndSettle();
      expect(devuelto, AccionNuevo.crear);
      await abrir(t);
      await t.ensureVisible(find.text('Dejar por fuera de esta carga'));
      await t.tap(find.text('Dejar por fuera de esta carga'));
      await t.pumpAndSettle();
      expect(devuelto, AccionNuevo.quitar);
    });

    testWidgets('sin permiso de crear: el botón no sirve y DICE por qué',
        (t) async {
      await abrir(t, puedeCrear: false);
      final boton = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Crear en el catálogo'));
      expect(boton.onPressed, isNull);
      expect(find.textContaining('Solo un coordinador o un administrador'),
          findsOneWidget);
    });

    testWidgets('todo lo que se toca mide 48 dp, tiene nombre y contraste',
        (t) async {
      final h = t.ensureSemantics();
      await abrir(t, puedeCrear: false);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(t, meetsGuideline(textContrastGuideline));
      h.dispose();
    });

    testWidgets('360 px con la letra al DOBLE: nada se desborda', (t) async {
      await abrir(t, escalaTexto: 2.0);
      expect(t.takeException(), isNull);
    });
  });
}
