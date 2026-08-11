-- schema_v28_fix_anular_bodega.sql
-- Aplicado en produccion el 2026-08-11 (migracion: fix_anular_movimiento_bodega_id).
--
-- PROBLEMA: al anular CUALQUIER movimiento, Postgres devolvia
--   ERROR 23502: null value in column "bodega_id" of relation "movimientos"
--                violates not-null constraint
--
-- CAUSA: anular_movimiento venia de schema_v2/v3, de antes de que existieran
-- las bodegas. Su insert del movimiento de ajuste nunca incluyo bodega_id, que
-- desde entonces es NOT NULL. Las otras funciones que insertan en movimientos
-- (trasladar, mover_serie, registrar_entrada_masiva, registrar_salida_masiva)
-- si fueron actualizadas en su momento; a esta se le paso.
--
-- ARREGLO: el ajuste hereda la bodega del movimiento original. Si la salida
-- fue de la Bodega PROPLAS, la anulacion devuelve a esa misma bodega.
--
-- PENDIENTE (no cubierto aqui): si el movimiento anulado forma parte de un
-- traslado (traslado_id no nulo), esto revierte solo una pata y las dos
-- bodegas quedan descuadradas. Falta definir el comportamiento deseado.

CREATE OR REPLACE FUNCTION public.anular_movimiento(p_mov uuid, p_motivo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m record; signo numeric;
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede anular movimientos';
    end if;
    select * into m from movimientos where id = p_mov;
    if not found then raise exception 'Movimiento no encontrado'; end if;
    if m.referencia is not null and m.referencia like 'ANULACION%' then
        raise exception 'Ese movimiento ya es una anulación';
    end if;
    signo := case when m.tipo in ('inicial','entrada') then -1 else 1 end;
    insert into movimientos(tipo, elemento_id, centro_costo_id, bodega_id, cantidad,
                            costo_unitario, referencia, observacion, usuario_id)
    values ('ajuste', m.elemento_id, m.centro_costo_id, m.bodega_id, signo * abs(m.cantidad),
            m.costo_unitario, 'ANULACION ' || left(p_mov::text, 8),
            coalesce(p_motivo, 'Anulación de movimiento'), auth.uid());
end; $function$;
