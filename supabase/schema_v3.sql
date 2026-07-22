-- =====================================================================
--  INVENTARIO PROPLAS · schema_v3  ·  ROLES MÚLTIPLES (RBAC)
--  Pegar en Supabase -> SQL Editor -> Run.  Idempotente.
--
--  Roles: admin · coordinador · operario_mas · operario_menos
--    admin          -> todo
--    coordinador    -> CRUD elementos y centros de costo
--    operario_mas   -> registra entradas y devoluciones
--    operario_menos -> registra salidas
--  Un usuario puede tener VARIOS roles (muchos-a-muchos).
-- =====================================================================

-- ---- 1) email en profiles (para la gestión de usuarios) -------------
alter table profiles add column if not exists email text;
update profiles p set email = u.email
  from auth.users u where u.id = p.id and p.email is null;

-- ---- 2) tabla de asignación usuario <-> rol (muchos-a-muchos) -------
create table if not exists usuario_roles (
    usuario_id uuid not null references auth.users(id) on delete cascade,
    rol        text not null check (rol in
                 ('admin','coordinador','operario_mas','operario_menos')),
    creado_en  timestamptz not null default now(),
    primary key (usuario_id, rol)
);
alter table usuario_roles enable row level security;

-- ---- 3) migrar el rol único anterior a la nueva tabla ---------------
insert into usuario_roles (usuario_id, rol)
    select id, 'admin' from profiles where rol = 'admin'
    on conflict do nothing;

-- ---- 4) helper: ¿el usuario actual tiene el rol X? ------------------
-- SECURITY DEFINER: corre como owner y NO dispara RLS (evita recursión).
create or replace function public.tiene_rol(p_rol text)
returns boolean language sql stable security definer
set search_path = public as $$
    select exists(
        select 1 from usuario_roles
        where usuario_id = auth.uid() and rol = p_rol);
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer
set search_path = public as $$
    select exists(select 1 from usuario_roles
                  where usuario_id = auth.uid() and rol = 'admin');
$$;

-- ---- 5) RLS de usuario_roles ---------------------------------------
drop policy if exists ur_sel on usuario_roles;
drop policy if exists ur_admin on usuario_roles;
-- cada quien ve sus roles; el admin ve todos
create policy ur_sel on usuario_roles for select to authenticated
    using (usuario_id = auth.uid() or public.es_admin());
-- solo admin asigna/quita roles
create policy ur_admin on usuario_roles for all to authenticated
    using (public.es_admin()) with check (public.es_admin());

-- ---- 6) RLS elementos / categorías / centros de costo --------------
-- Escritura: admin o coordinador. (La lectura sigue abierta por sel_auth.)
drop policy if exists adm_elem on elementos;
drop policy if exists adm_cat  on categorias;
drop policy if exists adm_cc   on centros_costo;

create policy cud_elem on elementos for all to authenticated
    using (public.tiene_rol('admin') or public.tiene_rol('coordinador'))
    with check (public.tiene_rol('admin') or public.tiene_rol('coordinador'));
create policy cud_cat on categorias for all to authenticated
    using (public.tiene_rol('admin') or public.tiene_rol('coordinador'))
    with check (public.tiene_rol('admin') or public.tiene_rol('coordinador'));
create policy cud_cc on centros_costo for all to authenticated
    using (public.tiene_rol('admin') or public.tiene_rol('coordinador'))
    with check (public.tiene_rol('admin') or public.tiene_rol('coordinador'));

-- ---- 7) RLS movimientos: por tipo y rol ----------------------------
drop policy if exists ins_mov on movimientos;
create policy ins_mov on movimientos for insert to authenticated with check (
    public.tiene_rol('admin')
    or (tipo = 'entrada' and public.tiene_rol('operario_mas'))
    or (tipo = 'salida'  and public.tiene_rol('operario_menos'))
    or (tipo = 'inicial' and public.tiene_rol('coordinador'))
    -- 'ajuste' solo entra vía anular_movimiento() (SECURITY DEFINER)
);

-- ---- 8) profiles: cada quien actualiza su nombre; admin todo -------
drop policy if exists prof_upd on profiles;
create policy prof_upd on profiles for update to authenticated
    using (id = auth.uid() or public.es_admin())
    with check (id = auth.uid() or public.es_admin());

-- ---- 9) anular_movimiento: usar el nuevo chequeo de admin ----------
create or replace function public.anular_movimiento(p_mov uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare m record; signo numeric;
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede anular movimientos';
    end if;
    select * into m from movimientos where id = p_mov;
    if not found then raise exception 'Movimiento no encontrado'; end if;
    if m.referencia is not null and m.referencia like 'ANULACION%' then
        raise exception 'Ese movimiento ya es una anulación';
    end if;
    signo := case when m.tipo in ('inicial','entrada') then -1 else 1 end;
    insert into movimientos(tipo, elemento_id, centro_costo_id, cantidad,
                            costo_unitario, referencia, observacion, usuario_id)
    values ('ajuste', m.elemento_id, m.centro_costo_id, signo * abs(m.cantidad),
            m.costo_unitario, 'ANULACION ' || left(p_mov::text, 8),
            coalesce(p_motivo, 'Anulación de movimiento'), auth.uid());
end; $$;

-- ---- 10) listar usuarios con sus roles (solo admin) ----------------
create or replace function public.listar_usuarios()
returns table(id uuid, email text, nombre text, roles text[])
language plpgsql stable security definer set search_path = public as $$
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede listar usuarios';
    end if;
    return query
        select p.id, p.email, p.nombre,
               coalesce(array_agg(ur.rol) filter (where ur.rol is not null), '{}')
        from profiles p
        left join usuario_roles ur on ur.usuario_id = p.id
        group by p.id, p.email, p.nombre
        order by p.email;
end; $$;

-- ---- 11) nuevos usuarios: perfil sin rol (el admin los asigna) -----
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, nombre, email)
    values (new.id,
            coalesce(new.raw_user_meta_data->>'nombre', new.email),
            new.email)
    on conflict (id) do update set email = excluded.email;
    return new;
end; $$;
