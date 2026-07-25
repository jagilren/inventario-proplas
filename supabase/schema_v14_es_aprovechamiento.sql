-- =====================================================================
--  INVENTARIO PROPLAS · schema_v14
--  Marca en el catálogo si un elemento es de aprovechamiento.
--  Todos arrancan en false.
-- =====================================================================
alter table elementos
  add column if not exists es_aprovechamiento boolean not null default false;
