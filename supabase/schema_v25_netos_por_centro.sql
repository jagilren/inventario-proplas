-- =====================================================================
--  INVENTARIO PROPLAS · schema_v25 · NETOS POR CENTRO DE COSTO
--
--  Responde la pregunta que ningun informe respondia: cuanto se llevo de
--  verdad un centro de costo, restando lo que devolvio.
--
--  El informe "Consumo por centro de costo" solo miraba tipo='salida', asi
--  que si un centro se llevaba 100 y devolvia 30, decia que consumio 100.
--
--  ADEMAS corrige como se valoriza:
--  cada movimiento GUARDA su costo_unitario (el promedio que el articulo
--  tenia en ese instante). El informe viejo, en cambio, valorizaba al
--  promedio de HOY — y cuando un articulo se agota su promedio queda en 0,
--  asi que esas salidas aparecian costando $0.
--  Medido sobre los datos reales: $945.686 con el metodo viejo contra
--  $2.210.937 al costo real. Subvaloraba el 57%, con 20 salidas en cero.
--
--  Aqui se usa costo_unitario y solo se cae al promedio actual si faltara.
-- =====================================================================

create or replace function public.netos_por_centro(
    p_desde timestamptz,
    p_hasta timestamptz
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
    valor_neto         numeric
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
            -- El costo con el que se movio de verdad. El coalesce es una red
            -- por si algun movimiento viejo no lo tuviera.
            coalesce(m.costo_unitario, e.costo_promedio) as costo
        from movimientos m
        join elementos e            on e.id = m.elemento_id
        left join centros_costo cc  on cc.id = m.centro_costo_id
        where m.centro_costo_id is not null
          and m.fecha >= p_desde
          and m.fecha <  p_hasta
          and not coalesce(e.es_aprovechamiento, false)
          -- Salidas, y entradas atribuidas a un centro (las devoluciones).
          and m.tipo in ('salida', 'entrada')
    )
    select
        centro,
        descripcion,
        elemento,
        unidad,
        sum(cantidad) filter (where tipo = 'salida')  as salidas,
        sum(cantidad) filter (where tipo = 'entrada') as devoluciones,
        -- Neto: lo que se llevo menos lo que devolvio.
        coalesce(sum(cantidad) filter (where tipo = 'salida'), 0)
          - coalesce(sum(cantidad) filter (where tipo = 'entrada'), 0) as neto,
        round(coalesce(sum(cantidad * costo) filter (where tipo = 'salida'), 0))
            as valor_salidas,
        round(coalesce(sum(cantidad * costo) filter (where tipo = 'entrada'), 0))
            as valor_devoluciones,
        round(
            coalesce(sum(cantidad * costo) filter (where tipo = 'salida'), 0)
          - coalesce(sum(cantidad * costo) filter (where tipo = 'entrada'), 0)
        ) as valor_neto
    from movs
    group by centro, descripcion, elemento, unidad
    order by centro, elemento;
$function$;
