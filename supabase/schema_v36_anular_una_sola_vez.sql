-- =====================================================================
--  INVENTARIO PROPLAS · schema_v36 · UN MOVIMIENTO SE ANULA UNA SOLA VEZ
--
--  EL PROBLEMA
--  `anular_movimiento` solo comprobaba una cosa: que el movimiento no
--  FUERA una anulacion. Nunca comprobaba que no ESTUVIERA YA anulado.
--  Pulsar el boton rojo dos veces sobre la misma salida creaba DOS
--  reversas, y la existencia quedaba compensada de mas: una salida de 10
--  anulada dos veces devolvia 20 al inventario. Silenciosamente.
--
--  En la app tampoco se veia venir: el boton seguia apareciendo en el
--  movimiento original despues de anularlo, porque la condicion miraba
--  `esAnulacion` (¿esta fila es una anulacion?) y no si ya tenia una.
--
--  Medido antes de arreglarlo: 7 anulaciones en produccion, ninguna
--  repetida. El error no alcanzo a ocurrir.
--
--  EL ARREGLO
--  El vinculo entre la anulacion y su movimiento original vivia solo en
--  un texto ('ANULACION ' + los primeros 8 caracteres del id). Eso sirve
--  para mostrar, no para garantizar nada. Ahora es una columna de verdad
--  con indice unico:
--
--    - `movimientos.anula_movimiento_id` -> movimientos(id)
--    - indice UNICO sobre esa columna
--
--  El indice es lo que de verdad cierra la puerta: aunque dos
--  administradores pulsen anular en el mismo segundo, o alguien de doble
--  clic, la segunda insercion no cabe en la tabla. Una comprobacion
--  suelta dentro de la funcion no bastaria: las dos pasarian la
--  comprobacion antes de que cualquiera de las dos insertara.
--
--  La referencia de texto se mantiene igual, para no romper lo que ya
--  la muestra en el kardex y en los informes.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La columna que ata la anulacion a su original
-- ---------------------------------------------------------------------
alter table movimientos
  add column if not exists anula_movimiento_id uuid references movimientos(id);

-- ---------------------------------------------------------------------
-- 2. Backfill de las anulaciones que ya existen, a partir del texto.
--    Se comprobo antes que ningun par de movimientos comparte los
--    primeros 8 caracteres del id, asi que el enganche no es ambiguo.
--    Sin auditoria: lo cambia la migracion, no una persona.
-- ---------------------------------------------------------------------
alter table movimientos disable trigger trg_aud_movimientos;

update movimientos a
   set anula_movimiento_id = o.id
  from movimientos o
 where a.referencia = 'ANULACION ' || left(o.id::text, 8)
   and a.anula_movimiento_id is null;

alter table movimientos enable trigger trg_aud_movimientos;

-- ---------------------------------------------------------------------
-- 2b. El candado de inmutabilidad (`fn_mov_solo_observacion`) compara una
--     lista fija de columnas, y la nueva no estaba en ella: se podria
--     re-apuntar una anulacion a otro movimiento con un simple update.
--     Se agrega. Va DESPUES del backfill, que necesita escribirla.
-- ---------------------------------------------------------------------
create or replace function public.fn_mov_solo_observacion()
returns trigger
language plpgsql
as $function$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.referencia, new.usuario_id, new.fecha,
      new.traslado_id, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.referencia, old.usuario_id, old.fecha,
      old.traslado_id, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $function$;

-- ---------------------------------------------------------------------
-- 3. La garantia: una anulacion por movimiento. Parcial, porque la
--    inmensa mayoria de los movimientos no anulan nada y los nulos no
--    deben chocar entre si.
-- ---------------------------------------------------------------------
create unique index if not exists movimientos_anula_uniq
  on movimientos (anula_movimiento_id)
  where anula_movimiento_id is not null;

-- ---------------------------------------------------------------------
-- 4. La funcion: comprueba antes (para dar un mensaje entendible) y
--    ademas traduce el choque del indice (para el caso de los dos
--    clics simultaneos, donde la comprobacion no alcanza a servir).
-- ---------------------------------------------------------------------
create or replace function public.anular_movimiento(
  p_mov uuid,
  p_motivo text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare m record; signo numeric;
begin
    if not public.es_admin() then
        raise exception 'Solo un administrador puede anular movimientos';
    end if;

    select * into m from movimientos where id = p_mov;
    if not found then raise exception 'Movimiento no encontrado'; end if;

    if m.anula_movimiento_id is not null
       or (m.referencia is not null and m.referencia like 'ANULACION%') then
        raise exception 'Ese movimiento ya es una anulación';
    end if;

    -- NUEVO: el que faltaba. Sin esto se podia anular dos veces y la
    -- existencia quedaba compensada de mas.
    if exists (select 1 from movimientos
                where anula_movimiento_id = p_mov) then
        raise exception 'Ese movimiento ya fue anulado';
    end if;

    signo := case when m.tipo in ('inicial','entrada') then -1 else 1 end;

    begin
        insert into movimientos(tipo, elemento_id, centro_costo_id, bodega_id,
                                cantidad, costo_unitario, referencia,
                                observacion, usuario_id, anula_movimiento_id)
        values ('ajuste', m.elemento_id, m.centro_costo_id, m.bodega_id,
                signo * abs(m.cantidad), m.costo_unitario,
                'ANULACION ' || left(p_mov::text, 8),
                coalesce(p_motivo, 'Anulación de movimiento'), auth.uid(),
                p_mov);
    exception when unique_violation then
        -- Dos anulaciones a la vez: la primera gano. Se traduce el error
        -- tecnico del indice a algo que el usuario entienda.
        raise exception 'Ese movimiento ya fue anulado';
    end;
end; $function$;

-- =====================================================================
--  Para revertir:
--    drop index movimientos_anula_uniq;
--    alter table movimientos drop column anula_movimiento_id;
--    (y volver a la version anterior de anular_movimiento)
-- =====================================================================
