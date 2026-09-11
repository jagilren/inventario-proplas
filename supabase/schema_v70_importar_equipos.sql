-- schema_v70_importar_equipos
--
-- Carga masiva de EQUIPOS desde una plantilla (Excel/CSV), de una
-- referencia sencilla o de un KIT con sus componentes
-- (docs/plan-importar-equipos.md).
--
-- Por cada equipo hace EXACTAMENTE lo que hace el alta de uno (la app:
-- ActivosService.alta + agregarComponentes), pero en la base y en UNA
-- transacción por llamada: si un equipo falla, no entra ninguno del lote.
-- En la app eran tres llamadas separadas; con cientos de equipos, un corte
-- de red a mitad dejaría equipos sin su entrada o kits sin componentes
-- (SDD §9.7: una regla que siempre debe cumplirse va en la base).
--
--   1. La referencia: la que venga (referencia_id) o, si viene
--      referencia_nueva, la busca por nombre+marca+modelo con la MISMA
--      normalización del índice único activo_referencias_uniq, y solo si
--      no existe la crea. Así un segundo lote, o una segunda carga, la
--      encuentra en vez de chocar.
--   2. El equipo (activos). El valor de un kit lo pone trg_valor_kit.
--   3. Su movimiento de ENTRADA: el trigger de negocio abre la ubicación y
--      pone el estado según la condición, como en cualquier alta.
--   4. Si es kit, sus componentes con agregar_componentes (todos o ninguno,
--      cada uno con su movimiento de alta).
--
-- Corre con los permisos de quien la llama (security invoker): la RLS de
-- cada tabla sigue mandando. La app la llama por lotes: la base corta toda
-- operación que pase de 8 segundos (statement_timeout de authenticated).

create or replace function importar_equipos(p_equipos jsonb)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  e        jsonb;
  v_ref    uuid;
  v_act    uuid;
  v_serial text;
  v_uid    uuid := auth.uid();
  v_email  text := auth.jwt() ->> 'email';
  v_rest   text;
  n        int := 0;
  nuevas   int := 0;
begin
  if not (es_admin() or tiene_rol('coordinador') or tiene_rol('equipos')) then
    raise exception 'No tienes permiso para importar equipos';
  end if;
  if p_equipos is null or jsonb_typeof(p_equipos) <> 'array'
     or jsonb_array_length(p_equipos) = 0 then
    raise exception 'No hay equipos para importar';
  end if;

  for e in select * from jsonb_array_elements(p_equipos) loop
    v_serial := btrim(coalesce(e ->> 'serial', ''));
    begin
      if v_serial = '' then
        raise exception 'Falta el serial';
      end if;

      -- 1. La referencia.
      v_ref := nullif(e ->> 'referencia_id', '')::uuid;
      if v_ref is null then
        if e -> 'referencia_nueva' is null
           or btrim(coalesce(e -> 'referencia_nueva' ->> 'nombre', '')) = '' then
          raise exception 'Falta la referencia';
        end if;
        select r.id into v_ref
          from activo_referencias r
         where upper(regexp_replace(btrim(r.nombre), '\s+', ' ', 'g'))
               = upper(regexp_replace(btrim(e -> 'referencia_nueva' ->> 'nombre'), '\s+', ' ', 'g'))
           and upper(regexp_replace(btrim(coalesce(r.marca, '')), '\s+', ' ', 'g'))
               = upper(regexp_replace(btrim(coalesce(e -> 'referencia_nueva' ->> 'marca', '')), '\s+', ' ', 'g'))
           and upper(regexp_replace(btrim(coalesce(r.modelo, '')), '\s+', ' ', 'g'))
               = upper(regexp_replace(btrim(coalesce(e -> 'referencia_nueva' ->> 'modelo', '')), '\s+', ' ', 'g'));
        if v_ref is null then
          insert into activo_referencias (nombre, marca, modelo, es_kit, activo)
          values (btrim(e -> 'referencia_nueva' ->> 'nombre'),
                  nullif(btrim(coalesce(e -> 'referencia_nueva' ->> 'marca', '')), ''),
                  nullif(btrim(coalesce(e -> 'referencia_nueva' ->> 'modelo', '')), ''),
                  coalesce((e -> 'referencia_nueva' ->> 'es_kit')::boolean, false),
                  true)
          returning id into v_ref;
          nuevas := nuevas + 1;
        end if;
      end if;

      -- 2. El equipo.
      insert into activos (referencia_id, serial, condicion, bodega_id,
                           valor_nuevo, porcentaje_valor, observacion,
                           creado_por, creado_email)
      values (v_ref, v_serial, e ->> 'condicion', (e ->> 'bodega_id')::uuid,
              coalesce((e ->> 'valor_nuevo')::numeric, 0),
              coalesce((e ->> 'porcentaje')::numeric, 100),
              nullif(btrim(coalesce(e ->> 'observacion', '')), ''),
              v_uid, v_email)
      returning id into v_act;

      -- 3. Su entrada (el trigger abre la ubicación y pone el estado).
      insert into activo_movimientos (activo_id, tipo, centro_costo_id,
                                      centro_costo_destino_id, bodega_id,
                                      condicion, usable, usuario_id,
                                      usuario_email)
      values (v_act, 'entrada', (e ->> 'centro_origen_id')::uuid,
              nullif(e ->> 'centro_destino_id', '')::uuid,
              (e ->> 'bodega_id')::uuid, e ->> 'condicion',
              case when e ->> 'condicion' = 'usado' then true end,
              v_uid, v_email);

      -- 4. Los componentes de un kit.
      if jsonb_typeof(e -> 'componentes') = 'array'
         and jsonb_array_length(e -> 'componentes') > 0 then
        perform agregar_componentes(v_act, e -> 'componentes');
      end if;

      n := n + 1;
    exception
      when unique_violation then
        get stacked diagnostics v_rest = constraint_name;
        if v_rest = 'activos_serial_key' then
          raise exception 'Serial %: ya existe un equipo con ese serial', v_serial;
        end if;
        raise exception 'Serial %: %', v_serial, sqlerrm;
      when others then
        -- Con el serial: en un lote de 50, "Falta la referencia" sola no
        -- dice cuál de los 50 falló.
        raise exception 'Serial %: %', v_serial, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('equipos', n, 'referencias_nuevas', nuevas);
end;
$$;

revoke all on function importar_equipos(jsonb) from public, anon;
grant execute on function importar_equipos(jsonb) to authenticated;
