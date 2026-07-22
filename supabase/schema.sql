-- =====================================================================
--  INVENTARIO PROPLAS  ·  Esquema Supabase (Postgres)
--  Generado para la app Flutter offline-first (mi_app)
--  Pegar en:  Supabase Dashboard -> SQL Editor -> New query -> Run
--  Es idempotente: se puede volver a ejecutar sin romper nada.
-- =====================================================================

-- ---- Extensiones necesarias -----------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists unaccent;   -- búsqueda sin tildes
create extension if not exists pg_trgm;    -- búsqueda por similitud

-- unaccent() no es "immutable" y no se puede usar en columnas generadas.
-- Envoltorio inmutable (patrón oficial Supabase) para poder indexarla:
create or replace function public.f_unaccent(text)
returns text
language sql
immutable
strict
parallel safe
set search_path = extensions, public
as $$ select unaccent('unaccent', $1) $$;

-- =====================================================================
--  1. CATEGORÍAS  (para agrupar / reclasificar elementos)
-- =====================================================================
create table if not exists categorias (
    id          uuid primary key default uuid_generate_v4(),
    nombre      text not null unique,
    parent_id   uuid references categorias(id) on delete set null, -- subcategorías
    activo      boolean not null default true,
    created_at  timestamptz not null default now()
);

-- =====================================================================
--  2. CENTROS DE COSTO  (hoja CC del Excel: 9 registros)
-- =====================================================================
create table if not exists centros_costo (
    id          uuid primary key default uuid_generate_v4(),
    codigo      text not null unique,          -- ej. NP00034
    descripcion text,
    cliente     text,
    activo      boolean not null default true,
    created_at  timestamptz not null default now()
);

-- =====================================================================
--  3. PERFILES / ROLES  (auditoría + permisos, ligado a Supabase Auth)
-- =====================================================================
create table if not exists profiles (
    id         uuid primary key references auth.users(id) on delete cascade,
    nombre     text,
    rol        text not null default 'bodeguero'
               check (rol in ('admin','bodeguero','consulta')),
    created_at timestamptz not null default now()
);

-- Crear perfil automáticamente al registrarse un usuario
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
    insert into public.profiles (id, nombre)
    values (new.id, coalesce(new.raw_user_meta_data->>'nombre', new.email))
    on conflict (id) do nothing;
    return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- =====================================================================
--  4. ELEMENTOS  (maestro único: hoja BD, 951 elementos)
--     existencia y costo_promedio los mantiene el trigger (§6).
-- =====================================================================
create table if not exists elementos (
    id             uuid primary key default uuid_generate_v4(),
    nombre         text not null unique,          -- regla: NO repetidos
    material       text,
    sch            text,
    unidad         text not null default 'UND',   -- UND / MT / Par
    categoria_id   uuid references categorias(id) on delete set null,
    codigo_barras  text unique,                   -- opcional (escaneo)
    imagen_url     text,                          -- opcional (Supabase Storage)
    stock_minimo   numeric(18,3) default 0,       -- alerta de mínimo
    existencia     numeric(18,3) not null default 0,   -- calculado
    costo_promedio numeric(18,4) not null default 0,   -- calculado (prom. móvil)
    activo         boolean not null default true,
    -- búsqueda inteligente (orden de palabras indiferente, sin tildes):
    busqueda       tsvector generated always as (
                        to_tsvector('simple',
                            public.f_unaccent(coalesce(nombre,'') || ' ' || coalesce(material,'')))
                   ) stored,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now()
);

create index if not exists idx_elementos_busqueda on elementos using gin (busqueda);
create index if not exists idx_elementos_nombre_trgm on elementos using gin (nombre gin_trgm_ops);
create index if not exists idx_elementos_categoria on elementos (categoria_id);

-- =====================================================================
--  5. MOVIMIENTOS  (unifica INVENTARIO_INICIAL + ENTRADAS + SALIDAS)
--     Append-only: no se editan ni borran; se corrige con 'ajuste'.
-- =====================================================================
create table if not exists movimientos (
    id              uuid primary key default uuid_generate_v4(),
    tipo            text not null
                    check (tipo in ('inicial','entrada','salida','ajuste')),
    elemento_id     uuid not null references elementos(id),
    centro_costo_id uuid references centros_costo(id),
    cantidad        numeric(18,3) not null,        -- salida/ajuste- pueden ser >0; el signo lo da el tipo
    costo_unitario  numeric(18,4),                 -- requerido en entrada/inicial
    fecha           timestamptz not null default now(),
    referencia      text,                          -- nº OC / documento (col DATO)
    observacion     text,
    usuario_id      uuid references profiles(id),  -- auditoría: quién
    -- soporte offline-first (evita duplicados al sincronizar):
    device_id       text,
    local_id        text,
    created_at      timestamptz not null default now(),
    unique (device_id, local_id)
);

create index if not exists idx_mov_elemento on movimientos (elemento_id, fecha);
create index if not exists idx_mov_fecha on movimientos (fecha);
create index if not exists idx_mov_cc on movimientos (centro_costo_id);

-- =====================================================================
--  6. TRIGGER: mantiene existencia y costo promedio ponderado MÓVIL
-- =====================================================================
create or replace function public.aplicar_movimiento()
returns trigger language plpgsql as $$
declare
    e_exist numeric(18,3);
    e_costo numeric(18,4);
    nueva_exist numeric(18,3);
begin
    select existencia, costo_promedio into e_exist, e_costo
      from elementos where id = new.elemento_id for update;

    if new.tipo in ('inicial','entrada') then
        if new.costo_unitario is null then
            raise exception 'El costo_unitario es obligatorio en movimientos de tipo %', new.tipo;
        end if;
        nueva_exist := e_exist + new.cantidad;
        -- promedio ponderado móvil
        if nueva_exist > 0 then
            e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
        end if;
        e_exist := nueva_exist;

    elsif new.tipo = 'salida' then
        -- BLOQUEO de existencias negativas
        if new.cantidad > e_exist then
            raise exception 'Existencia insuficiente: hay % y se intenta sacar %', e_exist, new.cantidad;
        end if;
        e_exist := e_exist - new.cantidad;   -- costo promedio no cambia

    elsif new.tipo = 'ajuste' then
        -- ajuste con cantidad firmada (+ suma, - resta)
        if new.cantidad >= 0 and new.costo_unitario is not null then
            nueva_exist := e_exist + new.cantidad;
            if nueva_exist > 0 then
                e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
            end if;
            e_exist := nueva_exist;
        else
            if abs(new.cantidad) > e_exist then
                raise exception 'Ajuste negativo mayor a la existencia (% ) : %', e_exist, new.cantidad;
            end if;
            e_exist := e_exist + new.cantidad;  -- cantidad es negativa
        end if;
    end if;

    update elementos
       set existencia = e_exist,
           costo_promedio = e_costo,
           updated_at = now()
     where id = new.elemento_id;

    return new;
end; $$;

drop trigger if exists trg_aplicar_movimiento on movimientos;
create trigger trg_aplicar_movimiento
    after insert on movimientos
    for each row execute function public.aplicar_movimiento();

-- =====================================================================
--  7. BÚSQUEDA INTELIGENTE  (palabras en cualquier orden, sin tildes)
--     Uso desde la app:  select * from buscar_elementos('tornillo inox');
-- =====================================================================
create or replace function public.buscar_elementos(q text)
returns setof elementos language sql stable as $$
    select *
    from elementos
    where activo
      and (
        q is null or q = '' or
        busqueda @@ plainto_tsquery('simple', public.f_unaccent(q)) or
        nombre ilike '%' || q || '%'
      )
    order by nombre
    limit 50;
$$;

-- =====================================================================
--  8. KARDEX  (historial de un elemento con saldo corrido)
--     Uso:  select * from kardex_elemento('<uuid>');
-- =====================================================================
create or replace function public.kardex_elemento(p_elemento uuid)
returns table (
    fecha timestamptz, tipo text, cantidad numeric,
    costo_unitario numeric, centro_costo text, referencia text, observacion text
) language sql stable as $$
    select m.fecha, m.tipo, m.cantidad, m.costo_unitario,
           cc.codigo, m.referencia, m.observacion
    from movimientos m
    left join centros_costo cc on cc.id = m.centro_costo_id
    where m.elemento_id = p_elemento
    order by m.fecha, m.created_at;
$$;

-- =====================================================================
--  9. SEGURIDAD (RLS): lectura a autenticados; escritura según rol
-- =====================================================================
alter table elementos      enable row level security;
alter table categorias     enable row level security;
alter table centros_costo  enable row level security;
alter table movimientos    enable row level security;
alter table profiles       enable row level security;

-- Lectura para cualquier usuario autenticado
create policy sel_auth on elementos     for select to authenticated using (true);
create policy sel_auth on categorias    for select to authenticated using (true);
create policy sel_auth on centros_costo for select to authenticated using (true);
create policy sel_auth on movimientos   for select to authenticated using (true);
create policy sel_self on profiles      for select to authenticated using (true);

-- Escritura de movimientos: bodeguero y admin (consulta no)
create policy ins_mov on movimientos for insert to authenticated
    with check (exists (select 1 from profiles p
                        where p.id = auth.uid() and p.rol in ('admin','bodeguero')));

-- Mantenimiento de catálogos (elementos, categorías, CC): sólo admin
create policy adm_elem on elementos    for all to authenticated
    using  (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'))
    with check (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'));
create policy adm_cat  on categorias   for all to authenticated
    using  (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'))
    with check (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'));
create policy adm_cc   on centros_costo for all to authenticated
    using  (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'))
    with check (exists (select 1 from profiles p where p.id=auth.uid() and p.rol='admin'));

-- =====================================================================
--  Fin del esquema
-- =====================================================================
