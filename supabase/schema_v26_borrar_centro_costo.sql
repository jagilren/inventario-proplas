-- =====================================================================
--  INVENTARIO PROPLAS · schema_v26
--  Borrado DEFINITIVO de un centro de costo, y del conteo que dice si se
--  puede.
--
--  Hasta ahora un centro solo se podia DESACTIVAR. Eso esta bien cuando ya
--  tiene historial (hay que conservar a que centro se le cargo cada salida),
--  pero para uno creado por error —un codigo mal escrito, un duplicado— es
--  un estorbo: queda para siempre en la lista marcado como "(inactivo)".
--
--  Mismo criterio que borrar_elemento (schema_v16): si no tiene ni un
--  movimiento, se borra de verdad; si tiene, se desactiva.
-- =====================================================================

-- Cuantos movimientos tiene el centro. La pantalla lo usa para decidir si
-- ofrece "Eliminar" o solo "Desactivar", y para poder DECIRLE al usuario
-- por que no se puede borrar en vez de solo negarselo.
create or replace function public.movimientos_de_centro(p_id uuid)
returns bigint
language sql
stable
as $function$
    select count(*) from movimientos where centro_costo_id = p_id;
$function$;

create or replace function public.borrar_centro_costo(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
    v_movs bigint;
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede borrar centros de costo';
    end if;

    select count(*) into v_movs from movimientos where centro_costo_id = p_id;
    if v_movs > 0 then
        raise exception
          'Este centro tiene % movimiento(s) en el historial; no se puede '
          'borrar. Desactivalo: asi desaparece de las listas pero el '
          'historial sigue sabiendo a quien se le cargo cada salida.', v_movs;
    end if;

    -- Los aprovechamientos tambien apuntan a centros de costo.
    if exists (select 1 from aprovechamiento_salidas where centro_costo_id = p_id) then
        raise exception
          'Este centro tiene salidas de aprovechamientos; no se puede borrar. '
          'Desactivalo.';
    end if;

    delete from centros_costo where id = p_id;
end;
$function$;
