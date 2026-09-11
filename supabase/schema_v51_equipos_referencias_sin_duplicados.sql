-- schema_v51_equipos_referencias_sin_duplicados
--
-- RECUPERADO el 2026-09-11 de supabase_migrations.schema_migrations
-- (versión 20260909205228): es el texto EXACTO que se aplicó a la base.
-- Se había aplicado desde el MCP sin guardar el archivo en el repo, y
-- la carpeta supabase/ saltaba de la v46 a la v54: reconstruir la base
-- desde los archivos habría dejado fuera estos pasos.


-- Evitar referencias y terceros duplicados en el módulo de Equipos.
--
-- Faltaba: `materiales` ya tenía este candado (materiales_nombre_uniq sobre
-- upper(btrim(nombre))) justamente porque el catálogo se fragmentaba con
-- texto libre. Las tablas de Equipos nacieron sin él.
--
-- Va más allá del de materiales: además de mayúsculas y espacios de los
-- extremos, colapsa los espacios INTERNOS, porque el archivo real de equipos
-- traía el mismo modelo escrito "( 96609016) CABLE" y "(96609016) CABLE".
--
-- La identidad de una referencia es nombre+marca+modelo, no solo el nombre:
-- una "BOMBA CENTRIFUGA" GRUNDFOS y una EBARA son dos referencias legítimas
-- y distintas. El coalesce evita que dos filas sin marca (NULL) se cuelen
-- como diferentes, que es el caso más común de duplicado real.
create unique index if not exists activo_referencias_uniq on activo_referencias (
  upper(regexp_replace(btrim(nombre), '\s+', ' ', 'g')),
  upper(regexp_replace(btrim(coalesce(marca,  '')), '\s+', ' ', 'g')),
  upper(regexp_replace(btrim(coalesce(modelo, '')), '\s+', ' ', 'g'))
);

create unique index if not exists activo_terceros_uniq on activo_terceros (
  upper(regexp_replace(btrim(nombre), '\s+', ' ', 'g'))
);
