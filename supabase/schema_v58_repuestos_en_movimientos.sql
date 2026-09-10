-- schema_v58_repuestos_en_movimientos
-- Aplicada el 2026-09-10. Incluye lo de schema_v56 y schema_v57.
--
-- Un equipo puede REINGRESAR "para repuestos".
--
-- El diseño original prohibía 'repuestos' en los movimientos ("es una
-- reclasificación posterior") y el alta mandaba 'usado' en su lugar. Dos
-- problemas:
--
-- 1. Un equipo que sale nuevo a un centro de costo y vuelve desarmado no se
--    podía reingresar como "para repuestos".
-- 2. Con schema_v57 (la entrada copia la condición a la ficha), ese truco del
--    alta se volvió un bug: un alta "para repuestos" quedaría como "usado".
--
-- Un equipo para repuestos queda con estado 'operativo' (está en la bodega y
-- no en mantenimiento) pero NO disponible, porque activos_disponibilidad
-- (schema_v55) excluye esa condición. Y sigue SUMANDO al valorizado.
--
-- NO se usa estado 'baja' para repuestos a propósito: el valorizado excluye
-- los de baja, y un donante de piezas sí tiene valor.

alter table activo_movimientos drop constraint activo_movimientos_condicion_check;
alter table activo_movimientos add constraint activo_movimientos_condicion_check
  check (condicion in ('nuevo', 'usado', 'repuestos', 'baja'));

create or replace function fn_aplicar_activo_movimiento() returns trigger
language plpgsql as $$
declare
  original record;
begin
  if new.tipo = 'salida' then
    update activos set estado = 'entregado' where id = new.activo_id;
    update activo_ubicaciones
       set fecha_hasta = new.fecha
     where activo_id = new.activo_id and fecha_hasta is null;

  elsif new.tipo = 'entrada' then
    if new.condicion = 'nuevo' or (new.condicion = 'usado' and new.usable) then
      update activos set estado = 'operativo' where id = new.activo_id;
    elsif new.condicion = 'usado' and not coalesce(new.usable, false) then
      update activos set estado = 'mantenimiento_interno' where id = new.activo_id;
    elsif new.condicion = 'repuestos' then
      update activos set estado = 'operativo' where id = new.activo_id;
    elsif new.condicion = 'baja' then
      update activos set estado = 'baja' where id = new.activo_id;
    end if;

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
