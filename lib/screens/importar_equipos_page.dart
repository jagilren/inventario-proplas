import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../activos_service.dart';
import '../data.dart';
import '../reportes.dart';
import '../util/dialogos.dart';
import '../util/import_archivo.dart';
import '../util/import_equipos.dart';
import '../util/picker.dart';
import '../widgets/carga_devolucion.dart';
import '../widgets/confirmar_descarte.dart';
import '../widgets/import_equipos_widgets.dart';

enum _Filtro { todos, listos, problemas }

/// Carga masiva de EQUIPOS desde una plantilla (Excel o CSV), de referencias
/// sencillas o de kits con sus componentes (docs/plan-importar-equipos.md).
///
/// Nada entra sin revisión: al subir el archivo se ve qué entra, qué
/// referencias se crearán y qué tiene problemas. La carga va a la base de a
/// lotes (importar_equipos, schema_v70): cada lote entra completo o no entra.
class ImportarEquiposPage extends StatefulWidget {
  const ImportarEquiposPage({super.key});
  @override
  State<ImportarEquiposPage> createState() => _ImportarEquiposPageState();
}

class _ImportarEquiposPageState extends State<ImportarEquiposPage> {
  List<ActivoReferencia> _referencias = [];
  List<Bodega> _bodegas = [];
  List<CentroCosto> _centros = [];
  bool _cargandoCatalogo = true;

  String? _archivo;
  bool _leyendo = false;
  RevisionImport? _revision;
  _Filtro _filtro = _Filtro.todos;

  bool _cargando = false;
  int _hechos = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    try {
      final res = await Future.wait([
        ActivosService.todasLasReferencias(soloActivas: false),
        InventarioService.bodegas(),
        InventarioService.centrosCosto(),
      ]);
      if (!mounted) return;
      setState(() {
        _referencias = res[0] as List<ActivoReferencia>;
        _bodegas = res[1] as List<Bodega>;
        _centros = res[2] as List<CentroCosto>;
        _cargandoCatalogo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoCatalogo = false);
      _msg('No se pudo traer el catálogo: $e');
    }
  }

  // ---- Plantilla ----
  Future<void> _plantilla() async {
    try {
      final activas = _referencias.where((r) => r.activo);
      final sencilla = activas.where((r) => !r.esKit).firstOrNull;
      final kit = activas.where((r) => r.esKit).firstOrNull;
      final componentes =
          kit == null ? <ComponentePlantilla>[] : await ActivosService.plantillaKit(kit.id);
      final guardado = await Reportes.descargarCsv(
        'plantilla_equipos',
        filasPlantillaEquipos(
          sencilla: sencilla,
          kit: kit,
          componentesKit: componentes,
          bodega: _bodegas.isEmpty ? '' : _bodegas.first.nombre,
        ),
      );
      _msg(guardado
          ? '✓ Plantilla descargada. Llénala y vuelve a subirla.'
          : 'No se guardó la plantilla: se canceló el diálogo.');
    } catch (e) {
      _msg('No se pudo generar la plantilla: $e');
    }
  }

  // ---- Leer y revisar ----
  Future<void> _elegirArchivo() async {
    String nombre;
    Uint8List bytes;
    try {
      if (kIsWeb) {
        final r = await abrirArchivoWeb('.xlsx,.csv');
        if (r == null) return;
        nombre = r.name;
        bytes = r.bytes;
      } else {
        // file_picker 12: pickFile devuelve el archivo directo (o null si
        // se canceló) y los bytes se leen aparte.
        final f = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['xlsx', 'csv'],
        );
        if (f == null) return;
        nombre = f.name;
        bytes = await f.readAsBytes();
      }
    } catch (e) {
      return _msg('No se pudo abrir el archivo: $e');
    }

    setState(() {
      _leyendo = true;
      _archivo = nombre;
      _revision = null;
    });
    try {
      final filas = leerPlantillaEquipos(leerFilasCrudas(bytes, nombre));
      if (filas.isEmpty) {
        throw const FormatException('El archivo no trae ningún equipo.');
      }
      final existentes = await ActivosService.serialesQueYaExisten(
          [for (final f in filas) f.serial]);
      var cat = CatalogoImport(
        referencias: _referencias,
        bodegas: _bodegas,
        centros: _centros,
        serialesExistentes: existentes,
      );
      var revision = analizarImportEquipos(filas, cat);
      // Los kits que vienen sin componentes copian los del último kit de
      // su referencia: se piden solo esas composiciones y se revisa otra vez.
      final kitsSinComponentes = {
        for (final e in revision.equipos)
          if (e.esKit && e.componentes.isEmpty && e.referencia != null)
            e.referencia!.id,
      };
      if (kitsSinComponentes.isNotEmpty) {
        final plantillas = <String, List<ComponentePlantilla>>{};
        for (final id in kitsSinComponentes) {
          plantillas[id] = await ActivosService.plantillaKit(id);
        }
        cat = CatalogoImport(
          referencias: _referencias,
          bodegas: _bodegas,
          centros: _centros,
          serialesExistentes: existentes,
          plantillas: plantillas,
        );
        revision = analizarImportEquipos(filas, cat);
      }
      if (!mounted) return;
      setState(() {
        _revision = revision;
        _filtro = revision.conProblemas > 0 ? _Filtro.problemas : _Filtro.todos;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _archivo = null);
      mostrarInfoDialog(context,
          icon: Icons.error_outline,
          color: Colors.red,
          titulo: 'Archivo inválido',
          contenido: e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _archivo = null);
      _msg('No se pudo revisar el archivo: $e');
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  // ---- Cargar ----
  Future<void> _cargar() async {
    final r = _revision;
    if (r == null) return;
    final listos = r.listos;
    if (listos.isEmpty) return;
    final kits = listos.where((e) => e.esKit).length;
    final nuevas = {
      for (final e in listos)
        if (e.referenciaNueva != null) e.referenciaNueva!,
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar carga'),
        content: SingleChildScrollView(
          child: Text(
            'Se cargarán ${listos.length} equipo(s)'
            '${kits > 0 ? ', $kits de ellos kits con sus componentes' : ''}.'
            '${nuevas.isNotEmpty ? '\n\nSe crearán ${nuevas.length} '
                'referencia(s) nueva(s).' : ''}'
            '${r.conProblemas > 0 ? '\n\n${r.conProblemas} equipo(s) con '
                'problemas NO se cargan.' : ''}'
            '\n\nVan a la base de a $tamanoLoteImport: cada lote entra '
            'completo o no entra.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cargar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _cargando = true;
      _hechos = 0;
      _total = listos.length;
    });
    final entraron = <EquipoImport>{};
    var refsCreadas = 0;
    String? error;
    for (var i = 0; i < listos.length; i += tamanoLoteImport) {
      final lote =
          listos.sublist(i, (i + tamanoLoteImport).clamp(0, listos.length));
      try {
        final res = await ActivosService.importarEquipos(
            [for (final e in lote) e.aJson()]);
        refsCreadas += res.referenciasNuevas;
        entraron.addAll(lote);
        if (mounted) setState(() => _hechos = entraron.length);
      } catch (e) {
        // Se detiene: lo que falta queda en pantalla, y subir el archivo
        // otra vez no duplica lo que ya entró (el serial no se repite).
        error = '$e';
        break;
      }
    }
    if (!mounted) return;
    final quedan = r.equipos.where((e) => !entraron.contains(e)).toList();
    setState(() {
      _cargando = false;
      _revision = quedan.isEmpty
          ? null
          : RevisionImport(
              quedan,
              r.referenciasNuevas
                  .where((n) => quedan.any((e) => e.referenciaNueva == n))
                  .toList(),
              r.problemasSueltos);
      if (_revision == null) _archivo = null;
    });
    await showDialog<void>(
      context: context,
      builder: (_) => DialogoCargaTerminada(resumen: [
        '✓ Equipos cargados: ${entraron.length}',
        if (refsCreadas > 0) '• Referencias creadas: $refsCreadas',
        if (quedan.isNotEmpty)
          '• Siguen en la pantalla, sin cargar: ${quedan.length}',
        if (error != null) '• Se detuvo en un lote: $error',
      ]),
    );
  }

  void _msg(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  List<EquipoImport> get _visibles {
    final r = _revision;
    if (r == null) return const [];
    return switch (_filtro) {
      _Filtro.todos => r.equipos,
      _Filtro.listos => r.listos,
      _Filtro.problemas => r.equipos.where((e) => !e.listo).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final r = _revision;
    final listos = r?.listos.length ?? 0;
    return ConfirmarDescarte(
      hayTrabajoSinGuardar: r != null && listos > 0 && !_cargando,
      queSePierde: '$listos equipo(s) revisados',
      child: Scaffold(
        appBar: AppBar(title: const Text('Importar equipos')),
        body: _cargandoCatalogo
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Text(
                    'Carga muchos equipos de una vez desde un Excel o CSV: '
                    'sencillos, o kits con sus componentes. Baja la '
                    'plantilla, llénala y súbela; antes de cargar verás qué '
                    'entra y qué no.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: (_leyendo || _cargando) ? null : _elegirArchivo,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_archivo ?? 'Elegir Excel/CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _plantilla,
                        icon: const Icon(Icons.download),
                        label: const Text('Plantilla'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline),
                        tooltip: 'Cómo llenar la plantilla',
                        onPressed: () => mostrarInfoDialog(context,
                            icon: Icons.table_chart,
                            color: Colors.teal,
                            titulo: 'Cómo llenar la plantilla',
                            contenido: ayudaImportEquipos),
                      ),
                    ],
                  ),
                  if (_leyendo) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 4),
                    const Text('Revisando el archivo contra el catálogo…'),
                  ],
                  if (_cargando) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                        value: _total == 0 ? null : _hechos / _total),
                    const SizedBox(height: 4),
                    Semantics(
                      liveRegion: true,
                      child: Text('Cargando: $_hechos de $_total equipos…'),
                    ),
                  ],
                  if (r != null) ..._revisionWidgets(r),
                ],
              ),
        bottomNavigationBar: r == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: (_cargando || listos == 0) ? null : _cargar,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text('CARGAR $listos EQUIPO(S)'),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _revisionWidgets(RevisionImport r) {
    final esquema = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 16),
      Semantics(
        liveRegion: true,
        child: Text(
          '${r.equipos.length} equipo(s) · ${r.listos.length} listo(s) · '
          '${r.conProblemas} con problemas',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      if (r.problemasSueltos.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final p in r.problemasSueltos)
          Text('✗ $p', style: TextStyle(color: esquema.error)),
      ],
      if (r.referenciasNuevas.isNotEmpty) ...[
        const SizedBox(height: 12),
        PanelReferenciasNuevas(nuevas: r.referenciasNuevas),
      ],
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final f in _Filtro.values)
            ChoiceChip(
              label: Text(switch (f) {
                _Filtro.todos => 'Todos (${r.equipos.length})',
                _Filtro.listos => 'Listos (${r.listos.length})',
                _Filtro.problemas => 'Con problemas (${r.conProblemas})',
              }),
              selected: _filtro == f,
              onSelected: (_) => setState(() => _filtro = f),
            ),
        ],
      ),
      const SizedBox(height: 4),
      if (_visibles.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Ningún equipo en este filtro.'),
        ),
      for (final e in _visibles) ...[
        TarjetaEquipoImport(equipo: e),
        const Divider(height: 1),
      ],
    ];
  }
}
