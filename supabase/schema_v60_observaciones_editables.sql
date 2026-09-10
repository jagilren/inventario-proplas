-- schema_v60_observaciones_editables
-- Aplicada el 2026-09-10.
--
-- Observaciones EDITABLES, con su historial de cambios visible.
--
-- La edición no necesita tabla nueva: cada observación se edita en su tabla
-- de origen, y las tres ya tienen el trigger fn_auditoria, que guarda por
-- cada cambio el campo, el valor anterior, el nuevo, el usuario y la fecha.
-- La auditoría existía; lo que faltaba era poder VERLA desde la ficha.
--
-- `auditoria` solo la leen admin y coordinador, y así debe seguir: guarda los
-- cambios de TODO el sistema, incluidos costos de inventario. Por eso estas
-- funciones son SECURITY DEFINER: leen la auditoría con permisos del dueño,
-- pero devuelven SOLO el historial del texto de UNA observación, y solo a
-- quien tiene acceso al módulo.

create or replace function observacion_historial(p_origen text, p_id uuid)
returns table (fecha timestamptz, antes text, despues text, usuario_email text)
language sql stable security definer
set search_path = public
as $$
  select au.fecha, au.valor_anterior::text, au.valor_nuevo::text, au.usuario_email
  from auditoria au
  where (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'))
    and au.accion = 'UPDATE'
    and au.registro_id = p_id
    and au.tabla = case p_origen when 'alta' then 'activos'
                                 when 'ubicacion' then 'activo_ubicaciones'
                                 else 'activo_observaciones' end
    and au.campo = case p_origen when 'alta' then 'observacion'
                                 when 'ubicacion' then 'detalle'
                                 else 'texto' end
  order by au.fecha desc;
$$;

create or replace function observacion_editada(p_origen text, p_id uuid)
returns boolean language sql stable security definer
set search_path = public
as $$ select exists (select 1 from observacion_historial(p_origen, p_id)); $$;

revoke all on function observacion_historial(text, uuid) from public, anon;
revoke all on function observacion_editada(text, uuid)   from public, anon;
grant execute on function observacion_historial(text, uuid) to authenticated;
grant execute on function observacion_editada(text, uuid)   to authenticated;

-- Dos columnas nuevas AL FINAL (create or replace no deja meterlas en medio):
-- `id`, para saber qué fila editar, y `editada`, para marcarla.
create or replace view activo_observaciones_todas
with (security_invoker = true) as
  select o.activo_id, o.fecha, o.texto, o.origen, o.contexto, o.usuario_email,
         o.id, observacion_editada(o.origen, o.id) as editada
  from activo_observaciones o
  union all
  select u.activo_id, u.fecha_desde, u.detalle, 'ubicacion'::text,
         coalesce(b.nombre, t.nombre), u.usuario_email,
         u.id, observacion_editada('ubicacion', u.id)
  from activo_ubicaciones u
  left join bodegas b on b.id = u.bodega_id
  left join activo_terceros t on t.id = u.tercero_id
  where u.detalle is not null and btrim(u.detalle) <> ''
  union all
  select a.id, a.creado_en, a.observacion, 'alta'::text, null::text, a.creado_email,
         a.id, observacion_editada('alta', a.id)
  from activos a
  where a.observacion is not null and btrim(a.observacion) <> '';
