-- schema_v64_kits_fase1
-- Aplicada el 2026-09-10. Probada antes en transacción con rollback (24 casos,
-- como un usuario con solo el rol 'equipos'). Ver docs/plan-kits-equipos.md §0.
-- Referencias KITZABLES — Fase 1 (SQL). Plan: docs/plan-kits-equipos.md
--
-- Una referencia puede ser un KIT: su equipo no vale un número escrito a
-- mano, vale la suma de sus componentes (nombre, cantidad, valor unitario).
-- Y esa composición tiene vida: se daña, se vende o se va como garantía una
-- parte, y queda registrado quién, cuándo, cuánto y a quién.
--
-- Todo cuelga de `es_kit = true`. Con `default false`, las referencias y los
-- equipos que existen se comportan exactamente igual que antes.
--
-- Lecciones del 2026-09-10 aplicadas desde el diseño:
--   * La regla va en la base (error 9.7): crear un componente es UNA función
--     que hace componente + su movimiento de alta juntos, no dos inserciones
--     desde la app que pueden quedar a medias.
--   * El candado de inmutabilidad nombra TODAS las columnas (schema_v63).
--   * Nada de un kit entregado se mueve: ya no es nuestro (regla 3).
--   * La observación de un movimiento solo la editan admin y coordinador
--     (schema_v62), con la misma función.

-- ---------------------------------------------------------------------
-- 1. El flag, en la REFERENCIA (ser kit es propiedad del modelo)
-- ---------------------------------------------------------------------

alter table activo_referencias
  add column es_kit boolean not null default false;

-- Inmutable en cuanto la referencia tenga equipos. Es la regla que sostiene
-- todo lo demás: marcar como kit una referencia con equipos les pondría el
-- valor en $0; quitárselo dejaría sus componentes huérfanos.
create or replace function fn_es_kit_inmutable() returns trigger
language plpgsql as $$
begin
  if new.es_kit is distinct from old.es_kit
     and exists (select 1 from activos where referencia_id = old.id) then
    raise exception 'No se puede cambiar si la referencia es un kit: ya tiene equipos creados. Crea otra referencia.';
  end if;
  return new;
end;
$$;

create trigger trg_es_kit_inmutable
  before update of es_kit on activo_referencias
  for each row execute function fn_es_kit_inmutable();

-- ---------------------------------------------------------------------
-- 2. Los componentes
-- ---------------------------------------------------------------------

create table activo_componentes (
  id             uuid primary key default extensions.uuid_generate_v4(),
  activo_id      uuid not null references activos(id),
  nombre         text not null check (btrim(nombre) <> ''),
  valor_unitario numeric not null default 0 check (valor_unitario >= 0),
  -- DERIVADA de los movimientos. Si alguien la escribe a mano, el trigger
  -- de abajo la sobreescribe con la suma verdadera.
  cantidad       numeric not null default 0 check (cantidad >= 0),
  subtotal       numeric generated always as
                   (round(cantidad * valor_unitario, 2)) stored,
  orden          int not null default 0,
  creado_por     uuid,
  creado_email   text,
  creado_en      timestamptz not null default now()
);

-- Misma normalización que activo_referencias_uniq y activo_terceros_uniq:
-- "TELA MEDIOS" y "tela  medios" son el mismo componente.
create unique index activo_componentes_uniq on activo_componentes
  (activo_id, upper(regexp_replace(btrim(nombre), '\s+', ' ', 'g')));
create index idx_activo_comp_activo on activo_componentes (activo_id, orden);

-- ---------------------------------------------------------------------
-- 3. La vida del kit: los movimientos de componente
-- ---------------------------------------------------------------------

create table activo_componente_movimientos (
  id             uuid primary key default extensions.uuid_generate_v4(),
  componente_id  uuid not null references activo_componentes(id),
  tipo           text not null check (tipo in (
                   'alta', 'aumento', 'disminucion',
                   'salida_venta', 'salida_garantia', 'baja_dano',
                   'anulacion')),
  -- Se ESTAMPA al insertar: +1 suma, -1 resta. La anulación toma el signo
  -- contrario del original. Así la cantidad es simplemente suma(signo*cant).
  signo          smallint not null default 1 check (signo in (-1, 1)),
  cantidad       numeric not null check (cantidad > 0),
  -- Estampado: lo que pasó, pasó a ese precio (como el valor de una salida).
  valor_unitario numeric not null default 0 check (valor_unitario >= 0),
  tercero_id     uuid references activo_terceros(id),
  anula_movimiento_id uuid references activo_componente_movimientos(id),
  observacion    text,
  usuario_id     uuid,
  usuario_email  text,
  fecha          timestamptz not null default now(),
  creado_en      timestamptz not null default now(),
  -- Vender o dar en garantía sin decir a quién no tiene sentido.
  constraint activo_comp_mov_tercero_check
    check (tipo not in ('salida_venta', 'salida_garantia') or tercero_id is not null),
  -- Una anulación siempre apunta al movimiento que anula, y solo ella.
  constraint activo_comp_mov_anula_check
    check ((tipo = 'anulacion') = (anula_movimiento_id is not null))
);

-- Un movimiento se anula UNA sola vez (igual que activo_movimientos_anula_uniq).
create unique index activo_comp_mov_anula_uniq
  on activo_componente_movimientos (anula_movimiento_id)
  where anula_movimiento_id is not null;

-- Regla de históricos del proyecto: del más reciente al más antiguo.
create index idx_activo_comp_mov
  on activo_componente_movimientos (componente_id, fecha desc);

-- ---------------------------------------------------------------------
-- 4. Reglas al insertar un movimiento de componente
-- ---------------------------------------------------------------------

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
    select * into v_orig from activo_componente_movimientos
     where id = new.anula_movimiento_id;
    if v_orig.id is null or v_orig.componente_id <> new.componente_id then
      raise exception 'El movimiento a anular no es de este componente';
    end if;
    if v_orig.tipo = 'anulacion' then
      raise exception 'Una anulación no se anula: registra un movimiento nuevo';
    end if;
    -- Mensaje claro. El índice único activo_comp_mov_anula_uniq sigue siendo
    -- la garantía de fondo: esto lo gana una carrera de dos toques, él no.
    if exists (select 1 from activo_componente_movimientos
                where anula_movimiento_id = new.anula_movimiento_id) then
      raise exception 'Este movimiento ya fue anulado';
    end if;
    -- Deshace exactamente lo que hizo el original.
    new.signo          := -v_orig.signo;
    new.cantidad       := v_orig.cantidad;
    new.valor_unitario := v_orig.valor_unitario;
  else
    -- Mensaje claro antes de que lo ataje activo_comp_mov_tercero_check.
    if new.tipo in ('salida_venta', 'salida_garantia') and new.tercero_id is null then
      raise exception 'Para vender o dar en garantía hay que decir a quién (el tercero)';
    end if;
    new.signo := case when new.tipo in ('alta', 'aumento') then 1 else -1 end;
    new.valor_unitario := v_comp.valor_unitario;
  end if;

  -- El usuario lo pone la base, no la app.
  if auth.uid() is not null then
    new.usuario_id    := auth.uid();
    new.usuario_email := (select email from profiles where id = auth.uid());
  end if;
  return new;
end;
$$;

create trigger trg_preparar_mov_componente
  before insert on activo_componente_movimientos
  for each row execute function fn_preparar_mov_componente();

-- Después de insertar, la cantidad del componente se recalcula.
create or replace function fn_mov_componente_recalcular() returns trigger
language plpgsql as $$
begin
  -- Basta con "tocar" la fila: el trigger BEFORE de activo_componentes
  -- recalcula la cantidad desde los movimientos.
  update activo_componentes set cantidad = cantidad where id = new.componente_id;
  return null;
end;
$$;

create trigger trg_mov_componente_recalcular
  after insert on activo_componente_movimientos
  for each row execute function fn_mov_componente_recalcular();

-- Candado: un movimiento no se edita, se anula. Solo la observación cambia.
-- La lista nombra TODAS las columnas (lección de schema_v63).
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
  return new;
end;
$$;

create trigger trg_mov_componente_solo_obs
  before update on activo_componente_movimientos
  for each row execute function fn_mov_componente_solo_obs();

-- La observación, como las demás del módulo: solo admin y coordinador.
create trigger trg_obs_solo_coord
  before update of observacion on activo_componente_movimientos
  for each row execute function fn_observacion_solo_coordinador('observacion');

-- ---------------------------------------------------------------------
-- 5. Reglas del componente: cantidad derivada, solo en kits
-- ---------------------------------------------------------------------

create or replace function fn_preparar_componente() returns trigger
language plpgsql as $$
declare
  v_suma   numeric;
  v_es_kit boolean;
  v_estado text;
begin
  if tg_op = 'INSERT' then
    select r.es_kit, a.estado into v_es_kit, v_estado
      from activos a join activo_referencias r on r.id = a.referencia_id
     where a.id = new.activo_id;
    if not coalesce(v_es_kit, false) then
      raise exception 'Solo un equipo cuya referencia es un kit puede tener componentes';
    end if;
    if v_estado = 'entregado' then
      raise exception 'Este kit fue entregado y ya no nos pertenece: no se le pueden agregar componentes';
    end if;
    if auth.uid() is not null then
      new.creado_por   := auth.uid();
      new.creado_email := (select email from profiles where id = auth.uid());
    end if;
  elsif new.activo_id is distinct from old.activo_id then
    raise exception 'Un componente no se cambia de equipo';
  end if;

  -- La cantidad NUNCA la decide quien escribe: es la suma de los movimientos.
  select coalesce(sum(signo * cantidad), 0) into v_suma
    from activo_componente_movimientos where componente_id = new.id;
  if v_suma < 0 then
    raise exception 'No hay suficientes "%": quedarían %', new.nombre, v_suma;
  end if;
  new.cantidad := v_suma;
  return new;
end;
$$;

create trigger trg_preparar_componente
  before insert or update on activo_componentes
  for each row execute function fn_preparar_componente();

-- Cada cambio de un componente recalcula el valor del equipo.
create or replace function fn_componente_recalcular_kit() returns trigger
language plpgsql as $$
begin
  -- "Tocar" el equipo: su trigger BEFORE recalcula valor_nuevo.
  update activos set valor_nuevo = valor_nuevo
   where id = coalesce(new.activo_id, old.activo_id);
  return null;
end;
$$;

create trigger trg_componente_recalcular_kit
  after insert or update or delete on activo_componentes
  for each row execute function fn_componente_recalcular_kit();

-- ---------------------------------------------------------------------
-- 6. El valor del KIT es la suma de sus componentes
-- ---------------------------------------------------------------------
--
-- valor_actual NO se toca: sigue siendo la columna generada
-- valor_nuevo * porcentaje / 100, que consumen seis funciones. Lo único que
-- cambia es quién escribe valor_nuevo cuando la referencia es un kit.
--
-- Ponderar cada componente y sumar da lo mismo que ponderar el total
-- ($1.540.000 x 70% = $1.078.000 por los dos caminos), y aplicar el
-- porcentaje UNA vez al total evita el arrastre de redondeo.

create or replace function fn_valor_kit() returns trigger
language plpgsql as $$
begin
  if exists (select 1 from activo_referencias
              where id = new.referencia_id and es_kit) then
    select coalesce(sum(subtotal), 0) into new.valor_nuevo
      from activo_componentes where activo_id = new.id;
  end if;
  return new;
end;
$$;

create trigger trg_valor_kit
  before insert or update on activos
  for each row execute function fn_valor_kit();

-- ---------------------------------------------------------------------
-- 7. Crear un componente: UNA operación
-- ---------------------------------------------------------------------
--
-- Componente + su movimiento de alta, juntos. Si fueran dos inserciones
-- desde la app, un corte de red en medio dejaría un componente en cero sin
-- historia. SECURITY INVOKER: aplica la RLS de quien llama.

create or replace function agregar_componente(
  p_activo uuid,
  p_nombre text,
  p_cantidad numeric,
  p_valor_unitario numeric,
  p_orden int default 0,
  p_observacion text default null)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
begin
  if coalesce(p_cantidad, 0) <= 0 then
    raise exception 'La cantidad de "%" tiene que ser mayor que cero', p_nombre;
  end if;

  insert into activo_componentes (activo_id, nombre, valor_unitario, orden)
  values (p_activo, btrim(p_nombre), coalesce(p_valor_unitario, 0), p_orden)
  returning id into v_id;

  insert into activo_componente_movimientos (componente_id, tipo, cantidad, observacion)
  values (v_id, 'alta', p_cantidad, p_observacion);

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. La plantilla: la composición del kit MÁS RECIENTE de la referencia
-- ---------------------------------------------------------------------
--
-- Del más reciente y no del primero: si en el kit 7 se ajustó la
-- composición, los kits 8 al 50 heredan la buena. Solo lo que sigue en el
-- kit (cantidad > 0). Es una SUGERENCIA para el formulario de alta: cada
-- equipo es dueño de sus componentes, no hay vínculo vivo.

create or replace function plantilla_kit(p_referencia uuid)
returns table (nombre text, cantidad numeric, valor_unitario numeric,
               orden int, desde_serial text)
language sql stable
set search_path = public
as $$
  with origen as (
    select a.id, a.serial
      from activos a
     where a.referencia_id = p_referencia
       and exists (select 1 from activo_componentes c
                    where c.activo_id = a.id and c.cantidad > 0)
     order by a.creado_en desc
     limit 1
  )
  select c.nombre, c.cantidad, c.valor_unitario, c.orden, o.serial
    from origen o
    join activo_componentes c on c.activo_id = o.id
   where c.cantidad > 0
   order by c.orden, c.nombre;
$$;

-- ---------------------------------------------------------------------
-- 9. Permisos (RLS) — los mismos del módulo. Sin DELETE: con historia,
--    nada se borra (se lleva a cero o se anula).
-- ---------------------------------------------------------------------

alter table activo_componentes enable row level security;
create policy equipos_sel on activo_componentes for select
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_ins on activo_componentes for insert
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_upd on activo_componentes for update
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'))
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));

alter table activo_componente_movimientos enable row level security;
create policy equipos_sel on activo_componente_movimientos for select
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_ins on activo_componente_movimientos for insert
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));
create policy equipos_upd on activo_componente_movimientos for update
  using (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'))
  with check (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos'));

-- ---------------------------------------------------------------------
-- 10. Auditoría
-- ---------------------------------------------------------------------

create trigger trg_aud_activo_componentes
  after insert or delete or update on activo_componentes
  for each row execute function fn_auditoria();

create trigger trg_aud_activo_componente_movimientos
  after insert or delete or update on activo_componente_movimientos
  for each row execute function fn_auditoria();

-- La pantalla de auditoría: que las tablas nuevas se lean por serial y
-- componente, no por códigos sueltos, y que salgan en la categoría Equipos.
-- De paso entra activo_observaciones (schema_v54), que nunca se agregó a esa
-- categoría: las ediciones de observaciones no salían en el filtro.
create or replace function public.auditoria_clasificada(
  p_categoria text default null::text, p_q text default null::text,
  p_limit integer default 10, p_offset integer default 0)
 returns table(fecha timestamp with time zone, accion text, campo text,
               valor_anterior text, valor_nuevo text, usuario_email text,
               tabla text, afectado text)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not (public.es_admin() or public.tiene_rol('coordinador')) then
    raise exception 'Solo admin o coordinador pueden ver la auditoría';
  end if;

  return query
  with con_nombre as (
    select a.fecha, a.accion, a.campo, a.valor_anterior, a.valor_nuevo,
      a.usuario_email, a.tabla,
      case when a.tabla = 'movimientos'
           then (select m.tipo from movimientos m where m.id = a.registro_id)
           when a.tabla = 'activo_movimientos'
           then (select m.tipo from activo_movimientos m where m.id = a.registro_id)
           end as mov_tipo,
      coalesce(
        -- 1) La tabla viva.
        case a.tabla
          when 'movimientos' then
            (select e.nombre from movimientos m join elementos e on e.id = m.elemento_id
               where m.id = a.registro_id)
          when 'elementos' then (select nombre from elementos where id = a.registro_id)
          when 'bodegas'   then (select nombre from bodegas   where id = a.registro_id)
          when 'centros_costo' then (select codigo from centros_costo where id = a.registro_id)
          when 'usuario_roles' then (select email from profiles where id = a.registro_id)
          when 'aprovechamiento_trozos' then
            (select e.nombre from aprovechamiento_trozos t join elementos e on e.id = t.elemento_id
               where t.id = a.registro_id)
          when 'aprovechamiento_salidas' then
            (select e.nombre from aprovechamiento_salidas s
               join aprovechamiento_trozos t on t.id = s.trozo_id
               join elementos e on e.id = t.elemento_id
               where s.id = a.registro_id)
          -- EQUIPOS: un equipo se identifica por su serial, no por un nombre.
          when 'activos' then (select serial from activos where id = a.registro_id)
          when 'activo_referencias' then
            (select nombre from activo_referencias where id = a.registro_id)
          when 'activo_terceros' then
            (select nombre from activo_terceros where id = a.registro_id)
          when 'activo_movimientos' then
            (select x.serial from activo_movimientos m join activos x on x.id = m.activo_id
               where m.id = a.registro_id)
          when 'activo_ubicaciones' then
            (select x.serial from activo_ubicaciones u join activos x on x.id = u.activo_id
               where u.id = a.registro_id)
          when 'activo_piezas' then
            (select x.serial || ' · ' || p.nombre from activo_piezas p
               join activos x on x.id = p.activo_id where p.id = a.registro_id)
          when 'activo_mantenimientos' then
            (select x.serial from activo_mantenimientos mt join activos x on x.id = mt.activo_id
               where mt.id = a.registro_id)
          when 'activo_observaciones' then
            (select x.serial from activo_observaciones o join activos x on x.id = o.activo_id
               where o.id = a.registro_id)
          when 'activo_componentes' then
            (select x.serial || ' · ' || c.nombre from activo_componentes c
               join activos x on x.id = c.activo_id where c.id = a.registro_id)
          when 'activo_componente_movimientos' then
            (select x.serial || ' · ' || c.nombre from activo_componente_movimientos cm
               join activo_componentes c on c.id = cm.componente_id
               join activos x on x.id = c.activo_id where cm.id = a.registro_id)
          else null
        end,
        -- 2) Lo que quedó guardado en ESTA misma fila (INSERT/DELETE).
        a.datos->>'codigo',
        a.datos->>'nombre',
        a.datos->>'email',
        a.datos->>'serial',
        -- 3) Lo que quedó guardado en CUALQUIER otra fila del mismo
        --    registro: así un UPDATE hereda el nombre de su INSERT.
        (select coalesce(a2.datos->>'codigo', a2.datos->>'nombre',
                         a2.datos->>'email', a2.datos->>'serial')
           from auditoria a2
          where a2.tabla = a.tabla
            and a2.registro_id = a.registro_id
            and a2.datos is not null
          order by a2.fecha
          limit 1)
      ) as afectado
    from auditoria a
  )
  select c.fecha, c.accion, c.campo, c.valor_anterior, c.valor_nuevo,
         c.usuario_email, c.tabla,
         coalesce(c.afectado, '(registro eliminado)') as afectado
  from con_nombre c
  where (
      p_categoria is null or p_categoria in ('', 'recientes')
      or (p_categoria = 'usuarios' and c.tabla = 'usuario_roles')
      or (p_categoria = 'bodegas'  and c.tabla = 'bodegas')
      or (p_categoria = 'centros'  and c.tabla = 'centros_costo')
      or (p_categoria = 'aprovechamientos'
          and c.tabla in ('aprovechamiento_trozos', 'aprovechamiento_salidas'))
      or (p_categoria = 'entradas' and c.tabla = 'movimientos' and c.mov_tipo = 'entrada')
      or (p_categoria = 'salidas'  and c.tabla = 'movimientos' and c.mov_tipo = 'salida')
      -- Todo el módulo de Equipos, y aparte solo sus entradas/salidas.
      or (p_categoria = 'equipos' and c.tabla in
            ('activos','activo_referencias','activo_terceros','activo_movimientos',
             'activo_ubicaciones','activo_piezas','activo_mantenimientos',
             'activo_observaciones','activo_componentes',
             'activo_componente_movimientos'))
      or (p_categoria = 'equipos_mov' and c.tabla = 'activo_movimientos')
    )
    and (p_q is null or p_q = ''
         or coalesce(c.afectado, '')      ilike '%' || p_q || '%'
         or coalesce(c.usuario_email, '') ilike '%' || p_q || '%')
  order by c.fecha desc
  limit p_limit offset p_offset;
end $function$;
