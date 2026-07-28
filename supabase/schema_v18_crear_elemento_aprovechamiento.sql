-- =====================================================================
--  INVENTARIO PROPLAS · schema_v18
--  RPC dedicada para crear elementos de Aprovechamientos: es_aprovechamiento
--  queda fijo en TRUE del lado del servidor (no solo por convencion de la
--  app), igual que el resto de altas de ese modulo (aprov_ins ya exige
--  admin/operario_mas).
-- =====================================================================

create or replace function public.crear_elemento_aprovechamiento(
    p_nombre   text,
    p_material text default null,
    p_sch      text default null,
    p_unidad   text default 'UND')
returns elementos
language plpgsql security definer set search_path = public as $$
declare
  v_row elementos;
begin
  if not (public.es_admin() or public.tiene_rol('operario_mas')) then
    raise exception 'Sin permiso para crear elementos de aprovechamiento';
  end if;
  if p_nombre is null or btrim(p_nombre) = '' then
    raise exception 'El nombre es obligatorio';
  end if;

  insert into elementos (nombre, material, sch, unidad, es_aprovechamiento, activo)
    values (btrim(p_nombre), p_material, p_sch, coalesce(p_unidad, 'UND'), true, true)
    returning * into v_row;

  return v_row;
end $$;
