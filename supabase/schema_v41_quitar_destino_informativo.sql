-- =====================================================================
--  INVENTARIO PROPLAS · schema_v41 · SE QUITA EL "DESTINO INFORMATIVO"
--
--  schema_v40 dejo un segundo campo (`centro_costo_destino_id`) para
--  anotar, de forma puramente informativa, a que centro quedaba
--  reasignada una devolucion — sin ningun efecto en los informes.
--
--  Decision del usuario (2026-09-03): ese campo se quita del todo. El
--  unico concepto que queda es el de siempre — "Centro de Costo Origen":
--  en una entrada, si se marca que es una devolucion, se especifica de
--  que centro viene la mercancia que se esta sumando al inventario. Eso
--  YA es exactamente lo que hacia `centro_costo_id` desde antes de que
--  existiera todo este feature (y que netos_por_centro/consumoPorCentro
--  ya usan sin cambios desde schema_v40) — lo unico que cambia es la UI:
--  pasa de "campo siempre visible con una nota" a una casilla explicita
--  "Es una devolucion" que revela el campo "Centro de Costo Origen".
--
--  Verificado antes de borrar: 0 filas reales en produccion usaban
--  `centro_costo_destino_id` — no se pierde ningun dato real.
--
--  netos_por_centro, consumoPorCentro (Dart) y el resto de los informes
--  NO se tocan: ninguno referenciaba esta columna (confirmado revisando
--  schema_v40 antes de escribir esto) — es exactamente la garantia de
--  "no reñir con los otros informes" que pidio el usuario.
-- =====================================================================

alter table movimientos drop constraint if exists chk_centro_destino_solo_entrada;
alter table movimientos drop column if exists centro_costo_destino_id;
-- El indice y la FK se van solos con la columna (Postgres los borra en
-- cascada al hacer drop column).

-- El candado de inmutabilidad, sin la columna que ya no existe.
create or replace function public.fn_mov_solo_observacion()
returns trigger language plpgsql as $function$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.referencia,
      new.usuario_id, new.fecha, new.traslado_id, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.referencia,
      old.usuario_id, old.fecha, old.traslado_id, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $function$;

-- =====================================================================
--  Para revertir: volver a agregar la columna y el CHECK de schema_v40,
--  y sumarla de vuelta al candado de inmutabilidad.
-- =====================================================================
