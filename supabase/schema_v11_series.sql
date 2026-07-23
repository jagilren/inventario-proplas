-- =====================================================================
--  INVENTARIO PROPLAS · schema_v11 · SERIALIZADO (elementos con serial)
--  Aplicar en Supabase y REINICIAR el API. Crear objetos UNA sola vez.
-- =====================================================================

-- 1) Bandera por elemento
alter table elementos add column if not exists serializado boolean not null default false;

-- 2) Unidades serializadas (una fila = una unidad física)
create table if not exists series (
    id                 uuid primary key default uuid_generate_v4(),
    elemento_id        uuid not null references elementos(id) on delete cascade,
    serial             text not null,
    bodega_id          uuid references bodegas(id),
    estado             text not null default 'disponible'
                       check (estado in ('disponible','consumido')),
    costo              numeric(18,4) not null default 0,
    fecha_ingreso      timestamptz not null default now(),
    movimiento_ingreso uuid references movimientos(id),
    movimiento_salida  uuid references movimientos(id),
    creado_en          timestamptz not null default now(),
    unique (elemento_id, serial)
);
create index if not exists idx_series_disp on series (elemento_id, bodega_id, estado);

-- 3) Traza: qué seriales tocó cada movimiento
create table if not exists movimiento_series (
    movimiento_id uuid not null references movimientos(id) on delete cascade,
    serie_id      uuid not null references series(id) on delete cascade,
    primary key (movimiento_id, serie_id)
);

-- 4) Recalcular existencias de un serializado desde la tabla series
create or replace function public._recompute_serie_bodega(p_el uuid, p_bod uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cnt numeric; v_costo numeric;
begin
    if p_bod is null then return; end if;
    select count(*), coalesce(avg(costo), 0) into v_cnt, v_costo
      from series where elemento_id = p_el and bodega_id = p_bod and estado = 'disponible';
    if v_cnt > 0 then
        insert into existencias(elemento_id, bodega_id, existencia, costo_promedio, updated_at)
            values (p_el, p_bod, v_cnt, v_costo, now())
        on conflict (elemento_id, bodega_id) do update
            set existencia = excluded.existencia, costo_promedio = excluded.costo_promedio,
                updated_at = now();
    else
        update existencias set existencia = 0, costo_promedio = 0, updated_at = now()
          where elemento_id = p_el and bodega_id = p_bod;
    end if;
end; $$;

create or replace function public.fn_sync_existencia_serie()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_el uuid;
begin
    v_el := coalesce(new.elemento_id, old.elemento_id);
    perform public._recompute_serie_bodega(v_el, coalesce(new.bodega_id, old.bodega_id));
    if tg_op = 'UPDATE' and new.bodega_id is distinct from old.bodega_id then
        perform public._recompute_serie_bodega(v_el, old.bodega_id);
    end if;
    -- Total del elemento (suma de todas las bodegas)
    update elementos e set
        existencia = coalesce((select sum(x.existencia) from existencias x where x.elemento_id = e.id), 0),
        costo_promedio = coalesce((
            select case when sum(x.existencia) > 0
                        then sum(x.existencia * x.costo_promedio) / sum(x.existencia) else 0 end
            from existencias x where x.elemento_id = e.id), 0),
        updated_at = now()
      where e.id = v_el;
    return null;
end; $$;

drop trigger if exists trg_sync_serie on series;
create trigger trg_sync_serie after insert or update or delete on series
    for each row execute function public.fn_sync_existencia_serie();

-- 5) aplicar_movimiento: para serializados el movimiento es solo el "log"
--    (existencias las maneja el trigger de series). Resto igual.
create or replace function public.aplicar_movimiento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    e_exist numeric(18,3);
    e_costo numeric(18,4);
    nueva_exist numeric(18,3);
begin
    if new.bodega_id is null then
        raise exception 'El movimiento requiere una bodega';
    end if;
    -- Serializados: no tocar existencias aquí (lo hace el trigger de series).
    if (select serializado from elementos where id = new.elemento_id) then
        return new;
    end if;

    select existencia, costo_promedio into e_exist, e_costo
      from existencias
     where elemento_id = new.elemento_id and bodega_id = new.bodega_id for update;
    if not found then e_exist := 0; e_costo := 0; end if;

    if new.tipo in ('inicial','entrada') then
        if new.costo_unitario is null then
            raise exception 'El costo_unitario es obligatorio en movimientos de tipo %', new.tipo;
        end if;
        nueva_exist := e_exist + new.cantidad;
        if nueva_exist > 0 then
            e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
        end if;
        e_exist := nueva_exist;
    elsif new.tipo = 'salida' then
        if new.cantidad > e_exist then
            raise exception 'Existencia insuficiente en la bodega: hay % y se intenta sacar %', e_exist, new.cantidad;
        end if;
        e_exist := e_exist - new.cantidad;
    elsif new.tipo = 'ajuste' then
        if new.cantidad >= 0 and new.costo_unitario is not null then
            nueva_exist := e_exist + new.cantidad;
            if nueva_exist > 0 then
                e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
            end if;
            e_exist := nueva_exist;
        else
            if abs(new.cantidad) > e_exist then
                raise exception 'Ajuste negativo mayor a la existencia (%): %', e_exist, new.cantidad;
            end if;
            e_exist := e_exist + new.cantidad;
        end if;
    end if;

    insert into existencias (elemento_id, bodega_id, existencia, costo_promedio, updated_at)
        values (new.elemento_id, new.bodega_id, e_exist, e_costo, now())
    on conflict (elemento_id, bodega_id) do update
        set existencia = excluded.existencia, costo_promedio = excluded.costo_promedio,
            updated_at = now();

    update elementos e set
        existencia = coalesce((select sum(x.existencia) from existencias x where x.elemento_id = e.id), 0),
        costo_promedio = coalesce((
            select case when sum(x.existencia) > 0
                        then sum(x.existencia * x.costo_promedio) / sum(x.existencia) else 0 end
            from existencias x where x.elemento_id = e.id), 0),
        updated_at = now()
      where e.id = new.elemento_id;
    return new;
end; $$;

-- 6) Mover seriales (entrada / salida / traslado) — atómico. Params en texto
--    para evitar líos de tipos con PostgREST.
create or replace function public.mover_serie(
    p_tipo text, p_elemento text, p_bodega text, p_serials text[],
    p_costo text default null, p_centro text default null,
    p_obs text default null, p_bodega_destino text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_el uuid := p_elemento::uuid;
    v_bod uuid := nullif(p_bodega, '')::uuid;
    v_dest uuid := nullif(p_bodega_destino, '')::uuid;
    v_costo numeric := coalesce(nullif(p_costo, '')::numeric, 0);
    v_centro uuid := nullif(p_centro, '')::uuid;
    v_mov uuid; v_mov2 uuid; v_tid uuid; v_serie uuid; s text;
    n int := coalesce(array_length(p_serials, 1), 0);
begin
    if n = 0 then raise exception 'Debes indicar al menos un serial'; end if;
    if p_tipo = 'entrada' and not (tiene_rol('admin') or tiene_rol('operario_mas')) then
        raise exception 'Sin permiso para entradas'; end if;
    if p_tipo = 'salida' and not (tiene_rol('admin') or tiene_rol('operario_menos')) then
        raise exception 'Sin permiso para salidas'; end if;
    if p_tipo = 'traslado' and not (tiene_rol('admin') or tiene_rol('coordinador')) then
        raise exception 'Sin permiso para traslados'; end if;

    if p_tipo = 'entrada' then
        insert into movimientos(tipo, elemento_id, bodega_id, cantidad, costo_unitario, observacion, usuario_id)
            values ('entrada', v_el, v_bod, n, v_costo, p_obs, auth.uid()) returning id into v_mov;
        foreach s in array p_serials loop
            insert into series(elemento_id, serial, bodega_id, estado, costo, movimiento_ingreso)
                values (v_el, s, v_bod, 'disponible', v_costo, v_mov) returning id into v_serie;
            insert into movimiento_series(movimiento_id, serie_id) values (v_mov, v_serie);
        end loop;

    elsif p_tipo = 'salida' then
        insert into movimientos(tipo, elemento_id, bodega_id, cantidad, centro_costo_id, observacion, usuario_id)
            values ('salida', v_el, v_bod, n, v_centro, p_obs, auth.uid()) returning id into v_mov;
        foreach s in array p_serials loop
            update series set estado = 'consumido', movimiento_salida = v_mov
              where elemento_id = v_el and serial = s and bodega_id = v_bod and estado = 'disponible'
              returning id into v_serie;
            if v_serie is null then raise exception 'Serial % no disponible en la bodega', s; end if;
            insert into movimiento_series(movimiento_id, serie_id) values (v_mov, v_serie);
        end loop;

    elsif p_tipo = 'traslado' then
        if v_dest is null or v_dest = v_bod then raise exception 'Bodega destino inválida'; end if;
        v_tid := uuid_generate_v4();
        insert into movimientos(tipo, elemento_id, bodega_id, cantidad, referencia, observacion, usuario_id, traslado_id)
            values ('salida', v_el, v_bod, n, 'TRASLADO', p_obs, auth.uid(), v_tid) returning id into v_mov;
        insert into movimientos(tipo, elemento_id, bodega_id, cantidad, costo_unitario, referencia, observacion, usuario_id, traslado_id)
            values ('entrada', v_el, v_dest, n, null, 'TRASLADO', p_obs, auth.uid(), v_tid) returning id into v_mov2;
        foreach s in array p_serials loop
            update series set bodega_id = v_dest
              where elemento_id = v_el and serial = s and bodega_id = v_bod and estado = 'disponible'
              returning id into v_serie;
            if v_serie is null then raise exception 'Serial % no disponible en la bodega origen', s; end if;
            insert into movimiento_series(movimiento_id, serie_id) values (v_mov, v_serie);
            insert into movimiento_series(movimiento_id, serie_id) values (v_mov2, v_serie);
        end loop;
    else
        raise exception 'Tipo % no soportado', p_tipo;
    end if;
end; $$;

-- 7) Serializar un elemento ya existente (cargar los seriales de sus unidades)
create or replace function public.serializar_elemento(p_elemento text, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_el uuid := p_elemento::uuid; it jsonb;
begin
    if not (tiene_rol('admin') or tiene_rol('coordinador')) then
        raise exception 'Solo admin o coordinador'; end if;
    update elementos set serializado = true where id = v_el;
    update existencias set existencia = 0, costo_promedio = 0 where elemento_id = v_el;
    for it in select * from jsonb_array_elements(p_items) loop
        insert into series(elemento_id, serial, bodega_id, estado, costo)
            values (v_el, it->>'serial', (it->>'bodega_id')::uuid, 'disponible',
                    coalesce((it->>'costo')::numeric, 0));
    end loop;
end; $$;

-- 8) RLS: lectura para autenticados; escritura solo por las RPC (security definer)
alter table series enable row level security;
alter table movimiento_series enable row level security;
drop policy if exists sel_series on series;
create policy sel_series on series for select to authenticated using (true);
drop policy if exists sel_movser on movimiento_series;
create policy sel_movser on movimiento_series for select to authenticated using (true);
