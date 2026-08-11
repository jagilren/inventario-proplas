-- =====================================================================
--  INVENTARIO PROPLAS · schema_v33 · AUDITORIA: DELETE Y MENOS RUIDO
--  Aplicado en produccion el 2026-08-11 (2 migraciones):
--    auditoria_delete_movimientos_y_menos_ruido
--    auditoria_archivar_correccion_zona_horaria
--
--  Hallazgo que motivo esto: el 67% de TODA la auditoria (958 de 1.426 filas)
--  era 'movimientos · UPDATE · campo fecha', todas en el mismo segundo del
--  2026-07-23 20:53:42, sin usuario, sumando +5 horas exactas
--  (00:00Z -> 05:00Z). O sea la correccion de zona horaria a hora de Colombia
--  tras la migracion del Excel: una sola operacion tecnica que tapaba lo que
--  de verdad hay que vigilar (14 cambios de nombre, 4 quitadas de rol...).
-- =====================================================================

-- ---- 1) movimientos ahora audita tambien el DELETE ------------------
--
-- Que NO audite INSERT esta bien: el movimiento ES el registro, ya trae
-- fecha, usuario, tipo, cantidad, bodega y centro. Auditarlo seria guardar lo
-- mismo dos veces.
--
-- Que no auditara DELETE si era un hueco. Hoy ningun usuario de la app puede
-- borrar un movimiento (no hay politica de DELETE en RLS), pero quien tenga
-- credenciales elevadas si, y no quedaria rastro. Los triggers disparan
-- aunque se salte el RLS, asi que esto cubre exactamente ese caso.

drop trigger if exists trg_aud_movimientos on public.movimientos;

create trigger trg_aud_movimientos
    after update or delete on public.movimientos
    for each row execute function public.fn_auditoria();

-- ---- 2) campos derivados que solo ensucian -------------------------
--
-- Se agregan a la lista de ignorados:
--   phash       hash perceptual de la imagen, lo calcula la app sola
--   imagen_url  derivado: cambia al cambiar la foto principal, que YA se
--               audita en elemento_imagenes (era duplicado)
--   orden       reordenar fotos, cosmetico
--   principal   idem
--
-- NO se ignoran longitud_actual ni consumido_en de aprovechamiento_trozos:
-- parecen duplicados del consumo (que ya se audita en aprovechamiento_salidas)
-- pero son justo los campos que alguien tocaria a mano para cuadrar un saldo
-- sin dejar rastro del consumo. Son pocas filas y cubren manipulacion real.

create or replace function public.fn_auditoria()
returns trigger
language plpgsql security definer
set search_path to 'public'
as $function$
declare
    v_old jsonb; v_new jsonb; k text;
    v_uid uuid; v_email text; v_reg uuid;
    ignorar text[] := array['updated_at','created_at','busqueda',
                            'existencia','costo_promedio',
                            'phash','imagen_url','orden','principal'];
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
end $function$;

-- ---- 3) archivar las 958 de la zona horaria ------------------------
--
-- NO se borran: auditoria que se borra deja de ser auditoria. Se mueven a
-- una tabla de archivo, con el mismo contenido y una nota de por que.
-- Resultado: la auditoria viva paso de 1.426 a 468 filas.

create table if not exists public.auditoria_archivo (
    like public.auditoria including all,
    motivo_archivo text,
    archivado_en   timestamptz not null default now()
);

alter table public.auditoria_archivo enable row level security;

drop policy if exists aud_arch_sel on public.auditoria_archivo;
create policy aud_arch_sel on public.auditoria_archivo
    for select using (public.es_admin() or public.tiene_rol('coordinador'));

with movidas as (
    delete from public.auditoria
     where tabla = 'movimientos'
       and accion = 'UPDATE'
       and campo = 'fecha'
       and usuario_id is null
       and fecha::date = date '2026-07-23'
    returning *
)
insert into public.auditoria_archivo
select m.*,
       'Correccion masiva de zona horaria (+5h) tras la migracion del Excel, '
       '2026-07-23 20:53:42. Operacion tecnica sin decision humana; archivada '
       'el 2026-08-11 para no tapar la auditoria real.' as motivo_archivo,
       now() as archivado_en
from movidas m;
