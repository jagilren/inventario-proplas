-- =====================================================================
--  INVENTARIO PROPLAS · schema_v37 · CENTRO DE COSTO ORIGEN (reasignación)
--
--  Caso real: llega una devolución de un centro (Tintexa NP00039), pero
--  el material se reasigna de una vez a otro centro (G000002), sin pasar
--  por bodega "sin dueño" en el medio. Se necesita UNA sola entrada
--  física (sube existencia una sola vez) que aparezca en "Neto por
--  Centro de Costo" en NEGATIVO para quien la devolvió y en POSITIVO
--  para quien se queda con la carga.
--
--  SIMULADO ANTES DE ESCRIBIR ESTO (transacciones con ROLLBACK, sin tocar
--  produccion). Se probaron y descartaron dos caminos:
--   1) Dos filas (salida+entrada, espejo de Traslados de bodega): la
--      existencia neta queda en CERO (las dos filas se cancelan) — no
--      hay una entrada real de 5 unidades como pide el negocio. Además,
--      si la bodega no tenia stock previo, la fila 'salida' revienta con
--      "Existencia insuficiente".
--   2) La misma pareja de filas, pero leyendo el costo_promedio del
--      elemento DESPUES de la salida: ese costo queda corrupto en $0,
--      porque la salida vacía momentaneamente el unico saldo del
--      elemento y el promedio se recalcula a 0 antes de que la segunda
--      fila alcance a leerlo. Mismo mecanismo que ya midió el bug del
--      "57% del consumo subvalorado" en schema_v29/consumoPorCentro.
--
--  SOLUCION: una sola fila fisica ('entrada'), mas una columna nueva
--  que SOLO afecta el informe, nunca la existencia.
--
--  NOMENCLATURA (importante, para no invertir los signos):
--   - `centro_costo_id` (YA EXISTE, sin cambios de comportamiento): en
--     una entrada, sigue siendo "a quien se le abona/acredita" — en una
--     devolucion simple es quien devuelve (como hoy); en una reasignación
--     es el DESTINO (quien se queda con la carga). Aparece POSITIVO.
--   - `centro_costo_origen_id` (NUEVA): solo se usa cuando hay
--     reasignación. Aparece NEGATIVO, con el MISMO costo de la entrada
--     (confirmado con el usuario: "al mismo promedio que entra"). NO
--     genera ninguna fila propia en `movimientos` ni en el Kardex —
--     confirmado con el usuario que esta "fila huerfana" en la
--     trazabilidad es aceptable para este caso.
--   - `aplicar_movimiento()` NO se toca: nunca mira estas columnas de
--     centro, solo bodega/tipo/cantidad/costo. Por eso no hay riesgo de
--     que esto duplique o cancele existencias — solo hay una fila fisica.
-- =====================================================================

alter table movimientos
  add column if not exists centro_costo_origen_id uuid references centros_costo(id);

-- Defensivo: hoy solo tiene sentido en una entrada. Si algun dia aplica
-- a otro tipo, se relaja aqui a proposito, no por descuido.
-- (Postgres no soporta "ADD CONSTRAINT IF NOT EXISTS": se guarda con un
-- bloque que revisa pg_constraint primero, para que la migracion se
-- pueda re-aplicar sin reventar.)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'chk_centro_origen_solo_entrada'
  ) then
    alter table movimientos
      add constraint chk_centro_origen_solo_entrada
      check (centro_costo_origen_id is null or tipo = 'entrada');
  end if;
end $$;

create index if not exists idx_mov_cc_origen on movimientos (centro_costo_origen_id);

-- El candado de inmutabilidad tiene que aprender la columna nueva. Sin
-- esto, se podria re-enganchar la reasignación a otro centro con un
-- simple UPDATE — el mismo hueco que casi se cuela con anula_movimiento_id
-- en schema_v36.
create or replace function public.fn_mov_solo_observacion()
returns trigger language plpgsql as $function$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.centro_costo_origen_id, new.referencia,
      new.usuario_id, new.fecha, new.traslado_id, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.centro_costo_origen_id, old.referencia,
      old.usuario_id, old.fecha, old.traslado_id, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $function$;

-- netos_por_centro: se agrega una segunda rama (UNION ALL) que trata la
-- reasignación como si fuera una 'salida' del centro origen, SOLO para
-- efectos del informe. No inserta nada en movimientos ni toca
-- existencias — usa el mismo m.fecha/usuario/costo de la entrada real,
-- asi que sigue siendo trazable hasta ESA fila (aunque no tenga fila
-- propia, como se acordó).
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
        -- Rama normal: cada movimiento aporta a SU PROPIO centro_costo_id.
        -- Sin cambios respecto a como funcionaba hasta schema_v31.
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

        union all

        -- NUEVA rama (schema_v37): la mitad "que resta" de una entrada
        -- con reasignación. Mismo costo con que entró (pedido explícito
        -- del usuario), tratada como 'salida' solo para el neto — sin
        -- fila propia en movimientos.
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
--  Para revertir:
--    drop function netos_por_centro (revertir al cuerpo de schema_v31)
--    drop function fn_mov_solo_observacion (revertir al de schema_v36)
--    alter table movimientos drop constraint chk_centro_origen_solo_entrada
--    alter table movimientos drop column centro_costo_origen_id
-- =====================================================================
