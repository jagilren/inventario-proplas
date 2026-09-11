-- schema_v50_auditoria_equipos
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909181529): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Auditoría del módulo de Equipos.
--
-- Los triggers ya venían grabando los cambios de las 7 tablas desde la
-- Fase 1 (fn_auditoria está conectada a todas). Lo que faltaba era poder
-- LEERLOS: la pantalla no sabía a qué equipo correspondía cada cambio
-- (mostraba "(registro eliminado)") ni tenía filtro para encontrarlos.
--
-- Un equipo se identifica por su SERIAL, no por un nombre, así que la
-- resolución del registro afectado necesita su propio caso por tabla.

-- 1) valor_actual es una columna GENERADA (valor_nuevo × porcentaje). Al
--    cambiar el porcentaje se registraban dos filas diciendo lo mismo.
--    Se ignora, igual que ya se ignoran existencia y costo_promedio.
create or replace function public.fn_auditoria()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_old jsonb; v_new jsonb; k text;
    v_uid uuid; v_email text; v_reg uuid;
    ignorar text[] := array['updated_at','created_at','busqueda',
                            'existencia','costo_promedio','valor_actual',
                            'phash','imagen_url','orden','principal'];
begin
    v_uid := auth.uid();
    if v_uid is not null then
        select email into v_email from profiles where id = v_uid;
    end if;

    if TG_OP = 'INSERT' then
        v_new := to_jsonb(NEW);
        v_reg := nullif(coalesce(v_new->>'id', v_new->>'usuario_id'), '')::uuid;
        insert into auditoria(tabla, registro_id, accion, datos, usuario_id, usuario_email)
        values (TG_TABLE_NAME, v_reg, 'INSERT', v_new, v_uid, v_email);
        return NEW;

    elsif TG_OP = 'DELETE' then
        v_old := to_jsonb(OLD);
        v_reg := nullif(coalesce(v_old->>'id', v_old->>'usuario_id'), '')::uuid;
        insert into auditoria(tabla, registro_id, accion, datos, usuario_id, usuario_email)
        values (TG_TABLE_NAME, v_reg, 'DELETE', v_old, v_uid, v_email);
        return OLD;

    else  -- UPDATE: una fila por cada campo que cambió
        v_old := to_jsonb(OLD); v_new := to_jsonb(NEW);
        v_reg := nullif(coalesce(v_new->>'id', v_new->>'usuario_id'), '')::uuid;
        for k in select jsonb_object_keys(v_new) loop
            if not (k = any(ignorar))
               and (v_old->>k) is distinct from (v_new->>k) then
                insert into auditoria(tabla, registro_id, accion, campo,
                                      valor_anterior, valor_nuevo, usuario_id, usuario_email)
                values (TG_TABLE_NAME, v_reg, 'UPDATE', k,
                        v_old->>k, v_new->>k, v_uid, v_email);
            end if;
        end loop;
        return NEW;
    end if;
end $function$;

-- 2) Identificar y filtrar los cambios de Equipos.
create or replace function public.auditoria_clasificada(
  p_categoria text default null,
  p_q text default null,
  p_limit integer default 10,
  p_offset integer default 0)
returns table(fecha timestamp with time zone, accion text, campo text,
              valor_anterior text, valor_nuevo text, usuario_email text,
              tabla text, afectado text)
language plpgsql stable security definer set search_path to 'public'
as $function$
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
           when a.tabla = 'activo_movimientos'
           then (select m.tipo from activo_movimientos m where m.id = a.registro_id)
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
          -- EQUIPOS: un equipo se identifica por su serial, no por un nombre.
          when 'activos' then (select serial from activos where id = a.registro_id)
          when 'activo_referencias' then
            (select nombre from activo_referencias where id = a.registro_id)
          when 'activo_terceros' then
            (select nombre from activo_terceros where id = a.registro_id)
          when 'activo_movimientos' then
            (select x.serial from activo_movimientos m join activos x on x.id = m.activo_id
               where m.id = a.registro_id)
          when 'activo_ubicaciones' then
            (select x.serial from activo_ubicaciones u join activos x on x.id = u.activo_id
               where u.id = a.registro_id)
          when 'activo_piezas' then
            (select x.serial || ' · ' || p.nombre from activo_piezas p
               join activos x on x.id = p.activo_id where p.id = a.registro_id)
          when 'activo_mantenimientos' then
            (select x.serial from activo_mantenimientos mt join activos x on x.id = mt.activo_id
               where mt.id = a.registro_id)
          else null
        end,
        -- 2) Lo que quedó guardado en ESTA misma fila (INSERT/DELETE).
        a.datos->>'codigo',
        a.datos->>'nombre',
        a.datos->>'email',
        a.datos->>'serial',
        -- 3) Lo que quedó guardado en CUALQUIER otra fila del mismo
        --    registro: así un UPDATE hereda el nombre de su INSERT.
        (select coalesce(a2.datos->>'codigo', a2.datos->>'nombre',
                         a2.datos->>'email', a2.datos->>'serial')
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
      -- Todo el módulo de Equipos, y aparte solo sus entradas/salidas.
      or (p_categoria = 'equipos' and c.tabla in
            ('activos','activo_referencias','activo_terceros','activo_movimientos',
             'activo_ubicaciones','activo_piezas','activo_mantenimientos'))
      or (p_categoria = 'equipos_mov' and c.tabla = 'activo_movimientos')
    )
    and (p_q is null or p_q = ''
         or coalesce(c.afectado, '')      ilike '%' || p_q || '%'
         or coalesce(c.usuario_email, '') ilike '%' || p_q || '%')
  order by c.fecha desc
  limit p_limit offset p_offset;
end $function$;
