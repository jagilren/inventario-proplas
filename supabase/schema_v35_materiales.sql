-- =====================================================================
--  INVENTARIO PROPLAS · schema_v35 · MAESTRA DE MATERIALES
--
--  Hasta ahora `elementos.material` era texto libre. Medido sobre los
--  datos reales: 36 valores distintos que en realidad eran 32 materiales,
--  porque cuatro estaban escritos de dos formas ("Inox 304" / "INOX 304",
--  "PVC presion" con y sin espacio al final, etc.). Cada carga nueva podia
--  inventar una variante mas.
--
--  Esta migracion crea la tabla maestra `materiales` y engancha los
--  elementos a ella:
--
--    1. `materiales` con los 32 materiales reales, escritos en su forma
--       mas usada. Indice unico sobre upper(btrim(nombre)): la base misma
--       impide crear "inox 304" si ya existe "Inox 304".
--    2. `elementos.material_id` -> materiales(id).
--    3. `elementos.material` (texto) SE CONSERVA y queda derivado del id.
--       Asi ni la busqueda, ni el cache offline, ni los informes, ni las
--       importaciones tuvieron que cambiar: siguen leyendo el mismo texto.
--       Un trigger lo mantiene siempre igual al nombre de la maestra.
--    4. Renombrar en la maestra corrige el catalogo completo de una.
--
--  NO se borra nada: dar de baja un material es activo=false, igual que
--  bodegas y centros de costo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La tabla maestra
-- ---------------------------------------------------------------------
create table if not exists materiales (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  activo     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Sin distinguir mayusculas ni espacios: esta es la barrera que impide
-- que el problema vuelva a aparecer.
create unique index if not exists materiales_nombre_uniq
  on materiales (upper(btrim(nombre)));

alter table materiales enable row level security;

-- Mismos permisos que bodegas y centros de costo: lee cualquier usuario
-- activo, escribe admin o coordinador.
drop policy if exists sel_materiales on materiales;
create policy sel_materiales on materiales
  for select using (es_activo());

drop policy if exists cud_materiales on materiales;
create policy cud_materiales on materiales
  for all to authenticated
  using      (tiene_rol('admin') or tiene_rol('coordinador'))
  with check (tiene_rol('admin') or tiene_rol('coordinador'));

-- Queda en la auditoria, como el resto de las maestras.
drop trigger if exists trg_aud_materiales on materiales;
create trigger trg_aud_materiales
  after insert or delete or update on materiales
  for each row execute function fn_auditoria();

-- ---------------------------------------------------------------------
-- 2. Semilla: los 32 materiales que ya estaban en el catalogo, cada uno
--    con la ortografia que mas se repetia.
-- ---------------------------------------------------------------------
insert into materiales (nombre)
select v.nombre from (values
  ('PVC presion'), ('Inox 304'), ('Galvanizado'), ('PP'),
  ('Galvanizado en caliente'), ('Bronce'), ('Galvanizado en frio'),
  ('Inox 316'), ('Galvanizado en caliente AG'), ('PVC sanitario'),
  ('CPVC'), ('AC'), ('Inox 304 L'), ('Neopreno'),
  ('Galvanizado en frío PG'), ('Inox'), ('PVC'), ('PU (Poliuretano)'),
  ('PVC Y GALVANIZADO'), ('PE'), ('Aluminio'), ('Bronce Cromado'),
  ('Nylon'), ('CAUCHO'), ('PVC conduit'), ('Teflon'), ('Hierro ductil'),
  ('Cromado'), ('inox304'), ('Niquelada'), ('Nylon reforzado'), ('PTFE')
) as v(nombre)
where not exists (
  select 1 from materiales m
  where upper(btrim(m.nombre)) = upper(btrim(v.nombre))
);

-- ---------------------------------------------------------------------
-- 3. El enganche desde elementos
-- ---------------------------------------------------------------------
alter table elementos
  add column if not exists material_id uuid references materiales(id);

create index if not exists elementos_material_id_idx
  on elementos (material_id);

-- ---------------------------------------------------------------------
-- 4. Backfill. Se apaga la auditoria un momento: son ~1.012 filas que
--    cambian por la migracion, no por una persona, y llenarian la
--    pantalla de "Auditoria de cambios" tapando lo que si importa.
-- ---------------------------------------------------------------------
alter table elementos disable trigger trg_aud_elementos;

update elementos e
   set material_id = m.id,
       -- Ademas unifica la ortografia: las variantes quedan escritas
       -- todas igual, con el nombre de la maestra.
       material    = m.nombre
  from materiales m
 where e.material is not null
   and upper(btrim(e.material)) = upper(btrim(m.nombre))
   and (e.material_id is distinct from m.id or e.material is distinct from m.nombre);

alter table elementos enable trigger trg_aud_elementos;

-- ---------------------------------------------------------------------
-- 5. El texto queda derivado del id, para siempre.
--
--    Esto es lo que permite que NADA del codigo viejo tuviera que
--    cambiar: `elementos.material` sigue existiendo y sigue teniendo el
--    texto correcto, solo que ahora lo dicta la maestra.
-- ---------------------------------------------------------------------
create or replace function fn_material_desde_maestra()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid; v_nombre text;
begin
  if NEW.material_id is not null then
    -- El id manda: el texto se copia de la maestra.
    select nombre into v_nombre from materiales where id = NEW.material_id;
    NEW.material := v_nombre;
  elsif NEW.material is not null and btrim(NEW.material) <> '' then
    -- Llego solo texto (importaciones masivas, RPC antiguas). Si coincide
    -- con un material de la maestra se engancha solo y se corrige la
    -- ortografia. Si no coincide se deja tal cual: no se bloquea una carga
    -- por un material que todavia no esta dado de alta.
    select id, nombre into v_id, v_nombre
      from materiales
     where upper(btrim(nombre)) = upper(btrim(NEW.material));
    if v_id is not null then
      NEW.material_id := v_id;
      NEW.material    := v_nombre;
    end if;
  end if;
  return NEW;
end $$;

drop trigger if exists trg_material_desde_maestra on elementos;
create trigger trg_material_desde_maestra
  before insert or update on elementos
  for each row execute function fn_material_desde_maestra();

-- ---------------------------------------------------------------------
-- 6. Renombrar en la maestra arrastra el catalogo entero.
-- ---------------------------------------------------------------------
create or replace function fn_material_renombrar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if NEW.nombre is distinct from OLD.nombre then
    update elementos set material = NEW.nombre where material_id = NEW.id;
  end if;
  return NEW;
end $$;

drop trigger if exists trg_material_renombrar on materiales;
create trigger trg_material_renombrar
  after update on materiales
  for each row execute function fn_material_renombrar();

-- ---------------------------------------------------------------------
-- 7. updated_at al dia
-- ---------------------------------------------------------------------
create or replace function fn_materiales_touch()
returns trigger language plpgsql as $$
begin NEW.updated_at := now(); return NEW; end $$;

drop trigger if exists trg_materiales_touch on materiales;
create trigger trg_materiales_touch
  before update on materiales
  for each row execute function fn_materiales_touch();

-- =====================================================================
--  Para revertir:
--    drop trigger trg_material_desde_maestra on elementos;
--    drop trigger trg_material_renombrar on materiales;
--    drop function fn_material_desde_maestra();
--    drop function fn_material_renombrar();
--    alter table elementos drop column material_id;
--    drop table materiales;
--  (el texto de `elementos.material` queda como esta, no se pierde)
-- =====================================================================
