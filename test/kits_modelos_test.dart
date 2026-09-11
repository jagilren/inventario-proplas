import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/activos_service.dart';

// Pruebas de la Fase 2 de Referencias KITZABLES (docs/plan-kits-equipos.md):
// los modelos y la traducción de errores. Sin red: todo lo que depende de la
// base se probó en la Fase 1 (schema_v64, 24 casos en rollback).

void main() {
  group('TipoMovComponente: la app y la base hablan de los mismos tipos', () {
    test('coinciden EXACTAMENTE con el check de la base (schema_v64)', () {
      // Si alguien agrega un tipo en la base y no aquí (o al revés), esta
      // prueba lo ataja antes de publicar: es la lista del constraint
      // activo_componente_movimientos_tipo_check.
      const enLaBase = {
        'alta', 'aumento', 'disminucion',
        'salida_venta', 'salida_garantia', 'baja_dano', 'anulacion',
      };
      expect(TipoMovComponente.values.map((t) => t.valor).toSet(), enLaBase);
    });

    test('el usuario no elige a mano ni el alta ni la anulación', () {
      expect(TipoMovComponente.elegibles,
          isNot(contains(TipoMovComponente.alta)));
      expect(TipoMovComponente.elegibles,
          isNot(contains(TipoMovComponente.anulacion)));
      expect(TipoMovComponente.elegibles, hasLength(5));
    });

    test('solo venta y garantía exigen tercero', () {
      final conTercero = TipoMovComponente.values
          .where((t) => t.pideTercero)
          .toSet();
      expect(conTercero, {
        TipoMovComponente.salidaVenta,
        TipoMovComponente.salidaGarantia,
      });
    });

    test('suman solo el alta y el aumento', () {
      final suman = TipoMovComponente.values.where((t) => t.suma).toSet();
      expect(suman, {TipoMovComponente.alta, TipoMovComponente.aumento});
    });

    test('desde() reconoce todos los tipos y no revienta con uno nuevo', () {
      for (final t in TipoMovComponente.values) {
        expect(TipoMovComponente.desde(t.valor), t);
      }
      expect(TipoMovComponente.desde('tipo_que_no_existe'), isNull);
    });

    test('las etiquetas son palabras completas, sin abreviaturas', () {
      for (final t in TipoMovComponente.values) {
        expect(t.accion.trim(), isNotEmpty);
        expect(t.historial.trim(), isNotEmpty);
        expect(t.accion, isNot(contains('.')),
            reason: '"${t.accion}" parece abreviada');
      }
    });
  });

  group('ActivoReferencia y Activo: saben si son kit', () {
    test('es_kit viene de la base', () {
      final r = ActivoReferencia.fromMap({
        'id': 'r1', 'nombre': 'KIT FILTROS 636', 'es_kit': true,
      });
      expect(r.esKit, isTrue);
    });

    test('sin la columna (caché viejo) se asume que NO es kit', () {
      final r = ActivoReferencia.fromMap({'id': 'r1', 'nombre': 'BOMBA'});
      expect(r.esKit, isFalse);
      expect(r.activo, isTrue);
    });

    Map<String, dynamic> activo({Object? esKit}) => {
          'id': 'a1',
          'referencia_id': 'r1',
          'activo_referencias': {
            'nombre': 'KIT FILTROS 636',
            'marca': null,
            'es_kit': ?esKit,
          },
          'serial': 'KIT-1',
          'condicion': 'nuevo',
          'estado': 'operativo',
          'bodega_id': 'b1',
          'valor_nuevo': 1540000,
          'porcentaje_valor': 70,
          'valor_actual': 1078000.0,
          'creado_en': '2026-09-10T18:00:00Z',
        };

    test('el equipo sabe que su referencia es un kit', () {
      expect(Activo.fromMap(activo(esKit: true)).referenciaEsKit, isTrue);
      expect(Activo.fromMap(activo(esKit: false)).referenciaEsKit, isFalse);
    });

    test('sin es_kit en la respuesta (consulta vieja) no es kit', () {
      expect(Activo.fromMap(activo()).referenciaEsKit, isFalse);
    });
  });

  group('ActivoComponente', () {
    test('lee números enteros y decimales como llegan de PostgREST', () {
      final c = ActivoComponente.fromMap({
        'id': 'c1', 'activo_id': 'a1', 'nombre': 'Tela filtros de los medios',
        'valor_unitario': 45000, 'cantidad': 24, 'subtotal': 1080000.00,
        'orden': 2,
      });
      expect(c.cantidad, 24);
      expect(c.subtotal, 1080000);
      expect(c.agotado, isFalse);
    });

    test('el ejemplo del usuario: al 70% la tela de los medios vale 756.000',
        () {
      final c = ActivoComponente.fromMap({
        'id': 'c1', 'activo_id': 'a1', 'nombre': 'Tela filtros de los medios',
        'valor_unitario': 45000, 'cantidad': 24, 'subtotal': 1080000,
      });
      expect(c.subtotalAl(70), 756000);
      expect(c.subtotalAl(100), 1080000);
    });

    test('un componente en cero está agotado, no desaparece', () {
      final c = ActivoComponente.fromMap({
        'id': 'c1', 'activo_id': 'a1', 'nombre': 'Guías',
        'valor_unitario': 15000, 'cantidad': 0, 'subtotal': 0,
      });
      expect(c.agotado, isTrue);
      expect(c.orden, 0);
    });
  });

  group('MovimientoComponente', () {
    Map<String, dynamic> mov({
      String tipo = 'baja_dano',
      int signo = -1,
      num cantidad = 3,
      String? tercero,
      String? anula,
    }) =>
        {
          'id': 'm1',
          'componente_id': 'c1',
          'tipo': tipo,
          'signo': signo,
          'cantidad': cantidad,
          'valor_unitario': 45000,
          'anula_movimiento_id': anula,
          'observacion': null,
          'usuario_email': 'kuribe@rpci.com.co',
          'fecha': '2026-09-10T18:12:00Z',
          'activo_terceros': tercero == null ? null : {'nombre': tercero},
        };

    test('lee el movimiento y su tercero', () {
      final m = MovimientoComponente.fromMap(
          mov(tipo: 'salida_venta', cantidad: 1, tercero: 'TALLER X'));
      expect(m.tipo, TipoMovComponente.salidaVenta);
      expect(m.etiqueta, 'Venta');
      expect(m.terceroNombre, 'TALLER X');
      expect(m.cantidadConSigno, -1);
      expect(m.esAnulacion, isFalse);
    });

    test('la cantidad se ve con signo tipográfico', () {
      expect(MovimientoComponente.fromMap(mov()).textoCantidad, '−3');
      expect(
          MovimientoComponente.fromMap(mov(tipo: 'aumento', signo: 1, cantidad: 2))
              .textoCantidad,
          '+2');
      // Un decimal no se trunca.
      expect(MovimientoComponente.fromMap(mov(cantidad: 2.5)).textoCantidad,
          '−2.5');
    });

    test('para el lector de pantalla va en palabras, sin signos', () {
      final dano = MovimientoComponente.fromMap(mov());
      expect(dano.descripcionAccesible, 'Daño, salieron 3');
      expect(dano.descripcionAccesible, isNot(contains('−')));

      final venta = MovimientoComponente.fromMap(
          mov(tipo: 'salida_venta', cantidad: 1, tercero: 'TALLER X'));
      expect(venta.descripcionAccesible, 'Venta, salieron 1, a TALLER X');
    });

    test('una anulación lo sabe, y toma el signo que le puso la base', () {
      final a = MovimientoComponente.fromMap(
          mov(tipo: 'anulacion', signo: 1, anula: 'm0'));
      expect(a.esAnulacion, isTrue);
      expect(a.etiqueta, 'Anulación');
      expect(a.cantidadConSigno, 3);
    });

    test('un tipo que la app no conoce se muestra crudo, sin reventar', () {
      final m = MovimientoComponente.fromMap(mov(tipo: 'tipo_futuro'));
      expect(m.tipo, isNull);
      expect(m.etiqueta, 'tipo_futuro');
    });
  });

  group('ComponentePlantilla', () {
    test('el kit del usuario suma 1.540.000', () {
      final filas = [
        {'nombre': 'Tela filtros de los extremos', 'cantidad': 2,
         'valor_unitario': 50000, 'orden': 1, 'desde_serial': 'KIT-7'},
        {'nombre': 'Tela filtros de los medios', 'cantidad': 24,
         'valor_unitario': 45000, 'orden': 2, 'desde_serial': 'KIT-7'},
        {'nombre': 'Guias filtro medios', 'cantidad': 24,
         'valor_unitario': 15000, 'orden': 3, 'desde_serial': 'KIT-7'},
      ].map(ComponentePlantilla.fromMap).toList();
      expect(filas.fold<num>(0, (s, c) => s + c.subtotal), 1540000);
      expect(filas.first.desdeSerial, 'KIT-7');
    });
  });

  group('Composición de un kit nuevo (Fase 4)', () {
    ComponentePlantilla c(String nombre,
            {num cantidad = 1, num valor = 1000}) =>
        ComponentePlantilla(
            nombre: nombre, cantidad: cantidad, valorUnitario: valor);

    test('claveComponente compara IGUAL que el índice único de la base', () {
      // upper(regexp_replace(btrim(nombre), '\s+', ' ', 'g'))
      expect(claveComponente('  tela   MEDIOS '), 'TELA MEDIOS');
      expect(claveComponente('Tela medios'), claveComponente('TELA  MEDIOS'));
      // La base NO quita tildes: para ella son distintos, y la app no puede
      // decir "repetido" donde la base diría que no.
      expect(claveComponente('Guías'), isNot(claveComponente('Guias')));
    });

    test('la composición del usuario está bien', () {
      expect(
          validarComposicionKit([
            c('Tela filtros de los extremos', cantidad: 2, valor: 50000),
            c('Tela filtros de los medios', cantidad: 24, valor: 45000),
            c('Guias filtro medios', cantidad: 24, valor: 15000),
          ]),
          isNull);
    });

    test('un kit sin componentes no se guarda: valdría \$0', () {
      expect(validarComposicionKit([]), contains('al menos un componente'));
    });

    test('dice CUÁL está mal', () {
      expect(validarComposicionKit([c('  ')]), 'Hay un componente sin nombre.');
      expect(validarComposicionKit([c('Guías', cantidad: 0)]),
          contains('"Guías"'));
      expect(validarComposicionKit([c('Tela', valor: -1)]), contains('"Tela"'));
    });

    test('un repetido escrito distinto también es repetido', () {
      expect(validarComposicionKit([c('Tela medios'), c('  tela   MEDIOS ')]),
          'El componente "tela   MEDIOS" está repetido.');
    });

    test('con tilde y sin tilde NO son repetidos (igual que en la base)', () {
      expect(validarComposicionKit([c('Guías'), c('Guias')]), isNull);
    });
  });

  group('Errores: el usuario ve un mensaje, no jerga de Postgres', () {
    test('las reglas de la base ya vienen en español: pasan tal cual', () {
      expect(
          mensajeDeErrorEquipos(
              'P0001', 'No hay suficientes "Guías": quedarían -2'),
          'No hay suficientes "Guías": quedarían -2');
    });

    test('nombre de componente repetido', () {
      expect(
          mensajeDeErrorEquipos('23505',
              'duplicate key value violates unique constraint "activo_componentes_uniq"'),
          'Este kit ya tiene un componente con ese nombre.');
    });

    test('anular dos veces (carrera de dos toques que ataja el índice)', () {
      expect(
          mensajeDeErrorEquipos('23505',
              'duplicate key value violates unique constraint "activo_comp_mov_anula_uniq"'),
          'Este movimiento ya fue anulado.');
    });

    test('vender sin tercero, si llegara hasta la constraint', () {
      expect(
          mensajeDeErrorEquipos('23514',
              'new row violates check constraint "activo_comp_mov_tercero_check"'),
          contains('decir a quién'));
    });

    test('sin permiso', () {
      expect(mensajeDeErrorEquipos('42501', 'permission denied'),
          'No tienes permiso para hacer esto.');
    });

    test('ningún mensaje traducido deja jerga a la vista', () {
      for (final (codigo, texto) in [
        ('23505', 'duplicate key value violates unique constraint "x"'),
        ('23514', 'new row violates check constraint "y"'),
        ('42501', 'permission denied for table z'),
      ]) {
        final m = mensajeDeErrorEquipos(codigo, texto);
        expect(m, isNot(contains('constraint')));
        expect(m, isNot(contains('duplicate')));
        expect(m, isNot(contains('permission')));
      }
    });

    test('ErrorEquipos se imprime solo con su mensaje', () {
      const e = ErrorEquipos('Este movimiento ya fue anulado.');
      // Así lo muestran las pantallas: 'No se pudo guardar: $e'.
      expect('No se pudo guardar: $e',
          'No se pudo guardar: Este movimiento ya fue anulado.');
    });
  });

  // schema_v67: la novedad de un componente sale en el listado de
  // OBSERVACIONES del equipo, con fecha, usuario, componente, movimiento,
  // cantidades y motivo. La base entrega los datos crudos; la app redacta.
  group('ActivoObservacion de un componente (schema_v67)', () {
    Map<String, dynamic> fila({
      String tipo = 'disminucion',
      int signo = -1,
      num cantidad = 2,
      num saldo = 22,
      String? tercero,
      bool anulado = false,
      String texto = 'Se rompieron al lavarlas',
    }) =>
        {
          'id': 'm1',
          'fecha': '2026-09-10T18:12:00Z',
          'texto': texto,
          'origen': 'componente',
          'contexto': null,
          'usuario_email': 'kuribe@rpci.com.co',
          'editada': false,
          'comp_nombre': 'Tela Filtro Mesh 100 Medios',
          'comp_tipo': tipo,
          'comp_signo': signo,
          'comp_cantidad': cantidad,
          'comp_saldo': saldo,
          'comp_tercero': tercero,
          'comp_anulado': anulado,
        };

    test('el caso del usuario: 24, se retiran 2, quedan 22', () {
      final o = ActivoObservacion.fromMap(fila());
      expect(o.esDeComponente, isTrue);
      expect(o.etiquetaOrigen, 'Componente del kit');
      expect(o.compNombre, 'Tela Filtro Mesh 100 Medios');
      expect(o.movimientoComponente, 'Se retiró: salieron 2 · quedan 22');
      expect(o.usuarioEmail, 'kuribe@rpci.com.co');
      expect(o.texto, 'Se rompieron al lavarlas');
    });

    test('una adición dice "entraron"', () {
      final o = ActivoObservacion.fromMap(
          fila(tipo: 'aumento', signo: 1, cantidad: 4, saldo: 26));
      expect(o.movimientoComponente, 'Se agregó: entraron 4 · quedan 26');
    });

    test('una venta dice a quién', () {
      final o = ActivoObservacion.fromMap(fila(
          tipo: 'salida_venta', cantidad: 1, saldo: 21, tercero: 'TINTEXA'));
      expect(o.movimientoComponente, 'Venta: salieron 1 a TINTEXA · quedan 21');
    });

    test('cantidades con decimales van con coma y sin ".0"', () {
      final o = ActivoObservacion.fromMap(
          fila(cantidad: 2.5, saldo: 21.0));
      expect(o.movimientoComponente, 'Se retiró: salieron 2,5 · quedan 21');
    });

    test('el lector de pantalla oye todo en una frase, con lo anulado', () {
      final o = ActivoObservacion.fromMap(fila(anulado: true));
      expect(
          o.descripcionAccesible,
          'Tela Filtro Mesh 100 Medios. Se retiró: salieron 2 · quedan 22. '
          'Anulado después. Motivo: Se rompieron al lavarlas');
    });

    test('las demás observaciones no cambian', () {
      final o = ActivoObservacion.fromMap({
        'id': 'o1',
        'fecha': '2026-09-10T18:12:00Z',
        'texto': 'Llegó con un golpe',
        'origen': 'manual',
        'contexto': null,
        'usuario_email': 'kuribe@rpci.com.co',
        'editada': false,
      });
      expect(o.esDeComponente, isFalse);
      expect(o.movimientoComponente, isNull);
      expect(o.compAnulado, isFalse);
      expect(o.descripcionAccesible, 'Llegó con un golpe');
      expect(o.etiquetaOrigen, 'Nota');
    });
  });

  group('El motivo es obligatorio (schema_v67), antes de ir a la base', () {
    test('registrar un movimiento sin motivo', () async {
      for (final motivo in [null, '', '   ']) {
        await expectLater(
            ActivosService.moverComponente(
                componenteId: 'c1',
                tipo: TipoMovComponente.disminucion,
                cantidad: 2,
                observacion: motivo),
            throwsA(isA<ErrorEquipos>()
                .having((e) => '$e', 'mensaje', contains('motivo'))));
      }
    });

    test('anular sin motivo', () async {
      final original = MovimientoComponente.fromMap({
        'id': 'm1',
        'componente_id': 'c1',
        'tipo': 'baja_dano',
        'signo': -1,
        'cantidad': 2,
        'valor_unitario': 45000,
        'anula_movimiento_id': null,
        'observacion': 'Se rompieron',
        'usuario_email': 'kuribe@rpci.com.co',
        'fecha': '2026-09-10T18:12:00Z',
        'activo_terceros': null,
      });
      await expectLater(
          ActivosService.anularMovimientoComponente(original, observacion: ' '),
          throwsA(isA<ErrorEquipos>()
              .having((e) => '$e', 'mensaje', contains('motivo'))));
    });
  });
}
