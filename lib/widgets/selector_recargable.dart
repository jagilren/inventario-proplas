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

  /// A partir de cuántas opciones se cambia el desplegable por una hoja con
  /// buscador. Con pocas (2 bodegas) el desplegable es más rápido; con
  /// muchas (centros de costo pueden ser miles) se vuelve inservible.
  final int umbralBuscador;

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
    this.umbralBuscador = 12,
  });

  @override
  Widget build(BuildContext context) {
    // Si el valor elegido ya no está en la lista (lo desactivaron desde otro
    // lado), se muestra vacío en vez de reventar.
    final seleccion = opciones.contains(valor) ? valor : null;

    // Con pocas opciones el desplegable de siempre es lo más cómodo. Cuando
    // son muchas (centros de costo pueden llegar a miles) un desplegable se
    // vuelve inservible: toca abrir una hoja con buscador.
    final conBuscador = opciones.length > umbralBuscador;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: conBuscador
              ? _CampoConBuscador<T>(
                  etiqueta: etiqueta,
                  icono: icono,
                  valor: seleccion,
                  opciones: opciones,
                  textoDe: textoDe,
                  onChanged: onChanged,
                )
              : DropdownButtonFormField<T>(
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

/// Campo que, al tocarlo, abre una hoja con buscador en vez de desplegar una
/// lista larguísima. Se usa solo cuando hay muchas opciones.
class _CampoConBuscador<T> extends StatelessWidget {
  final String etiqueta;
  final IconData? icono;
  final T? valor;
  final List<T> opciones;
  final String Function(T) textoDe;
  final ValueChanged<T?> onChanged;

  const _CampoConBuscador({
    required this.etiqueta,
    required this.icono,
    required this.valor,
    required this.opciones,
    required this.textoDe,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = valor;
    return InkWell(
      onTap: () async {
        final sel = await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _HojaBuscador<T>(
            titulo: etiqueta,
            opciones: opciones,
            textoDe: textoDe,
            actual: valor,
          ),
        );
        if (sel != null) onChanged(sel);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: icono == null ? null : Icon(icono),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.search),
          // Se avisa que son muchas, para que no extrañe que no despliegue.
          helperText: '${opciones.length} opciones · toca para buscar',
        ),
        child: Text(
          v == null ? 'Seleccionar…' : textoDe(v),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: v == null ? Theme.of(context).hintColor : null,
          ),
        ),
      ),
    );
  }
}

/// Hoja inferior con buscador. Filtra por palabras sueltas, en cualquier
/// orden y sin tildes — igual que el buscador de artículos, para que se
/// sienta como el resto de la app.
class _HojaBuscador<T> extends StatefulWidget {
  final String titulo;
  final List<T> opciones;
  final String Function(T) textoDe;
  final T? actual;

  const _HojaBuscador({
    required this.titulo,
    required this.opciones,
    required this.textoDe,
    required this.actual,
  });

  @override
  State<_HojaBuscador<T>> createState() => _HojaBuscadorState<T>();
}

class _HojaBuscadorState<T> extends State<_HojaBuscador<T>> {
  final _ctrl = TextEditingController();
  late List<T> _filtradas = widget.opciones;

  static String _sinTildes(String s) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = con.indexOf(ch);
      b.write(i >= 0 ? sin[i] : ch);
    }
    return b.toString();
  }

  void _buscar(String q) {
    final palabras = _sinTildes(q).split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty).toList();
    setState(() {
      _filtradas = palabras.isEmpty
          ? widget.opciones
          : widget.opciones.where((o) {
              final t = _sinTildes(widget.textoDe(o));
              return palabras.every(t.contains);
            }).toList();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(widget.titulo,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: 'Escribe para filtrar…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _ctrl.clear(); _buscar(''); },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_filtradas.length} de ${widget.opciones.length}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
            ),
          ),
          Expanded(
            child: _filtradas.isEmpty
                ? const Center(child: Text('Sin coincidencias'))
                : ListView.builder(
                    itemCount: _filtradas.length,
                    itemBuilder: (_, i) {
                      final o = _filtradas[i];
                      final esActual = o == widget.actual;
                      return ListTile(
                        dense: true,
                        title: Text(widget.textoDe(o)),
                        trailing: esActual
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () => Navigator.pop(context, o),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
