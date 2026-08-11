-- =====================================================================
--  INVENTARIO PROPLAS · schema_v31 · NETOS FILTRABLE POR CENTRO
--  Aplicado en produccion el 2026-08-11
--  (migracion: netos_por_centro_filtro_opcional_centro)
--
--  Regla del usuario: todo informe que vaya POR centro de costo debe dejar
--  elegir el centro (con buscador), y si no se elige ninguno, trae TODOS.
--
--  netos_por_centro recibe ahora p_centro. Null = todos los centros, que es
--  exactamente el comportamiento que tenia antes, asi que nada se rompe.
--
--  El otro informe por centro ("Consumo por centro de costo") no necesita
--  migracion: se arma con PostgREST desde Dart y alli se agrega un .eq()
--  condicional.
--
--  Igual que en schema_v20 con buscar_elementos, hay que soltar la version
--  de 2 argumentos: si quedaran las dos, una llamada con solo las fechas
--  seria ambigua.
-- =====================================================================

drop function if exists public.netos_por_centro(timestamptz, timestamptz);
drop function if exists public.netos_por_centro(timestamptz, timestamptz, uuid);

create or replace function public.netos_por_centro(
    p_desde  timestamptz,
    p_hasta  timestamptz,
    p_centro uuid default null
)
returns table (
    centro             text,
    descripcion        text,
    elemento           text,
    unidad             text,
    salidas            numeric,
    devoluciones       numeric,
    neto               numeric,
    valor_salidas      numeric,
    valor_devoluciones numeric,
    valor_neto         numeric,
    primera_fecha      timestamptz,
    ultima_fecha       timestamptz,
    usuarios           text
)
language sql
stable
as $function$
    with movs as (
        select
            coalesce(cc.codigo, '(sin centro)')      as centro,
            coalesce(cc.descripcion, '')             as descripcion,
            e.nombre                                 as elemento,
            e.unidad                                 as unidad,
            m.tipo,
            m.cantidad,
            m.fecha,
            pr.email                                 as email,
            coalesce(m.costo_unitario, e.costo_promedio) as costo
        from movimientos m
        join elementos e            on e.id = m.elemento_id
        left join centros_costo cc  on cc.id = m.centro_costo_id
        left join profiles pr       on pr.id = m.usuario_id
        where m.centro_costo_id is not null
          -- Filtro opcional: null = todos los centros.
          and (p_centro is null or m.centro_costo_id = p_centro)
          and m.fecha >= p_desde
          and m.fecha <  p_hasta
          and not coalesce(e.es_aprovechamiento, false)
          and m.tipo in ('salida', 'entrada')
    )
    select
        centro,
        descripcion,
        elemento,
        unidad,
        sum(cantidad) filter (where tipo = 'salida')  as salidas,
        sum(cantidad) filter (where tipo = 'entrada') as devoluciones,
        coalesce(sum(cantidad) filter (where tipo = 'salida'), 0)
          - coalesce(sum(cantidad) filter (where tipo = 'entrada'), 0) as neto,
        round(coalesce(sum(cantidad * costo) filter (where tipo = 'salida'), 0))
            as valor_salidas,
        round(coalesce(sum(cantidad * costo) filter (where tipo = 'entrada'), 0))
            as valor_devoluciones,
        round(
            coalesce(sum(cantidad * costo) filter (where tipo = 'salida'), 0)
          - coalesce(sum(cantidad * costo) filter (where tipo = 'entrada'), 0)
        ) as valor_neto,
        min(fecha) as primera_fecha,
        max(fecha) as ultima_fecha,
        coalesce(
            string_agg(distinct email, ', ') filter (where email is not null),
            ''
        ) as usuarios
    from movs
    group by centro, descripcion, elemento, unidad
    order by centro, elemento;
$function$;
