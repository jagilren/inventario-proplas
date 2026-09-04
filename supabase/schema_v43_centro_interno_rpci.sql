-- =====================================================================
--  INVENTARIO PROPLAS · schema_v43 · CENTRO DE COSTO: "ES INTERNO DE RPCI"
--
--  Reemplaza el filtro que quedo "quemado" en el codigo de la app
--  (movimiento_page.dart/devoluciones_page.dart filtraban el selector de
--  "Centro de Costo Destino" a los codigos G000001/G000002 a mano) por
--  un campo real de la maestra de Centros de Costo: `es_interno`.
--
--  Un centro "interno de RPCI" es un centro administrativo de la propia
--  empresa (bodega, general) — a diferencia de un centro de CLIENTE
--  externo (NP00039 Tintexa, NP00040, etc.), que nunca deberia aparecer
--  como "a quien queda atribuida una entrada" (Centro de Costo Destino).
--
--  Backfill: G000001 y G000002 quedan marcados como internos (eran los
--  dos que el codigo tenia hardcodeados). El resto queda en false.
-- =====================================================================

alter table centros_costo
  add column if not exists es_interno boolean not null default false;

update centros_costo set es_interno = true
 where codigo in ('G000001', 'G000002') and not es_interno;
