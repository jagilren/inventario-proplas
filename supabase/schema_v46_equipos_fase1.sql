-- =====================================================================
--  INVENTARIO PROPLAS · schema_v46 · Módulo de EQUIPOS — Fase 1 (SQL)
--
--  Diseño completo en docs/plan-modulo-equipos.md (sesión 2026-09-09).
--  Reemplaza por completo el borrador viejo schema_v19_activos.sql, que
--  nunca se aplicó. Módulo APARTE del inventario de venta (elementos) y
--  de Aprovechamientos: sin ninguna FK hacia esas tablas
--  (activos-no-son-elementos.md), solo comparte bodegas, centros_costo,
--  usuarios/roles y el mecanismo de auditoría.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. activo_referencias — catálogo de modelos (evita fragmentar texto
--    libre, misma razón que existe la maestra "materiales").
-- ---------------------------------------------------------------------
create table if not exists activo_referencias (
  id            uuid primary key default uuid_generate_v4(),
  nombre        text not null,
  marca         text,
  modelo        text,
  tipo          text,
  ficha_tipica  jsonb not null default '{}'::jsonb,
  activo        boolean not null default true
);
create index if not exists idx_activo_ref_activo on activo_referencias (activo);

-- ---------------------------------------------------------------------
-- 2. activo_terceros — catálogo de talleres/clientes/proveedores
--    externos (para activo_ubicaciones). Igual que arriba: catálogo,
--    nunca texto libre.
-- ---------------------------------------------------------------------
create table if not exists activo_terceros (
  id        uuid primary key default uuid_generate_v4(),
  nombre    text not null,
  tipo      text check (tipo in ('taller','cliente','proveedor','otro')),
  contacto  text,
  activo    boolean not null default true
);
create index if not exists idx_activo_terceros_activo on activo_terceros (activo);

-- ---------------------------------------------------------------------
-- 3. activos — cada unidad física, individual y SIEMPRE serializada.
--    condicion = clasificación comercial. estado = disponibilidad
--    operativa. Son preguntas distintas (sección 3.2 del plan).
-- ---------------------------------------------------------------------
create table if not exists activos (
  id                uuid primary key default uuid_generate_v4(),
  referencia_id     uuid not null references activo_referencias(id),
  serial            text not null unique,
  condicion         text not null check (condicion in ('nuevo','usado','repuestos','baja')),
  estado            text not null default 'operativo'
                      check (estado in ('operativo','mantenimiento_interno',
                                        'mantenimiento_externo','entregado','baja')),
  -- Solo aplica si estado='mantenimiento_externo'. Texto libre A PROPÓSITO
  -- (decisión explícita del usuario, sección 3.2 del plan): no pasa por
  -- el catálogo activo_terceros.
  mantenimiento_actor  text,
  bodega_id         uuid not null references bodegas(id),  -- bodega DUEÑA (RPCI/PROPLAS)
  valor_nuevo       numeric(18,2) not null default 0,
  porcentaje_valor  numeric(5,2) not null default 100 check (porcentaje_valor between 0 and 100),
  valor_actual      numeric(18,2) generated always as
                      (round(valor_nuevo * porcentaje_valor / 100, 2)) stored,
  ficha             jsonb not null default '{}'::jsonb,
  observacion       text,
  creado_por        uuid,
  creado_email      text,
  creado_en         timestamptz not null default now()
);
create index if not exists idx_activos_referencia on activos (referencia_id);
create index if not exists idx_activos_estado on activos (estado);
create index if not exists idx_activos_bodega on activos (bodega_id);

-- ---------------------------------------------------------------------
-- 4. activo_ubicaciones — historial de ubicación FÍSICA (kardex de
--    ubicación). NO afecta inventario/existencia. bodega_id XOR
--    tercero_id: "propia" es estructural (apunta a bodegas real), nunca
--    por convención (sección 3.4 del plan).
-- ---------------------------------------------------------------------
create table if not exists activo_ubicaciones (
  id            uuid primary key default uuid_generate_v4(),
  activo_id     uuid not null references activos(id),
  bodega_id     uuid references bodegas(id),
  tercero_id    uuid references activo_terceros(id),
  detalle       text,
  fecha_desde   timestamptz not null default now(),
  fecha_hasta   timestamptz,   -- null = la ubicación ACTUAL
  usuario_id    uuid,
  usuario_email text,
  creado_en     timestamptz not null default now(),
  constraint chk_ubicacion_bodega_xor_tercero check (
    (bodega_id is not null and tercero_id is null) or
    (bodega_id is null and tercero_id is not null)
  )
);
create index if not exists idx_activo_ubic_activo on activo_ubicaciones (activo_id, fecha_desde desc);
-- Nunca dos ubicaciones "vigentes" (fecha_hasta null) a la vez para el mismo equipo.
create unique index if not exists idx_activo_ubic_vigente
  on activo_ubicaciones (activo_id) where fecha_hasta is null;

-- ---------------------------------------------------------------------
-- 5. activo_piezas — lista libre de piezas buenas/malas por equipo
--    (decisión tomada: lista libre, no integrable a Existencias por
--    ahora, sección 3.5 del plan).
-- ---------------------------------------------------------------------
create table if not exists activo_piezas (
  id               uuid primary key default uuid_generate_v4(),
  activo_id        uuid not null references activos(id),
  nombre           text not null,
  estado           text not null default 'desconocido'
                     check (estado in ('buena','mala','desconocido')),
  observacion      text,
  actualizado_por   uuid,
  actualizado_email text,
  actualizado_en    timestamptz not null default now()
);
create index if not exists idx_activo_piezas_activo on activo_piezas (activo_id);

-- ---------------------------------------------------------------------
-- 6. activo_mantenimientos — hoja de vida (intervenciones registradas).
-- ---------------------------------------------------------------------
create table if not exists activo_mantenimientos (
  id            uuid primary key default uuid_generate_v4(),
  activo_id     uuid not null references activos(id),
  fecha         date not null default current_date,
  tipo          text,
  descripcion   text not null,
  responsable   text,
  costo         numeric(18,2) not null default 0,
  usuario_id    uuid,
  usuario_email text,
  creado_en     timestamptz not null default now()
);
create index if not exists idx_activo_mant_activo on activo_mantenimientos (activo_id, fecha desc);

-- ---------------------------------------------------------------------
-- 7. activo_movimientos — entrada/salida/ajuste REAL (sí afecta
--    inventario). Unificada (no dos tablas), mismo criterio de
--    "un campo cambia de rol según tipo" que ya usa `movimientos`
--    (sección 3.7 del plan).
-- ---------------------------------------------------------------------
create table if not exists activo_movimientos (
  id                        uuid primary key default uuid_generate_v4(),
  activo_id                 uuid not null references activos(id),
  tipo                      text not null check (tipo in ('entrada','salida','ajuste')),
  anula_movimiento_id       uuid references activo_movimientos(id),

  -- SALIDA: a quién se entrega (obligatorio en la app, resta inventario).
  -- ENTRADA: de dónde viene (obligatorio en la app).
  centro_costo_id           uuid references centros_costo(id),
  -- Solo ENTRADA: a quién queda atribuido (interno, informativo).
  centro_costo_destino_id   uuid references centros_costo(id),
  -- Solo ENTRADA: bodega física donde entra.
  bodega_id                 uuid references bodegas(id),

  -- Solo ENTRADA: snapshot en ese momento. Nunca 'repuestos' aquí — esa
  -- condición es exclusivamente una reclasificación posterior manual
  -- sobre `activos.condicion` (sección 3.2 y punto 10.4 del plan).
  condicion                 text check (condicion in ('nuevo','usado','baja')),
  -- Solo ENTRADA, solo si condicion='usado'.
  usable                    boolean,

  valor                     numeric(18,2),
  observacion               text,
  usuario_id                uuid,
  usuario_email             text,
  fecha                     timestamptz not null default now(),
  creado_en                 timestamptz not null default now()
);
create index if not exists idx_activo_mov_activo on activo_movimientos (activo_id, fecha desc);
create index if not exists idx_activo_mov_centro on activo_movimientos (centro_costo_id);
create index if not exists idx_activo_mov_fecha on activo_movimientos (fecha desc);
-- Mismo mecanismo que movimientos_anula_uniq: nunca se anula dos veces.
create unique index if not exists activo_movimientos_anula_uniq
  on activo_movimientos (anula_movimiento_id) where anula_movimiento_id is not null;

-- =====================================================================
--  VISTA: disponibilidad — regla DERIVADA, nunca un campo manual
--  (sección 3.8 del plan). security_invoker: respeta la RLS de quien
--  consulta, no la del dueño de la vista.
-- =====================================================================
create or replace view activos_disponibilidad
  with (security_invoker = true) as
select
  a.*,
  au.bodega_id   as ubicacion_actual_bodega_id,
  au.tercero_id  as ubicacion_actual_tercero_id,
  au.fecha_desde as ubicacion_actual_desde,
  (a.estado = 'operativo' and au.bodega_id is not null) as disponible
from activos a
left join activo_ubicaciones au
  on au.activo_id = a.id and au.fecha_hasta is null;

-- =====================================================================
--  TRIGGERS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Inmutabilidad de activo_movimientos: solo se puede editar
-- `observacion` después de creado (mismo candado que fn_mov_solo_observacion
-- sobre `movimientos`, pero con las columnas propias de esta tabla).
-- ---------------------------------------------------------------------
create or replace function public.fn_activo_mov_solo_observacion()
returns trigger
language plpgsql
as $$
begin
  if (new.tipo, new.activo_id, new.centro_costo_id, new.centro_costo_destino_id,
      new.bodega_id, new.condicion, new.usable, new.valor,
      new.usuario_id, new.usuario_email, new.fecha, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.activo_id, old.centro_costo_id, old.centro_costo_destino_id,
      old.bodega_id, old.condicion, old.usable, old.valor,
      old.usuario_id, old.usuario_email, old.fecha, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento de equipo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_activo_mov_solo_obs on activo_movimientos;
create trigger trg_activo_mov_solo_obs
  before update on activo_movimientos
  for each row execute function public.fn_activo_mov_solo_observacion();

-- ---------------------------------------------------------------------
-- BEFORE INSERT: en una SALIDA, si no mandaron valor, se estampa con el
-- valor_actual vigente del equipo en ese momento (mismo criterio que
-- fn_estampar_costo_salida en movimientos: solo si viene null, nunca
-- pisa un valor que sí mandaron).
-- ---------------------------------------------------------------------
create or replace function public.fn_estampar_valor_activo_salida()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.tipo = 'salida' and new.valor is null then
    select a.valor_actual into new.valor from activos a where a.id = new.activo_id;
    new.valor := coalesce(new.valor, 0);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_estampar_valor_activo_salida on activo_movimientos;
create trigger trg_estampar_valor_activo_salida
  before insert on activo_movimientos
  for each row execute function public.fn_estampar_valor_activo_salida();

-- ---------------------------------------------------------------------
-- AFTER INSERT: la lógica de negocio real. Entrada/salida/ajuste
-- cambian `activos.estado`; una entrada además abre la ubicación nueva
-- (cerrando la anterior) en un solo paso (sección 3.7 del plan).
-- ---------------------------------------------------------------------
create or replace function public.fn_aplicar_activo_movimiento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  original record;
begin
  if new.tipo = 'salida' then
    update activos set estado = 'entregado' where id = new.activo_id;

  elsif new.tipo = 'entrada' then
    if new.condicion = 'nuevo' or (new.condicion = 'usado' and new.usable) then
      update activos set estado = 'operativo' where id = new.activo_id;
    elsif new.condicion = 'usado' and not coalesce(new.usable, false) then
      update activos set estado = 'mantenimiento_interno' where id = new.activo_id;
    elsif new.condicion = 'baja' then
      update activos set estado = 'baja' where id = new.activo_id;
    end if;

    -- Abre la ubicación nueva, cerrando la vigente (si había una).
    if new.bodega_id is not null then
      update activo_ubicaciones
         set fecha_hasta = new.fecha
       where activo_id = new.activo_id and fecha_hasta is null;

      insert into activo_ubicaciones
        (activo_id, bodega_id, fecha_desde, usuario_id, usuario_email)
      values
        (new.activo_id, new.bodega_id, new.fecha, new.usuario_id, new.usuario_email);
    end if;

  elsif new.tipo = 'ajuste' then
    select * into original from activo_movimientos where id = new.anula_movimiento_id;
    if original.tipo = 'salida' then
      update activos set estado = 'operativo' where id = new.activo_id;
    elsif original.tipo = 'entrada' then
      update activos set estado = 'entregado' where id = new.activo_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_aplicar_activo_movimiento on activo_movimientos;
create trigger trg_aplicar_activo_movimiento
  after insert on activo_movimientos
  for each row execute function public.fn_aplicar_activo_movimiento();

-- ---------------------------------------------------------------------
-- Auditoría: se reutiliza fn_auditoria() (genérica, ya usada por
-- movimientos/elementos/etc.) en las 7 tablas — sin inventar nada nuevo.
-- ---------------------------------------------------------------------
drop trigger if exists trg_aud_activo_referencias on activo_referencias;
create trigger trg_aud_activo_referencias
  after insert or update or delete on activo_referencias
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activo_terceros on activo_terceros;
create trigger trg_aud_activo_terceros
  after insert or update or delete on activo_terceros
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activos on activos;
create trigger trg_aud_activos
  after insert or update or delete on activos
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activo_ubicaciones on activo_ubicaciones;
create trigger trg_aud_activo_ubicaciones
  after insert or update or delete on activo_ubicaciones
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activo_piezas on activo_piezas;
create trigger trg_aud_activo_piezas
  after insert or update or delete on activo_piezas
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activo_mantenimientos on activo_mantenimientos;
create trigger trg_aud_activo_mantenimientos
  after insert or update or delete on activo_mantenimientos
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_activo_movimientos on activo_movimientos;
create trigger trg_aud_activo_movimientos
  after insert or update or delete on activo_movimientos
  for each row execute function public.fn_auditoria();

-- =====================================================================
--  FUNCIONES RPC
-- =====================================================================

-- ---------------------------------------------------------------------
-- cambiar_ubicacion_activo: cierra la ubicación vigente y abre la nueva
-- en un solo paso (sección 3.4 del plan). Sirve también para "Marcar
-- regreso a bodega" (se llama con p_bodega_id = la bodega dueña).
-- ---------------------------------------------------------------------
create or replace function public.cambiar_ubicacion_activo(
  p_activo uuid,
  p_bodega_id uuid default null,
  p_tercero_id uuid default null,
  p_detalle text default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos')) then
    raise exception 'No tienes permiso para cambiar la ubicación de un equipo';
  end if;

  if (p_bodega_id is null) = (p_tercero_id is null) then
    raise exception 'Debes indicar exactamente una: bodega propia o tercero, no ambas ni ninguna';
  end if;

  update activo_ubicaciones
     set fecha_hasta = now()
   where activo_id = p_activo and fecha_hasta is null;

  insert into activo_ubicaciones (activo_id, bodega_id, tercero_id, detalle, usuario_id, usuario_email)
  values (p_activo, p_bodega_id, p_tercero_id, p_detalle,
          auth.uid(), (select email from profiles where id = auth.uid()));
end;
$$;

grant execute on function public.cambiar_ubicacion_activo(uuid, uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- anular_activo_movimiento: mismo patrón que anular_movimiento() —
-- nunca borra, inserta un 'ajuste' enlazado. El caso "alta nueva" (el
-- primer y único movimiento del equipo) se rechaza a propósito en vez
-- de adivinar un estado anterior que no existe (sección 3.7 del plan,
-- "Anulación — RESUELTO"): ahí corresponde borrar/inactivar el equipo
-- directo, no anular un movimiento.
-- ---------------------------------------------------------------------
create or replace function public.anular_activo_movimiento(
  p_mov uuid,
  p_motivo text default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  m record;
  es_primer_movimiento boolean;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede anular movimientos de equipos';
  end if;

  select * into m from activo_movimientos where id = p_mov;
  if not found then raise exception 'Movimiento no encontrado'; end if;

  if m.tipo = 'ajuste' then
    raise exception 'Ese movimiento ya es una anulación';
  end if;

  if exists (select 1 from activo_movimientos where anula_movimiento_id = p_mov) then
    raise exception 'Ese movimiento ya fue anulado';
  end if;

  if m.tipo = 'entrada' then
    select not exists (
      select 1 from activo_movimientos
       where activo_id = m.activo_id and id <> m.id and fecha < m.fecha
    ) into es_primer_movimiento;

    if es_primer_movimiento then
      raise exception 'Este es el primer movimiento del equipo (alta nueva): no se anula asi. Si fue un error de captura, borra o inactiva el equipo directamente.';
    end if;
  end if;

  begin
    insert into activo_movimientos (activo_id, tipo, anula_movimiento_id, observacion, usuario_id, usuario_email)
    values (m.activo_id, 'ajuste', p_mov, coalesce(p_motivo, 'Anulación de movimiento'),
            auth.uid(), (select email from profiles where id = auth.uid()));
  exception when unique_violation then
    raise exception 'Ese movimiento ya fue anulado';
  end;
end;
$$;

grant execute on function public.anular_activo_movimiento(uuid, text) to authenticated;

-- =====================================================================
--  RLS — sección 8.2 del plan: ver + editar exige admin, coordinador,
--  o el rol 'equipos' (acceso COMPLETO al módulo, no solo lectura).
--  El rol 'equipos' en sí (Roles.equipos en Dart) es tema de la Fase 3
--  (Navegación) — aquí solo se prepara la RLS para reconocerlo quien
--  ya tenga esa fila en usuario_roles.
-- =====================================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'activo_referencias','activo_terceros','activos',
    'activo_ubicaciones','activo_piezas','activo_mantenimientos',
    'activo_movimientos'
  ]
  loop
    execute format('alter table %I enable row level security', t);

    execute format('drop policy if exists equipos_sel on %I', t);
    execute format($p$
      create policy equipos_sel on %I for select to authenticated
      using (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
    $p$, t);

    execute format('drop policy if exists equipos_ins on %I', t);
    execute format($p$
      create policy equipos_ins on %I for insert to authenticated
      with check (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
    $p$, t);

    execute format('drop policy if exists equipos_upd on %I', t);
    execute format($p$
      create policy equipos_upd on %I for update to authenticated
      using (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
      with check (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
    $p$, t);

    execute format('drop policy if exists equipos_del on %I', t);
    execute format($p$
      create policy equipos_del on %I for delete to authenticated
      using (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
    $p$, t);
  end loop;
end $$;
