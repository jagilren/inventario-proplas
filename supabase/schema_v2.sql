-- =====================================================================
--  INVENTARIO PROPLAS · schema_v2  (pulido v1)
--  Pegar en Supabase -> SQL Editor -> Run.  Idempotente.
-- =====================================================================

-- ---- 1) RESUMEN para el dashboard -----------------------------------
create or replace function public.resumen_inventario()
returns table (
    total_elementos    bigint,
    valorizacion_total numeric,
    bajo_minimo        bigint,
    total_movimientos  bigint
) language sql stable as $$
    select
        (select count(*) from elementos where activo),
        (select coalesce(sum(existencia * costo_promedio), 0) from elementos where activo),
        (select count(*) from elementos
           where activo and stock_minimo > 0 and existencia <= stock_minimo),
        (select count(*) from movimientos);
$$;

-- ---- 2) ÚLTIMOS movimientos (para el dashboard) ---------------------
create or replace function public.ultimos_movimientos(p_limit int default 15)
returns table (
    fecha timestamptz, tipo text, cantidad numeric,
    elemento text, unidad text, centro_costo text
) language sql stable as $$
    select m.fecha, m.tipo, m.cantidad, e.nombre, e.unidad, cc.codigo
    from movimientos m
    join elementos e on e.id = m.elemento_id
    left join centros_costo cc on cc.id = m.centro_costo_id
    order by m.created_at desc
    limit p_limit;
$$;

-- ---- 2b) KARDEX con id de movimiento (para poder anular) ------------
drop function if exists public.kardex_elemento(uuid);
create or replace function public.kardex_elemento(p_elemento uuid)
returns table (
    id uuid, fecha timestamptz, tipo text, cantidad numeric,
    costo_unitario numeric, centro_costo text, referencia text, observacion text
) language sql stable as $$
    select m.id, m.fecha, m.tipo, m.cantidad, m.costo_unitario,
           cc.codigo, m.referencia, m.observacion
    from movimientos m
    left join centros_costo cc on cc.id = m.centro_costo_id
    where m.elemento_id = p_elemento
    order by m.fecha desc, m.created_at desc;
$$;

-- ---- 3) ANULAR un movimiento (solo admin, reversa auditable) --------
-- No borra: inserta un 'ajuste' que compensa el efecto en existencias.
create or replace function public.anular_movimiento(p_mov uuid, p_motivo text default null)
returns void language plpgsql security definer as $$
declare
    m record;
    es_admin boolean;
    signo numeric;
begin
    select exists(select 1 from profiles where id = auth.uid() and rol = 'admin')
      into es_admin;
    if not es_admin then
        raise exception 'Solo un administrador puede anular movimientos';
    end if;

    select * into m from movimientos where id = p_mov;
    if not found then
        raise exception 'Movimiento no encontrado';
    end if;
    if m.referencia is not null and m.referencia like 'ANULACION%' then
        raise exception 'Ese movimiento ya es una anulación';
    end if;

    -- Si entró (inicial/entrada), la reversa resta; si salió, la reversa suma.
    if m.tipo in ('inicial','entrada') then
        signo := -1;
    else
        signo := 1;
    end if;

    insert into movimientos(tipo, elemento_id, centro_costo_id, cantidad,
                            costo_unitario, referencia, observacion, usuario_id)
    values ('ajuste', m.elemento_id, m.centro_costo_id, signo * abs(m.cantidad),
            m.costo_unitario, 'ANULACION ' || left(p_mov::text, 8),
            coalesce(p_motivo, 'Anulación de movimiento'), auth.uid());
end; $$;
