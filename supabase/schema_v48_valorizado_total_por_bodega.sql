-- schema_v48_valorizado_total_por_bodega
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909171628): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Valorizado total por bodega: inventario + equipos, la única vista que
-- cruza los dos módulos (sección 9.1 del plan).
--
-- NUNCA se unen las filas crudas de `existencias` y `activos`: son formas de
-- datos incompatibles (cantidad × costo promedio vs. valor fijo por unidad
-- serializada). Se agrega cada mundo por separado y se suman los totales,
-- unidos solo por bodega_id.
--
-- Los aprovechamientos se excluyen con un FILTER y no en el ON del join:
-- puesto en el ON, la fila de existencia sobrevive igual al LEFT JOIN y se
-- terminaría sumando, que es justo lo contrario de lo que se busca.
-- Mismo criterio que el informe "Existencias valorizadas" ya existente.
create or replace function public.valorizado_total_por_bodega()
returns table(
  bodega text,
  valorizado_inventario numeric,
  valorizado_equipos numeric,
  valorizado_total numeric
)
language sql
stable
as $fn$
  with inv as (
    select b.id, b.nombre,
           coalesce(sum(x.existencia * x.costo_promedio)
                    filter (where not coalesce(e.es_aprovechamiento, false)), 0) as valor
    from bodegas b
    left join existencias x on x.bodega_id = b.id
    left join elementos e on e.id = x.elemento_id
    where b.activo
    group by b.id, b.nombre
  ),
  eq as (
    select b.id,
           coalesce(sum(a.valor_actual), 0) as valor
    from bodegas b
    left join activos a on a.bodega_id = b.id and a.estado <> 'entregado'
    where b.activo
    group by b.id
  )
  select inv.nombre, inv.valor, eq.valor, inv.valor + eq.valor
  from inv join eq using (id)
  order by inv.nombre;
$fn$;
