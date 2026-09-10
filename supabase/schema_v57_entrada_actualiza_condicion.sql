-- schema_v57_entrada_actualiza_condicion
-- Aplicada el 2026-09-10. Incluye lo de schema_v56.
--
-- Al reingresar un equipo, su CONDICIÓN es la que traiga el movimiento.
--
-- `fn_aplicar_activo_movimiento` usaba `new.condicion` para decidir el
-- ESTADO, pero nunca la copiaba a `activos.condicion`. Una bomba que salió
-- nueva y volvió usada seguía diciendo "nuevo" en su ficha — y por lo tanto
-- se seguía valorizando como nueva.
--
-- Los valores permitidos coinciden: activo_movimientos.condicion admite
-- nuevo/usado/baja, todos válidos en activos.condicion.

create or replace function fn_aplicar_activo_movimiento() returns trigger
language plpgsql as $$
declare
  original record;
begin
  if new.tipo = 'salida' then
    update activos set estado = 'entregado' where id = new.activo_id;
    -- Entregar es SALIR del inventario: el equipo deja de ser nuestro.
    update activo_ubicaciones
       set fecha_hasta = new.fecha
     where activo_id = new.activo_id and fecha_hasta is null;

  elsif new.tipo = 'entrada' then
    if new.condicion = 'nuevo' or (new.condicion = 'usado' and new.usable) then
      update activos set estado = 'operativo' where id = new.activo_id;
    elsif new.condicion = 'usado' and not coalesce(new.usable, false) then
      update activos set estado = 'mantenimiento_interno' where id = new.activo_id;
    elsif new.condicion = 'baja' then
      update activos set estado = 'baja' where id = new.activo_id;
    end if;

    -- El equipo vuelve a ser nuestro CON LA CONDICIÓN CON LA QUE REGRESÓ.
    -- Si salió nuevo y volvió usado, vale como usado.
    if new.condicion is not null then
      update activos set condicion = new.condicion where id = new.activo_id;
    end if;

    if new.bodega_id is not null then
      update activo_ubicaciones
         set fecha_hasta = new.fecha
       where activo_id = new.activo_id and fecha_hasta is null;

      insert into activo_ubicaciones
        (activo_id, bodega_id, fecha_desde, usuario_id, usuario_email)
      values
        (new.activo_id, new.bodega_id, new.fecha, new.usuario_id, new.usuario_email);
    end if;

  elsif new.tipo = 'ajuste' then
    select * into original from activo_movimientos where id = new.anula_movimiento_id;
    if original.tipo = 'salida' then
      -- Se anula una entrega: vuelve a ser nuestro y vuelve a su bodega.
      update activos set estado = 'operativo' where id = new.activo_id;
      update activo_ubicaciones set fecha_hasta = new.fecha
       where activo_id = new.activo_id and fecha_hasta is null;
      insert into activo_ubicaciones
        (activo_id, bodega_id, fecha_desde, usuario_id, usuario_email)
      select new.activo_id, a.bodega_id, new.fecha, new.usuario_id, new.usuario_email
        from activos a where a.id = new.activo_id;
    elsif original.tipo = 'entrada' then
      update activos set estado = 'entregado' where id = new.activo_id;
      update activo_ubicaciones set fecha_hasta = new.fecha
       where activo_id = new.activo_id and fecha_hasta is null;
    end if;
  end if;

  return new;
end;
$$;
