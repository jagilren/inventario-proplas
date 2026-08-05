-- =====================================================================
--  INVENTARIO PROPLAS · schema_v21 · SALIDA MASIVA
--
--  Permite despachar muchos elementos de una sola vez (una lista que llega
--  en Excel) hacia un centro de costo, sin tener que registrarlos uno a uno.
--
--  Por qué una RPC y no un bucle desde la app:
--   1) ATOMICIDAD. Una salida puede ser rechazada por falta de existencia.
--      Con un bucle, si la fila 25 de 40 falla, quedan 24 salidas
--      registradas y una salida a medias en el inventario real. Aquí todo
--      ocurre dentro de una sola transaccion: o entran las 40, o ninguna.
--   2) VELOCIDAD. 40 llamadas sueltas son ~40 viajes de red (~13 s medidos);
--      esto es un solo viaje.
--
--  No cubre elementos serializados: esos necesitan decir CUÁLES seriales
--  salen, y eso no cabe en una fila de "nombre + cantidad". Se registran
--  aparte, como hasta ahora.
-- =====================================================================

-- ---- 1) VALIDACIÓN PREVIA -------------------------------------------
-- Dice, sin tocar nada, qué líneas alcanzan y cuáles no. La pantalla la
-- usa para pintar en rojo lo que falta ANTES de que el usuario confirme.
--
-- Ojo: agrupa por elemento. Si la lista trae el mismo artículo en dos
-- líneas, lo que importa es la SUMA contra la existencia, no cada línea
-- por separado (dos líneas de 6 contra un saldo de 10 no alcanzan).
create or replace function public.validar_salida_masiva(
    p_bodega uuid,
    p_items  jsonb
)
returns table (
    elemento_id uuid,
    nombre      text,
    unidad      text,
    pedido      numeric,
    disponible  numeric,
    alcanza     boolean
)
language sql
stable
as $function$
    with pedido as (
        select (it->>'elemento_id')::uuid    as eid,
               sum((it->>'cantidad')::numeric) as cant
        from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) it
        where (it->>'elemento_id') is not null
        group by 1
    )
    select p.eid,
           e.nombre,
           e.unidad,
           p.cant,
           coalesce(x.existencia, 0),
           coalesce(x.existencia, 0) >= p.cant
    from pedido p
    join elementos e on e.id = p.eid
    left join existencias x
           on x.elemento_id = p.eid
          and x.bodega_id   = p_bodega
    -- Primero lo que NO alcanza: es lo que el usuario tiene que arreglar.
    order by (coalesce(x.existencia, 0) >= p.cant), e.nombre;
$function$;

-- ---- 2) REGISTRO EN UNA SOLA TRANSACCIÓN ----------------------------
-- p_items: [{"elemento_id": "uuid", "cantidad": 5}, ...]
--
-- p_device y p_lote arman la llave (device_id, local_id) que ya usa la app
-- para no subir dos veces el mismo movimiento. Si el usuario pulsa "Cargar"
-- dos veces con el mismo lote, la segunda choca contra esa llave única y la
-- transaccion entera se deshace: no quedan duplicados a medias.
--
-- security invoker a proposito: las politicas RLS de movimientos siguen
-- decidiendo quien puede registrar salidas (rol operario_menos, etc.).
create or replace function public.registrar_salida_masiva(
    p_bodega       uuid,
    p_centro_costo uuid,
    p_device       text,
    p_lote         text,
    p_items        jsonb,
    p_referencia   text default 'SALIDA MASIVA',
    p_observacion  text default null
)
returns integer
language plpgsql
security invoker
as $function$
declare
    v_filas integer := 0;
begin
    if p_bodega is null then
        raise exception 'Falta la bodega de origen';
    end if;
    if p_lote is null or btrim(p_lote) = '' then
        raise exception 'Falta el identificador del lote';
    end if;
    if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
        raise exception 'No hay lineas para registrar';
    end if;

    -- El disparador aplicar_movimiento() corre por fila y valida la
    -- existencia de cada una. Si alguna no alcanza, lanza excepcion y toda
    -- esta funcion (que es una sola transaccion) se deshace sola.
    insert into movimientos (
        tipo, elemento_id, bodega_id, centro_costo_id, cantidad,
        referencia, observacion, usuario_id, fecha, device_id, local_id
    )
    select 'salida',
           (t.it->>'elemento_id')::uuid,
           p_bodega,
           p_centro_costo,
           (t.it->>'cantidad')::numeric,
           p_referencia,
           p_observacion,
           auth.uid(),
           now(),
           p_device,
           p_lote || '-' || t.ord
    from jsonb_array_elements(p_items) with ordinality as t(it, ord)
    where (t.it->>'elemento_id') is not null
      and (t.it->>'cantidad')::numeric > 0;

    get diagnostics v_filas = row_count;

    if v_filas = 0 then
        raise exception 'Ninguna linea tenia elemento y cantidad validos';
    end if;

    return v_filas;
end;
$function$;
