-- schema_v61_ubicacion_arrastra_estado
-- Aplicada el 2026-09-10. Error 9.7 del SDD.
--
-- Cambiar la UBICACIÓN también mueve el ESTADO.
--
-- La ventana "Cambiar ubicación" llamaba a esta función, que solo movía la
-- ubicación y NUNCA miraba el estado. Una bomba mandada al TALLER JUAN
-- GABRIEL MONTOYA por ahí siguió diciendo "Operativo".
--
-- Se arregla aquí, en la base, y no en la pantalla: así ningún camino puede
-- dejar el estado y la ubicación contando historias distintas.
--
--   a un tercero tipo 'taller'  -> estado mantenimiento_externo
--                                  + el taller (y el detalle) en mantenimiento_actor
--   a una bodega, desde taller  -> estado operativo, sin mantenimiento_actor
--   un equipo entregado         -> se rechaza: ya no es nuestro
--
-- Compatible con la ventana de Estado: esa pone el estado ANTES de llamar
-- aquí, así que al llegar no queda nada por cambiar y no pisa lo elegido.

create or replace function cambiar_ubicacion_activo(
  p_activo uuid,
  p_bodega_id uuid default null,
  p_tercero_id uuid default null,
  p_detalle text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_estado  text;
  v_tercero activo_terceros%rowtype;
begin
  if not (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos')) then
    raise exception 'No tienes permiso para cambiar la ubicación de un equipo';
  end if;

  if (p_bodega_id is null) = (p_tercero_id is null) then
    raise exception 'Debes indicar exactamente una: bodega propia o tercero, no ambas ni ninguna';
  end if;

  -- FOR UPDATE: dos personas moviendo el mismo equipo a la vez no pueden
  -- dejar el estado de una y la ubicación de la otra.
  select estado into v_estado from activos where id = p_activo for update;

  if v_estado = 'entregado' then
    raise exception 'Este equipo fue entregado y ya no nos pertenece: registra su regreso con una entrada';
  end if;

  update activo_ubicaciones
     set fecha_hasta = now()
   where activo_id = p_activo and fecha_hasta is null;

  insert into activo_ubicaciones (activo_id, bodega_id, tercero_id, detalle, usuario_id, usuario_email)
  values (p_activo, p_bodega_id, p_tercero_id, p_detalle,
          auth.uid(), (select email from profiles where id = auth.uid()));

  if p_tercero_id is not null then
    select * into v_tercero from activo_terceros where id = p_tercero_id;
    if v_tercero.tipo = 'taller' then
      update activos
         set estado = 'mantenimiento_externo',
             mantenimiento_actor = v_tercero.nombre
               || coalesce(' · ' || nullif(btrim(p_detalle), ''), '')
       where id = p_activo;
    end if;

  elsif v_estado = 'mantenimiento_externo' then
    update activos
       set estado = 'operativo',
           mantenimiento_actor = null
     where id = p_activo;
  end if;
end;
$$;
