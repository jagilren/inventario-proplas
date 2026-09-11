-- schema_v49b_inmutabilidad_device_local_id
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909180748): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- device_id y local_id son la llave que impide subir dos veces un
-- movimiento encolado sin conexión. Si se pudieran editar después, esa
-- protección se podría burlar, así que entran al mismo candado que el
-- resto: de un movimiento ya creado solo se edita la observación.
create or replace function public.fn_activo_mov_solo_observacion()
returns trigger
language plpgsql
as $$
begin
  if (new.tipo, new.activo_id, new.centro_costo_id, new.centro_costo_destino_id,
      new.bodega_id, new.condicion, new.usable, new.valor,
      new.usuario_id, new.usuario_email, new.fecha, new.anula_movimiento_id,
      new.device_id, new.local_id)
     is distinct from
     (old.tipo, old.activo_id, old.centro_costo_id, old.centro_costo_destino_id,
      old.bodega_id, old.condicion, old.usable, old.valor,
      old.usuario_id, old.usuario_email, old.fecha, old.anula_movimiento_id,
      old.device_id, old.local_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento de equipo';
  end if;
  return new;
end;
$$;
