-- =====================================================================
--  INVENTARIO PROPLAS · schema_v10 · MULTI-BODEGA (Fase 3)
--
--  Los elementos pueden estar en N bodegas. La existencia y el costo
--  promedio pasan a ser POR (elemento + bodega). elementos.existencia y
--  elementos.costo_promedio se mantienen como TOTAL (para la vista global).
--  Aplicar en Supabase (idempotente).
-- =====================================================================

-- ---- 1) BODEGAS ------------------------------------------------------
create table if not exists bodegas (
    id         uuid primary key default uuid_generate_v4(),
    nombre     text not null unique,
    codigo     text unique,
    activo     boolean not null default true,
    created_at timestamptz not null default now()
);
-- Bodega por defecto (donde queda todo lo actual)
insert into bodegas (nombre, codigo)
    values ('Bodega PROPLAS', 'PRINCIPAL')
    on conflict (nombre) do nothing;

-- ---- 2) EXISTENCIAS por (elemento + bodega) --------------------------
create table if not exists existencias (
    elemento_id    uuid not null references elementos(id) on delete cascade,
    bodega_id      uuid not null references bodegas(id) on delete cascade,
    existencia     numeric(18,3) not null default 0,
    costo_promedio numeric(18,4) not null default 0,
    stock_minimo   numeric(18,3) not null default 0,
    updated_at     timestamptz not null default now(),
    primary key (elemento_id, bodega_id)
);
create index if not exists idx_existencias_bodega on existencias (bodega_id);

-- ---- 3) MOVIMIENTOS: bodega + enlace de traslado ---------------------
alter table movimientos add column if not exists bodega_id   uuid references bodegas(id);
alter table movimientos add column if not exists traslado_id uuid;

-- Backfill: todo lo existente queda en la Bodega PROPLAS
update movimientos
   set bodega_id = (select id from bodegas where codigo = 'PRINCIPAL')
 where bodega_id is null;

-- Ahora sí, obligatorio
alter table movimientos alter column bodega_id set not null;

-- ---- 4) TRIGGER: stock por bodega + total en elementos ---------------
create or replace function public.aplicar_movimiento()
returns trigger language plpgsql
security definer set search_path = public
as $$
declare
    e_exist numeric(18,3);
    e_costo numeric(18,4);
    nueva_exist numeric(18,3);
begin
    if new.bodega_id is null then
        raise exception 'El movimiento requiere una bodega';
    end if;

    -- Existencia/costo actuales de ESA bodega (0 si aún no existe la fila)
    select existencia, costo_promedio into e_exist, e_costo
      from existencias
     where elemento_id = new.elemento_id and bodega_id = new.bodega_id
       for update;
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

    -- Guardar la existencia de la bodega
    insert into existencias (elemento_id, bodega_id, existencia, costo_promedio, updated_at)
        values (new.elemento_id, new.bodega_id, e_exist, e_costo, now())
    on conflict (elemento_id, bodega_id)
        do update set existencia = excluded.existencia,
                      costo_promedio = excluded.costo_promedio,
                      updated_at = now();

    -- Actualizar el TOTAL del elemento (suma de todas las bodegas)
    update elementos e
       set existencia = coalesce((select sum(x.existencia) from existencias x where x.elemento_id = e.id), 0),
           costo_promedio = coalesce((
               select case when sum(x.existencia) > 0
                           then sum(x.existencia * x.costo_promedio) / sum(x.existencia)
                           else 0 end
               from existencias x where x.elemento_id = e.id), 0),
           updated_at = now()
     where e.id = new.elemento_id;

    return new;
end; $$;

-- ---- 5) TRASLADO entre bodegas (salida origen + entrada destino) -----
create or replace function public.trasladar(
    p_elemento uuid, p_cantidad numeric,
    p_origen uuid, p_destino uuid, p_obs text default null)
returns void language plpgsql
security definer set search_path = public
as $$
declare
    puede boolean;
    costo_origen numeric(18,4);
    tid uuid := uuid_generate_v4();
begin
    select public.tiene_rol('admin') or public.tiene_rol('coordinador') into puede;
    if not puede then
        raise exception 'Solo admin o coordinador pueden trasladar';
    end if;
    if p_origen = p_destino then
        raise exception 'La bodega de origen y destino no pueden ser la misma';
    end if;

    -- costo de la bodega origen, para que el costo viaje con el material
    select costo_promedio into costo_origen
      from existencias where elemento_id = p_elemento and bodega_id = p_origen;

    -- salida del origen (el trigger valida que haya stock)
    insert into movimientos(tipo, elemento_id, bodega_id, cantidad, referencia,
                            observacion, usuario_id, traslado_id)
    values ('salida', p_elemento, p_origen, p_cantidad, 'TRASLADO',
            p_obs, auth.uid(), tid);

    -- entrada al destino, al costo del origen
    insert into movimientos(tipo, elemento_id, bodega_id, cantidad, costo_unitario,
                            referencia, observacion, usuario_id, traslado_id)
    values ('entrada', p_elemento, p_destino, p_cantidad, coalesce(costo_origen, 0),
            'TRASLADO', p_obs, auth.uid(), tid);
end; $$;

-- ---- 6) Existencia por bodega de un elemento (para el detalle) -------
create or replace function public.existencias_por_bodega(p_elemento uuid)
returns table (bodega text, bodega_id uuid, existencia numeric, costo_promedio numeric)
language sql stable as $$
    select b.nombre, b.id, x.existencia, x.costo_promedio
    from existencias x
    join bodegas b on b.id = x.bodega_id
    where x.elemento_id = p_elemento and x.existencia <> 0
    order by b.nombre;
$$;

-- ---- 7) RLS ----------------------------------------------------------
alter table bodegas     enable row level security;
alter table existencias enable row level security;

drop policy if exists sel_bodegas on bodegas;
create policy sel_bodegas on bodegas for select to authenticated using (true);
drop policy if exists cud_bodegas on bodegas;
create policy cud_bodegas on bodegas for all to authenticated
    using (public.tiene_rol('admin') or public.tiene_rol('coordinador'))
    with check (public.tiene_rol('admin') or public.tiene_rol('coordinador'));

drop policy if exists sel_existencias on existencias;
create policy sel_existencias on existencias for select to authenticated using (true);
-- existencias solo las escribe el trigger (security definer); nadie a mano
