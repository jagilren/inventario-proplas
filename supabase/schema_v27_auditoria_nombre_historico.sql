-- =====================================================================
--  INVENTARIO PROPLAS · schema_v27
--  La auditoría vuelve a decir A QUIÉN le pasó cada cosa, aunque el
--  registro ya no exista.
--
--  EL PROBLEMA: el nombre del afectado se resolvía consultando la tabla
--  VIVA (select codigo from centros_costo where id = ...). Si el registro
--  se borró o se desactivó después, esa consulta devuelve vacío y TODA su
--  historia queda anónima: se veía "activo: true → false" sin decir de qué
--  centro de costo se estaba hablando. Para eso no sirve una auditoría.
--
--  LA SOLUCIÓN: buscar el nombre en tres pasos, en orden:
--    1. La tabla viva (lo de siempre, para lo que aún existe).
--    2. La columna 'datos' de ESA fila de auditoría — el trigger guarda ahí
--       el registro completo en los INSERT y los DELETE.
--    3. La columna 'datos' de CUALQUIER otra fila de auditoría del mismo
--       registro. Así un UPDATE hereda el nombre del INSERT que lo creó,
--       aunque el registro ya no exista.
--
--  Con esto se recupera el nombre RETROACTIVAMENTE, sin migrar datos: la
--  información ya estaba guardada, solo no se estaba usando.
-- =====================================================================

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
      coalesce(
        -- 1) La tabla viva.
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
        end,
        -- 2) Lo que quedó guardado en ESTA misma fila (INSERT/DELETE).
        a.datos->>'codigo',
        a.datos->>'nombre',
        a.datos->>'email',
        -- 3) Lo que quedó guardado en CUALQUIER otra fila del mismo
        --    registro: así un UPDATE hereda el nombre de su INSERT.
        (select coalesce(a2.datos->>'codigo', a2.datos->>'nombre',
                         a2.datos->>'email')
           from auditoria a2
          where a2.tabla = a.tabla
            and a2.registro_id = a.registro_id
            and a2.datos is not null
          order by a2.fecha
          limit 1)
      ) as afectado
    from auditoria a
  )
  select c.fecha, c.accion, c.campo, c.valor_anterior, c.valor_nuevo,
         c.usuario_email, c.tabla,
         -- Si de plano no se pudo averiguar, se dice, en vez de dejar el
         -- hueco en blanco que no explica nada.
         coalesce(c.afectado, '(registro eliminado)') as afectado
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
