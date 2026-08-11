-- =====================================================================
--  INVENTARIO PROPLAS · schema_v30 · COSTO EN LAS SALIDAS
--  Aplicado en produccion el 2026-08-11
--  (migraciones: estampar_costo_unitario_en_salidas
--              + backfill_costo_unitario_12_salidas)
--
--  SINTOMA: en el informe, la salida del "Collarin PVC Presion SCH 80
--  2x1/2\"" aparecia valorizada en $0, cuando el articulo habia entrado a
--  $15.000.
--
--  CAUSA: aplicar_movimiento() exige costo_unitario en 'inicial' y
--  'entrada', pero en 'salida' solo resta la existencia: nunca lo estampa.
--  Y la pantalla de movimiento individual manda null a proposito para las
--  salidas (lib/screens/movimiento_page.dart:193). Esas salidas quedan sin
--  costo PARA SIEMPRE. Cuando ademas dejan la existencia en 0, el
--  costo_promedio del elemento cae a 0, y los informes -que caen al
--  promedio actual cuando falta costo_unitario- las valorizan en $0.
--
--  Por eso solo habia 12 casos y no cientos: las salidas normales se hacen
--  por salida masiva (desde Excel) y esa RPC si estampa el costo. La
--  pantalla individual casi no se usaba.
--
--  POR QUE EN LA BASE Y NO EN FLUTTER: la app no es el unico camino. La
--  cola offline sincroniza inserts directos (los 12 casos vinieron por ahi,
--  con device_id) y cualquier cliente futuro entraria igual.
--
--  BEFORE INSERT es lo que corresponde: corre antes de
--  trg_aplicar_movimiento (AFTER INSERT), asi que 'existencias' todavia
--  tiene el promedio ANTERIOR al movimiento, que es justo el costo con el
--  que la mercancia esta saliendo. Las salidas no alteran el promedio
--  movil, asi que esto NO cambia ninguna valorizacion de existencias: solo
--  deja registrado el costo de la salida.
-- =====================================================================

create or replace function public.fn_estampar_costo_salida()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
    if new.tipo = 'salida' and new.costo_unitario is null then
        select x.costo_promedio
          into new.costo_unitario
          from existencias x
         where x.elemento_id = new.elemento_id
           and x.bodega_id  = new.bodega_id;
        -- Si el articulo nunca tuvo costo (entro en 0 desde el Excel), queda
        -- en 0: no hay dato que inventar, pero al menos no queda nulo.
        new.costo_unitario := coalesce(new.costo_unitario, 0);
    end if;
    return new;
end $function$;

drop trigger if exists trg_estampar_costo_salida on public.movimientos;

create trigger trg_estampar_costo_salida
    before insert on public.movimientos
    for each row execute function public.fn_estampar_costo_salida();


-- ---------------------------------------------------------------------
--  CORRECCION PUNTUAL de las 12 salidas que ya estaban sin costo.
--  (Todas del 2026-08-11, hechas desde la pantalla de movimiento
--  individual y sincronizadas desde un dispositivo.)
--
--  VALOR USADO: existencias.costo_promedio de esa bodega. Es EXACTO, no una
--  aproximacion, porque las salidas no alteran el promedio movil: el
--  promedio de hoy es el mismo que habia en el momento de la salida. Se
--  revisaron los 12 uno por uno; el unico que tuvo una entrada posterior
--  ("Conector Macho JACO Nylon 220 PSI 1/2ODx1/2 NPT") la recibio al mismo
--  precio ($33.150), asi que su promedio tampoco cambio.
--
--  Hay que desactivar trg_mov_solo_obs un instante: impide editar cualquier
--  campo de un movimiento que no sea la observacion (inmutabilidad, correcta
--  como regla general). Se reactiva en la misma transaccion, asi que no
--  puede quedar apagado. La auditoria (trg_aud_movimientos) queda ACTIVA a
--  proposito: estos cambios deben registrarse.
--
--  Este bloque ya se ejecuto; se deja por trazabilidad. Es idempotente:
--  volver a correrlo no toca nada, porque ya no quedan salidas con costo
--  nulo.
-- ---------------------------------------------------------------------

alter table public.movimientos disable trigger trg_mov_solo_obs;

update public.movimientos m
   set costo_unitario = coalesce(x.costo_promedio, 0)
  from public.existencias x
 where x.elemento_id = m.elemento_id
   and x.bodega_id   = m.bodega_id
   and m.tipo        = 'salida'
   and m.costo_unitario is null;

alter table public.movimientos enable trigger trg_mov_solo_obs;
