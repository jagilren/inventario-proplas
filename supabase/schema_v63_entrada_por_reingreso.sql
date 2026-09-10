-- schema_v63_entrada_por_reingreso
-- Aplicada el 2026-09-10.
--
-- Marcar las entradas que son REINGRESO de un equipo que se había entregado.
--
-- Una entrada puede ser el ALTA de un equipo nuevo o el REINGRESO de uno que
-- ya se había entregado a un centro de costo y vuelve. En listados e informes
-- las dos decían solo "Entrada".
--
-- DECISIÓN: se ESTAMPA al insertar, no se deriva al consultar. Es un hecho del
-- momento del movimiento, como el valor de una salida (que ya se estampa con
-- fn_estampar_valor_activo_salida). Derivarlo después se complica con las
-- anulaciones y obligaría a repetir la lógica en cada informe.
--
-- Criterio: es reingreso si el equipo estaba 'entregado' al entrar. Funciona
-- porque fn_aplicar_activo_movimiento (que cambia el estado) corre AFTER
-- insert: un trigger BEFORE todavía ve el estado viejo. Lo decide SIEMPRE la
-- base: si la app manda un valor, se sobreescribe.

alter table activo_movimientos
  add column es_reingreso boolean not null default false;

-- Lo que ya existía (al 2026-09-10, exactamente uno: la bomba
-- A9772113810000036 P12209 a las 13:57). Va ANTES de ampliar el candado.
update activo_movimientos m
   set es_reingreso = true
 where m.tipo = 'entrada'
   and exists (select 1 from activo_movimientos s
                where s.activo_id = m.activo_id
                  and s.tipo = 'salida'
                  and s.fecha < m.fecha);

create or replace function fn_estampar_reingreso() returns trigger
language plpgsql as $$
begin
  new.es_reingreso := new.tipo = 'entrada'
    and exists (select 1 from activos
                 where id = new.activo_id and estado = 'entregado');
  return new;
end;
$$;

create trigger trg_estampar_reingreso
  before insert on activo_movimientos
  for each row execute function fn_estampar_reingreso();

-- El candado de inmutabilidad nombra las columnas UNA POR UNA: una columna
-- nueva que no esté en la lista queda editable sin que nadie se entere.
create or replace function fn_activo_mov_solo_observacion() returns trigger
language plpgsql as $$
begin
  if (new.tipo, new.activo_id, new.centro_costo_id, new.centro_costo_destino_id,
      new.bodega_id, new.condicion, new.usable, new.valor,
      new.usuario_id, new.usuario_email, new.fecha, new.anula_movimiento_id,
      new.device_id, new.local_id, new.es_reingreso)
     is distinct from
     (old.tipo, old.activo_id, old.centro_costo_id, old.centro_costo_destino_id,
      old.bodega_id, old.condicion, old.usable, old.valor,
      old.usuario_id, old.usuario_email, old.fecha, old.anula_movimiento_id,
      old.device_id, old.local_id, old.es_reingreso)
  then
    raise exception 'Solo se puede editar la observación de un movimiento de equipo';
  end if;
  return new;
end;
$$;
