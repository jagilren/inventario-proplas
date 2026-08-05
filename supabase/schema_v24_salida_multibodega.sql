-- =====================================================================
--  INVENTARIO PROPLAS · schema_v24 · SALIDA MASIVA MULTI-BODEGA
--
--  Problema: en una salida de 110 líneas, si 3 artículos no tienen saldo en
--  la bodega elegida pero sí en otra, antes tocaba abandonar la pantalla,
--  ir a Traslados y volver a empezar — perdiendo los 110 emparejamientos.
--
--  Solución: cada línea puede salir de SU PROPIA bodega. Las 107 salen de
--  la bodega general y las 3 excepciones desde donde de verdad está el
--  material. Todo en la misma transacción, sin traslados.
--
--  Por qué así y no con un traslado automático: si la mercancía está en
--  RPCI y se le entrega al cliente, entonces salió de RPCI. Registrar un
--  traslado a la bodega principal que nunca ocurrió llenaría el kardex de
--  movimientos ficticios.
--
--  En p_items, cada línea puede traer "bodega_id". Si no lo trae, se usa
--  p_bodega (la general de la pantalla).
-- =====================================================================

-- ---- 1) Bodegas donde SÍ hay saldo de un artículo -------------------
-- La usa la pantalla para ofrecer, en la línea que no alcanza, desde qué
-- otra bodega se puede despachar.
create or replace function public.bodegas_con_saldo(
    p_elemento uuid,
    p_excluir  uuid default null
)
returns table (bodega_id uuid, bodega text, existencia numeric)
language sql
stable
as $function$
    select b.id, b.nombre, x.existencia
    from existencias x
    join bodegas b on b.id = x.bodega_id
    where x.elemento_id = p_elemento
      and x.existencia > 0
      and b.activo
      and (p_excluir is null or b.id is distinct from p_excluir)
    order by x.existencia desc;
$function$;

-- ---- 2) Validación por (artículo + bodega efectiva) ------------------
-- Cambia el tipo de retorno, así que hay que soltar la versión anterior.
drop function if exists public.validar_salida_masiva(uuid, jsonb);

create or replace function public.validar_salida_masiva(
    p_bodega uuid,
    p_items  jsonb
)
returns table (
    elemento_id   uuid,
    bodega_id     uuid,      -- de qué bodega sale ESTA línea
    bodega        text,
    nombre        text,
    unidad        text,
    pedido        numeric,
    disponible    numeric,
    alcanza       boolean,
    en_otras      numeric,   -- saldo en las demás bodegas
    otras_detalle text
)
language sql
stable
as $function$
    with pedido as (
        -- Agrupa por artículo Y bodega: dos líneas del mismo artículo que
        -- salen de la misma bodega compiten por el mismo saldo; si salen de
        -- bodegas distintas, no.
        select (it->>'elemento_id')::uuid                        as eid,
               coalesce((it->>'bodega_id')::uuid, p_bodega)      as bid,
               sum((it->>'cantidad')::numeric)                   as cant
        from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) it
        where (it->>'elemento_id') is not null
        group by 1, 2
    ),
    otras as (
        select p.eid, p.bid,
               coalesce(sum(x.existencia), 0) as total,
               string_agg(
                   b.nombre || ': ' ||
                   trim(to_char(x.existencia, 'FM999999990.###')),
                   ' · ' order by x.existencia desc) as detalle
        from pedido p
        left join existencias x
               on x.elemento_id = p.eid
              and x.bodega_id is distinct from p.bid
              and x.existencia > 0
        left join bodegas b on b.id = x.bodega_id
        group by p.eid, p.bid
    )
    select p.eid,
           p.bid,
           bo.nombre,
           e.nombre,
           e.unidad,
           p.cant,
           coalesce(x.existencia, 0),
           coalesce(x.existencia, 0) >= p.cant,
           coalesce(o.total, 0),
           o.detalle
    from pedido p
    join elementos e on e.id = p.eid
    left join bodegas bo on bo.id = p.bid
    left join existencias x
           on x.elemento_id = p.eid
          and x.bodega_id   = p.bid
    left join otras o on o.eid = p.eid and o.bid = p.bid
    order by (coalesce(x.existencia, 0) >= p.cant), e.nombre;
$function$;

-- ---- 3) Registro: cada línea sale de su bodega -----------------------
-- Misma firma que antes (no hace falta soltarla): lo que cambia es que
-- ahora cada elemento de p_items puede traer su propio "bodega_id".
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
    -- existencia de cada una contra SU bodega. Si alguna no alcanza, lanza
    -- excepcion y toda esta funcion (una sola transaccion) se deshace.
    insert into movimientos (
        tipo, elemento_id, bodega_id, centro_costo_id, cantidad,
        referencia, observacion, usuario_id, fecha, device_id, local_id
    )
    select 'salida',
           (t.it->>'elemento_id')::uuid,
           coalesce((t.it->>'bodega_id')::uuid, p_bodega),
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
