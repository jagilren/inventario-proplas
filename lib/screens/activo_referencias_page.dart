import 'package:flutter/material.dart';
import '../activos_service.dart';
import 'activo_alta_page.dart';
import '../util/import_archivo.dart';
import '../widgets/campo_obligatorio.dart';
import '../widgets/kit_componentes.dart';
import '../widgets/pie_cargar_mas.dart';

/// Catálogo de referencias de equipos (los modelos: "Bomba Grundfos DNA30").
///
/// Es la maestra que evita que el mismo modelo quede escrito de tres formas
/// distintas, igual que `materiales` para el catálogo de elementos. Un equipo
/// individual (`activos`) siempre apunta a una de estas.
///
/// Siguiendo la regla del proyecto: una referencia con equipos asociados no se
/// borra, se inactiva.
class ActivoReferenciasPage extends StatefulWidget {
  /// Abierta desde el alta de un equipo: al crear una referencia se vuelve
  /// allá con ella, para seguir sin tener que buscarla.
  final bool elegirAlCrear;
  const ActivoReferenciasPage({super.key, this.elegirAlCrear = false});
  @override
  State<ActivoReferenciasPage> createState() => _ActivoReferenciasPageState();
}

class _ActivoReferenciasPageState extends State<ActivoReferenciasPage> {
  static const _porPagina = 50;

  final List<ActivoReferencia> _refs = [];
  int _offset = 0;
  bool _hayMas = true;
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _mostrarInactivas = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _recargar() => _cargar(desdeCero: true);

  Future<void> _cargar({bool desdeCero = false}) async {
    if (_cargandoMas) return;
    setState(() {
      _error = null;
      if (desdeCero || _offset == 0) {
        _offset = 0; _hayMas = true; _refs.clear(); _cargando = true;
      } else {
        _cargandoMas = true;
      }
    });
    try {
      final res = await ActivosService.referencias(
        soloActivas: !_mostrarInactivas,
        offset: _offset,
        limit: _porPagina,
      );
      if (!mounted) return;
      setState(() {
        _refs.addAll(res);
        _offset += res.length;
        if (res.length < _porPagina) _hayMas = false;
        _cargando = false; _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _cargando = false; _cargandoMas = false; });
    }
  }

  Future<void> _abrirFormulario({ActivoReferencia? ref}) async {
    // Devuelve la referencia CREADA, o true si se editó una.
    final guardado = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true, // el teclado no debe tapar los campos
      builder: (_) => _FormularioReferencia(referencia: ref),
    );
    if (guardado == null || !mounted) return;
    if (guardado is ActivoReferencia && widget.elegirAlCrear) {
      Navigator.pop(context, guardado);
      return;
    }
    _recargar();
    // Un kit recién creado todavía no tiene componentes: se agregan a cada
    // EQUIPO. Sin este aviso, quien lo creaba no veía cuál era el paso
    // siguiente (pasó el 2026-09-10 con "KIT DE PRUEBA01").
    if (guardado is ActivoReferencia && guardado.esKit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kit "${guardado.nombre}" creado. Sus componentes se '
            'agregan a cada equipo de este kit.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Crear equipo',
          onPressed: () => _crearEquipo(guardado),
        ),
      ));
    }
  }

  /// El alta de un equipo con esta referencia ya elegida.
  Future<void> _crearEquipo(ActivoReferencia r) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ActivoAltaPage(referenciaInicial: r)));
    if (mounted) _recargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referencias de equipos'),
        actions: [
          IconButton(
            icon: Icon(_mostrarInactivas
                ? Icons.visibility
                : Icons.visibility_off),
            tooltip: _mostrarInactivas
                ? 'Ocultar las inactivas'
                : 'Mostrar también las inactivas',
            onPressed: () {
              setState(() => _mostrarInactivas = !_mostrarInactivas);
              _recargar();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 12),
              Text('No se pudo cargar el catálogo.\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _recargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_refs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay referencias.\nCrea la primera con el botón "Nueva".',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _recargar,
      child: ListView.separated(
        // Espacio al final para que el FAB no tape la última fila.
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _refs.length + 1, // +1: pie de "Cargar más"
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == _refs.length) {
            return PieCargarMas(
                cargando: _cargandoMas, hayMas: _hayMas, onCargarMas: _cargar);
          }
          final r = _refs[i];
          final detalle = [r.marca, r.modelo, r.tipo]
              .where((e) => e != null && e.isNotEmpty)
              .join(' · ');
          return ListTile(
            // Un kit se distingue a simple vista, con ícono Y texto: solo con
            // color no lo nota quien no distingue colores, y un lector de
            // pantalla no lee colores.
            title: Row(
              children: [
                Flexible(child: Text(r.nombre)),
                if (r.esKit) ...[
                  const SizedBox(width: 8),
                  const MarcaKit(),
                ],
              ],
            ),
            subtitle: detalle.isEmpty ? null : Text(detalle),
            // Un kit activo ofrece el paso siguiente: crear un equipo, que es
            // donde van sus componentes. Con tooltip, que el lector de
            // pantalla lee como nombre del botón.
            trailing: !r.activo
                ? const Text('Inactiva', style: TextStyle(fontSize: 12))
                : r.esKit
                    ? IconButton(
                        icon: const Icon(Icons.add_box_outlined),
                        tooltip: 'Crear un equipo de este kit',
                        onPressed: () => _crearEquipo(r),
                      )
                    : const Icon(Icons.chevron_right),
            onTap: () => _abrirFormulario(ref: r),
          );
        },
      ),
    );
  }
}

class _FormularioReferencia extends StatefulWidget {
  final ActivoReferencia? referencia;
  const _FormularioReferencia({this.referencia});
  @override
  State<_FormularioReferencia> createState() => _FormularioReferenciaState();
}

class _FormularioReferenciaState extends State<_FormularioReferencia> {
  late final TextEditingController _nombre;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _tipo;
  late bool _activo;
  late bool _esKit;
  /// null mientras se averigua. Una referencia con equipos no puede cambiar
  /// si es kit (schema_v64): el interruptor se deshabilita y DICE por qué,
  /// en vez de dejarlo oprimir y que la base lo rechace al guardar.
  bool? _tieneEquipos;
  bool _guardando = false;
  bool _mostrarErrores = false;

  @override
  void initState() {
    super.initState();
    final r = widget.referencia;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _marca = TextEditingController(text: r?.marca ?? '');
    _modelo = TextEditingController(text: r?.modelo ?? '');
    _tipo = TextEditingController(text: r?.tipo ?? '');
    _activo = r?.activo ?? true;
    _esKit = r?.esKit ?? false;
    if (r == null) {
      _tieneEquipos = false;
    } else {
      ActivosService.referenciaTieneEquipos(r.id).then(
        (v) { if (mounted) setState(() => _tieneEquipos = v); },
        // Si no se pudo averiguar, se deja bloqueado: es lo seguro. La base
        // lo rechazaría de todas formas si ya hay equipos.
        onError: (_) { if (mounted) setState(() => _tieneEquipos = true); },
      );
    }
  }

  /// El texto bajo el interruptor "Es un kit". Siempre dice algo: qué hace,
  /// o por qué no se puede cambiar.
  String get _ayudaKit => switch (_tieneEquipos) {
    null => 'Revisando si esta referencia ya tiene equipos…',
    true => 'No se puede cambiar: esta referencia ya tiene equipos. Si te '
        'equivocaste, crea otra referencia.',
    false => _esKit
        ? 'Sus equipos valdrán la suma de sus componentes. Los componentes se '
            'agregan a cada equipo, al crearlo en "Nuevo equipo".'
        : 'Actívalo si el equipo está hecho de varias partes que se cuentan '
            'y se valoran por separado.',
  };

  @override
  void dispose() {
    _nombre.dispose();
    _marca.dispose();
    _modelo.dispose();
    _tipo.dispose();
    super.dispose();
  }

  String? _t(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Antes de crear, avisa si ya existe una referencia PARECIDA.
  ///
  /// La base impide las duplicadas exactas, pero no distingue "BOMBA 2HP" de
  /// "BOMBA 2 HP" — y así es como se fragmenta un catálogo. Se usa el mismo
  /// emparejador que la app ya aplica al importar archivos, así que respeta
  /// su regla de que las medidas que se contradicen no emparejan.
  ///
  /// Devuelve true si se debe continuar guardando.
  Future<bool> _confirmarSiSeParece() async {
    // Se comparan TODAS, incluidas las inactivas: el candado de la base
    // también las cuenta, así que una inactiva parecida igual haría chocar.
    final todas =
        await ActivosService.todasLasReferencias(soloActivas: false);
    final mio = normalizarTexto(
        [_nombre.text, _marca.text, _modelo.text]
            .where((e) => e.trim().isNotEmpty)
            .join(' '));

    ActivoReferencia? parecida;
    var mejor = 0.0;
    for (final r in todas) {
      final s = similitud(mio, normalizarTexto(r.etiqueta));
      if (s > mejor) { mejor = s; parecida = r; }
    }
    if (parecida == null || mejor < 0.70) return true;
    // Copia inmutable: dentro del closure del diálogo Dart ya no puede
    // garantizar que la variable mutable siga sin ser nula.
    final candidata = parecida;

    if (!mounted) return false;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿No será la misma?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ya existe una referencia muy parecida:'),
            const SizedBox(height: 10),
            Text(candidata.etiqueta,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Crear dos referencias para el mismo modelo hace que sus '
              'equipos queden repartidos y los conteos no cuadren.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Usar la que ya existe')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Es distinta, crearla')),
        ],
      ),
    );
    return seguir == true;
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _mostrarErrores = true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = widget.referencia;
      if (r == null) {
        if (!await _confirmarSiSeParece()) {
          if (mounted) setState(() => _guardando = false);
          return;
        }
        final creada = await ActivosService.crearReferencia(
          nombre: _nombre.text.trim(),
          marca: _t(_marca),
          modelo: _t(_modelo),
          tipo: _t(_tipo),
          esKit: _esKit,
        );
        if (!mounted) return;
        // La creada, no un true: la lista la usa para ofrecer el siguiente
        // paso de un kit (crear un equipo).
        Navigator.pop(context, creada);
        return;
      } else {
        await ActivosService.editarReferencia(
          r.id,
          nombre: _nombre.text.trim(),
          // Cadena vacía y no null: null significaría "no cambiar", y así
          // se puede borrar un dato que ya estaba escrito.
          marca: _marca.text.trim(),
          modelo: _modelo.text.trim(),
          tipo: _tipo.text.trim(),
          activo: _activo,
          // Solo si cambió: mandarlo igual no molesta, pero así ni se toca.
          esKit: _esKit != r.esKit ? _esKit : null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      // El candado de la base habla en jerga ("duplicate key value violates
      // unique constraint activo_referencias_uniq"); aquí se traduce.
      final txt = '$e';
      final duplicada = txt.contains('activo_referencias_uniq') ||
          txt.contains('23505') ||
          txt.contains('duplicate key');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(duplicada
              ? 'Ya existe una referencia con ese mismo nombre, marca y '
                  'modelo. Búscala en la lista (puede estar inactiva).'
              : 'No se pudo guardar: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.referencia != null;
    return Padding(
      // viewInsets: el formulario sube con el teclado en vez de quedar tapado.
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
                  child: Text(
                      editando ? 'Editar referencia' : 'Nueva referencia',
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
              autofocus: !editando,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: marcarError(
                const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej: BOMBA CENTRÍFUGA',
                  border: OutlineInputBorder(),
                ),
                _mostrarErrores && _nombre.text.trim().isEmpty,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _marca,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Marca', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Modelo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tipo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                hintText: 'Ej: BOMBA, MOTOR, HERRAMIENTA',
                border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            // SwitchListTile y no un Switch suelto: toda la fila se puede
            // tocar (no solo el interruptorcito), y el lector de pantalla
            // lee título, estado y la razón del subtítulo juntos.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.inventory_2_outlined),
              title: const Text('Es un kit compuesto por varios componentes'),
              subtitle: Text(_ayudaKit),
              value: _esKit,
              onChanged: _tieneEquipos == false
                  ? (v) => setState(() => _esKit = v)
                  : null,
            ),
            if (editando) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                subtitle: const Text(
                    'Una referencia inactiva no se ofrece al crear equipos'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
