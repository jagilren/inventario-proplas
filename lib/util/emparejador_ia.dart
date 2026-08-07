import '../data.dart';
import 'import_archivo.dart';

/// Proveedores de IA disponibles. El ID viaja a la Edge Function, que es
/// quien guarda las llaves — la app nunca las ve.
enum ProveedorIA { anthropic, openai, china }

extension ProveedorIAX on ProveedorIA {
  String get id => switch (this) {
        ProveedorIA.anthropic => 'anthropic',
        ProveedorIA.openai => 'openai',
        ProveedorIA.china => 'china',
      };

  String get etiqueta => switch (this) {
        ProveedorIA.anthropic => 'Anthropic (Claude)',
        ProveedorIA.openai => 'OpenAI (GPT)',
        ProveedorIA.china => 'Proveedor chino',
      };
}

/// Un modelo concreto que se le puede pedir al proveedor.
///
/// Los precios son en USD por millón de tokens, y sirven SOLO para estimar
/// el costo en pantalla antes de decidir. Envejecen: si el proveedor cambia
/// tarifas, hay que actualizarlos aquí (precios verificados 2026-08-05).
class ModeloIA {
  final String id;
  final String etiqueta;
  final double entradaPorMillon;
  final double salidaPorMillon;
  final String nota;

  const ModeloIA(this.id, this.etiqueta, this.entradaPorMillon,
      this.salidaPorMillon, this.nota);

  /// Costo estimado de emparejar [lineas] líneas.
  ///
  /// Los tokens por línea salen de medir el formato real que se manda:
  /// cada línea lleva su texto más 8 candidatos con nombre. Es un orden de
  /// magnitud para decidir, no una factura.
  double costo(int lineas) =>
      lineas * (88 / 1e6 * entradaPorMillon + 50 / 1e6 * salidaPorMillon);
}

/// Modelos habilitados por proveedor.
///
/// ⚠️ Esta lista debe coincidir con la LISTA BLANCA de la Edge Function
/// (`supabase/functions/emparejar-ia/index.ts`). El servidor rechaza
/// cualquier modelo que no esté allá — la app propone, el servidor decide.
const modelosPorProveedor = <ProveedorIA, List<ModeloIA>>{
  ProveedorIA.anthropic: [
    ModeloIA('claude-haiku-4-5', 'Haiku 4.5', 1, 5, 'El más barato y rápido'),
    ModeloIA('claude-sonnet-5', 'Sonnet 5', 3, 15, 'Intermedio'),
    ModeloIA('claude-opus-5', 'Opus 5', 5, 25, 'El más capaz'),
  ],
  ProveedorIA.openai: [
    ModeloIA('gpt-4o-mini', 'GPT-4o mini', 0.15, 0.6, 'El más barato'),
    ModeloIA('gpt-4o', 'GPT-4o', 2.5, 10, 'El más capaz'),
  ],
  ProveedorIA.china: [
    ModeloIA('moonshot-v1-8k', 'Kimi 8k', 0.2, 0.2, 'Contexto corto'),
    ModeloIA('moonshot-v1-32k', 'Kimi 32k', 0.5, 0.5, 'Contexto amplio'),
    ModeloIA('deepseek-chat', 'DeepSeek', 0.3, 1.2, ''),
    ModeloIA('qwen-plus', 'Qwen Plus', 0.4, 1.2, ''),
  ],
};

/// Resultado de emparejar una línea, venga del algoritmo local o de la IA.
///
/// Las dos vías devuelven ESTA misma forma, y por eso la pantalla no tiene
/// que saber cuál corrió: mismos colores, mismo lápiz para corregir, misma
/// revisión. La IA es "otro emparejador", no otra interfaz.
class Emparejamiento {
  final String texto; // el texto tal como venía en el Excel
  final Elemento? match;
  final double score;
  const Emparejamiento(this.texto, this.match, this.score);
}

/// Empareja con un LLM, usando el algoritmo local como filtro previo.
///
/// Por qué híbrido y no mandarle el catálogo entero: son ~1.000 artículos.
/// Mandarlos completos multiplica el costo y la lentitud sin mejorar nada,
/// porque el algoritmo local ya sabe descartar lo que claramente no aplica.
/// El modelo se reserva para lo que el algoritmo NO puede: entender
/// abreviaturas, sinónimos y nombres del proveedor que no se parecen a los
/// del catálogo.
class EmparejadorIA {
  final EmparejadorCatalogo local;

  /// Cuántos candidatos se le ofrecen al modelo por cada línea. Más
  /// candidatos = más costo por línea; con 8 ya entra casi siempre el
  /// correcto.
  static const candidatosPorLinea = 8;

  EmparejadorIA(this.local);

  /// Empareja todos los textos de una vez. Devuelve la misma cantidad de
  /// resultados que textos recibió, en el mismo orden.
  ///
  /// Si la IA falla (sin llave, sin red, error del proveedor), lanza una
  /// excepción con el motivo: la pantalla la muestra y ofrece seguir con el
  /// algoritmo local, en vez de dejar al usuario sin nada.
  Future<List<Emparejamiento>> emparejar(
    List<String> textos, {
    ProveedorIA proveedor = ProveedorIA.anthropic,
    /// Modelo concreto. Si va null, manda el que tenga configurado el
    /// servidor como valor por defecto.
    String? modelo,
  }) async {
    if (textos.isEmpty) return [];

    // 1) El local propone candidatos por cada línea.
    final lineas = <Map<String, dynamic>>[];
    for (final t in textos) {
      lineas.add({
        'texto': t,
        'candidatos': [
          for (final c in _candidatos(t))
            {'id': c.id, 'nombre': c.nombre},
        ],
      });
    }

    // 2) La IA decide entre esos candidatos.
    final res = await InventarioService.emparejarConIA(
      lineas: lineas,
      proveedor: proveedor.id,
      modelo: modelo,
    );

    // 3) Se traduce de vuelta a elementos. Se busca por id contra el
    //    catálogo: si el modelo se inventara un id, la línea queda sin
    //    emparejar en vez de apuntar a un artículo que no existe.
    final porId = {for (final e in local.catalogo) e.id: e};
    final porTexto = <String, Emparejamiento>{};
    for (final r in res) {
      final texto = (r['texto'] ?? '') as String;
      final id = r['elemento_id'] as String?;
      final score = ((r['score'] ?? 0) as num).toDouble();
      porTexto[texto] = Emparejamiento(texto, id == null ? null : porId[id],
          score.clamp(0, 1).toDouble());
    }

    // Se responde en el orden original. Si el modelo omitió una línea, esa
    // queda sin emparejar (no se inventa nada).
    return [
      for (final t in textos) porTexto[t] ?? Emparejamiento(t, null, 0),
    ];
  }

  /// Los N artículos más parecidos según el algoritmo local, sin aplicar el
  /// umbral: aquí interesa OFRECER opciones, no decidir. Decidir es trabajo
  /// del modelo.
  List<Elemento> _candidatos(String texto) {
    final nq = normalizarTexto(texto);
    if (nq.isEmpty) return const [];
    final puntajes = <({Elemento e, double s})>[];
    for (final e in local.catalogo) {
      final s = similitud(nq, normalizarTexto(e.nombre));
      if (s > 0) puntajes.add((e: e, s: s));
    }
    puntajes.sort((a, b) => b.s.compareTo(a.s));
    return [
      for (final p in puntajes.take(candidatosPorLinea)) p.e,
    ];
  }
}
