// Edge Function: emparejar-ia
//
// Empareja las líneas de un archivo de compra con artículos del catálogo,
// usando un LLM. La app manda los textos del Excel y, por cada uno, los
// candidatos que el algoritmo LOCAL ya preseleccionó; el modelo solo elige
// entre esos.
//
// POR QUÉ VIVE AQUÍ Y NO EN LA APP: las llaves de los proveedores serían
// públicas dentro del Flutter web o de la APK — cualquiera puede abrirlas y
// sacarlas. Aquí son secretos del servidor, y rotarlas no obliga a
// recompilar ni a redesplegar la app.
//
// POR QUÉ MANDA CANDIDATOS Y NO EL CATÁLOGO ENTERO: son ~1.000 artículos.
// Mandarlos completos en cada línea multiplica el costo y la lentitud sin
// mejorar el resultado: el algoritmo local ya sabe descartar lo que
// claramente no aplica. El modelo se usa para lo que el algoritmo NO puede,
// que es entender el lenguaje (abreviaturas, sinónimos, nombres del
// proveedor que no se parecen a los tuyos).
//
// Deploy:  supabase functions deploy emparejar-ia
// Secretos: Dashboard → Project Settings → Edge Functions → Secrets
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ---------------------------------------------------------------------
// Configuración por proveedor.
//
// El ID del modelo NO está clavado en el código: vive como variable de
// entorno para poder cambiarlo (o subirlo de gama) editando un campo, sin
// recompilar la app ni volver a desplegar esta función.
// ---------------------------------------------------------------------
type Proveedor = "anthropic" | "openai" | "china";

interface Config {
  url: string;
  llave: string | undefined;
  modelo: string;
}

function config(p: Proveedor): Config {
  switch (p) {
    case "anthropic":
      return {
        url: "https://api.anthropic.com/v1/messages",
        llave: Deno.env.get("ANTHROPIC_API_KEY"),
        // Haiku 4.5: elegir entre 8 candidatos ya filtrados es tarea sencilla,
        // no hace falta un modelo de gama alta. Se puede subir a
        // claude-opus-5 cambiando este secreto.
        modelo: Deno.env.get("IA_MODELO_ANTHROPIC") ?? "claude-haiku-4-5",
      };
    case "openai":
      return {
        url: "https://api.openai.com/v1/chat/completions",
        llave: Deno.env.get("OPENAI_API_KEY"),
        modelo: Deno.env.get("IA_MODELO_OPENAI") ?? "gpt-4o-mini",
      };
    case "china":
      return {
        // Sirve para cualquier proveedor con API compatible con OpenAI
        // (Kimi/Moonshot, DeepSeek, Qwen...). Solo cambia la URL base.
        url: Deno.env.get("IA_URL_CHINA") ??
          "https://api.moonshot.cn/v1/chat/completions",
        llave: Deno.env.get("IA_API_KEY_CHINA"),
        modelo: Deno.env.get("IA_MODELO_CHINA") ?? "moonshot-v1-8k",
      };
  }
}

// ---------------------------------------------------------------------
// El encargo que se le da al modelo.
// ---------------------------------------------------------------------
const INSTRUCCIONES = `Eres un experto en inventarios de una empresa de tratamiento de aguas.

Tu tarea: por cada texto que viene de un archivo de compra, decidir cuál de
los artículos candidatos del catálogo es EL MISMO artículo.

REGLAS, en orden de importancia:
1. Las MEDIDAS deben coincidir. Un tapón de 1/2" NO es un tapón de 2-1/2".
   Fíjate en pulgadas, diámetros, calibres, SCH, longitudes. Si las medidas
   se contradicen, NO es el mismo artículo.
2. El MATERIAL debe coincidir (PVC, inox 304, bronce, galvanizado...).
3. El texto del archivo suele venir abreviado o escrito distinto: es normal
   que diga menos que el nombre del catálogo. Eso NO impide emparejar,
   siempre que nada se contradiga.
4. Si ninguno de los candidatos es el mismo artículo, devuelve
   elemento_id: null. Es MEJOR no emparejar que emparejar mal: un
   emparejamiento equivocado mete plata en el artículo que no es.

Devuelve un score entre 0 y 1 con tu seguridad:
- 0.95-1.0 = seguro que es el mismo
- 0.7-0.95 = muy probable, que lo revise una persona
- menos de 0.7 = dudoso
Usa null en elemento_id si no hay ninguno aceptable.`;

interface Linea {
  texto: string;
  candidatos: { id: string; nombre: string }[];
}

interface Resultado {
  texto: string;
  elemento_id: string | null;
  score: number;
}

// ---- Anthropic --------------------------------------------------------
async function pedirAnthropic(c: Config, lineas: Linea[]): Promise<Resultado[]> {
  const r = await fetch(c.url, {
    method: "POST",
    headers: {
      "x-api-key": c.llave!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: c.modelo,
      max_tokens: 8000,
      system: INSTRUCCIONES,
      // Salida estructurada: la respuesta SIEMPRE viene con esta forma, no
      // hay que confiar en que el modelo devuelva un JSON limpio.
      output_config: {
        format: {
          type: "json_schema",
          schema: esquema(),
        },
      },
      messages: [{ role: "user", content: JSON.stringify({ lineas }) }],
    }),
  });
  if (!r.ok) throw new Error(`Anthropic ${r.status}: ${await r.text()}`);
  const data = await r.json();
  const texto = data.content?.find((b: { type: string }) => b.type === "text")?.text ?? "{}";
  return JSON.parse(texto).resultados ?? [];
}

// ---- OpenAI y compatibles (incluye las chinas) ------------------------
async function pedirOpenAICompatible(
  c: Config,
  lineas: Linea[],
): Promise<Resultado[]> {
  const r = await fetch(c.url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${c.llave!}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: c.modelo,
      messages: [
        { role: "system", content: INSTRUCCIONES },
        { role: "user", content: JSON.stringify({ lineas }) },
      ],
      response_format: { type: "json_object" },
    }),
  });
  if (!r.ok) throw new Error(`${c.url} ${r.status}: ${await r.text()}`);
  const data = await r.json();
  const texto = data.choices?.[0]?.message?.content ?? "{}";
  return JSON.parse(texto).resultados ?? [];
}

function esquema() {
  return {
    type: "object",
    properties: {
      resultados: {
        type: "array",
        items: {
          type: "object",
          properties: {
            texto: { type: "string" },
            elemento_id: { type: ["string", "null"] },
            score: { type: "number" },
          },
          required: ["texto", "elemento_id", "score"],
          additionalProperties: false,
        },
      },
    },
    required: ["resultados"],
    additionalProperties: false,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    // 1) Solo usuarios autenticados de la app. Sin esto, cualquiera con la
    //    URL podría gastar los tokens de la empresa.
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey);
    const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
    const { data: userData } = await admin.auth.getUser(jwt);
    if (!userData?.user?.id) return json({ error: "No autenticado" }, 401);

    // 2) Entrada
    const cuerpo = await req.json();
    const proveedor: Proveedor = cuerpo.proveedor ?? "anthropic";
    const lineas: Linea[] = cuerpo.lineas ?? [];
    if (lineas.length === 0) return json({ error: "No hay líneas" }, 400);
    if (lineas.length > 300) {
      return json({ error: "Máximo 300 líneas por llamada" }, 400);
    }

    const c = config(proveedor);
    if (!c.llave) {
      return json({
        error: `Falta la llave del proveedor "${proveedor}". ` +
          `Configúrala en Supabase → Project Settings → Edge Functions → Secrets.`,
      }, 400);
    }

    // 3) Consultar al modelo
    const t0 = Date.now();
    const resultados = proveedor === "anthropic"
      ? await pedirAnthropic(c, lineas)
      : await pedirOpenAICompatible(c, lineas);

    return json({
      resultados,
      proveedor,
      modelo: c.modelo,
      ms: Date.now() - t0,
    });
  } catch (e) {
    // El mensaje sube a la app para que el usuario sepa qué pasó, en vez de
    // ver un fallo mudo.
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}
