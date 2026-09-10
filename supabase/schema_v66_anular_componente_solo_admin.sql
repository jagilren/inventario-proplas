-- schema_v66_anular_componente_solo_admin
-- Referencias KITZABLES — Fase 5 (docs/plan-kits-equipos.md).
--
-- Anular un movimiento de componente: SOLO EL ADMINISTRADOR, igual que
-- anular un movimiento de equipo.
--
-- anular_activo_movimiento() ya rechaza a quien no sea admin ("Solo un
-- administrador puede anular movimientos de equipos"). La Fase 1 de los kits
-- (schema_v64) no copió esa regla, y dejaba anular un movimiento de
-- componente a cualquiera con acceso al módulo: dos reglas distintas para lo
-- mismo dentro del mismo módulo. Se encontró al diseñar la pantalla de la
-- Fase 5, antes de que nadie pudiera usarla.
--
-- `auth.uid() is not null`: las correcciones directas en la base, sin sesión,
-- no pasan por aquí (mismo criterio que schema_v62).
--
-- El resto de la función queda idéntico a schema_v64.

create or replace function fn_preparar_mov_componente() returns trigger
language plpgsql as $$
declare
  v_comp   activo_componentes%rowtype;
  v_estado text;
  v_orig   activo_componente_movimientos%rowtype;
begin
  select * into v_comp from activo_componentes where id = new.componente_id;
  select estado into v_estado from activos where id = v_comp.activo_id;

  if v_estado = 'entregado' then
    raise exception 'Este kit fue entregado y ya no nos pertenece: no se le pueden mover componentes';
  end if;

  if new.tipo = 'anulacion' then
    if auth.uid() is not null and not es_admin() then
      raise exception 'Solo un administrador puede anular movimientos de componentes';
    end if;
    select * into v_orig from activo_componente_movimientos
     where id = new.anula_movimiento_id;
    if v_orig.id is null or v_orig.componente_id <> new.componente_id then
      raise exception 'El movimiento a anular no es de este componente';
    end if;
    if v_orig.tipo = 'anulacion' then
      raise exception 'Una anulación no se anula: registra un movimiento nuevo';
    end if;
    if exists (select 1 from activo_componente_movimientos
                where anula_movimiento_id = new.anula_movimiento_id) then
      raise exception 'Este movimiento ya fue anulado';
    end if;
    new.signo          := -v_orig.signo;
    new.cantidad       := v_orig.cantidad;
    new.valor_unitario := v_orig.valor_unitario;
  else
    if new.tipo in ('salida_venta', 'salida_garantia') and new.tercero_id is null then
      raise exception 'Para vender o dar en garantía hay que decir a quién (el tercero)';
    end if;
    new.signo := case when new.tipo in ('alta', 'aumento') then 1 else -1 end;
    new.valor_unitario := v_comp.valor_unitario;
  end if;

  if auth.uid() is not null then
    new.usuario_id    := auth.uid();
    new.usuario_email := (select email from profiles where id = auth.uid());
  end if;
  return new;
end;
$$;
