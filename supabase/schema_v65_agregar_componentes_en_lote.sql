-- schema_v65_agregar_componentes_en_lote
-- Referencias KITZABLES — Fase 4 (docs/plan-kits-equipos.md).
--
-- Al crear un kit, sus componentes se guardan TODOS O NINGUNO.
--
-- El alta de un kit llega con varios componentes (la plantilla del kit
-- anterior, ajustada). Guardarlos con una llamada por componente deja un
-- riesgo silencioso: si la red se cae a mitad, el kit queda con 2 de sus 4
-- componentes y vale menos de lo que debería, sin que nadie lo note. Una
-- función PL/pgSQL corre en UNA transacción: si un componente falla, no
-- queda ninguno — y un kit sin componentes sí se nota (la pestaña dice que
-- vale $0 y ofrece agregarlos).
--
-- Reutiliza agregar_componente() (schema_v64) para cada uno: mismas reglas,
-- mismo movimiento de alta, sin repetir la lógica.

create or replace function agregar_componentes(
  p_activo uuid,
  p_componentes jsonb)
returns int
language plpgsql
set search_path = public
as $$
declare
  v jsonb;
  n int := 0;
begin
  if p_componentes is null
     or jsonb_typeof(p_componentes) <> 'array'
     or jsonb_array_length(p_componentes) = 0 then
    raise exception 'No hay componentes para agregar';
  end if;

  for v in select * from jsonb_array_elements(p_componentes) loop
    n := n + 1;
    begin
      perform agregar_componente(
        p_activo,
        v->>'nombre',
        (v->>'cantidad')::numeric,
        (v->>'valor_unitario')::numeric,
        coalesce((v->>'orden')::int, n),
        nullif(btrim(coalesce(v->>'observacion', '')), ''));
    exception
      -- Decir CUÁL está repetido. Relanzar aborta toda la función: no queda
      -- guardado ninguno de los anteriores.
      when unique_violation then
        raise exception 'El componente "%" está repetido', btrim(v->>'nombre');
    end;
  end loop;

  return n;
end;
$$;
