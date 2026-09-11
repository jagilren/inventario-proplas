-- schema_v49_equipos_offline_y_realtime
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909180735): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Equipos: soporte para trabajo sin conexión y avisos en vivo.
--
-- Mismo mecanismo que ya usa `movimientos`, no uno nuevo:
--  · device_id + local_id con índice único = la misma llave que impide subir
--    dos veces un movimiento que quedó en la cola del dispositivo. Sin WHERE
--    a propósito: en Postgres los NULL son distintos entre sí, así que los
--    movimientos registrados en línea (ambos nulos) no chocan nunca.
--  · device_id además sirve para que el aviso en vivo ignore el eco de lo
--    que registró este mismo aparato.
alter table activo_movimientos add column if not exists device_id text;
alter table activo_movimientos add column if not exists local_id text;

create unique index if not exists activo_movimientos_device_id_local_id_key
  on activo_movimientos (device_id, local_id);

-- Publicar la tabla para Realtime, igual que `movimientos`.
alter publication supabase_realtime add table activo_movimientos;
