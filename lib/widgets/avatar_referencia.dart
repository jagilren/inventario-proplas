import 'package:flutter/material.dart';
import '../util/import_archivo.dart' show normalizarTexto;

/// ADORNO de las listas "Por referencia" y "Disponibles" de Equipos
/// (2026-09-11): un círculo de color con un ícono según el tipo de equipo, o
/// su inicial.
///
/// Es solo visual y se puede QUITAR sin tocar nada más:
/// - apagarlo en las dos listas: poner [mostrarAvatarReferencias] en false;
/// - borrarlo del todo: este archivo y sus dos usos en
///   `lib/screens/equipos_home_page.dart` (el `leading:` de cada lista).
///
/// No consulta la base: sale del NOMBRE de la referencia, que la lista ya
/// tiene. Por eso adivina por palabras ("bomba", "kit"…); si no reconoce el
/// tipo, pone la inicial.
const bool mostrarAvatarReferencias = true;

/// Tipos que se reconocen por palabras del nombre, en orden: gana el primero
/// que aparezca en la lista (un "KIT … de bomba" es un kit). Colores
/// oscuros: el ícono y la letra van en blanco, y con uno claro no se leerían
/// al sol de una bodega (lo mide la prueba de contraste).
const _tipos = <(List<String>, IconData, Color)>[
  (['kit'], Icons.inventory_2_outlined, Color(0xFF6A1B9A)),
  (['bomba', 'dosificadora'], Icons.water_drop_outlined, Color(0xFF1565C0)),
  (['motor'], Icons.settings_outlined, Color(0xFF37474F)),
  (['compresor', 'blower', 'soplador'], Icons.air, Color(0xFF00695C)),
  (['filtro', 'prensa'], Icons.filter_alt_outlined, Color(0xFF2E7D32)),
  (['valvula'], Icons.plumbing, Color(0xFFBF360C)),
  (['tanque', 'tolva'], Icons.propane_tank_outlined, Color(0xFF4E342E)),
  (['centrifuga', 'decanter', 'agitador', 'mezclador'], Icons.cyclone,
      Color(0xFFAD1457)),
  (['tablero', 'variador', 'sensor', 'medidor', 'controlador'],
      Icons.electrical_services, Color(0xFF283593)),
];

/// Para las que no se reconocen: el color sale del nombre, así cada
/// referencia tiene siempre el mismo.
const paletaAvatarReferencia = <Color>[
  Color(0xFF00695C), Color(0xFF1565C0), Color(0xFF6A1B9A),
  Color(0xFFAD1457), Color(0xFF2E7D32), Color(0xFF4E342E),
  Color(0xFFBF360C), Color(0xFF283593), Color(0xFF37474F),
];

/// Cómo se ve una referencia: ícono (o null, y entonces la inicial) y color.
({IconData? icono, Color color, String inicial}) aspectoReferencia(
    String nombre) {
  final palabras = normalizarTexto(nombre).split(' ');
  for (final (claves, icono, color) in _tipos) {
    if (palabras.any((p) => claves.any(p.startsWith))) {
      return (icono: icono, color: color, inicial: '');
    }
  }
  // La primera LETRA: "(97721138) Bomba…" no debe dar "(".
  final letra = RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').firstMatch(nombre)?.group(0);
  // Suma de los caracteres y no hashCode: hashCode puede cambiar entre la
  // web y el celular, y el color de una referencia tiene que ser el mismo.
  final suma = normalizarTexto(nombre).codeUnits.fold<int>(0, (a, c) => a + c);
  return (
    icono: null,
    color: paletaAvatarReferencia[suma % paletaAvatarReferencia.length],
    inicial: (letra ?? '#').toUpperCase(),
  );
}

class AvatarReferencia extends StatelessWidget {
  final String nombre;
  const AvatarReferencia({super.key, required this.nombre});

  @override
  Widget build(BuildContext context) {
    final a = aspectoReferencia(nombre);
    // Decorativo: el nombre ya está escrito al lado, y el lector de
    // pantalla no tiene por qué decir "B" o "gota" antes de él.
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: 20,
        backgroundColor: a.color,
        child: a.icono != null
            ? Icon(a.icono, color: Colors.white, size: 22)
            : Text(
                a.inicial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
