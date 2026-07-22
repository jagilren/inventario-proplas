-- =====================================================================
--  INVENTARIO PROPLAS · schema_v5 · AUDITORÍA DE CAMBIOS
--
--  Registra QUIÉN cambió QUÉ, CUÁNDO, con valor anterior y nuevo.
--  Cubre: elementos, centros_costo, categorias, usuario_roles, profiles.
--
--  NO audita existencia ni costo_promedio: esos cambian con cada
--  movimiento y ya quedan trazados en el kardex (evita ruido inútil).
-- =====================================================================

create table if not exists auditoria (
    id             uuid primary key default uuid_generate_v4(),
    tabla          text not null,
    registro_id    uuid,
    accion         text not null check (accion in ('INSERT','UPDATE','DELETE')),
    campo          text,          -- solo en UPDATE
    valor_anterior text,
    valor_nuevo    text,
    datos          jsonb,         -- registro completo en INSERT/DELETE
    usuario_id     uuid,
    usuario_email  text,
    fecha          timestamptz not null default now()
);

create index if not exists idx_aud_registro on auditoria (tabla, registro_id, fecha desc);
create index if not exists idx_aud_fecha on auditoria (fecha desc);

-- ---- Función genérica de auditoría ---------------------------------
create or replace function public.fn_auditoria()
returns trigger language plpgsql security definer set search_path = public as $$
declare
    v_old jsonb; v_new jsonb; k text;
    v_uid uuid; v_email text; v_reg uuid;
    -- columnas que NO se auditan (derivadas o ruido)
    ignorar text[] := array['updated_at','created_at','busqueda',
                            'existencia','costo_promedio'];
begin
    v_uid := auth.uid();
    if v_uid is not null then
        select email into v_email from profiles where id = v_uid;
    end if;

    if TG_OP = 'INSERT' then
        v_new := to_jsonb(NEW);
        v_reg := nullif(coalesce(v_new->>'id', v_new->>'usuario_id'), '')::uuid;
        insert into auditoria(tabla, registro_id, accion, datos, usuario_id, usuario_email)
        values (TG_TABLE_NAME, v_reg, 'INSERT', v_new, v_uid, v_email);
        return NEW;

    elsif TG_OP = 'DELETE' then
        v_old := to_jsonb(OLD);
        v_reg := nullif(coalesce(v_old->>'id', v_old->>'usuario_id'), '')::uuid;
        insert into auditoria(tabla, registro_id, accion, datos, usuario_id, usuario_email)
        values (TG_TABLE_NAME, v_reg, 'DELETE', v_old, v_uid, v_email);
        return OLD;

    else  -- UPDATE: una fila por cada campo que cambió
        v_old := to_jsonb(OLD); v_new := to_jsonb(NEW);
        v_reg := nullif(coalesce(v_new->>'id', v_new->>'usuario_id'), '')::uuid;
        for k in select jsonb_object_keys(v_new) loop
            if not (k = any(ignorar))
               and (v_old->>k) is distinct from (v_new->>k) then
                insert into auditoria(tabla, registro_id, accion, campo,
                                      valor_anterior, valor_nuevo, usuario_id, usuario_email)
                values (TG_TABLE_NAME, v_reg, 'UPDATE', k,
                        v_old->>k, v_new->>k, v_uid, v_email);
            end if;
        end loop;
        return NEW;
    end if;
end $$;

-- ---- Conectar el disparador a las tablas ---------------------------
drop trigger if exists trg_aud_elementos on elementos;
create trigger trg_aud_elementos after insert or update or delete on elementos
    for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_cc on centros_costo;
create trigger trg_aud_cc after insert or update or delete on centros_costo
    for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_cat on categorias;
create trigger trg_aud_cat after insert or update or delete on categorias
    for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_roles on usuario_roles;
create trigger trg_aud_roles after insert or update or delete on usuario_roles
    for each row execute function public.fn_auditoria();

-- ---- Seguridad: solo admin lee; nadie escribe a mano ---------------
alter table auditoria enable row level security;
drop policy if exists aud_sel on auditoria;
create policy aud_sel on auditoria for select to authenticated
    using (public.es_admin() or public.tiene_rol('coordinador'));
-- (sin políticas de insert/update/delete: solo el trigger puede escribir)

-- ---- Consultas para la app -----------------------------------------
-- Historial de un registro concreto (ej. un elemento)
create or replace function public.historial_registro(p_tabla text, p_id uuid)
returns table (fecha timestamptz, accion text, campo text,
               valor_anterior text, valor_nuevo text, usuario_email text)
language sql stable as $$
    select a.fecha, a.accion, a.campo, a.valor_anterior, a.valor_nuevo, a.usuario_email
    from auditoria a
    where a.tabla = p_tabla and a.registro_id = p_id
    order by a.fecha desc
    limit 200;
$$;

-- Auditoría reciente global (para el admin)
create or replace function public.auditoria_reciente(p_limit int default 100)
returns table (fecha timestamptz, tabla text, accion text, campo text,
               valor_anterior text, valor_nuevo text, usuario_email text)
language sql stable as $$
    select a.fecha, a.tabla, a.accion, a.campo,
           a.valor_anterior, a.valor_nuevo, a.usuario_email
    from auditoria a
    order by a.fecha desc
    limit p_limit;
$$;
