-- =====================================================================
--  INVENTARIO PROPLAS · schema_v15
--  El inventario OFICIAL nunca muestra los elementos marcados como
--  es_aprovechamiento (esos viven en el módulo de Aprovechamientos).
--  Se excluyen del buscador, del resumen y de los últimos movimientos.
-- =====================================================================

-- ---- Buscador de elementos: excluir aprovechamiento -----------------
create or replace function public.buscar_elementos(q text)
returns setof elementos
language sql
stable
as $function$
    select e.*
    from elementos e
    where e.activo
      and not coalesce(e.es_aprovechamiento, false)
      and (
        q is null or btrim(q) = ''
        or (
            select bool_and(
                case
                    when w ~ '^[a-z]$'
                        then t.texto ~ ('\m' || w || '\M')
                    else
                        t.texto like '%' || w || '%'
                end
            )
            from unnest(
                    regexp_split_to_array(lower(public.f_unaccent(btrim(q))), '\s+')
                 ) as w,
                 lateral (
                    select lower(public.f_unaccent(
                        coalesce(e.nombre, '')   || ' ' ||
                        coalesce(e.material, '') || ' ' ||
                        coalesce(e.sch, '')      || ' ' ||
                        coalesce(e.codigo_barras, '')
                    )) as texto
                 ) t
        )
      )
    order by e.nombre
    limit 100;
$function$;

-- ---- Resumen del tablero: excluir aprovechamiento -------------------
create or replace function public.resumen_inventario()
returns table (
    total_elementos    bigint,
    valorizacion_total numeric,
    bajo_minimo        bigint,
    total_movimientos  bigint
) language sql stable as $$
    select
        (select count(*) from elementos
           where activo and not coalesce(es_aprovechamiento, false)),
        (select coalesce(sum(existencia * costo_promedio), 0) from elementos
           where activo and not coalesce(es_aprovechamiento, false)),
        (select count(*) from elementos
           where activo and not coalesce(es_aprovechamiento, false)
             and stock_minimo > 0 and existencia <= stock_minimo),
        (select count(*) from movimientos m
           join elementos e on e.id = m.elemento_id
           where not coalesce(e.es_aprovechamiento, false));
$$;

-- ---- Últimos movimientos del tablero: excluir aprovechamiento -------
create or replace function public.ultimos_movimientos(p_limit int default 15)
returns table (
    fecha timestamptz, tipo text, cantidad numeric,
    elemento text, unidad text, centro_costo text
) language sql stable as $$
    select m.fecha, m.tipo, m.cantidad, e.nombre, e.unidad, cc.codigo
    from movimientos m
    join elementos e on e.id = m.elemento_id
    left join centros_costo cc on cc.id = m.centro_costo_id
    where not coalesce(e.es_aprovechamiento, false)
    order by m.created_at desc
    limit p_limit;
$$;
