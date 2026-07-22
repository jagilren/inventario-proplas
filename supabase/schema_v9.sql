-- =====================================================================
--  INVENTARIO PROPLAS · schema_v9 · Buscador: letras solas = palabra completa
--
--  Problema: al buscar la letra "A" sola, se tomaba como fragmento y
--  hacía match dentro de "pArte" -> traía Parte A y Parte C.
--  Solución: si una palabra de la búsqueda es UNA sola letra (a,b,c...),
--  se exige como PALABRA COMPLETA (límites \m \M), no como fragmento.
--  Las demás palabras siguen como fragmento (para búsquedas parciales).
-- =====================================================================
create or replace function public.buscar_elementos(q text)
returns setof elementos
language sql
stable
as $function$
    select e.*
    from elementos e
    where e.activo
      and (
        q is null or btrim(q) = ''
        or (
            select bool_and(
                case
                    when w ~ '^[a-z]$'
                        then t.texto ~ ('\m' || w || '\M')
                    else
                        t.texto like '%' || w || '%'
                end
            )
            from unnest(
                    regexp_split_to_array(lower(public.f_unaccent(btrim(q))), '\s+')
                 ) as w,
                 lateral (
                    select lower(public.f_unaccent(
                        coalesce(e.nombre, '')   || ' ' ||
                        coalesce(e.material, '') || ' ' ||
                        coalesce(e.sch, '')      || ' ' ||
                        coalesce(e.codigo_barras, '')
                    )) as texto
                 ) t
        )
      )
    order by e.nombre
    limit 100;
$function$;
