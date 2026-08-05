import 'package:flutter/material.dart';

/// Desplegable de catálogo (centros de costo, bodegas…) con un botón para
/// volver a pedirlo al servidor sin salir de la pantalla.
///
/// Para qué: estas listas se cargan una sola vez al abrir la vista. Si otra
/// persona crea un centro de costo mientras tú tienes la pantalla abierta,
/// no aparece. El botón ↻ la refresca en el sitio, sin perder lo que ya
/// llevas escrito en el formulario.
///
/// Cuidados de móvil:
/// - El desplegable ocupa todo el ancho disponible y recorta con puntos
///   suspensivos, así una etiqueta larga no descuadra la fila.
/// - El botón respeta el área táctil mínima de Material (48 dp) aunque se
///   vea compacto: se puede pulsar con el dedo sin apuntar.
/// - Mientras recarga, el indicador ocupa exactamente el mismo espacio que
///   el ícono, así que la fila no “salta”.
class SelectorRecargable<T> extends StatelessWidget {
  /// Texto del campo (ej. 'Centro de costo destino').
  final String etiqueta;

  /// Ícono opcional a la izquierda del campo.
  final IconData? icono;

  /// Valor elegido. Debe ser uno de [opciones] (o null).
  final T? valor;

  final List<T> opciones;

  /// Cómo mostrar cada opción en la lista.
  final String Function(T) textoDe;

  final ValueChanged<T?> onChanged;

  /// Qué hacer al pulsar ↻. La pantalla es la que vuelve a consultar y
  /// actualiza su propia lista.
  final Future<void> Function() onRecargar;

  /// True mientras la recarga está en curso.
  final bool recargando;

  /// Texto de ayuda cuando la lista está vacía.
  final String textoVacio;

  const SelectorRecargable({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.opciones,
    required this.textoDe,
    required this.onChanged,
    required this.onRecargar,
    this.recargando = false,
    this.icono,
    this.textoVacio = 'No hay opciones. Pulsa ↻ para volver a consultar.',
  });

  @override
  Widget build(BuildContext context) {
    // Si el valor elegido ya no está en la lista (lo desactivaron desde otro
    // lado), se muestra vacío en vez de reventar.
    final seleccion = opciones.contains(valor) ? valor : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<T>(
            initialValue: seleccion,
            isExpanded: true, // etiquetas largas: recorta, no desborda
            decoration: InputDecoration(
              labelText: etiqueta,
              prefixIcon: icono == null ? null : Icon(icono),
              border: const OutlineInputBorder(),
              helperText: opciones.isEmpty ? textoVacio : null,
              helperMaxLines: 2,
            ),
            items: opciones
                .map((o) => DropdownMenuItem<T>(
                      value: o,
                      child: Text(
                        textoDe(o),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: opciones.isEmpty ? null : onChanged,
          ),
        ),
        const SizedBox(width: 4),
        // Se alinea con el alto del campo, no con el helperText de abajo.
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton(
            onPressed: recargando ? null : onRecargar,
            tooltip: 'Volver a consultar la lista',
            // Área táctil de 48 dp (lo mínimo de Material para el dedo)
            // pero sin el relleno de sobra que se comería el ancho.
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: recargando
                // Mismo tamaño que el ícono: la fila no cambia de ancho.
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}

/// Aviso corto tras recargar un catálogo: dice si de verdad llegó algo nuevo.
/// Sin esto, el usuario pulsa ↻, no ve cambios y no sabe si funcionó.
void avisarRecarga(BuildContext context, int antes, int despues) {
  final nuevos = despues - antes;
  final texto = switch (nuevos) {
    0 => 'La lista ya estaba al día',
    1 => '✓ Se agregó 1 nuevo',
    > 1 => '✓ Se agregaron $nuevos nuevos',
    _ => 'La lista cambió: ahora hay $despues',
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(texto), duration: const Duration(seconds: 2)),
  );
}

/// Vuelve a consultar un catálogo y avisa qué cambió.
///
/// Devuelve la lista nueva, o null si no se pudo traer (sin señal), para que
/// la pantalla deje la que ya tenía en vez de vaciar el desplegable.
/// Evita repetir el mismo bloque de try/catch en cada pantalla.
Future<List<T>?> recargarCatalogo<T>(
  BuildContext context,
  Future<List<T>> Function() consultar,
  int cuantosHabia,
) async {
  try {
    final lista = await consultar();
    if (context.mounted) avisarRecarga(context, cuantosHabia, lista.length);
    return lista;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sin señal: no se pudo actualizar la lista'),
        duration: Duration(seconds: 2),
      ));
    }
    return null;
  }
}
