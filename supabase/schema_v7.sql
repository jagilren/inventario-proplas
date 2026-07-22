-- =====================================================================
--  INVENTARIO PROPLAS · schema_v7 · VARIAS FOTOS POR ELEMENTO
--
--  Pasa de una sola foto (columna elementos.imagen_url) a una galería
--  de hasta 3 fotos por elemento, con una marcada como PRINCIPAL.
--
--  elementos.imagen_url se CONSERVA y pasa a ser la foto principal:
--  así la lista de Existencias sigue mostrando la miniatura sin tener
--  que consultar otra tabla por cada fila (rápido y simple).
--
--  Archivos en el balde: elementos-img/{elemento_id}/{uuid}.jpg
-- =====================================================================

create table if not exists elemento_imagenes (
    id          uuid primary key default uuid_generate_v4(),
    elemento_id uuid not null references elementos(id) on delete cascade,
    url         text not null,
    ruta        text not null,          -- ruta dentro del balde, para poder borrarla
    principal   boolean not null default false,
    orden       int not null default 0,
    usuario_id  uuid references profiles(id),
    created_at  timestamptz not null default now()
);

create index if not exists idx_elem_img on elemento_imagenes (elemento_id, orden);

-- ---- Límite de 3 fotos por elemento (se valida en la base) ---------
create or replace function public.fn_limite_imagenes()
returns trigger language plpgsql as $$
declare n int;
begin
    select count(*) into n from elemento_imagenes where elemento_id = new.elemento_id;
    if n >= 3 then
        raise exception 'Máximo 3 fotos por elemento (ya tiene %)', n;
    end if;
    return new;
end $$;

drop trigger if exists trg_limite_imagenes on elemento_imagenes;
create trigger trg_limite_imagenes before insert on elemento_imagenes
    for each row execute function public.fn_limite_imagenes();

-- ---- Mantener UNA sola principal y sincronizar elementos.imagen_url --
create or replace function public.fn_sync_principal()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_elem uuid; v_url text;
begin
    v_elem := coalesce(new.elemento_id, old.elemento_id);

    -- si se marcó una como principal, desmarcar las demás
    if TG_OP in ('INSERT','UPDATE') and new.principal then
        update elemento_imagenes set principal = false
         where elemento_id = v_elem and id <> new.id and principal;
    end if;

    -- si el elemento quedó sin ninguna principal, ascender la más antigua
    if not exists (select 1 from elemento_imagenes
                   where elemento_id = v_elem and principal) then
        update elemento_imagenes set principal = true
         where id = (select id from elemento_imagenes
                     where elemento_id = v_elem
                     order by orden, created_at limit 1);
    end if;

    -- reflejar la principal en elementos.imagen_url (para la lista)
    select url into v_url from elemento_imagenes
     where elemento_id = v_elem and principal limit 1;
    update elementos set imagen_url = v_url where id = v_elem;

    return null;
end $$;

drop trigger if exists trg_sync_principal on elemento_imagenes;
create trigger trg_sync_principal
    after insert or update or delete on elemento_imagenes
    for each row execute function public.fn_sync_principal();

-- ---- Seguridad: leen todos los autenticados; escriben admin/coordinador
alter table elemento_imagenes enable row level security;
drop policy if exists ei_sel on elemento_imagenes;
drop policy if exists ei_cud on elemento_imagenes;
create policy ei_sel on elemento_imagenes for select to authenticated using (true);
create policy ei_cud on elemento_imagenes for all to authenticated
    using (public.tiene_rol('admin') or public.tiene_rol('coordinador'))
    with check (public.tiene_rol('admin') or public.tiene_rol('coordinador'));

-- ---- Auditoría de la galería ---------------------------------------
drop trigger if exists trg_aud_elem_img on elemento_imagenes;
create trigger trg_aud_elem_img
    after insert or update or delete on elemento_imagenes
    for each row execute function public.fn_auditoria();

-- ---- Migrar la foto única existente a la galería --------------------
insert into elemento_imagenes (elemento_id, url, ruta, principal, orden)
select e.id, e.imagen_url, e.id || '.jpg', true, 0
from elementos e
where e.imagen_url is not null and e.imagen_url <> ''
  and not exists (select 1 from elemento_imagenes i where i.elemento_id = e.id);

-- ---- Consulta para la app ------------------------------------------
create or replace function public.imagenes_elemento(p_elemento uuid)
returns table (id uuid, url text, ruta text, principal boolean, orden int)
language sql stable as $$
    select i.id, i.url, i.ruta, i.principal, i.orden
    from elemento_imagenes i
    where i.elemento_id = p_elemento
    order by i.principal desc, i.orden, i.created_at;
$$;
