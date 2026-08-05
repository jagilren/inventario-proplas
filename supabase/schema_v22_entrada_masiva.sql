-- =====================================================================
--  INVENTARIO PROPLAS · schema_v22 · ENTRADA MASIVA (compra a proveedor)
--
--  Hermana de registrar_salida_masiva (schema_v21), pero para lo que ENTRA
--  por una compra. Misma garantía: todo ocurre en UNA transacción, así que
--  o entran todas las líneas de la factura o no entra ninguna.
--
--  DIFERENCIA CLAVE CON LAS DEVOLUCIONES:
--  una devolución entra al costo promedio que el artículo YA tenía (vuelve
--  algo que ya era tuyo). Una COMPRA entra al precio que le pagaste al
--  proveedor, y ese precio es el que recalcula el promedio ponderado móvil:
--
--      nuevo_promedio = (exist_ant * costo_ant + cantidad * costo_compra)
--                       / nueva_existencia
--
--  Por eso el costo unitario es obligatorio aquí: si las compras entraran
--  al promedio viejo, la valorización nunca se enteraría de que los precios
--  subieron y se iría desviando de la realidad sin que se note.
--  (El disparador aplicar_movimiento() ya lo exige para tipo 'entrada'.)
--
--  El costo va SIN IVA, que es como se valoriza el inventario.
--  No lleva centro de costo: la mercancía viene de un proveedor, no vuelve
--  de un proyecto.
-- =====================================================================

-- p_items: [{"elemento_id": "uuid", "cantidad": 10, "costo": 12500}, ...]
--
-- p_referencia: número de factura u orden de compra. Queda en el campo
-- 'referencia' de movimientos, el mismo que ya se usa para documentos.
create or replace function public.registrar_entrada_masiva(
    p_bodega       uuid,
    p_device       text,
    p_lote         text,
    p_items        jsonb,
    p_referencia   text default null,
    p_observacion  text default null
)
returns integer
language plpgsql
security invoker
as $function$
declare
    v_filas integer := 0;
    v_malos integer := 0;
begin
    if p_bodega is null then
        raise exception 'Falta la bodega donde entra la mercancia';
    end if;
    if p_lote is null or btrim(p_lote) = '' then
        raise exception 'Falta el identificador del lote';
    end if;
    if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
        raise exception 'No hay lineas para registrar';
    end if;

    -- Se avisa ANTES y con un mensaje claro, en vez de dejar que reviente
    -- el disparador con "el costo_unitario es obligatorio".
    select count(*) into v_malos
    from jsonb_array_elements(p_items) it
    where (it->>'elemento_id') is null
       or coalesce((it->>'cantidad')::numeric, 0) <= 0
       or coalesce((it->>'costo')::numeric, -1) < 0
       or (it->>'costo') is null;
    if v_malos > 0 then
        raise exception
          '% linea(s) sin costo unitario, sin cantidad o sin articulo. '
          'En una compra el costo es obligatorio: es el que recalcula el '
          'promedio ponderado.', v_malos;
    end if;

    insert into movimientos (
        tipo, elemento_id, bodega_id, cantidad, costo_unitario,
        referencia, observacion, usuario_id, fecha, device_id, local_id
    )
    select 'entrada',
           (t.it->>'elemento_id')::uuid,
           p_bodega,
           (t.it->>'cantidad')::numeric,
           (t.it->>'costo')::numeric,
           p_referencia,
           p_observacion,
           auth.uid(),
           now(),
           p_device,
           p_lote || '-' || t.ord
    from jsonb_array_elements(p_items) with ordinality as t(it, ord);

    get diagnostics v_filas = row_count;
    return v_filas;
end;
$function$;
