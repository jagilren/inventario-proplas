-- schema_v47_activos_resumen_por_referencia
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909170541): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Nivel 1 del Módulo de Equipos: una fila por modelo con sus contadores.
-- El conteo se hace en la base a propósito (GROUP BY), nunca bajando todas
-- las unidades a Dart — misma lección del resumen de Aprovechamientos.
--
-- SECURITY INVOKER (por defecto): la RLS de `activos` filtra sola, así que
-- quien no tenga acceso al módulo simplemente recibe cero filas.
create or replace function public.activos_resumen_por_referencia()
returns table(
  referencia_id uuid,
  nombre text,
  marca text,
  modelo text,
  total bigint,
  disponibles bigint
)
language sql
stable
as $fn$
  select r.id, r.nombre, r.marca, r.modelo,
         count(d.id) as total,
         count(*) filter (where d.disponible) as disponibles
  from activo_referencias r
  join activos_disponibilidad d on d.referencia_id = r.id
  group by r.id, r.nombre, r.marca, r.modelo
  order by r.nombre;
$fn$;
