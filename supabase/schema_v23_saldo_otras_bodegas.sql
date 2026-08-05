-- =====================================================================
--  INVENTARIO PROPLAS · schema_v23
--  La validación de salida masiva ahora dice también CUÁNTO hay del
--  artículo en las OTRAS bodegas.
--
--  El problema que resuelve: si pides 12 y en la bodega elegida no hay
--  ninguno, antes se veía "hay 0 · faltan 12" — exactamente igual que un
--  artículo que no existe en ninguna parte. Pero puede haber 50 en otra
--  bodega, y en ese caso lo que hace falta no es comprar ni corregir el
--  archivo: es trasladar, o despachar desde la otra bodega.
--
--  Sin este dato el usuario no tiene cómo distinguir los dos casos.
-- =====================================================================

drop function if exists public.validar_salida_masiva(uuid, jsonb);

create or replace function public.validar_salida_masiva(
    p_bodega uuid,
    p_items  jsonb
)
returns table (
    elemento_id   uuid,
    nombre        text,
    unidad        text,
    pedido        numeric,
    disponible    numeric,   -- en la bodega elegida
    alcanza       boolean,
    en_otras      numeric,   -- total disponible en las demás bodegas
    otras_detalle text       -- "Bodega RPCI: 50" (solo las que tienen saldo)
)
language sql
stable
as $function$
    with pedido as (
        -- Agrupa por elemento: si el archivo trae el mismo artículo en dos
        -- líneas, lo que importa es la SUMA contra la existencia.
        select (it->>'elemento_id')::uuid      as eid,
               sum((it->>'cantidad')::numeric) as cant
        from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) it
        where (it->>'elemento_id') is not null
        group by 1
    ),
    otras as (
        select x.elemento_id,
               sum(x.existencia) as total,
               string_agg(
                   b.nombre || ': ' ||
                   trim(to_char(x.existencia, 'FM999999990.###')),
                   ' · ' order by x.existencia desc) as detalle
        from existencias x
        join bodegas b on b.id = x.bodega_id
        where x.bodega_id is distinct from p_bodega
          and x.existencia > 0
        group by x.elemento_id
    )
    select p.eid,
           e.nombre,
           e.unidad,
           p.cant,
           coalesce(x.existencia, 0),
           coalesce(x.existencia, 0) >= p.cant,
           coalesce(o.total, 0),
           o.detalle
    from pedido p
    join elementos e on e.id = p.eid
    left join existencias x
           on x.elemento_id = p.eid
          and x.bodega_id   = p_bodega
    left join otras o on o.elemento_id = p.eid
    -- Primero lo que NO alcanza: es lo que el usuario tiene que resolver.
    order by (coalesce(x.existencia, 0) >= p.cant), e.nombre;
$function$;
