import 'package:flutter_test/flutter_test.dart';
import 'package:mi_app/reportes.dart';

// Informe "Composición de kits" (Fase 6, docs/plan-kits-equipos.md): que
// cuadre al peso con el ejemplo real y con el informe de valorización.

Map<String, dynamic> kit({
  String serial = 'KIT-1',
  String estado = 'operativo',
  bool refActiva = true,
  num pct = 70,
  num valorNuevo = 1540000,
  num valorActual = 1078000,
  List<Map<String, dynamic>> componentes = const [],
}) =>
    {
      'serial': serial,
      'estado': estado,
      'porcentaje_valor': pct,
      'valor_nuevo': valorNuevo,
      'valor_actual': valorActual,
      'activo_referencias': {
        'nombre': 'KIT FILTROS 636',
        'activo': refActiva,
        'es_kit': true,
      },
      'bodegas': {'nombre': 'Bodega RPCI'},
      'activo_componentes': componentes,
    };

const _delUsuario = [
  // Desordenados a propósito: el informe los ordena por `orden`.
  {'nombre': 'Guias filtro medios', 'cantidad': 24, 'valor_unitario': 15000,
   'subtotal': 360000, 'orden': 3},
  {'nombre': 'Tela filtros de los extremos', 'cantidad': 2,
   'valor_unitario': 50000, 'subtotal': 100000, 'orden': 1},
  {'nombre': 'Tela filtros de los medios', 'cantidad': 24,
   'valor_unitario': 45000, 'subtotal': 1080000, 'orden': 2},
];

void main() {
  test('el kit del usuario: filas por componente y total que cuadra', () {
    final f = filasComposicionKits([kit(componentes: _delUsuario)]);
    // Encabezado + 3 componentes + total del kit + total general.
    expect(f, hasLength(6));
    expect([for (final r in f.sublist(1, 4)) r[4]], [
      'Tela filtros de los extremos',
      'Tela filtros de los medios',
      'Guias filtro medios',
    ]);
    // Los subtotales a nuevo suman el valor a nuevo del kit…
    final aNuevo = f.sublist(1, 4).fold<num>(0, (s, r) => s + (r[7] as num));
    expect(aNuevo, 1540000);
    // …y los ponderados al 70% suman el valor actual: 1.078.000.
    final alPct = f.sublist(1, 4).fold<num>(0, (s, r) => s + (r[9] as num));
    expect(alPct, 1078000);
    // La fila del kit trae los valores de la BASE, no una suma de aquí.
    expect(f[4][4], 'TOTAL DEL KIT');
    expect(f[4][7], 1540000);
    expect(f[4][9], 1078000);
    expect(f.last[9], 1078000);
  });

  test('un kit sin componentes también sale, y dice que vale \$0', () {
    final f = filasComposicionKits(
        [kit(serial: 'KIT-VACIO', valorNuevo: 0, valorActual: 0)]);
    expect(f[1][4], contains('sin componentes'));
    expect(f[2][4], 'TOTAL DEL KIT');
  });

  test('entregado, de baja o de referencia retirada: sale pero NO suma', () {
    final f = filasComposicionKits([
      kit(serial: 'A', componentes: _delUsuario),
      kit(serial: 'B', estado: 'entregado', componentes: _delUsuario),
      kit(serial: 'C', estado: 'baja', componentes: _delUsuario),
      kit(serial: 'D', refActiva: false, componentes: _delUsuario),
    ]);
    // Solo el kit A cuenta: la misma regla de "Valorización de activos".
    expect(f.last[9], 1078000);
    final totalesKit = f.where((r) => r[4] == 'TOTAL DEL KIT').toList();
    expect([for (final r in totalesKit) r[10]], ['Sí', 'No', 'No', 'No']);
  });
}
