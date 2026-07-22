-- =====================================================================
--  INVENTARIO PROPLAS · schema_v4 · BUSCADOR POR FRAGMENTOS
--
--  Problema del buscador anterior: usaba búsqueda por palabras COMPLETAS,
--  así que "concen Reducc" no encontraba "Reduccion Concentrica ...".
--
--  Nuevo comportamiento: parte lo que escribes en palabras y exige que
--  TODAS aparezcan como fragmento, en CUALQUIER orden, sin importar
--  tildes ni mayúsculas. Busca en nombre + material + SCH + código barras.
--    "concen reducc"  -> encuentra "Reduccion Concentrica Inox 304..."
--    "inox 4 reducc"  -> también
-- =====================================================================
create or replace function public.buscar_elementos(q text)
returns setof elementos language sql stable as $$
    select e.*
    from elementos e
    where e.activo
      and (
        q is null or btrim(q) = ''
        or (
            select bool_and(
                lower(public.f_unaccent(
                    coalesce(e.nombre, '')        || ' ' ||
                    coalesce(e.material, '')      || ' ' ||
                    coalesce(e.sch, '')           || ' ' ||
                    coalesce(e.codigo_barras, '')
                )) like '%' || w || '%'
            )
            from unnest(
                regexp_split_to_array(lower(public.f_unaccent(btrim(q))), '\s+')
            ) as w
        )
      )
    order by e.nombre
    limit 100;
$$;
