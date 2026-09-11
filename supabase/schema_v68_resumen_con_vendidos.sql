-- schema_v68_resumen_con_vendidos
--
-- La vista EQUIPOS POR REFERENCIA mostraba "N disponibles · N no
-- disponibles", y "no disponibles" era total − disponibles: metía en el
-- mismo saco un equipo en el taller y uno que ya se VENDIÓ (entregado a un
-- centro de costo, que dejó de ser nuestro). Ahora el resumen cuenta los
-- vendidos aparte.
--
-- Vendido = estado 'entregado' (SDD, "entregar es salir del inventario, de
-- verdad"). Disponible exige estado 'operativo', así que las dos cuentas no
-- se pisan: no disponibles = total − disponibles − vendidos.
--
-- Cambia el tipo que devuelve la función, y eso Postgres no lo deja hacer
-- con create or replace: se borra y se crea, en la misma transacción. La
-- columna nueva va AL FINAL: la app publicada lee por nombre y la ignora.

drop function if exists activos_resumen_por_referencia();

create function activos_resumen_por_referencia()
returns table(
  referencia_id uuid,
  nombre        text,
  marca         text,
  modelo        text,
  total         bigint,
  disponibles   bigint,
  vendidos      bigint
)
language sql
stable
set search_path = public
as $$
  select r.id, r.nombre, r.marca, r.modelo,
         count(d.id)                                   as total,
         count(*) filter (where d.disponible)          as disponibles,
         count(*) filter (where d.estado = 'entregado') as vendidos
  from activo_referencias r
  join activos_disponibilidad d on d.referencia_id = r.id
  group by r.id, r.nombre, r.marca, r.modelo
  order by r.nombre;
$$;

-- Corre con los permisos de quien la llama (no es security definer): la RLS
-- de las tablas de abajo sigue mandando. Solo la app con sesión la usa.
revoke all on function activos_resumen_por_referencia() from public, anon;
grant execute on function activos_resumen_por_referencia() to authenticated;
