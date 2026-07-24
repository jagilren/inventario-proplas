-- =====================================================================
--  INVENTARIO PROPLAS · schema_v13 · APROVECHAMIENTOS (trozos/retazos)
--
--  Inventario PARALELO e independiente de trozos sobrantes, valorizados a
--  $0. NO toca las existencias oficiales, ni la valorización, ni los informes.
--  Reutiliza el catálogo (elementos), las bodegas (ubicación) y los centros
--  de costo.
--
--  CONSUMO PARCIAL: un trozo se puede ir sacando por sub-segmentos. Cada
--  trozo tiene longitud inicial y longitud_actual (lo que queda). Cuando
--  llega a 0, queda consumido. Cada sub-salida se registra en una tabla
--  aparte (con su cantidad y centro de costo).
-- =====================================================================

drop table if exists aprovechamiento_salidas cascade;
drop table if exists aprovechamiento_trozos  cascade;

-- ---- Trozos (piezas físicas aprovechables) --------------------------
create table aprovechamiento_trozos (
  id              uuid primary key default uuid_generate_v4(),
  elemento_id     uuid not null references elementos(id) on delete cascade,
  longitud        numeric(18,3) not null check (longitud > 0),   -- inicial
  longitud_actual numeric(18,3) not null check (longitud_actual >= 0), -- disponible
  bodega_id       uuid references bodegas(id),                   -- ubicación
  observacion     text,
  creado_por      uuid,
  creado_en       timestamptz not null default now(),
  consumido_en    timestamptz                                    -- cuando llega a 0
);
create index idx_aprov_disp on aprovechamiento_trozos (elemento_id)
  where longitud_actual > 0;

-- ---- Sub-salidas (cada segmento que se saca de un trozo) ------------
create table aprovechamiento_salidas (
  id              uuid primary key default uuid_generate_v4(),
  trozo_id        uuid not null references aprovechamiento_trozos(id) on delete cascade,
  cantidad        numeric(18,3) not null check (cantidad > 0),
  centro_costo_id uuid references centros_costo(id),
  observacion     text,
  usuario_id      uuid,
  fecha           timestamptz not null default now()
);
create index idx_aprov_sal_trozo on aprovechamiento_salidas (trozo_id);

-- ---- Trigger: al ingresar, el saldo disponible arranca = longitud ---
create or replace function public.fn_aprov_ini()
returns trigger language plpgsql as $$
begin
  if new.longitud_actual is null then
    new.longitud_actual := new.longitud;
  end if;
  return new;
end $$;

drop trigger if exists trg_aprov_ini on aprovechamiento_trozos;
create trigger trg_aprov_ini before insert on aprovechamiento_trozos
  for each row execute function public.fn_aprov_ini();

-- ---- Trigger: al registrar una sub-salida, descuenta del trozo ------
create or replace function public.fn_aprov_salida()
returns trigger language plpgsql security definer set search_path = public as $$
declare rem numeric;
begin
  select longitud_actual into rem
    from aprovechamiento_trozos where id = new.trozo_id for update;
  if rem is null then raise exception 'Trozo no existe'; end if;
  if new.cantidad > rem then
    raise exception 'No hay tanto en el trozo (quedan %)', rem;
  end if;
  update aprovechamiento_trozos
     set longitud_actual = longitud_actual - new.cantidad,
         consumido_en = case when longitud_actual - new.cantidad <= 0
                             then now() else null end
   where id = new.trozo_id;
  return new;
end $$;

drop trigger if exists trg_aprov_salida on aprovechamiento_salidas;
create trigger trg_aprov_salida before insert on aprovechamiento_salidas
  for each row execute function public.fn_aprov_salida();

-- ---- RLS ------------------------------------------------------------
alter table aprovechamiento_trozos  enable row level security;
alter table aprovechamiento_salidas enable row level security;

-- Ver: cualquier autenticado.
drop policy if exists aprov_sel on aprovechamiento_trozos;
create policy aprov_sel on aprovechamiento_trozos for select to authenticated using (true);
drop policy if exists aprov_sal_sel on aprovechamiento_salidas;
create policy aprov_sal_sel on aprovechamiento_salidas for select to authenticated using (true);

-- Ingresar trozo (ENTRADA): operario+ o admin.
drop policy if exists aprov_ins on aprovechamiento_trozos;
create policy aprov_ins on aprovechamiento_trozos for insert to authenticated
  with check (public.es_admin() or public.tiene_rol('operario_mas'));

-- Sacar sub-segmento (SALIDA): operario- o admin. El trigger descuenta.
drop policy if exists aprov_sal_ins on aprovechamiento_salidas;
create policy aprov_sal_ins on aprovechamiento_salidas for insert to authenticated
  with check (public.es_admin() or public.tiene_rol('operario_menos'));

-- Borrar trozo (corrección): admin o coordinador.
drop policy if exists aprov_del on aprovechamiento_trozos;
create policy aprov_del on aprovechamiento_trozos for delete to authenticated
  using (public.es_admin() or public.tiene_rol('coordinador'));
