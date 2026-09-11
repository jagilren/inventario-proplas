# Plan: importar EQUIPOS desde una plantilla

**Estado:** diseñado y construido el 2026-09-11 (`schema_v70`).
**Extiende:** el Módulo de Equipos (`docs/sdd-modulo-equipos.md`, §5.7).
**Sigue la plantilla de 10 secciones de** `docs/sdd-modulo-equipos.md`.

---

## 1. Objetivo y alcance

**El pedido:** una plantilla para cargar muchos EQUIPOS a la vez, de una
referencia **sencilla** o de un **kit** con sus componentes.

**El caso real:** el catálogo de equipos está en un Excel de 1.414 filas
(`EQUIPOS_FABRICACIONES`), y hay una propuesta de ~276 referencias agrupadas.
Crearlos uno por uno con el alta no es realista.

**Dentro:** la plantilla descargable (con ejemplos del catálogo real), la
revisión de cada fila antes de cargar, la creación de las referencias que
falten y la carga en la base.

**Fuera, a propósito:**
- Equipos **ya entregados** (vendidos): la carga es un **alta** — el equipo
  entra a una bodega. La historia de lo que ya se vendió es otra cosa.
- Equipos **usados no utilizables** (que entran a mantenimiento): la carga
  los toma como utilizables. Si hace falta, se cambia el estado en su ficha.
- Seriales repetidos en el Excel viejo: los detecta la revisión, pero
  decidir cuál es el bueno es del usuario.

---

## 2. Relación con lo que ya existe

| Pieza | Qué hacía | Para qué sirve aquí |
|---|---|---|
| `ActivosService.alta` + `agregarComponentes` | Alta de UN equipo: tres llamadas desde la app | La carga hace **exactamente lo mismo**, pero en la base y en una sola operación |
| `agregar_componentes` (`schema_v65`) | Los componentes de un kit, todos o ninguno | Se llama desde la función de carga |
| `plantilla_kit` | La composición del último kit de una referencia | Un kit que viene **sin** componentes copia esa |
| `leerPesos()` | Lee "1.540.000" como en Colombia | VALOR NUEVO y VALOR UNITARIO |
| `similitud()` | El parecido de dos textos | Las referencias del catálogo que se parecen a una nueva |
| `DialogoCargaTerminada` | El resumen de Devoluciones | El resumen de esta carga |

---

## 3. El formato

Una hoja (sirve Excel y CSV). Las columnas se ubican por su **nombre
completo**, así que el orden no importa:

| Columna | Qué va | Si va vacía |
|---|---|---|
| SERIAL | El del equipo | No entra |
| REFERENCIA | El modelo | No entra |
| MARCA, MODELO | Para encontrar la referencia o crearla | — |
| ES KIT | SI / NO | Se toma la del catálogo (o SI si trae componentes) |
| CONDICION | nuevo, usado, repuestos, baja | No entra |
| PORCENTAJE | 0 a 100 | 100 (con aviso si es usado) |
| VALOR NUEVO | En pesos | No entra (salvo kits: no se usa) |
| BODEGA | "Bodega RPCI", o "RPCI" a secas | No entra |
| CENTRO ORIGEN | Código | `COMPRA`, como el alta |
| CENTRO DESTINO | Código (interno) | `G000002`, como el alta |
| OBSERVACION | Texto | — |
| COMPONENTE, CANTIDAD, VALOR UNITARIO | Solo en las filas de componentes | — |

**Kits (decisión del usuario):** el kit en una fila y sus componentes **en las
filas de abajo, con el mismo SERIAL**, llenando solo COMPONENTE, CANTIDAD y
VALOR UNITARIO. Un componente con el SERIAL vacío es del kit de arriba.

---

## 4. Reglas de negocio

1. **Nada entra sin revisión.** Al subir el archivo se ve, fila por fila, qué
   entra, qué referencias se crean y qué tiene problemas — **con texto**, no
   solo en rojo.
2. **Una referencia que no existe se CREA al cargar** (decisión del usuario),
   **una sola vez** aunque la usen cien equipos, y antes se muestra a cuáles
   del catálogo se parece. Se busca como la compara el índice único de la base
   (nombre + marca + modelo, sin espacios de sobra y en mayúsculas).
3. Si hay **dos referencias con el mismo nombre**, se pide la MARCA. Una
   **desactivada** no se usa ni se duplica: lo dice.
4. **Una referencia nueva es kit si cualquiera de sus equipos trae
   componentes** — decidido con **todas** las filas leídas: fila por fila, el
   resultado dependía del orden del Excel.
5. Un kit **sin** componentes copia los del **último kit** de su referencia
   (con aviso); un kit **nuevo** sin componentes no entra.
6. **El serial no se repite:** ni en el archivo (las dos filas lo dicen) ni con
   uno que ya exista. Por eso **subir el mismo archivo otra vez no duplica
   nada**.
7. Las filas de **EJEMPLO** de la plantilla no entran: si alguien las deja, la
   revisión las marca.
8. Los centros siguen la regla del alta: el **origen** no puede ser interno y
   el **destino** tiene que serlo.

---

## 5. La base: `importar_equipos(p_equipos)`, `schema_v70`

Por cada equipo: la referencia (la que viene, o la busca y si no existe la
crea), el equipo, su **entrada** (el trigger abre la ubicación y pone el
estado, como en cualquier alta) y, si es kit, sus componentes. **Todo en una
transacción por llamada**: si un equipo falla, no entra ninguno del lote, y el
error dice el serial.

**Los lotes.** La base corta toda operación que pase de **8 segundos**. Se
midió: **100 equipos en 0,86 s**. La app manda de a 100 — margen de 9 veces.
Si un lote falla, se detiene: lo que entró sale de la pantalla y lo que falta
se queda, y como el serial no se repite, volver a cargar no duplica.

Corre con los permisos de quien la llama (la RLS sigue mandando): puede
cargar quien puede dar de alta un equipo. Sin sesión, no existe.

---

## 6. Interfaz — móvil primero

Menú del módulo → **Importar equipos**. Una sola lista con desplazamiento:
el botón para elegir el archivo, **Plantilla** y la ayuda (i); después el
resumen (*"120 equipos · 115 listos · 5 con problemas"*), el panel de
**referencias que se crearán** con sus parecidas, filtros Todos / Listos /
Con problemas (se abre en "Con problemas" si hay), y cada equipo con su ícono,
su fila del Excel y sus problemas escritos. Abajo, **CARGAR N EQUIPOS**, con
el avance *"Cargando 200 de 1.400…"* y el resumen al final.

---

## 7. Cómo se probó

- **En la base, deshecho al final:** 100 equipos (sencillos, usados al 70 %,
  kits con componentes, dos referencias nuevas) en 0,86 s; el kit quedó con su
  valor calculado y su ubicación; las referencias nuevas se crearon una vez;
  una segunda carga encontró la referencia escrita con otras mayúsculas; un
  serial repetido frenó el lote entero **sin dejar nada**; componentes en un
  equipo que no es kit, rechazados; sin sesión, sin permiso.
- **En la app:** 34 pruebas — la plantilla que baja la app se vuelve a leer
  entera (y sus ejemplos no entran), cada regla de la sección 4, las pantallas
  con las guías de accesibilidad de Flutter y en 360 px con la letra al doble.
  Control negativo: al quitar a propósito el bloqueo de los ejemplos, la
  decisión de kit con todas las filas y los problemas escritos en la fila,
  fallaron las pruebas que los cuidan.

---

## 8. Riesgos

| Riesgo | Cómo se ataja |
|---|---|
| Duplicar referencias escritas distinto | Las parecidas se muestran antes de cargar; la base además impide el nombre+marca+modelo idéntico |
| Un lote a medias | Cada lote es una transacción: entra completo o no entra |
| Pasar el límite de 8 segundos | Lotes de 100, medidos |
| Cargar el Excel viejo tal cual | No sirve: sus columnas no son las de la plantilla, y la revisión lo dice |

---

## 9. Decisiones del usuario (2026-09-11)

- **Referencias que no existen:** se crean al cargar (recomendado), con la
  lista y sus parecidas antes.
- **Componentes de un kit:** en las filas de abajo con el mismo SERIAL
  (recomendado): una sola hoja, sirve en CSV.

---

## 10. Decisiones descartadas

| Idea | Por qué no |
|---|---|
| Tres llamadas desde la app por equipo, como el alta | Con cientos de equipos, un corte a mitad deja equipos sin entrada o kits sin componentes |
| Una sola llamada con todo el archivo | 1.400 equipos no caben en 8 segundos |
| Una segunda hoja de componentes | No sirve en CSV (decisión del usuario) |
| Traer todos los seriales de la base para compararlos | No escala; se pregunta solo por los del archivo, de a 200 |
