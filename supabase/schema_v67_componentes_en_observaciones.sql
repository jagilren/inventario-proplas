-- schema_v67_componentes_en_observaciones
-- Pedido del usuario el 2026-09-10: cuando se suman o restan unidades de un
-- componente de un kit, la novedad tiene que quedar en el listado de
-- OBSERVACIONES de la ficha del equipo, con fecha, usuario, componente,
-- movimiento, cantidades y el MOTIVO escrito por el usuario.
--
-- 1. El motivo es OBLIGATORIO en todo movimiento de componente menos el alta
--    (la composición inicial del kit no es una novedad). También en la
--    anulación, y no se puede dejar vacío editándolo después.
-- 2. La vista del listado gana un cuarto origen, 'componente'. Entrega los
--    datos CRUDOS (componente, tipo, signo, cantidad, saldo, tercero,
--    anulado) y la app los redacta con las mismas etiquetas de siempre
--    (TipoMovComponente): una sola fuente para las palabras.
-- 3. El saldo ("quedan 22") es el de ESE momento, calculado con los
--    movimientos hasta ese punto: si después se retiran más, la línea vieja
--    no cambia.
-- 4. Editar el motivo queda en el historial de cambios (observacion_historial).

-- 1a. Al insertar (idéntico a schema_v66 + el motivo obligatorio).
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

  if new.tipo <> 'alta' and btrim(coalesce(new.observacion, '')) = '' then
    raise exception 'Escribe el motivo: por qué cambia la cantidad de "%"', v_comp.nombre;
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

-- 1b. El candado de inmutabilidad (idéntico a schema_v64) + el motivo no se
--     puede dejar vacío al editarlo.
create or replace function fn_mov_componente_solo_obs() returns trigger
language plpgsql as $$
begin
  if (new.componente_id, new.tipo, new.signo, new.cantidad, new.valor_unitario,
      new.tercero_id, new.anula_movimiento_id, new.usuario_id,
      new.usuario_email, new.fecha, new.creado_en)
     is distinct from
     (old.componente_id, old.tipo, old.signo, old.cantidad, old.valor_unitario,
      old.tercero_id, old.anula_movimiento_id, old.usuario_id,
      old.usuario_email, old.fecha, old.creado_en)
  then
    raise exception 'Un movimiento de componente no se edita: se anula. Solo se puede corregir su observación.';
  end if;
  if new.tipo <> 'alta' and btrim(coalesce(new.observacion, '')) = '' then
    raise exception 'El motivo no puede quedar vacío';
  end if;
  return new;
end;
$$;

-- 4. El historial de cambios de una observación entiende el origen nuevo.
create or replace function observacion_historial(p_origen text, p_id uuid)
returns table (fecha timestamptz, antes text, despues text, usuario_email text)
language sql stable security definer
set search_path = public
as $$
  select au.fecha, au.valor_anterior::text, au.valor_nuevo::text, au.usuario_email
  from auditoria au
  where (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'))
    and au.accion = 'UPDATE'
    and au.registro_id = p_id
    and au.tabla = case p_origen when 'alta' then 'activos'
                                 when 'ubicacion' then 'activo_ubicaciones'
                                 when 'componente' then 'activo_componente_movimientos'
                                 else 'activo_observaciones' end
    and au.campo = case p_origen when 'alta' then 'observacion'
                                 when 'ubicacion' then 'detalle'
                                 when 'componente' then 'observacion'
                                 else 'texto' end
  order by au.fecha desc;
$$;

-- 2 y 3. La vista: las columnas nuevas van AL FINAL (create or replace no
-- deja meterlas en medio) y en los otros tres orígenes van en null.
create or replace view activo_observaciones_todas
with (security_invoker = true) as
  select o.activo_id, o.fecha, o.texto, o.origen, o.contexto, o.usuario_email,
         o.id, observacion_editada(o.origen, o.id) as editada,
         null::text as comp_nombre, null::text as comp_tipo,
         null::smallint as comp_signo, null::numeric as comp_cantidad,
         null::numeric as comp_saldo, null::text as comp_tercero,
         null::boolean as comp_anulado
  from activo_observaciones o
  union all
  select u.activo_id, u.fecha_desde, u.detalle, 'ubicacion'::text,
         coalesce(b.nombre, t.nombre), u.usuario_email,
         u.id, observacion_editada('ubicacion', u.id),
         null, null, null, null, null, null, null
  from activo_ubicaciones u
  left join bodegas b on b.id = u.bodega_id
  left join activo_terceros t on t.id = u.tercero_id
  where u.detalle is not null and btrim(u.detalle) <> ''
  union all
  select a.id, a.creado_en, a.observacion, 'alta'::text, null::text, a.creado_email,
         a.id, observacion_editada('alta', a.id),
         null, null, null, null, null, null, null
  from activos a
  where a.observacion is not null and btrim(a.observacion) <> ''
  union all
  select c.activo_id, m.fecha, coalesce(nullif(btrim(m.observacion), ''), '(sin motivo)'),
         'componente'::text, null::text, m.usuario_email,
         m.id, observacion_editada('componente', m.id),
         c.nombre, m.tipo, m.signo, m.cantidad, m.saldo, t.nombre,
         exists (select 1 from activo_componente_movimientos x
                  where x.anula_movimiento_id = m.id)
  from (
    -- El saldo DE ESE MOMENTO: la suma de los movimientos hasta ese punto.
    -- Ante un EMPATE de fecha (todo lo de una misma transacción comparte la
    -- misma now()), el alta cuenta primero: es el punto de partida. Sin esto
    -- el orden lo decidía el uuid, que es aleatorio, y un retiro podía salir
    -- con "quedan −2" (lo detectó la prueba de esta migración).
    select mm.*,
           sum(mm.signo * mm.cantidad) over (
             partition by mm.componente_id
             order by mm.fecha, (mm.tipo <> 'alta'), mm.creado_en, mm.id
             rows between unbounded preceding and current row) as saldo
    from activo_componente_movimientos mm
  ) m
  join activo_componentes c on c.id = m.componente_id
  left join activo_terceros t on t.id = m.tercero_id
  -- El alta es la composición inicial, no una novedad.
  where m.tipo <> 'alta';
