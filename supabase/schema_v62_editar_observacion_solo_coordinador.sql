-- schema_v62_editar_observacion_solo_coordinador
-- Aplicada el 2026-09-10.
--
-- Solo ADMIN y COORDINADOR modifican una observación ya escrita.
-- Cualquiera con acceso al módulo puede AGREGAR observaciones nuevas.
--
-- Va en la base y no solo escondiendo el lápiz: lección del error 9.7.
--
-- 1. De paso, un hueco de la Fase 1: el rol 'equipos' nunca se agregó a la
--    restricción de usuario_roles. El módulo pregunta por él en todos sus
--    permisos y la app lo ofrece, pero la base rechazaba asignarlo.

alter table usuario_roles drop constraint usuario_roles_rol_check;
alter table usuario_roles add constraint usuario_roles_rol_check check (rol in (
  'admin', 'coordinador', 'operario_mas', 'operario_menos',
  'exportar', 'remisiones', 'equipos'));

-- 2. El candado. No se quita el UPDATE de esas tablas (el rol 'equipos'
--    necesita cambiar el estado, cerrar ubicaciones...): se bloquea cambiar
--    UNA columna concreta, que llega como argumento del trigger.
--
--    `auth.uid() is not null`: las correcciones directas en la base, sin
--    sesión, no pasan por aquí. Un anónimo tampoco: la RLS no le deja
--    actualizar ninguna fila, así que el trigger ni se dispara.

create or replace function fn_observacion_solo_coordinador() returns trigger
language plpgsql as $$
declare
  col text := tg_argv[0];
begin
  if (to_jsonb(new) ->> col) is distinct from (to_jsonb(old) ->> col)
     and auth.uid() is not null
     and not (es_admin() or tiene_rol('coordinador')) then
    raise exception 'Solo un administrador o un coordinador puede modificar una observación ya escrita';
  end if;
  return new;
end;
$$;

create trigger trg_obs_solo_coord
  before update of observacion on activos
  for each row execute function fn_observacion_solo_coordinador('observacion');

create trigger trg_obs_solo_coord
  before update of detalle on activo_ubicaciones
  for each row execute function fn_observacion_solo_coordinador('detalle');

create trigger trg_obs_solo_coord
  before update of texto on activo_observaciones
  for each row execute function fn_observacion_solo_coordinador('texto');
