-- =====================================================================
--  INVENTARIO PROPLAS · schema_v17
--  Auditoría clasificada por sub-pestañas, con nombre del afectado,
--  búsqueda y paginación. NO toca el historial por registro (kardex).
-- =====================================================================

-- ---- 1) Ampliar la cobertura de auditoría --------------------------
drop trigger if exists trg_aud_bodegas on bodegas;
create trigger trg_aud_bodegas after insert or update or delete on bodegas
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_aprov_trozos on aprovechamiento_trozos;
create trigger trg_aud_aprov_trozos
  after insert or update or delete on aprovechamiento_trozos
  for each row execute function public.fn_auditoria();

drop trigger if exists trg_aud_aprov_salidas on aprovechamiento_salidas;
create trigger trg_aud_aprov_salidas
  after insert or delete on aprovechamiento_salidas
  for each row execute function public.fn_auditoria();

-- ---- 2) Consulta clasificada, con nombre del afectado --------------
--  Categorías: recientes(null) | entradas | salidas | bodegas |
--  centros | usuarios | aprovechamientos
create or replace function public.auditoria_clasificada(
    p_categoria text default null,
    p_q         text default null,
    p_limit     int  default 10,
    p_offset    int  default 0)
returns table (
    fecha          timestamptz,
    accion         text,
    campo          text,
    valor_anterior text,
    valor_nuevo    text,
    usuario_email  text,
    tabla          text,
    afectado       text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.es_admin() or public.tiene_rol('coordinador')) then
    raise exception 'Solo admin o coordinador pueden ver la auditoría';
  end if;

  return query
  with con_nombre as (
    select a.fecha, a.accion, a.campo, a.valor_anterior, a.valor_nuevo,
      a.usuario_email, a.tabla,
      case when a.tabla = 'movimientos'
           then (select m.tipo from movimientos m where m.id = a.registro_id)
           end as mov_tipo,
      case a.tabla
        when 'movimientos' then
          (select e.nombre from movimientos m join elementos e on e.id = m.elemento_id
             where m.id = a.registro_id)
        when 'elementos' then (select nombre from elementos where id = a.registro_id)
        when 'bodegas'   then (select nombre from bodegas   where id = a.registro_id)
        when 'centros_costo' then (select codigo from centros_costo where id = a.registro_id)
        when 'usuario_roles' then (select email from profiles where id = a.registro_id)
        when 'aprovechamiento_trozos' then
          (select e.nombre from aprovechamiento_trozos t join elementos e on e.id = t.elemento_id
             where t.id = a.registro_id)
        when 'aprovechamiento_salidas' then
          (select e.nombre from aprovechamiento_salidas s
             join aprovechamiento_trozos t on t.id = s.trozo_id
             join elementos e on e.id = t.elemento_id
             where s.id = a.registro_id)
        else null
      end as afectado
    from auditoria a
  )
  select c.fecha, c.accion, c.campo, c.valor_anterior, c.valor_nuevo,
         c.usuario_email, c.tabla, c.afectado
  from con_nombre c
  where (
      p_categoria is null or p_categoria in ('', 'recientes')
      or (p_categoria = 'usuarios' and c.tabla = 'usuario_roles')
      or (p_categoria = 'bodegas'  and c.tabla = 'bodegas')
      or (p_categoria = 'centros'  and c.tabla = 'centros_costo')
      or (p_categoria = 'aprovechamientos'
          and c.tabla in ('aprovechamiento_trozos', 'aprovechamiento_salidas'))
      or (p_categoria = 'entradas' and c.tabla = 'movimientos' and c.mov_tipo = 'entrada')
      or (p_categoria = 'salidas'  and c.tabla = 'movimientos' and c.mov_tipo = 'salida')
    )
    and (p_q is null or p_q = ''
         or coalesce(c.afectado, '')      ilike '%' || p_q || '%'
         or coalesce(c.usuario_email, '') ilike '%' || p_q || '%')
  order by c.fecha desc
  limit p_limit offset p_offset;
end $$;
