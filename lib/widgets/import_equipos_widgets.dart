import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../activos_service.dart';
import '../util/import_equipos.dart';
import 'avatar_referencia.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Un equipo del archivo en la revisión de la carga masiva: qué es, dónde
/// queda y cuánto vale, y sus problemas ESCRITOS en la fila (no solo un
/// color): así se corrige el Excel sin adivinar.
class TarjetaEquipoImport extends StatelessWidget {
  final EquipoImport equipo;
  const TarjetaEquipoImport({super.key, required this.equipo});

  @override
  Widget build(BuildContext context) {
    final e = equipo;
    final esquema = Theme.of(context).colorScheme;
    final ref = e.referencia?.etiqueta ?? e.referenciaNueva?.etiqueta ??
        (e.nombreReferencia.isEmpty ? '(sin referencia)' : e.nombreReferencia);
    final detalle = [
      if (e.bodega != null) e.bodega!.nombre,
      if (e.condicion != null) Activo.etiquetaCondicion(e.condicion!),
      if (e.esKit)
        'Kit · ${e.componentes.length} '
            'componente${e.componentes.length == 1 ? '' : 's'}',
      if (e.listo || e.valorCalculado > 0) _money.format(e.valorCalculado),
      if (e.porcentaje != 100) 'al ${e.porcentaje} %',
    ].join(' · ');
    return ListTile(
      leading: mostrarAvatarReferencias
          ? AvatarReferencia(nombre: e.nombreReferencia)
          : null,
      title: Row(
        children: [
          Flexible(
            child: Text(e.serial.isEmpty ? '(sin serial)' : e.serial,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text('fila ${e.fila}',
              style: TextStyle(
                  fontSize: 12, color: esquema.onSurfaceVariant)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: ref),
            if (e.referenciaNueva != null)
              TextSpan(
                  text: ' · NUEVA',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: esquema.tertiary)),
          ])),
          if (detalle.isNotEmpty) Text(detalle),
          for (final m in e.errores)
            Text('✗ $m',
                style: TextStyle(color: esquema.error, fontSize: 13)),
          for (final m in e.avisos)
            Text('Aviso: $m',
                style: TextStyle(color: esquema.tertiary, fontSize: 13)),
        ],
      ),
      isThreeLine: true,
    );
  }
}

/// Las referencias que la carga va a CREAR, con las del catálogo a las que
/// se parecen. Se muestra ANTES de cargar: crear un duplicado es fácil y
/// deshacerlo no.
class PanelReferenciasNuevas extends StatelessWidget {
  final List<ReferenciaNuevaImport> nuevas;
  const PanelReferenciasNuevas({super.key, required this.nuevas});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final n = nuevas.length;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(Icons.fiber_new_outlined, color: esquema.tertiary),
        title: Text('Se crearán $n referencia${n == 1 ? '' : 's'} nueva'
            '${n == 1 ? '' : 's'}'),
        subtitle: const Text('Tócalo para ver cuáles y a qué se parecen'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in nuevas)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${r.etiqueta}${r.esKit ? ' (kit)' : ''} · '
                      '${r.equipos} equipo${r.equipos == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (r.parecidas.isNotEmpty)
                    Text(
                      'Se parece a: '
                      '${r.parecidas.map((p) => p.etiqueta).join(' / ')}. '
                      'Si es la misma, corrige el nombre en el archivo.',
                      style: TextStyle(fontSize: 13, color: esquema.tertiary),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
