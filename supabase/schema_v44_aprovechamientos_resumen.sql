-- v44: el resumen de Aprovechamientos bajaba TODOS los trozos de la
-- historia (todos los elementos, incluidos los consumidos) para sumarlos
-- en Dart. Se repetía en cada movimiento de CUALQUIER usuario en TODA la
-- app, porque la pantalla escucha el aviso en vivo global. Se mueve la
-- agregación a Postgres: el cliente ya no baja una fila por trozo, solo
-- una fila por elemento.

create or replace function public.aprovechamientos_resumen()
returns table(
  elemento_id uuid,
  nombre text,
  unidad text,
  material text,
  sch text,
  codigo_barras text,
  disponibles bigint,
  total_disponible numeric,
  total_trozos bigint,
  ultima_creacion timestamptz
)
language sql
stable
as $$
  select
    e.id as elemento_id,
    e.nombre,
    e.unidad,
    e.material,
    e.sch,
    e.codigo_barras,
    count(*) filter (where t.longitud_actual > 0) as disponibles,
    coalesce(sum(t.longitud_actual) filter (where t.longitud_actual > 0), 0) as total_disponible,
    count(*) as total_trozos,
    max(t.creado_en) as ultima_creacion
  from aprovechamiento_trozos t
  join elementos e on e.id = t.elemento_id
  group by e.id, e.nombre, e.unidad, e.material, e.sch, e.codigo_barras;
$$;

-- Apoyan los dos listados paginados (histórico global y por elemento) que
-- reemplazan a las consultas sin límite.
create index if not exists idx_aprov_trozos_creado
  on aprovechamiento_trozos (creado_en desc);
create index if not exists idx_aprov_trozos_elemento_creado
  on aprovechamiento_trozos (elemento_id, creado_en desc);
