-- =====================================================================
--  INVENTARIO PROPLAS · schema_v32 · USUARIOS INACTIVOS
--  Aplicado en produccion el 2026-08-11 (3 migraciones seguidas):
--    usuarios_activo_puerta_unica
--    usuarios_inactivos_bloquear_lectura
--    usuarios_inactivar_activar_borrar
--
--  PROBLEMA: no habia forma de dar de baja a nadie. Lo unico posible era
--  quitarle los roles, y eso le impide ESCRIBIR pero no VER: las 13 politicas
--  de SELECT eran USING(true), o sea cualquier autenticado leia existencias,
--  costos y movimientos completos. Un ex-empleado seguia entrando y mirando
--  todo.
--
--  REGLA DEL NEGOCIO (la misma de centros de costo y elementos): si tiene
--  movimientos NO se borra, se inactiva. Si no tiene, se borra de verdad.
--  La FK movimientos.usuario_id -> profiles es NO ACTION, asi que la base ya
--  lo impedia por estructura; ahora ademas se explica en la pantalla.
--
--  DISEÑO: los roles NO se borran al inactivar. Lo que bloquea es la bandera,
--  que revisan tanto las funciones de rol como las politicas de lectura. Asi
--  reactivar devuelve a la persona exactamente como estaba y nadie tiene que
--  acordarse de que permisos tenia.
-- =====================================================================

-- ---- 1/3 · la bandera y las dos puertas unicas ----------------------

alter table public.profiles
    add column if not exists activo boolean not null default true;

-- Puerta de LECTURA. SECURITY DEFINER para leer profiles sin depender de la
-- politica de profiles (seria circular). Sin sesion devuelve false.
create or replace function public.es_activo()
returns boolean
language sql stable security definer
set search_path to 'public'
as $function$
    select coalesce((select p.activo from profiles p where p.id = auth.uid()), false);
$function$;

-- Puerta de ESCRITURA. Todas las politicas de escritura ya pasaban por
-- tiene_rol()/es_admin(), asi que agregando aqui la condicion se cierran
-- TODAS de una vez, sin tocar politica por politica y sin olvidar ninguna.
create or replace function public.es_admin()
returns boolean
language sql stable security definer
set search_path to 'public'
as $function$
    select exists(
        select 1 from usuario_roles ur
        join profiles p on p.id = ur.usuario_id
        where ur.usuario_id = auth.uid() and ur.rol = 'admin' and p.activo);
$function$;

create or replace function public.tiene_rol(p_rol text)
returns boolean
language sql stable security definer
set search_path to 'public'
as $function$
    select exists(
        select 1 from usuario_roles ur
        join profiles p on p.id = ur.usuario_id
        where ur.usuario_id = auth.uid() and ur.rol = p_rol and p.activo);
$function$;

-- ---- 2/3 · las 13 politicas de SELECT dejan de ser USING(true) ------

drop policy if exists aprov_sal_sel on public.aprovechamiento_salidas;
create policy aprov_sal_sel on public.aprovechamiento_salidas
    for select using (public.es_activo());

drop policy if exists aprov_sel on public.aprovechamiento_trozos;
create policy aprov_sel on public.aprovechamiento_trozos
    for select using (public.es_activo());

drop policy if exists sel_bodegas on public.bodegas;
create policy sel_bodegas on public.bodegas
    for select using (public.es_activo());

drop policy if exists sel_auth on public.categorias;
create policy sel_auth on public.categorias
    for select using (public.es_activo());

drop policy if exists sel_auth on public.centros_costo;
create policy sel_auth on public.centros_costo
    for select using (public.es_activo());

drop policy if exists ei_sel on public.elemento_imagenes;
create policy ei_sel on public.elemento_imagenes
    for select using (public.es_activo());

drop policy if exists sel_auth on public.elementos;
create policy sel_auth on public.elementos
    for select using (public.es_activo());

drop policy if exists sel_existencias on public.existencias;
create policy sel_existencias on public.existencias
    for select using (public.es_activo());

drop policy if exists adj_sel on public.movimiento_adjuntos;
create policy adj_sel on public.movimiento_adjuntos
    for select using (public.es_activo());

drop policy if exists sel_movser on public.movimiento_series;
create policy sel_movser on public.movimiento_series
    for select using (public.es_activo());

drop policy if exists sel_auth on public.movimientos;
create policy sel_auth on public.movimientos
    for select using (public.es_activo());

drop policy if exists sel_series on public.series;
create policy sel_series on public.series
    for select using (public.es_activo());

-- Excepcion a proposito: el inactivo SI lee su propia fila, para que la app
-- pueda decirle "tu cuenta esta inactiva" en vez de una pantalla vacia.
drop policy if exists sel_self on public.profiles;
create policy sel_self on public.profiles
    for select using (id = auth.uid() or public.es_activo());

-- ---- 3/3 · funciones de gestion ------------------------------------

drop function if exists public.listar_usuarios();

create or replace function public.listar_usuarios()
returns table(id uuid, email text, nombre text, roles text[], activo boolean)
language plpgsql stable security definer
set search_path to 'public'
as $function$
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede listar usuarios';
    end if;
    return query
        select p.id, p.email, p.nombre,
               coalesce(array_agg(ur.rol) filter (where ur.rol is not null), '{}'),
               p.activo
        from profiles p
        left join usuario_roles ur on ur.usuario_id = p.id
        group by p.id, p.email, p.nombre, p.activo
        order by p.activo desc, p.email;  -- los inactivos al final
end; $function$;

create or replace function public.usos_de_usuario(p_id uuid)
returns table(movimientos bigint, imagenes bigint)
language sql stable security definer
set search_path to 'public'
as $function$
    select (select count(*) from movimientos       where usuario_id = p_id),
           (select count(*) from elemento_imagenes where usuario_id = p_id);
$function$;

create or replace function public.inactivar_usuario(p_id uuid, p_activo boolean)
returns void
language plpgsql security definer
set search_path to 'public'
as $function$
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede activar o inactivar usuarios';
    end if;
    if p_id = auth.uid() and not p_activo then
        raise exception 'No puedes inactivarte a ti mismo';
    end if;
    -- Red de seguridad: sin ningun admin activo nadie podria volver a entrar
    -- a arreglarlo. Hoy hay UN solo admin, asi que esto es riesgo real.
    if not p_activo
       and exists (select 1 from usuario_roles where usuario_id = p_id and rol = 'admin')
       and (select count(*) from usuario_roles ur
              join profiles p on p.id = ur.usuario_id
             where ur.rol = 'admin' and p.activo) <= 1 then
        raise exception 'Es el último administrador activo: no se puede inactivar';
    end if;

    update profiles set activo = p_activo where id = p_id;
    if not found then raise exception 'Usuario no encontrado'; end if;
end; $function$;

create or replace function public.borrar_usuario(p_id uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $function$
declare n_mov bigint; n_img bigint;
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede borrar usuarios';
    end if;
    if p_id = auth.uid() then
        raise exception 'No puedes borrarte a ti mismo';
    end if;

    select movimientos, imagenes into n_mov, n_img from public.usos_de_usuario(p_id);
    if n_mov > 0 or n_img > 0 then
        raise exception
            'El usuario tiene % movimientos y % imágenes: no se puede borrar, solo inactivar',
            n_mov, n_img;
    end if;

    -- profiles.id -> auth.users es ON DELETE CASCADE: esto se lleva tambien
    -- el perfil y los roles.
    delete from auth.users where id = p_id;
    if not found then raise exception 'Usuario no encontrado'; end if;
end; $function$;
