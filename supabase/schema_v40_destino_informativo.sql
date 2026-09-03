-- =====================================================================
--  INVENTARIO PROPLAS · schema_v40 · DESTINO PASA A SER INFORMATIVO
--
--  schema_v37 modelaba una devolución con reasignación como: el ORIGEN
--  (quien devuelve) resta en "Neto por Centro de Costo" (como si fuera
--  una salida propia), y el DESTINO suma (como si fuera una devolución).
--  Eso era exactamente lo que el usuario pidió en su momento, y se probó
--  contra datos reales — pero al simular un caso con salidas REALES
--  previas hacia el mismo origen, el resultado no cuadraba con la
--  aritmética esperada: 10 salidas reales + esta "resta" del origen
--  daban -13, cuando el negocio esperaba -7 (10 tomadas - 3 devueltas).
--
--  LA REGLA CORRECTA (confirmada por el usuario 2026-09-03):
--   - El ORIGEN (quien devuelve) SIEMPRE suma — es una devolución
--     normal, punto. Exactamente el mecanismo que `centro_costo_id` ya
--     tenía ANTES de que existiera esta funcionalidad. No hace falta
--     ningún truco nuevo para esto.
--   - El DESTINO (a quién se reasigna el material) NO tiene ningún
--     efecto en "Neto por Centro de Costo". Las unidades simplemente
--     entran al inventario general de la bodega (eso ya pasa solo, es
--     pura física). El destino queda como referencia informativa/de
--     trazabilidad (Kardex, "Movimientos por fecha"), nada más. Si ese
--     centro alguna vez saca el material de verdad, se refleja con una
--     SALIDA normal — el mecanismo de siempre, sin nada especial.
--
--  Como el campo ya NO guarda "quien devuelve" (eso vuelve a vivir en
--  `centro_costo_id`, sin cambios), sino "a quién se reasigna", se
--  renombra de `centro_costo_origen_id` a `centro_costo_destino_id`.
--  Dejarlo con el nombre viejo habría sido la misma trampa de
--  nomenclatura que ya mordió una vez esta sesión (ver
--  pgrst201-doble-fk-centros-costo): un campo llamado "origen"
--  guardando en realidad el destino.
--
--  Verificado antes de renombrar: CERO filas reales en producción usan
--  `centro_costo_origen_id` todavía (toda la validación de esta
--  funcionalidad se hizo en transacciones ROLLBACK) — el rename no
--  reinterpreta ningún dato real.
-- =====================================================================

alter table movimientos
  rename column centro_costo_origen_id to centro_costo_destino_id;

alter table movimientos
  rename constraint movimientos_centro_costo_origen_id_fkey
  to movimientos_centro_costo_destino_id_fkey;

alter index idx_mov_cc_origen rename to idx_mov_cc_destino;

alter table movimientos drop constraint chk_centro_origen_solo_entrada;
alter table movimientos
  add constraint chk_centro_destino_solo_entrada
  check (centro_costo_destino_id is null or tipo = 'entrada');

-- El candado de inmutabilidad, con el nombre de columna actualizado.
create or replace function public.fn_mov_solo_observacion()
returns trigger language plpgsql as $function$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.centro_costo_destino_id, new.referencia,
      new.usuario_id, new.fecha, new.traslado_id, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.centro_costo_destino_id, old.referencia,
      old.usuario_id, old.fecha, old.traslado_id, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $function$;

-- netos_por_centro: se QUITA la rama sintética de schema_v37 (el destino
-- ya no aporta nada al informe). Vuelve a ser una sola rama, igual que en
-- schema_v31, pero CONSERVANDO el arreglo de schema_v39 (un movimiento
-- anulado no cuenta).
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
--  Para revertir: volver a agregar la rama UNION ALL de schema_v37/v39
--  usando centro_costo_destino_id, y renombrar la columna de vuelta.
-- =====================================================================
