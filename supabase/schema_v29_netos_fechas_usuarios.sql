-- =====================================================================
--  INVENTARIO PROPLAS · schema_v29 · NETOS CON VENTANA Y USUARIOS
--  Aplicado en produccion el 2026-08-11
--  (migracion: netos_por_centro_con_fechas_y_usuarios)
--
--  Regla del usuario: todo informe que implique movimientos debe decir la
--  fecha del movimiento y quien lo ejecuto.
--
--  El problema aqui es que "Neto por centro de costo" NO lista movimientos:
--  cada fila RESUME muchos (todas las salidas menos todas las devoluciones
--  de un elemento en un centro, en todo el rango). Puede haber 20 salidas
--  de 4 personas distintas en 3 meses en un solo renglon, asi que no existe
--  "la" fecha ni "el" usuario de la fila.
--
--  En vez de inventar un dato, se devuelve la ventana real:
--    primera_fecha · ultima_fecha · usuarios (lista sin repetir)
--  Asi el resumen queda rastreable sin dejar de ser resumen. Para el detalle
--  movimiento por movimiento estan "Movimientos por fecha" y "Consumo por
--  centro de costo".
--
--  La firma cambia (3 columnas nuevas), y eso obliga a soltar la funcion
--  antes: CREATE OR REPLACE no puede cambiar el tipo de retorno.
--  El resto del cuerpo es identico a schema_v25 (costo_unitario y demas).
-- =====================================================================

drop function if exists public.netos_por_centro(timestamptz, timestamptz);

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
            -- El costo con el que se movio de verdad. El coalesce es una red
            -- por si algun movimiento viejo no lo tuviera.
            coalesce(m.costo_unitario, e.costo_promedio) as costo
        from movimientos m
        join elementos e            on e.id = m.elemento_id
        left join centros_costo cc  on cc.id = m.centro_costo_id
        left join profiles pr       on pr.id = m.usuario_id
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
        ) as valor_neto,
        min(fecha) as primera_fecha,
        max(fecha) as ultima_fecha,
        -- Quienes movieron este elemento en este centro, sin repetir.
        coalesce(
            string_agg(distinct email, ', ') filter (where email is not null),
            ''
        ) as usuarios
    from movs
    group by centro, descripcion, elemento, unidad
    order by centro, elemento;
$function$;
