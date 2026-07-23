-- =====================================================================
--  INVENTARIO PROPLAS · schema_v12
--  1) Editar SOLO la observación de un movimiento (con candado + auditoría)
--  2) Adjuntos (PDF/XLSX/imagen) por movimiento
--
--  Permiso (ambas cosas): admin, coordinador o quien registró el movimiento.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) CANDADO: en un UPDATE a movimientos solo puede cambiar la observación.
--    Protege la integridad: el trigger de stock (aplicar_movimiento) es
--    AFTER INSERT, así que editar otra columna descuadraría existencias.
-- ---------------------------------------------------------------------
create or replace function public.fn_mov_solo_observacion()
returns trigger language plpgsql as $$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.referencia, new.usuario_id, new.fecha, new.traslado_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.referencia, old.usuario_id, old.fecha, old.traslado_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $$;

drop trigger if exists trg_mov_solo_obs on movimientos;
create trigger trg_mov_solo_obs before update on movimientos
  for each row execute function public.fn_mov_solo_observacion();

-- RLS: permitir UPDATE a admin, coordinador o el autor del movimiento.
drop policy if exists upd_obs_mov on movimientos;
create policy upd_obs_mov on movimientos for update to authenticated
  using (public.es_admin() or public.tiene_rol('coordinador')
         or usuario_id = auth.uid())
  with check (public.es_admin() or public.tiene_rol('coordinador')
              or usuario_id = auth.uid());

-- Auditoría: solo en UPDATE (para no inflar con cada entrada/salida).
drop trigger if exists trg_aud_movimientos on movimientos;
create trigger trg_aud_movimientos after update on movimientos
  for each row execute function public.fn_auditoria();

-- ---------------------------------------------------------------------
-- 2) ADJUNTOS por movimiento
-- ---------------------------------------------------------------------
create table if not exists movimiento_adjuntos (
  id            uuid primary key default uuid_generate_v4(),
  movimiento_id uuid not null references movimientos(id) on delete cascade,
  nombre        text not null,
  ruta          text not null,     -- ruta dentro del balde de storage
  url           text not null,     -- url pública para abrir/descargar
  tipo          text,              -- mime
  tamano        bigint,
  subido_por    uuid,
  creado_en     timestamptz not null default now()
);
create index if not exists idx_mov_adj on movimiento_adjuntos (movimiento_id);

alter table movimiento_adjuntos enable row level security;

-- Ver: cualquier usuario autenticado.
drop policy if exists adj_sel on movimiento_adjuntos;
create policy adj_sel on movimiento_adjuntos for select to authenticated using (true);

-- Insertar/borrar: admin, coordinador o autor del movimiento.
drop policy if exists adj_ins on movimiento_adjuntos;
create policy adj_ins on movimiento_adjuntos for insert to authenticated
  with check (
    public.es_admin() or public.tiene_rol('coordinador')
    or exists (select 1 from movimientos m
               where m.id = movimiento_id and m.usuario_id = auth.uid())
  );

drop policy if exists adj_del on movimiento_adjuntos;
create policy adj_del on movimiento_adjuntos for delete to authenticated
  using (
    public.es_admin() or public.tiene_rol('coordinador')
    or exists (select 1 from movimientos m
               where m.id = movimiento_id and m.usuario_id = auth.uid())
  );

-- ---------------------------------------------------------------------
-- 3) Balde de Storage para los adjuntos (público, con tope y tipos)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('adjuntos-mov', 'adjuntos-mov', true, 10485760,
        array['application/pdf',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'application/vnd.ms-excel',
              'text/csv',
              'image/jpeg','image/png'])
on conflict (id) do update
  set public = true,
      file_size_limit = 10485760,
      allowed_mime_types = array['application/pdf',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              'application/vnd.ms-excel',
              'text/csv',
              'image/jpeg','image/png'];

drop policy if exists adjmov_ver on storage.objects;
drop policy if exists adjmov_subir on storage.objects;
drop policy if exists adjmov_borrar on storage.objects;

-- Ver: público (la URL abre sin sesión, como las fotos).
create policy adjmov_ver on storage.objects for select
  using (bucket_id = 'adjuntos-mov');

-- Subir: admin, coordinador o autor del movimiento (la carpeta es el id del mov).
create policy adjmov_subir on storage.objects for insert to authenticated
  with check (
    bucket_id = 'adjuntos-mov'
    and (
      public.tiene_rol('admin') or public.tiene_rol('coordinador')
      or exists (select 1 from movimientos m
                 where m.id = ((storage.foldername(name))[1])::uuid
                   and m.usuario_id = auth.uid())
    )
  );

-- Borrar: mismos permisos.
create policy adjmov_borrar on storage.objects for delete to authenticated
  using (
    bucket_id = 'adjuntos-mov'
    and (
      public.tiene_rol('admin') or public.tiene_rol('coordinador')
      or exists (select 1 from movimientos m
                 where m.id = ((storage.foldername(name))[1])::uuid
                   and m.usuario_id = auth.uid())
    )
  );
