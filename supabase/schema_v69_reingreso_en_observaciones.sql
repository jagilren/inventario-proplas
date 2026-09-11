-- schema_v69_reingreso_en_observaciones
--
-- Pedido del usuario (2026-09-11): "al registrar el reingreso de un equipo,
-- esto queda registrado en los movimientos pero también en el listado de
-- observaciones como un elemento más". Un reingreso quedaba SOLO en
-- movimientos: su texto vive en activo_movimientos.observacion y la
-- ubicación que abre no lleva detalle, así que el listado no lo veía.
--
-- 1. La vista del listado gana un quinto origen, 'reingreso'. Sale SIEMPRE,
--    aunque no tenga texto: el reingreso es un hecho de la vida del equipo,
--    no una nota opcional. Datos crudos (centro, bodega, condición,
--    anulado); la app redacta con las palabras de la ficha (flujoMovimiento,
--    "Entrada · REINGRESO"). Columnas nuevas AL FINAL, null en los demás.
-- 2. El historial de cambios entiende el origen nuevo.
-- 3. La regla hermana que faltaba: "solo admin y coordinador modifican una
--    observación ya escrita" (schema_v62) estaba en las otras cuatro tablas
--    de observaciones, pero NO en activo_movimientos. Con el lápiz del
--    listado, el rol `equipos` habría podido cambiar el texto de un
--    reingreso. Se agrega el mismo trigger.

-- 2.
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
                                 when 'reingreso' then 'activo_movimientos'
                                 else 'activo_observaciones' end
    and au.campo = case p_origen when 'alta' then 'observacion'
                                 when 'ubicacion' then 'detalle'
                                 when 'componente' then 'observacion'
                                 when 'reingreso' then 'observacion'
                                 else 'texto' end
  order by au.fecha desc;
$$;

-- 3.
drop trigger if exists trg_obs_solo_coord on activo_movimientos;
create trigger trg_obs_solo_coord
  before update of observacion on activo_movimientos
  for each row execute function fn_observacion_solo_coordinador('observacion');

-- 1.
create or replace view activo_observaciones_todas
with (security_invoker = true) as
  select o.activo_id, o.fecha, o.texto, o.origen, o.contexto, o.usuario_email,
         o.id, observacion_editada(o.origen, o.id) as editada,
         null::text as comp_nombre, null::text as comp_tipo,
         null::smallint as comp_signo, null::numeric as comp_cantidad,
         null::numeric as comp_saldo, null::text as comp_tercero,
         null::boolean as comp_anulado,
         null::text as mov_centro, null::text as mov_centro_destino,
         null::text as mov_bodega, null::text as mov_condicion,
         null::boolean as mov_anulado
  from activo_observaciones o
  union all
  select u.activo_id, u.fecha_desde, u.detalle, 'ubicacion'::text,
         coalesce(b.nombre, t.nombre), u.usuario_email,
         u.id, observacion_editada('ubicacion', u.id),
         null, null, null, null, null, null, null,
         null, null, null, null, null
  from activo_ubicaciones u
  left join bodegas b on b.id = u.bodega_id
  left join activo_terceros t on t.id = u.tercero_id
  where u.detalle is not null and btrim(u.detalle) <> ''
  union all
  select a.id, a.creado_en, a.observacion, 'alta'::text, null::text, a.creado_email,
         a.id, observacion_editada('alta', a.id),
         null, null, null, null, null, null, null,
         null, null, null, null, null
  from activos a
  where a.observacion is not null and btrim(a.observacion) <> ''
  union all
  select c.activo_id, m.fecha, coalesce(nullif(btrim(m.observacion), ''), '(sin motivo)'),
         'componente'::text, null::text, m.usuario_email,
         m.id, observacion_editada('componente', m.id),
         c.nombre, m.tipo, m.signo, m.cantidad, m.saldo, t.nombre,
         exists (select 1 from activo_componente_movimientos x
                  where x.anula_movimiento_id = m.id),
         null, null, null, null, null
  from (
    select mm.*,
           sum(mm.signo * mm.cantidad) over (
             partition by mm.componente_id
             order by mm.fecha, (mm.tipo <> 'alta'), mm.creado_en, mm.id
             rows between unbounded preceding and current row) as saldo
    from activo_componente_movimientos mm
  ) m
  join activo_componentes c on c.id = m.componente_id
  left join activo_terceros t on t.id = m.tercero_id
  where m.tipo <> 'alta'
  union all
  -- 5º origen: el REINGRESO. Siempre, con o sin texto ('' si no escribió).
  select m.activo_id, m.fecha, coalesce(m.observacion, ''), 'reingreso'::text,
         null::text, m.usuario_email,
         m.id, observacion_editada('reingreso', m.id),
         null, null, null, null, null, null, null,
         cc.codigo, ccd.codigo, b.nombre, m.condicion,
         exists (select 1 from activo_movimientos x
                  where x.anula_movimiento_id = m.id)
  from activo_movimientos m
  left join centros_costo cc  on cc.id  = m.centro_costo_id
  left join centros_costo ccd on ccd.id = m.centro_costo_destino_id
  left join bodegas b on b.id = m.bodega_id
  where m.tipo = 'entrada' and m.es_reingreso;
