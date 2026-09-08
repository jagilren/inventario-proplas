-- v45: "Neto por Centro de Costo" agrupa muchos movimientos en una sola
-- fila (por centro+elemento), así que nunca hubo una sola observación que
-- mostrar. Se agrega "observaciones": concatena la de CADA movimiento del
-- grupo, más reciente primero, cada una con su fecha entre paréntesis
-- (hora Colombia), separadas por "||". Mismo criterio que ya usaba
-- "usuarios" (agregación en la propia consulta, sin bajar filas crudas).

-- Cambia el tipo de retorno (columna nueva): CREATE OR REPLACE no lo
-- permite, hay que borrar la función y volver a crearla.
drop function if exists public.netos_por_centro(timestamptz, timestamptz, uuid);

create function public.netos_por_centro(
  p_desde timestamp with time zone,
  p_hasta timestamp with time zone,
  p_centro uuid default null::uuid
)
returns table(
  centro text, descripcion text, elemento text, unidad text,
  salidas numeric, devoluciones numeric, neto numeric,
  valor_salidas numeric, valor_devoluciones numeric, valor_neto numeric,
  primera_fecha timestamp with time zone, ultima_fecha timestamp with time zone,
  usuarios text, observaciones text
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
            m.observacion                            as observacion,
            pr.email                                 as email,
            coalesce(m.costo_unitario, e.costo_promedio) as costo
        from movimientos m
        join elementos e            on e.id = m.elemento_id
        left join centros_costo cc  on cc.id = m.centro_costo_id
        left join profiles pr       on pr.id = m.usuario_id
        where m.centro_costo_id is not null
          and (p_centro is null or m.centro_costo_id = p_centro)
          and m.fecha >= p_desde
          and m.fecha <  p_hasta
          and not coalesce(e.es_aprovechamiento, false)
          and m.tipo in ('salida', 'entrada')
          and not exists (
                select 1 from movimientos r where r.anula_movimiento_id = m.id
              )
    )
    select
        centro, descripcion, elemento, unidad,
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
        ) as usuarios,
        coalesce(
            string_agg(
                '(' || to_char(fecha at time zone 'America/Bogota', 'DD/MM/YYYY HH24:MI') || ') ' || observacion,
                '||' order by fecha desc
            ) filter (where observacion is not null and btrim(observacion) <> ''),
            ''
        ) as observaciones
    from movs
    group by centro, descripcion, elemento, unidad
    order by centro, elemento;
$function$;

grant execute on function public.netos_por_centro(timestamptz, timestamptz, uuid) to public;
