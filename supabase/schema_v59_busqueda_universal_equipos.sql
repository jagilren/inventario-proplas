-- schema_v59_busqueda_universal_equipos
-- Aplicada el 2026-09-10.
--
-- Búsqueda universal de equipos: serial, nombre de la referencia, marca,
-- modelo y tipo — sin importar mayúsculas ni tildes, y cada palabra por
-- separado ("grundfos diafragma" encuentra la bomba de diafragma Grundfos).
--
-- Se resuelve en la base porque la referencia vive en OTRA tabla: filtrar
-- "serial O nombre de referencia" desde la app obligaría a mandar la lista de
-- referencias que coinciden como IN(...), y con miles revienta la URL.

alter table activo_referencias
  add column busqueda text generated always as (
    upper(f_unaccent(
      nombre || ' ' || coalesce(marca, '') || ' ' ||
      coalesce(modelo, '') || ' ' || coalesce(tipo, '')
    ))
  ) stored;

-- Un LIKE '%texto%' NO usa un btree (ni el text_pattern_ops del serial, que
-- solo sirve para prefijos): sin trigramas cada búsqueda recorre la tabla.
create index idx_activo_ref_busqueda_trgm
  on activo_referencias using gin (busqueda gin_trgm_ops);
create index idx_activos_serial_busqueda_trgm
  on activos using gin (serial_busqueda gin_trgm_ops);

-- setof activos: PostgREST puede seguir haciendo embeds, filtros y paginación
-- encima. SECURITY INVOKER (por defecto): aplica la RLS de quien busca.
create or replace function buscar_activos(p_texto text)
returns setof activos
language sql stable
set search_path = public, extensions
as $$
  select a.*
  from activos a
  join activo_referencias r on r.id = a.referencia_id
  where not exists (
    select 1
    from unnest(regexp_split_to_array(
           upper(f_unaccent(btrim(coalesce(p_texto, '')))), '\s+')) as w(palabra)
    where w.palabra <> ''
      and a.serial_busqueda not like '%' || w.palabra || '%'
      and r.busqueda        not like '%' || w.palabra || '%'
  );
$$;
