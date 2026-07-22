-- =====================================================================
--  INVENTARIO PROPLAS · schema_v8 · FIX CRÍTICO del trigger de stock
--
--  Problema: aplicar_movimiento() NO era SECURITY DEFINER, así que al
--  insertar un movimiento desde un usuario autenticado, sus consultas
--  internas (SELECT ... FOR UPDATE y UPDATE de elementos) quedaban
--  filtradas por RLS -> leía existencia NULL -> ni bloqueaba salidas
--  sin stock ni actualizaba la existencia. Con service_role funcionaba
--  (salta RLS), por eso la migración quedó bien pero la app fallaba.
--
--  Solución: SECURITY DEFINER + search_path fijo, para que el trigger
--  corra con privilegios del dueño y calcule/valide SIEMPRE bien,
--  sin importar el rol del usuario que registra el movimiento.
-- =====================================================================
create or replace function public.aplicar_movimiento()
returns trigger language plpgsql
security definer set search_path = public
as $$
declare
    e_exist numeric(18,3);
    e_costo numeric(18,4);
    nueva_exist numeric(18,3);
begin
    select existencia, costo_promedio into e_exist, e_costo
      from elementos where id = new.elemento_id for update;

    if e_exist is null then
        raise exception 'Elemento % no encontrado', new.elemento_id;
    end if;

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
            raise exception 'Existencia insuficiente: hay % y se intenta sacar %', e_exist, new.cantidad;
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

    update elementos
       set existencia = e_exist,
           costo_promedio = e_costo,
           updated_at = now()
     where id = new.elemento_id;

    return new;
end; $$;
