-- =====================================================================
--  INVENTARIO PROPLAS · schema_v34 · AVISOS EN VIVO (Realtime)
--
--  Publica `movimientos` en Realtime para que las vistas abiertas se
--  refresquen solas cuando OTRO usuario registra o anula un movimiento.
--  Antes, `InventarioService.revision` solo reaccionaba a los cambios del
--  propio aparato: quien estuviera mirando "últimas salidas" no veía lo que
--  registraba un compañero hasta recargar a mano.
--
--  El cliente (lib/realtime_service.dart) usa el evento solo como campanazo:
--  al recibirlo vuelve a consultar con la query normal, que trae nombres,
--  centro y usuario, respeta RLS y mantiene el orden de más reciente a más
--  antiguo. Por eso NO hace falta 'replica identity full'.
--
--  Costo: Realtime está incluido en el plan Free (200 conexiones
--  concurrentes, 100 mensajes/segundo). No implica cambiar de plan.
--
--  APLICADO en producción el 2026-08-19.
-- =====================================================================

alter publication supabase_realtime add table movimientos;

-- Para revertir:
--   alter publication supabase_realtime drop table movimientos;
