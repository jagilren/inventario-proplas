import 'package:flutter/material.dart';

/// El resumen al terminar una carga de Devoluciones, con el botón para
/// descargar lo que NO se cargó.
///
/// Sin esa descarga, una línea que quedaba por fuera (un artículo NUEVO que
/// nadie con permiso resolvió, uno sin reconocer, uno en $0) solo se podía
/// volver a cargar subiendo el archivo completo otra vez… y eso repetía las
/// líneas que ya habían entrado.
class DialogoCargaTerminada extends StatefulWidget {
  /// Las líneas del resumen ("✓ Cargados: 12", "• Sin costo…").
  final List<String> resumen;

  /// Cuántas líneas no se cargaron.
  final int pendientes;

  /// Guarda el CSV de lo que no se cargó. Devuelve false si se canceló el
  /// diálogo de guardar (en el celular). Null si no hay nada pendiente.
  final Future<bool> Function()? descargarPendientes;

  const DialogoCargaTerminada({
    super.key,
    required this.resumen,
    this.pendientes = 0,
    this.descargarPendientes,
  });

  @override
  State<DialogoCargaTerminada> createState() => _DialogoCargaTerminadaState();
}

class _DialogoCargaTerminadaState extends State<DialogoCargaTerminada> {
  bool _guardando = false;
  // null: todavía no se intentó. Si no, lo que pasó, en palabras.
  String? _estado;
  bool _guardado = false;

  Future<void> _descargar() async {
    setState(() {
      _guardando = true;
      _estado = null;
    });
    try {
      final ok = await widget.descargarPendientes!();
      if (!mounted) return;
      setState(() {
        _guardado = ok;
        _estado = ok
            ? '✓ Guardado. Cuando esté resuelto, súbelo aquí en Devoluciones: '
                'solo trae lo que faltó.'
            : 'No se guardó: se canceló el diálogo. Puedes intentarlo otra vez.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _estado = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final n = widget.pendientes;
    return AlertDialog(
      title: const Text('Carga terminada'),
      // Con scroll: en 360 px con la letra grande no cabe todo.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in widget.resumen) Text(l),
            if (n > 0 && widget.descargarPendientes != null) ...[
              const Divider(height: 24),
              Text(
                'Quedaron $n línea(s) sin cargar. Siguen en la pantalla para '
                'resolverlas. Si vas a cerrar, descárgalas: ese archivo se '
                'vuelve a subir aquí y no repite lo que ya entró.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _guardando ? null : _descargar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.file_download),
                label: Text('Descargar lo que no se cargó ($n)'),
              ),
              if (_estado != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  // Se anuncia solo: el lector de pantalla dice si se guardó.
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _estado!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _guardado ? esquema.primary : esquema.error,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo')),
      ],
    );
  }
}
