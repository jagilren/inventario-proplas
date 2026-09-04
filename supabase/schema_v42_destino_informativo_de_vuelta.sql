-- =====================================================================
--  INVENTARIO PROPLAS · schema_v42 · CENTRO DE COSTO DESTINO, DE VUELTA
--
--  schema_v41 quito centro_costo_destino_id porque un solo "destino
--  informativo" (sin dueño de UI claro) no aportaba lo suficiente.
--
--  Decision del usuario (2026-09-04): SI hace falta, pero con las dos
--  columnas de los informes claramente separadas y con nombre propio
--  -"Centro de Costo Origen" y "Centro de Costo Destino"- en vez de una
--  columna generica "Centro de costo" + una columna "Rol" que las
--  distinguiera. Mismo comportamiento de fondo que schema_v40: el
--  destino es PURAMENTE INFORMATIVO, no afecta Neto ni Consumo por
--  Centro -eso lo sigue decidiendo solo `centro_costo_id` (el origen).
--
--  En la UI: al marcar "Es una devolucion" en una ENTRADA, aparecen DOS
--  campos -"Centro de Costo Origen" (obligatorio) y "Centro de Costo
--  Destino" (opcional)-, en vez de uno solo.
-- =====================================================================

alter table movimientos
  add column if not exists centro_costo_destino_id uuid references centros_costo(id);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'chk_centro_destino_solo_entrada'
  ) then
    alter table movimientos
      add constraint chk_centro_destino_solo_entrada
      check (centro_costo_destino_id is null or tipo = 'entrada');
  end if;
end $$;

create index if not exists idx_mov_cc_destino on movimientos (centro_costo_destino_id);

-- El candado de inmutabilidad, con la columna de vuelta.
create or replace function public.fn_mov_solo_observacion()
returns trigger language plpgsql as $function$
begin
  if (new.tipo, new.elemento_id, new.bodega_id, new.cantidad, new.costo_unitario,
      new.centro_costo_id, new.centro_costo_destino_id, new.referencia,
      new.usuario_id, new.fecha, new.traslado_id, new.anula_movimiento_id)
     is distinct from
     (old.tipo, old.elemento_id, old.bodega_id, old.cantidad, old.costo_unitario,
      old.centro_costo_id, old.centro_costo_destino_id, old.referencia,
      old.usuario_id, old.fecha, old.traslado_id, old.anula_movimiento_id)
  then
    raise exception 'Solo se puede editar la observación de un movimiento';
  end if;
  return new;
end $function$;

-- netos_por_centro / consumoPorCentro (Dart) NO se tocan: nunca deben
-- leer centro_costo_destino_id -esa es la garantia de "puramente
-- informativo" que pidio el usuario.
