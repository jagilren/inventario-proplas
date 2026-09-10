-- schema_v54_activo_observaciones
-- Aplicada el 2026-09-10.
--
-- Observaciones del equipo en un solo listado cronológico.
--
-- La ficha del equipo tenía UNA observación (la del alta) y nada más. Cada
-- cambio de estado o de ubicación podía traer un comentario, pero se perdía
-- o quedaba enterrado en otra pantalla.
--
-- Diseño: una tabla SOLO para lo que hoy no tiene dónde vivir (el comentario
-- de un cambio de estado), y una VISTA que la une con lo que ya se guardaba.
-- No se copia ningún texto de una tabla a otra: `activo_ubicaciones.detalle`
-- y `activos.observacion` siguen siendo la única fuente de su propio texto.
--
-- Ver docs/sdd-modulo-equipos.md, sección 3 decisión (d).

create table activo_observaciones (
  id            uuid primary key default extensions.uuid_generate_v4(),
  activo_id     uuid not null references activos(id),
  texto         text not null check (btrim(texto) <> ''),
  origen        text not null default 'estado'
                  check (origen in ('estado','manual')),
  -- Qué estaba pasando cuando se escribió: "Pasó a: En un taller externo".
  contexto      text,
  usuario_id    uuid,
  usuario_email text,
  fecha         timestamptz not null default now()
);

-- Regla de históricos del proyecto: del más reciente al más antiguo.
create index idx_activo_obs on activo_observaciones (activo_id, fecha desc);

alter table activo_observaciones enable row level security;
create policy equipos_sel on activo_observaciones for select
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_ins on activo_observaciones for insert
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_upd on activo_observaciones for update
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'))
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_del on activo_observaciones for delete
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));

create trigger trg_aud_activo_observaciones
  after insert or delete or update on activo_observaciones
  for each row execute function fn_auditoria();

-- El listado que ve el usuario. security_invoker para que aplique la RLS
-- de las tablas de abajo y no la del dueño de la vista.
create view activo_observaciones_todas
with (security_invoker = true) as
  select o.activo_id, o.fecha, o.texto, o.origen, o.contexto, o.usuario_email
  from activo_observaciones o
  union all
  select u.activo_id, u.fecha_desde, u.detalle, 'ubicacion'::text,
         coalesce(b.nombre, t.nombre), u.usuario_email
  from activo_ubicaciones u
  left join bodegas b on b.id = u.bodega_id
  left join activo_terceros t on t.id = u.tercero_id
  where u.detalle is not null and btrim(u.detalle) <> ''
  union all
  select a.id, a.creado_en, a.observacion, 'alta'::text, null::text, a.creado_email
  from activos a
  where a.observacion is not null and btrim(a.observacion) <> '';
