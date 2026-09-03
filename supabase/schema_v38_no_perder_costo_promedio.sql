-- =====================================================================
--  INVENTARIO PROPLAS · schema_v38 · NO PERDER EL COSTO_PROMEDIO EN CERO
--
--  Cuando un elemento se agota (existencia total = 0), `elementos.
--  costo_promedio` se recalculaba con:
--
--    case when sum(existencia) > 0 then promedio_ponderado else 0 end
--
--  Al llegar a cero, el promedio ponderado es matematicamente 0/0
--  (indefinido), y el ELSE lo resolvia forzando un CERO literal — que no
--  significa "no vale nada", sino "no hay como calcularlo ahora mismo".
--  El ultimo costo real quedaba enterrado.
--
--  Medido antes de corregir: 27 elementos activos, agotados, con
--  elementos.costo_promedio = 0 mientras alguna de sus bodegas (en
--  `existencias`, que NUNCA se resetea asi) todavia conservaba el ultimo
--  costo real. Cero movimientos historicos con costo_unitario nulo — el
--  parche anterior (coalesce en consumoPorCentro/netos_por_centro) sigue
--  sirviendo, pero la causa de fondo nunca se toco.
--
--  Donde muerde de verdad, hoy: Devoluciones valoriza automaticamente al
--  costo_promedio del elemento (`devoluciones_page.dart:262`). Si el
--  articulo esta agotado, la devolucion entraba a $0 en silencio -la app
--  ya tiene un aviso "⚠ costo 0" para esto (`devoluciones_page.dart:477`),
--  prueba de que el sintoma ya se habia notado, pero nunca se corrigio la
--  causa. Tambien se ve en Kardex, el catalogo y las sugerencias de costo
--  al registrar una entrada.
--
--  MISMO PATRON, TRIPLICADO. Se encontraron tres copias del mismo error:
--   1) aplicar_movimiento()      -> elementos.costo_promedio (el principal)
--   2) fn_sync_existencia_serie() -> elementos.costo_promedio (elementos
--      serializados; 0 elementos serializados activos hoy, asi que sin
--      daño en produccion todavia, pero es el mismo hueco esperando)
--   3) _recompute_serie_bodega()  -> existencias.costo_promedio (a nivel
--      de BODEGA, para series; mas agresivo que el resto: aqui el detalle
--      SI se perdia, no solo el agregado)
--
--  ARREGLO: cuando no hay como calcular el promedio (todo en cero), no se
--  fuerza a 0 — se deja el valor que ya tenia. Una vez vuelva a entrar
--  stock real, el promedio ponderado lo pisa solo con el dato correcto;
--  mientras tanto, el ultimo costo conocido sigue siendo consultable.
-- =====================================================================

create or replace function public.aplicar_movimiento()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    e_exist numeric(18,3);
    e_costo numeric(18,4);
    nueva_exist numeric(18,3);
begin
    if new.bodega_id is null then
        raise exception 'El movimiento requiere una bodega';
    end if;
    if (select serializado from elementos where id = new.elemento_id) then
        return new;
    end if;

    select existencia, costo_promedio into e_exist, e_costo
      from existencias
     where elemento_id = new.elemento_id and bodega_id = new.bodega_id for update;
    if not found then e_exist := 0; e_costo := 0; end if;

    if new.tipo in ('inicial','entrada') then
        if new.costo_unitario is null then
            raise exception 'El costo_unitario es obligatorio en movimientos de tipo %', new.tipo;
        end if;
        nueva_exist := e_exist + new.cantidad;
        if nueva_exist > 0 then
            e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
        end if;
        e_exist := nueva_exist;
    elsif new.tipo = 'salida' then
        if new.cantidad > e_exist then
            raise exception 'Existencia insuficiente en la bodega: hay % y se intenta sacar %', e_exist, new.cantidad;
        end if;
        e_exist := e_exist - new.cantidad;
    elsif new.tipo = 'ajuste' then
        if new.cantidad >= 0 and new.costo_unitario is not null then
            nueva_exist := e_exist + new.cantidad;
            if nueva_exist > 0 then
                e_costo := (e_exist * e_costo + new.cantidad * new.costo_unitario) / nueva_exist;
            end if;
            e_exist := nueva_exist;
        else
            if abs(new.cantidad) > e_exist then
                raise exception 'Ajuste negativo mayor a la existencia (%): %', e_exist, new.cantidad;
            end if;
            e_exist := e_exist + new.cantidad;
        end if;
    end if;

    insert into existencias (elemento_id, bodega_id, existencia, costo_promedio, updated_at)
        values (new.elemento_id, new.bodega_id, e_exist, e_costo, now())
    on conflict (elemento_id, bodega_id) do update
        set existencia = excluded.existencia, costo_promedio = excluded.costo_promedio,
            updated_at = now();

    -- FIX schema_v38: si sum(existencia)=0, nullif(...,0) da NULL, la
    -- resta queda NULL, y el COALESCE de afuera conserva e.costo_promedio
    -- (lo que YA tenia) en vez de forzar un 0 que borra el ultimo costo
    -- real. Con stock > 0 el calculo es IDENTICO al de siempre.
    update elementos e set
        existencia = coalesce((select sum(x.existencia) from existencias x where x.elemento_id = e.id), 0),
        costo_promedio = coalesce((
            select sum(x.existencia * x.costo_promedio) / nullif(sum(x.existencia), 0)
            from existencias x where x.elemento_id = e.id), e.costo_promedio),
        updated_at = now()
      where e.id = new.elemento_id;
    return new;
end; $function$;

create or replace function public.fn_sync_existencia_serie()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_el uuid;
begin
    v_el := coalesce(new.elemento_id, old.elemento_id);
    perform public._recompute_serie_bodega(v_el, coalesce(new.bodega_id, old.bodega_id));
    if tg_op = 'UPDATE' and new.bodega_id is distinct from old.bodega_id then
        perform public._recompute_serie_bodega(v_el, old.bodega_id);
    end if;
    -- Mismo fix que aplicar_movimiento(): no perder el ultimo costo
    -- promedio cuando el elemento serializado se queda sin unidades
    -- disponibles.
    update elementos e set
        existencia = coalesce((select sum(x.existencia) from existencias x where x.elemento_id = e.id), 0),
        costo_promedio = coalesce((
            select sum(x.existencia * x.costo_promedio) / nullif(sum(x.existencia), 0)
            from existencias x where x.elemento_id = e.id), e.costo_promedio),
        updated_at = now()
      where e.id = v_el;
    return null;
end; $function$;

create or replace function public._recompute_serie_bodega(p_el uuid, p_bod uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_cnt numeric; v_costo numeric;
begin
    if p_bod is null then return; end if;
    select count(*), coalesce(avg(costo), 0) into v_cnt, v_costo
      from series where elemento_id = p_el and bodega_id = p_bod and estado = 'disponible';
    if v_cnt > 0 then
        insert into existencias(elemento_id, bodega_id, existencia, costo_promedio, updated_at)
            values (p_el, p_bod, v_cnt, v_costo, now())
        on conflict (elemento_id, bodega_id) do update
            set existencia = excluded.existencia, costo_promedio = excluded.costo_promedio,
                updated_at = now();
    else
        -- FIX schema_v38: se deja costo_promedio TAL COMO ESTABA. Antes
        -- este 'else' lo forzaba a 0 apenas se vendia el ultimo serial
        -- disponible de esa bodega — mas agresivo que el resto del
        -- sistema, porque aqui se perdia hasta a nivel de bodega, no
        -- solo en el agregado del elemento.
        update existencias set existencia = 0, updated_at = now()
          where elemento_id = p_el and bodega_id = p_bod;
    end if;
end; $function$;

-- ---------------------------------------------------------------------
-- BACKFILL: recuperar el costo de los elementos ya afectados. Se toma la
-- fila de existencias con costo>0 actualizada mas recientemente -el
-- ultimo costo real que tuvo el elemento antes de agotarse del todo.
-- No aplica a un elemento genuinamente nuevo (nunca tuvo costo real):
-- para esos no hay fila con costo>0 que recuperar, y quedan en 0, que es
-- lo correcto.
--
-- Sin auditoria: lo corrige la migracion, no una persona.
-- ---------------------------------------------------------------------
alter table elementos disable trigger trg_aud_elementos;

update elementos e
   set costo_promedio = r.costo_recuperado,
       updated_at = now()
  from (
    select distinct on (x.elemento_id)
           x.elemento_id, x.costo_promedio as costo_recuperado
      from existencias x
     where x.costo_promedio > 0
     order by x.elemento_id, x.updated_at desc
  ) r
 where r.elemento_id = e.id
   and e.activo and e.existencia = 0 and e.costo_promedio = 0;

alter table elementos enable trigger trg_aud_elementos;

-- =====================================================================
--  Para revertir el comportamiento (no el backfill, que no se puede
--  deshacer sin saber los valores previos, que eran 0):
--    volver a poner "else 0 end" / "costo_promedio = 0" en las tres
--    funciones, como estaban antes de schema_v38.
-- =====================================================================
