-- schema_v55_disponible_excluye_repuestos_y_baja
-- Aplicada el 2026-09-10.
--
-- Un equipo "para repuestos" o "de baja" NO está disponible para entregar.
--
-- La regla anterior era `estado = 'operativo' and está en una bodega`. Eso
-- excluía la baja por ESTADO, pero no la condición 'repuestos' ni la
-- condición 'baja': una bomba marcada para repuestos aparecía como lista
-- para entregar.
--
-- condicion y estado son cosas distintas a propósito (ver SDD, sección 3a):
-- la condicion dice cuánto vale, el estado si se puede usar. Para
-- DISPONIBILIDAD mandan las dos.
--
-- OJO: esta fórmula está duplicada en lib/local_store.dart
-- (ajustarEstadoActivoLocal) para el modo offline, y se muestra como aviso
-- en la hoja "Estado y condición". Si cambia aquí, cambia allá, o las
-- listas online y offline se contradicen.

create or replace view activos_disponibilidad
with (security_invoker = true) as
 select a.id, a.referencia_id, a.serial, a.condicion, a.estado,
    a.mantenimiento_actor, a.bodega_id, a.valor_nuevo, a.porcentaje_valor,
    a.valor_actual, a.ficha, a.observacion, a.creado_por, a.creado_email,
    a.creado_en, a.serial_busqueda,
    au.bodega_id as ubicacion_actual_bodega_id,
    au.tercero_id as ubicacion_actual_tercero_id,
    au.fecha_desde as ubicacion_actual_desde,
    a.estado = 'operativo'
      and a.condicion not in ('repuestos', 'baja')
      and au.bodega_id is not null as disponible
   from activos a
     left join activo_ubicaciones au
       on au.activo_id = a.id and au.fecha_hasta is null;
