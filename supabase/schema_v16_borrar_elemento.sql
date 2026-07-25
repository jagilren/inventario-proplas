-- =====================================================================
--  INVENTARIO PROPLAS · schema_v16
--  Borrado DEFINITIVO de un elemento (panel Catálogo completo del admin).
--  Solo admin, y solo si el elemento no tiene historial (movimientos,
--  tramos de aprovechamiento o seriales). Si tiene historial → desactivar.
-- =====================================================================
create or replace function public.borrar_elemento(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede borrar elementos';
  end if;
  if exists (select 1 from movimientos where elemento_id = p_id)
     or exists (select 1 from aprovechamiento_trozos where elemento_id = p_id)
     or exists (select 1 from series where elemento_id = p_id) then
    raise exception 'El elemento tiene historial; no se puede borrar. Desactívalo.';
  end if;
  delete from elemento_imagenes where elemento_id = p_id;
  delete from existencias      where elemento_id = p_id;
  delete from elementos        where id = p_id;
end $$;
