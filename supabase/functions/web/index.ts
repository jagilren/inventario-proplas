// Edge Function: web
// Sirve la app Flutter (build/web) desde Storage con el content-type correcto.
// Necesario porque Storage entrega el HTML como text/plain y el navegador
// no lo renderiza. Esta función actúa de intermediario.
const BUCKET = "webapp";
// Supabase recorta "/functions/v1" antes de invocar la función, así que la
// ruta puede llegar como "/web/archivo" o como "/functions/v1/web/archivo".
const PREFIJOS = ["/functions/v1/web", "/web"];

const TIPOS: Record<string, string> = {
  html: "text/html; charset=utf-8",
  js: "application/javascript; charset=utf-8",
  mjs: "application/javascript; charset=utf-8",
  json: "application/json; charset=utf-8",
  css: "text/css; charset=utf-8",
  png: "image/png",
  jpg: "image/jpeg",
  svg: "image/svg+xml",
  ico: "image/x-icon",
  wasm: "application/wasm",
  otf: "font/otf",
  ttf: "font/ttf",
  woff: "font/woff",
  woff2: "font/woff2",
  bin: "application/octet-stream",
  symbols: "text/plain; charset=utf-8",
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  let ruta = url.pathname;
  for (const p of PREFIJOS) {
    if (ruta.startsWith(p)) { ruta = ruta.slice(p.length); break; }
  }
  ruta = ruta.replace(/^\/+/, "");
  if (ruta === "") ruta = "index.html";

  const base = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const r = await fetch(`${base}/storage/v1/object/${BUCKET}/${ruta}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });

  if (!r.ok) {
    // rutas desconocidas -> index.html (la app maneja su navegación)
    if (!ruta.includes(".")) {
      const idx = await fetch(`${base}/storage/v1/object/${BUCKET}/index.html`, {
        headers: { apikey: key, Authorization: `Bearer ${key}` },
      });
      return new Response(idx.body, {
        status: idx.ok ? 200 : 404,
        headers: { "Content-Type": TIPOS.html, "Cache-Control": "no-cache" },
      });
    }
    return new Response("No encontrado: " + ruta, { status: 404 });
  }

  const ext = ruta.split(".").pop()?.toLowerCase() ?? "";
  return new Response(r.body, {
    status: 200,
    headers: {
      "Content-Type": TIPOS[ext] ?? "application/octet-stream",
      "Cache-Control": ext === "html" ? "no-cache" : "public, max-age=3600",
      "Access-Control-Allow-Origin": "*",
    },
  });
});
