-- schema_v53_valorizado_excluir_inactivos
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260910021212): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- El valorizado de equipos por bodega contaba cosas que no debía.
--
-- 1. Equipos cuya REFERENCIA está desactivada. Desactivar una referencia es
--    sacar ese modelo del catálogo; sus unidades no deben seguir sumando al
--    valor de la bodega.
-- 2. Equipos dados de BAJA. Solo se excluía 'entregado', así que una unidad
--    de baja seguía sumando su valor. Si además nadie le bajaba el
--    porcentaje a 0, sumaba el valor completo de algo ya descartado.
--
-- El filtro va en un FILTER y no en el ON del LEFT JOIN, por la misma razón
-- que en la parte de inventario: puesto en el ON, la fila sobrevive igual al
-- left join y se termina sumando. Y el LEFT JOIN desde `bodegas` se conserva
-- para que una bodega sin equipos devuelva 0 y no desaparezca del informe.
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
           coalesce(sum(a.valor_actual) filter (
             where a.estado not in ('entregado', 'baja')
               and coalesce(r.activo, true)
           ), 0) as valor
    from bodegas b
    left join activos a on a.bodega_id = b.id
    left join activo_referencias r on r.id = a.referencia_id
    where b.activo
    group by b.id
  )
  select inv.nombre, inv.valor, eq.valor, inv.valor + eq.valor
  from inv join eq using (id)
  order by inv.nombre;
$fn$;
