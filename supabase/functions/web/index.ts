// Edge Function: web — RETIRADA (2026-09-02)
//
// Servía la app Flutter desde el bucket `webapp` de Storage. Ya no aplica:
// la app se publica en Cloudflare Pages (https://inventario-proplas.pages.dev)
// y el bucket `webapp` fue eliminado, así que esto solo devolvía 404.
//
// POR QUÉ ERA UN RIESGO
// Quedó con verify_jwt=false, o sea invocable por cualquiera sin
// credenciales. Cada petición —incluidos los 404— consume una invocación
// de la cuota gratis, que es de 500.000/mes POR ORGANIZACIÓN, no por
// proyecto: quemarla aquí afectaría a todos los proyectos de la cuenta.
// Además leía Storage con el SERVICE_ROLE_KEY.
//
// QUÉ SE HIZO
// Se cerró con verify_jwt=true: el gateway de Supabase ahora rechaza las
// peticiones anónimas ANTES de ejecutar este código, así que un curl suelto
// ya no gasta invocaciones. El cuerpo se vació para que no quede código con
// el service_role rondando.
//
// PARA ELIMINARLA DEL TODO (recomendado):
//   supabase functions delete web --project-ref nyvaswimcxbqxnlcnxij
//
// PARA REVIVIRLA: el código original está en el historial de git
// (supabase/functions/web/index.ts, antes del 2026-09-02).

Deno.serve(() =>
  new Response(
    JSON.stringify({
      estado: "retirada",
      mensaje: "Esta función ya no se usa. La app está en Cloudflare Pages.",
      url: "https://inventario-proplas.pages.dev",
    }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  )
);
