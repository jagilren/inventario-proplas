-- =====================================================================
--  INVENTARIO PROPLAS · schema_v6 · IMÁGENES POR ELEMENTO
--
--  Balde público 'elementos-img' para la foto de cada elemento.
--  Convención de archivo:  {elemento_id}.jpg  (reemplazar = upsert)
--
--  Permisos: ver = cualquiera (público) · subir/cambiar/borrar = admin
--  o coordinador (reutiliza public.tiene_rol de schema_v3.sql).
-- =====================================================================

-- ---- 1) Balde público con límite de tamaño y tipos permitidos ------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('elementos-img', 'elementos-img', true, 2097152,
        array['image/jpeg','image/png'])
on conflict (id) do update
    set public = true,
        file_size_limit = 2097152,
        allowed_mime_types = array['image/jpeg','image/png'];

-- ---- 2) Políticas de acceso a los archivos -------------------------
drop policy if exists img_ver on storage.objects;
drop policy if exists img_subir on storage.objects;
drop policy if exists img_actualizar on storage.objects;
drop policy if exists img_borrar on storage.objects;

-- Ver: público (la URL de la imagen debe abrir sin sesión)
create policy img_ver on storage.objects for select
    using (bucket_id = 'elementos-img');

-- Subir / reemplazar / borrar: solo admin o coordinador
create policy img_subir on storage.objects for insert to authenticated
    with check (bucket_id = 'elementos-img'
                and (public.tiene_rol('admin') or public.tiene_rol('coordinador')));

create policy img_actualizar on storage.objects for update to authenticated
    using (bucket_id = 'elementos-img'
           and (public.tiene_rol('admin') or public.tiene_rol('coordinador')))
    with check (bucket_id = 'elementos-img'
                and (public.tiene_rol('admin') or public.tiene_rol('coordinador')));

create policy img_borrar on storage.objects for delete to authenticated
    using (bucket_id = 'elementos-img'
           and (public.tiene_rol('admin') or public.tiene_rol('coordinador')));
