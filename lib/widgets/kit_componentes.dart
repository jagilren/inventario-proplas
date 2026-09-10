// Piezas visuales de los KITS (Referencias KITZABLES, Fase 3 —
// docs/plan-kits-equipos.md). Viven aquí y no dentro de la ficha del equipo
// para poder PROBARLAS: test/kit_componentes_widget_test.dart mide su
// accesibilidad (área táctil, nombres para el lector de pantalla, contraste)
// y que no se desborden en un celular de 360 px con la letra agrandada.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:intl/intl.dart';
import '../activos_service.dart';

final _money =
    NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);

/// "2" y no "2.0"; "2,5" con coma, como se escribe en Colombia.
String textoCantidad(num n) =>
    n % 1 == 0 ? n.toInt().toString() : n.toString().replaceAll('.', ',');

/// Cifras del mismo ancho: en una columna de valores los dígitos quedan
/// alineados y se comparan de un vistazo.
const _cifras = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// La marca "KIT" junto al nombre de una referencia kitzable. Ícono Y texto:
/// solo con color no lo nota quien no distingue colores, y un lector de
/// pantalla no lee colores.
class MarcaKit extends StatelessWidget {
  const MarcaKit({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Es un kit',
      // Que el lector diga "Es un kit" una vez, y no "ícono" + "KIT".
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 13, color: color),
            const SizedBox(width: 3),
            Text('KIT',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Una tarjeta por componente. Tarjeta y no fila de tabla: en 360 px una
/// tabla de cuatro columnas con nombres largos no se lee.
class TarjetaComponente extends StatelessWidget {
  final ActivoComponente componente;
  /// El porcentaje del equipo. Si es menor que 100 se muestra también el
  /// subtotal ponderado.
  final num porcentaje;
  const TarjetaComponente({
    super.key,
    required this.componente,
    required this.porcentaje,
  });

  /// Toda la tarjeta en UNA frase para el lector de pantalla. Sin esto leería
  /// "24 por 45.000" (el ×) y las cifras sueltas, sin decir qué es cada una.
  String get fraseAccesible {
    final c = componente;
    final cant = textoCantidad(c.cantidad);
    return [
      c.agotado ? '${c.nombre}, agotado' : c.nombre,
      '$cant ${c.cantidad == 1 ? "unidad" : "unidades"} a '
          '${_money.format(c.valorUnitario)} cada una',
      'subtotal ${_money.format(c.subtotal)}',
      if (porcentaje < 100)
        'al ${textoCantidad(porcentaje)} por ciento, '
            '${_money.format(c.subtotalAl(porcentaje))}',
    ].join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final c = componente;
    final gris = Theme.of(context).colorScheme.onSurfaceVariant;
    final ponderado = porcentaje < 100;
    final cant = textoCantidad(c.cantidad);

    return Semantics(
      container: true,
      label: fraseAccesible,
      excludeSemantics: true,
      child: Card(
        margin: const EdgeInsets.only(top: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      c.nombre,
                      // Agotado: en el color secundario del tema, NO con
                      // opacidad — la opacidad baja el contraste por debajo
                      // de lo legible.
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: c.agotado ? gris : null),
                    ),
                  ),
                  if (c.agotado)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Agotado',
                          style: TextStyle(
                              fontSize: 12,
                              color: gris,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Wrap y no Row: con la letra agrandada, el total baja de línea
              // en vez de desbordarse.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text('$cant × ${_money.format(c.valorUnitario)}',
                      style: _cifras.copyWith(color: gris)),
                  Text(_money.format(c.subtotal),
                      style: _cifras.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              if (ponderado) ...[
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text('al ${textoCantidad(porcentaje)}%',
                        style: TextStyle(fontSize: 12.5, color: gris)),
                    Text(_money.format(c.subtotalAl(porcentaje)),
                        style: _cifras.copyWith(fontSize: 12.5, color: gris)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El valor del kit, fijo al pie de la pestaña Componentes.
class PieTotalKit extends StatelessWidget {
  final num total;
  final num porcentaje;
  const PieTotalKit({super.key, required this.total, required this.porcentaje});

  @override
  Widget build(BuildContext context) {
    final ponderado = porcentaje < 100;
    final actual = total * porcentaje / 100;
    return Semantics(
      container: true,
      label: [
        'Valor del kit a nuevo, ${_money.format(total)}',
        if (ponderado)
          'al ${textoCantidad(porcentaje)} por ciento, ${_money.format(actual)}',
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    const Text('Valor del kit a nuevo'),
                    Text(_money.format(total),
                        style: _cifras.copyWith(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
                if (ponderado) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      Text('Al ${textoCantidad(porcentaje)}% (su condición)'),
                      Text(_money.format(actual),
                          style: _cifras.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja para agregar un componente a un kit.
///
/// El valor unitario va en pesos ENTEROS y solo acepta dígitos: si alguien
/// escribe "45.000" como se escribe en Colombia, un campo decimal lo leería
/// como 45. Debajo de cada número se muestra cómo quedó entendido.
class HojaComponente extends StatefulWidget {
  final String activoId;
  final int orden;
  const HojaComponente({super.key, required this.activoId, required this.orden});
  @override
  State<HojaComponente> createState() => _HojaComponenteState();
}

class _HojaComponenteState extends State<HojaComponente> {
  final _nombre = TextEditingController();
  final _cantidad = TextEditingController();
  final _valor = TextEditingController();
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void dispose() {
    _nombre.dispose();
    _cantidad.dispose();
    _valor.dispose();
    super.dispose();
  }

  /// Acepta coma o punto como separador DECIMAL ("2,5" = 2.5): una cantidad
  /// puede ser de metros de tela. Lo que se entendió se muestra en vivo.
  num? get _cant => num.tryParse(_cantidad.text.trim().replaceAll(',', '.'));
  int? get _vr => int.tryParse(_valor.text.trim());

  String? get _errorNombre =>
      _nombre.text.trim().isEmpty ? 'Escribe el nombre del componente' : null;
  String? get _errorCantidad {
    final c = _cant;
    if (_cantidad.text.trim().isEmpty) return 'Escribe cuántos hay';
    if (c == null) return 'No es un número';
    if (c <= 0) return 'Tiene que ser mayor que cero';
    return null;
  }

  String? get _errorValor =>
      _valor.text.trim().isEmpty ? 'Escribe el valor de cada uno' : null;

  bool get _valido =>
      _errorNombre == null && _errorCantidad == null && _errorValor == null;

  Future<void> _guardar() async {
    if (!_valido) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      await ActivosService.agregarComponente(
        activoId: widget.activoId,
        nombre: _nombre.text,
        cantidad: _cant!,
        valorUnitario: _vr!,
        orden: widget.orden,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      // ErrorEquipos ya trae el mensaje listo ("Este kit ya tiene un
      // componente con ese nombre."); la hoja queda abierta para corregir.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo agregar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gris = Theme.of(context).colorScheme.onSurfaceVariant;
    final cant = _cant;
    final vr = _vr;
    final subtotal = (cant != null && vr != null) ? cant * vr : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Agregar componente',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar sin guardar',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Tela filtros de los medios',
                border: const OutlineInputBorder(),
                // errorText y no solo un color: el lector de pantalla lo
                // anuncia.
                errorText: _mostrarErrores ? _errorNombre : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cantidad,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Cantidad *',
                hintText: 'Ej: 24',
                border: const OutlineInputBorder(),
                errorText: _mostrarErrores ? _errorCantidad : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valor,
              keyboardType: TextInputType.number,
              // Solo dígitos: pesos enteros, sin puntos ni comas que se
              // puedan confundir con decimales.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _guardar(),
              decoration: InputDecoration(
                labelText: 'Valor unitario *',
                hintText: 'Ej: 45000',
                prefixText: '\$ ',
                border: const OutlineInputBorder(),
                errorText: _mostrarErrores ? _errorValor : null,
                // Lo que se entendió, en el formato de toda la app.
                helperText: vr == null
                    ? 'En pesos, sin puntos'
                    : '= ${_money.format(vr)} cada uno',
              ),
            ),
            if (subtotal != null) ...[
              const SizedBox(height: 14),
              // liveRegion: el lector anuncia el subtotal cuando cambia.
              Semantics(
                liveRegion: true,
                child: Text(
                  'Subtotal: ${textoCantidad(cant!)} × ${_money.format(vr)} = '
                  '${_money.format(subtotal)}',
                  style: _cifras.copyWith(color: gris, fontSize: 13.5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }
}
