-- =====================================================================
--  INVENTARIO PROPLAS · schema_v20 · BUSCADOR PAGINADO
--
--  Antes: buscar_elementos(q) devolvía como máximo 100 filas y no había
--  forma de llegar a la 101. En la pantalla "Existencias" eso significaba
--  que el catálogo solo era navegable hasta el elemento nº 100, y que una
--  búsqueda con más de 100 coincidencias escondía el resto sin avisar.
--
--  Ahora la función recibe límite y desplazamiento, así la pantalla puede
--  ir pidiendo de a poco ("Cargar más") y alcanzar CUALQUIER artículo.
--
--  IMPORTANTE: el filtro sigue evaluándose sobre TODO el catálogo en el
--  servidor. El límite solo recorta cuántas filas se envían por viaje, no
--  cuántas se revisan. Buscar nunca deja de encontrar.
--
--  Los valores por defecto (100 / 0) reproducen exactamente el
--  comportamiento anterior, para que los buscadores emergentes de las
--  otras pantallas sigan funcionando igual sin tocarlos.
-- =====================================================================

-- La firma cambia, así que hay que quitar la versión de un solo argumento:
-- si se dejaran las dos, una llamada con solo 'q' quedaría ambigua.
drop function if exists public.buscar_elementos(text);

create or replace function public.buscar_elementos(
    q        text,
    p_limit  int default 100,
    p_offset int default 0
)
returns setof elementos
language sql
stable
as $function$
    select e.*
    from elementos e
    where e.activo
      and not coalesce(e.es_aprovechamiento, false)
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
    limit  greatest(coalesce(p_limit, 100), 1)
    offset greatest(coalesce(p_offset, 0), 0);
$function$;

-- Cuántos artículos coinciden en TOTAL con la búsqueda (sin paginar).
-- La pantalla lo usa para decir "mostrando 10 de 137" y para saber si
-- todavía quedan páginas por traer.
create or replace function public.contar_elementos(q text default null)
returns bigint
language sql
stable
as $function$
    select count(*)
    from elementos e
    where e.activo
      and not coalesce(e.es_aprovechamiento, false)
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
      );
$function$;
