import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data.dart';
import '../util/carrito_salida.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// Una línea del carrito de "Armar salida": qué se despacha, cuánto, cuánto
/// vale y —cuando la base ya respondió— cuánto hay en la bodega.
///
/// El problema va ESCRITO en la línea, no solo en rojo: quien despacha tiene
/// que saber si el artículo no alcanza aquí pero sí hay en otra bodega.
class TarjetaLineaSalida extends StatelessWidget {
  final LineaSalida linea;
  /// Lo que respondió la base para esta línea (null si aún no se sabe).
  final ValidacionSalida? saldo;
  final VoidCallback? onEditar;
  final VoidCallback? onQuitar;

  const TarjetaLineaSalida({
    super.key,
    required this.linea,
    this.saldo,
    this.onEditar,
    this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final l = linea;
    final esquema = Theme.of(context).colorScheme;
    final problema = problemaLinea(l, saldo);
    return ListTile(
      title: Text(l.elemento.nombre),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${textoCantidadSalida(l.cantidad)} ${l.elemento.unidad} · '
              '${_money.format(l.valor)}'),
          if (problema != null)
            Text('✗ $problema',
                style: TextStyle(color: esquema.error, fontSize: 13))
          else if (saldo != null)
            Text('Hay ${textoCantidadSalida(saldo!.disponible)} '
                '${l.elemento.unidad} en la bodega',
                style: TextStyle(
                    color: esquema.onSurfaceVariant, fontSize: 12.5)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'Cambiar la cantidad de ${l.elemento.nombre}',
            onPressed: onEditar,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            tooltip: 'Quitar ${l.elemento.nombre}',
            onPressed: onQuitar,
          ),
        ],
      ),
      onTap: onEditar,
    );
  }
}

/// El pie del carrito: cuántos artículos y cuánto suma. Va fijo abajo,
/// encima del botón de despachar.
class PieCarritoSalida extends StatelessWidget {
  final List<LineaSalida> lineas;
  const PieCarritoSalida({super.key, required this.lineas});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${resumenCarrito(lineas)}. Total estimado '
          '${_money.format(totalCarrito(lineas))}.',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(resumenCarrito(lineas),
                style: TextStyle(color: esquema.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Text(_money.format(totalCarrito(lineas)),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}
