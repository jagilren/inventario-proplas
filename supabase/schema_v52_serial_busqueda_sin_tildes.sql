-- schema_v52_serial_busqueda_sin_tildes
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909221437): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Buscar un serial ignorando tildes Y mayúsculas.
--
-- `ilike` ya ignoraba mayúsculas, pero NO tildes: buscar "motor-nu-01" no
-- encontraba "MOTOR-ÑÚ-01". Verificado con datos, no supuesto.
--
-- Se resuelve con una columna GENERADA en vez de normalizar en cada consulta:
-- así se puede INDEXAR, que es lo que hace que la búsqueda siga siendo rápida
-- con miles de unidades de una misma referencia. Normalizar al vuelo obligaría
-- a recorrer la tabla entera en cada búsqueda.

-- unaccent() es STABLE, y una columna generada exige IMMUTABLE. El envoltorio
-- fija el diccionario explícitamente, que es lo que la vuelve determinista.
create or replace function public.f_unaccent(text)
returns text language sql immutable parallel safe strict as
$$ select public.unaccent('public.unaccent', $1) $$;

alter table activos
  add column if not exists serial_busqueda text
  generated always as (upper(public.f_unaccent(serial))) stored;

-- text_pattern_ops: es el que sirve para los LIKE con comodín al final.
create index if not exists idx_activos_serial_busqueda
  on activos (serial_busqueda text_pattern_ops);

-- La vista hace `a.*`, así que hay que recrearla para que exponga la columna
-- nueva. No basta CREATE OR REPLACE: al aparecer una columna en medio,
-- Postgres lo rechaza porque cambiaría el orden de las existentes.
drop view if exists activos_disponibilidad;
create view activos_disponibilidad with (security_invoker = true) as
select a.*,
       au.bodega_id   as ubicacion_actual_bodega_id,
       au.tercero_id  as ubicacion_actual_tercero_id,
       au.fecha_desde as ubicacion_actual_desde,
       (a.estado = 'operativo' and au.bodega_id is not null) as disponible
from activos a
left join activo_ubicaciones au
  on au.activo_id = a.id and au.fecha_hasta is null;
