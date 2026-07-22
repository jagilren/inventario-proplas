// Edge Function: crear-usuario
// Crea un usuario en Supabase Auth y le asigna roles.
// Solo un ADMIN (según usuario_roles) puede invocarla.
// Deploy:  supabase functions deploy crear-usuario
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey);

    // 1) identificar a quien llama (por su JWT) y verificar que es admin
    const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
    const { data: userData } = await admin.auth.getUser(jwt);
    const callerId = userData?.user?.id;
    if (!callerId) {
      return json({ error: "No autenticado" }, 401);
    }
    const { data: roles } = await admin
      .from("usuario_roles").select("rol")
      .eq("usuario_id", callerId).eq("rol", "admin");
    if (!roles || roles.length === 0) {
      return json({ error: "Solo un administrador puede crear usuarios" }, 403);
    }

    // 2) crear el usuario
    const { email, password, nombre, roles: nuevosRoles } = await req.json();
    if (!email || !password) {
      return json({ error: "Faltan email o contraseña" }, 400);
    }
    const { data: creado, error: e1 } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { nombre: nombre ?? email.split("@")[0] },
    });
    if (e1) return json({ error: e1.message }, 400);

    // 3) asignar roles
    const uid = creado.user.id;
    if (Array.isArray(nuevosRoles) && nuevosRoles.length > 0) {
      await admin.from("usuario_roles").insert(
        nuevosRoles.map((r: string) => ({ usuario_id: uid, rol: r })));
    }

    return json({ ok: true, id: uid });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
