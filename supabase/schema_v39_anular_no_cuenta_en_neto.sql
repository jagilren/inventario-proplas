-- =====================================================================
--  INVENTARIO PROPLAS · schema_v39 · ANULAR YA NO CUENTA EN NETO POR CENTRO
--
--  Al anular un movimiento, la reversa se registra como tipo='ajuste'
--  (para no romper la regla "solo entrada/salida cuentan"). Pero
--  `netos_por_centro` SOLO lee tipo in ('salida','entrada') -el 'ajuste'
--  de la reversa queda totalmente invisible para ese informe. Resultado:
--  el movimiento original seguia contando en el Neto del centro PARA
--  SIEMPRE, aunque ya estuviera anulado.
--
--  Medido antes de corregir: 4 anulaciones reales en produccion, todas
--  sobre entradas con centro G000002 -el numero de ese centro estaba
--  inflado en 6 unidades (1+1+2+2) que ya no deberian contar.
--
--  ARREGLO: excluir de netos_por_centro cualquier movimiento cuyo id
--  aparezca como `anula_movimiento_id` de otra fila -es decir, cualquier
--  movimiento que YA fue anulado, sin importar cuando. Se trata como si
--  nunca hubiera pasado, que es exactamente lo que "anular" significa.
--  El indice unico `movimientos_anula_uniq` (schema_v36) hace que esta
--  comprobacion sea un lookup de indice, no un escaneo.
--
--  Se aplica a las DOS ramas del UNION ALL (la normal y la de
--  centro_costo_origen_id de schema_v37): si se anula una entrada con
--  reasignacion, las dos mitades (destino positivo y origen negativo)
--  desaparecen juntas del informe, como debe ser.
--
--  Kardex y "Movimientos por fecha" NO se tocan: ahi se debe seguir
--  viendo el movimiento original Y su reversa, para la trazabilidad
--  completa -esto es solo para el RESUMEN neto por centro.
-- =====================================================================

create or replace function public.netos_por_centro(
  p_desde timestamp with time zone,
  p_hasta timestamp with time zone,
  p_centro uuid default null
)
returns table(
  centro text, descripcion text, elemento text, unidad text,
  salidas numeric, devoluciones numeric, neto numeric,
  valor_salidas numeric, valor_devoluciones numeric, valor_neto numeric,
  primera_fecha timestamp with time zone, ultima_fecha timestamp with time zone,
  usuarios text
)
language sql stable
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
          and (p_centro is null or m.centro_costo_id = p_centro)
          and m.fecha >= p_desde
          and m.fecha <  p_hasta
          and not coalesce(e.es_aprovechamiento, false)
          and m.tipo in ('salida', 'entrada')
          -- NUEVO schema_v39: si este movimiento ya fue anulado, no cuenta.
          and not exists (
                select 1 from movimientos r where r.anula_movimiento_id = m.id
              )

        union all

        select
            coalesce(cc.codigo, '(sin centro)')      as centro,
            coalesce(cc.descripcion, '')             as descripcion,
            e.nombre                                 as elemento,
            e.unidad                                 as unidad,
            'salida'                                 as tipo,
            m.cantidad,
            m.fecha,
            pr.email                                 as email,
            coalesce(m.costo_unitario, e.costo_promedio) as costo
        from movimientos m
        join elementos e            on e.id = m.elemento_id
        left join centros_costo cc  on cc.id = m.centro_costo_origen_id
        left join profiles pr       on pr.id = m.usuario_id
        where m.centro_costo_origen_id is not null
          and (p_centro is null or m.centro_costo_origen_id = p_centro)
          and m.fecha >= p_desde
          and m.fecha <  p_hasta
          and not coalesce(e.es_aprovechamiento, false)
          and m.tipo = 'entrada'
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
        ) as usuarios
    from movs
    group by centro, descripcion, elemento, unidad
    order by centro, elemento;
$function$;

-- =====================================================================
--  Para revertir: quitar las dos clausulas "and not exists (...)" y
--  volver a como estaba en schema_v37.
-- =====================================================================
