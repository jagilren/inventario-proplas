# Plan: elementos NUEVOS en la remisión de devolución

**Estado:** propuesto el 2026-09-11 · decisiones tomadas el mismo día
(sección 9: **D1 = B**, D2–D4 como se recomendaron) · **fases 1 y 2
construidas y publicadas juntas** el 2026-09-11 (sección 0).
**Extiende:** Remisión de devolución (`lib/screens/remision_devolucion_page.dart`)
y Devoluciones · carga masiva (`lib/screens/devoluciones_page.dart`).
**Sigue la plantilla de 10 secciones de** `docs/sdd-modulo-equipos.md`.

---

## 0. Qué quedó construido (2026-09-11)

Las fases 1 y 2 salieron **en el mismo commit**: así Devoluciones entiende
los NUEVO desde el primer día en que la remisión los puede escribir, que era
lo que exigía el orden de la sección 7. La fase 3 (informes) sigue opcional.

| Pieza | Dónde |
|---|---|
| Formato de 7 columnas, una línea de la remisión (`LineaDevolucion`) y la observación del movimiento | `lib/util/plantilla_import.dart` |
| Lector por nombre COMPLETO de columna, `emparejarFilaDevolucion` (regla 1), `parecidos` y `mismoNombre` | `lib/util/import_archivo.dart` |
| Hoja del ingeniero (`HojaElementoNuevo`) y de la bodega (`HojaResolverNuevo`) | `lib/widgets/remision_nuevo.dart` |
| "¿No está? Agregarlo como NUEVO" en la remisión; firma = correo de quien genera (D4) | `lib/screens/remision_devolucion_page.dart` |
| Filas NUEVO primero y sin emparejar solas; resolver, crear, dejar por fuera; abono al centro de origen (D1) | `lib/screens/devoluciones_page.dart` |
| Crear desde la devolución: nombre y unidad puestos, sin existencia inicial, sin seriales ni aprovechamiento | `lib/screens/editar_elemento_page.dart` (`desdeDevolucion`) |

**Qué cambió del plan al construir:**

- **Los parecidos no podían usar `similitud()`.** Con medidas distintas
  devuelve siempre el mismo tope (0,45): un tubo de PVC salía igual de
  "parecido" a una válvula que otra válvula de otra medida. Se ordenan por
  las palabras y la medida distinta solo resta un 15 %. Se calibró contra
  nombres reales del catálogo: con el umbral en 0,45, "Válvula de bola inox
  316 1/2 Magna" trae las cuatro válvulas de bola y nada más, y "Filtro de
  canasta 2"" (que de verdad es nuevo) no trae parecidos falsos.
- **La regla 1 salió de la pantalla** a una función (`emparejarFilaDevolucion`)
  para poder probarla: vivía dentro del estado privado de Devoluciones, donde
  ninguna prueba la veía, y es la que evita cargar un artículo como otro.

**Cómo se probó.** En la base, deshecho al final: el artículo nace en $0 y
existencia 0; tras la devolución de 2 a $185.000 queda en $185.000 con 2; el
centro de origen recibe el abono de $370.000; el mismo nombre otra vez lo
rechaza la base (23505); y un usuario al que se le quita el rol de
coordinador no puede crear (42501, RLS). En la app, 26 pruebas nuevas (165 en
total): el viaje de ida y vuelta remisión → Devoluciones, archivos viejos de
2 y 3 columnas, columnas en otro orden y "185.000" escrito a mano, las guías
de accesibilidad de Flutter y 360 px con la letra al doble. Control negativo:
al romper a propósito la regla 1, el bloqueo del nombre repetido y el permiso
de crear, **fallaron las tres pruebas** que las cuidan.

---

## 1. Objetivo y alcance

**El pedido:** que en el CSV de la remisión se puedan poner artículos que
**no existen** en la base, con su cantidad y un **costo promedio estimado**
por el ingeniero que arma la remisión.

**El caso real:** el ingeniero recoge sobrantes en una obra. Algunos nunca
pasaron por la bodega (se compraron directo para el proyecto, o nunca se
crearon en el catálogo) y hoy no hay cómo devolverlos: la remisión solo deja
elegir artículos del catálogo, y si alguien los escribe a mano en el CSV,
Devoluciones los deja por fuera ("sin emparejar").

**Dentro:** proponer el artículo nuevo en la remisión, llevarlo en el CSV,
resolverlo en Devoluciones (es uno que ya existía, o se crea en el
catálogo) y cargarlo con el costo estimado.

**Fuera, a propósito:**
- Que el ingeniero cree artículos en el catálogo. Él **propone**; el
  catálogo lo gobiernan admin y coordinador (sección 6).
- Serializados: un artículo nuevo que entra por aquí nunca es serializado.
- Guardar la remisión en la base (se discute en la decisión D4).

---

## 2. Relación con lo que ya existe

Hoy el viaje es:

```
Remisión (ingeniero)            CSV                    Devoluciones (bodega)
elige del catálogo  ──►  ELEMENTO | CANTIDAD |  ──►  empareja cada fila con el
                         COSTO PROMEDIO              catálogo y la carga como
                                                     entrada de devolución
```

Tres piezas que ya existen y el plan **reutiliza**, no reinventa:

| Pieza | Qué hace hoy | Para qué sirve aquí |
|---|---|---|
| `EmparejadorCatalogo` (`lib/util/import_archivo.dart`) | Busca el artículo más parecido, respetando las medidas (1/2" ≠ 2-1/2") | Antes de aceptar un "nuevo", mostrar **los parecidos**: casi siempre ya existe con otro nombre |
| `costoManual` en Devoluciones | Si un artículo está en $0, la línea exige un costo a mano | Un artículo recién creado está en $0: el costo estimado entra **por el mismo camino** |
| `leerPesos()` + `pesosEntendidos()` (`lib/util/dinero.dart`) | Lee "1.540.000" como en Colombia y muestra "= $1.540.000" | El campo del costo estimado |

**El hallazgo que ordena todo el plan.** Si hoy alguien pone a mano un
artículo nuevo en el CSV, Devoluciones lo empareja **por parecido**. Si el
nombre se parece lo suficiente a otro del catálogo, se carga **como ese
otro**, al costo de ese otro, sin que nadie lo note. Por eso el cargador
tiene que entender la marca de "NUEVO" **antes** de que la remisión la
empiece a escribir (sección 7).

---

## 3. El formato del archivo

Siete columnas. **Cada columna significa una sola cosa:**

| ELEMENTO | CANTIDAD | COSTO PROMEDIO | NUEVO | UNIDAD | COSTO ESTIMADO | ESTIMADO POR |
|---|---|---|---|---|---|---|
| Tubo PVC 2" | 10 | 12500 | | | | |
| Codo 90° 1" | 4 | 3200 | | | | |
| Válvula mariposa 4" wafer | 2 | | SI | UND | 185000 | ing.perez@rpci.com.co |

- **Del catálogo:** como hoy. `COSTO PROMEDIO` es informativo.
- **Nuevo:** `NUEVO = SI`, con `UNIDAD`, `COSTO ESTIMADO` (por unidad) y
  `ESTIMADO POR`. `COSTO PROMEDIO` va vacío: no existe todavía.

**Por qué no usar la columna `COSTO PROMEDIO` para el estimado:** porque en
las filas del catálogo esa columna **no se usa** al cargar, y en las nuevas
sí. Una columna que a veces se ignora y a veces manda es una trampa para
quien edita el archivo en Excel.

**Compatibilidad:** los archivos de dos y de tres columnas se siguen
cargando igual. El lector tiene que ubicar las columnas nuevas por su
**nombre completo**: hoy detecta el costo buscando la palabra "costo", y con
dos columnas de costo esa búsqueda se quedaría con la primera. Es
exactamente el tipo de error que la prueba de hoy ("la columna nueva NO se
toma como la cantidad") está hecha para atajar.

**No hay cambios en la base** para la opción recomendada: ni tablas ni
columnas. Un artículo nuevo es una fila más de `elementos`, y su ingreso es
un movimiento de entrada como cualquier otro.

---

## 4. Reglas de negocio

1. **Un "NUEVO" nunca se empareja solo.** Aunque el nombre se parezca a uno
   del catálogo. Se le muestran los parecidos y **una persona decide**.
2. **Resolver una fila nueva tiene tres salidas:**
   - **"Es este del catálogo"**: pasa a ser una fila normal. Su costo es
     el promedio actual del artículo; si ese artículo está en $0, se propone
     el estimado como costo a mano (la regla de hoy).
   - **"Crear en el catálogo"** (admin o coordinador): abre el formulario de
     artículo que ya existe, con el nombre y la unidad puestos. El costo
     **no se escribe ahí**: nace en $0 y lo pone la entrada.
   - **"Dejar por fuera"**: no se carga y sale en el resumen.
3. **El costo estimado es una propuesta, no un hecho.** Quien carga lo ve,
   lo puede corregir antes de cargar, y el movimiento guarda los dos datos en
   la observación: *"Elemento nuevo desde remisión · estimado por
   ing.perez@…: $185.000 · cargado a $180.000"*.
4. **El primer costo promedio de un artículo nuevo es el estimado.** Así
   funciona el promedio móvil desde existencia cero; las compras siguientes
   lo van corrigiendo. Por eso la regla 3 importa: un estimado inflado
   infla la valorización de la bodega hasta que llegue una compra real.
5. **Una fila nueva sin cantidad, sin unidad o sin costo estimado no se
   carga**, y lo dice en la fila, no solo al final.
6. **Ninguna fila nueva se carga sin resolver.** Las resueltas se cargan
   igual que las demás.

---

## 5. Interfaz — móvil primero

### 5.1 En la remisión (el ingeniero)

- En el buscador, al final de los resultados (y cuando no hay ninguno):
  **"¿No está? Agregarlo como NUEVO"**.
- Antes del formulario, **"¿Es alguno de estos?"** con los 3 más parecidos
  del catálogo. Tocar uno lo agrega como artículo del catálogo; si ninguno
  es, se sigue.
- Formulario en hoja inferior con X para cerrar: **Nombre \***,
  **Unidad \*** (UND / MT / Par, las que usa el catálogo hoy),
  **Cantidad \***, **Costo estimado por unidad \*** con "= $185.000" debajo.
  Errores escritos en cada campo, no solo en color.
- En la lista, la línea dice **"NUEVO · estimado $185.000"** con texto, no
  solo con un color.
- Funciona sin señal, como el resto de la remisión.

### 5.2 En Devoluciones (la bodega)

- Aviso arriba, junto al de hoy: *"2 artículos NUEVOS por resolver"*.
- Las filas nuevas, agrupadas y primero, con lo que propuso el ingeniero, sus
  parecidos en el catálogo y los tres botones de la regla 2. El lector de
  pantalla oye la fila como una frase.
- El diálogo de confirmar dice cuántos artículos se crearon y cuánto suma
  lo que entra a costo **estimado**.
- El resumen final agrega *"Nuevos creados: N"*.

---

## 6. Permisos

Medido en la base el 2026-09-11:

| Acción | Quién puede hoy | Dónde se hace cumplir |
|---|---|---|
| Armar la remisión y proponer un nuevo | rol `remisiones` o admin | La app (no toca la base) |
| **Crear** un artículo en el catálogo | **admin o coordinador** | RLS `cud_elem` en `elementos` |
| Registrar la entrada | admin u `operario_mas` | RLS `ins_mov` en `movimientos` |

Hoy los tres usuarios que cargan tienen todos esos roles, así que no se nota.
Pero un bodeguero que sea **solo** `operario_mas` podrá cargar las filas
del catálogo y **no** podrá crear el nuevo: su botón "Crear en el catálogo"
dirá que lo pida a un coordinador, y esa fila quedará pendiente. Las pruebas
se hacen **por rol**, no con los usuarios que existen (lección del SDD de
Equipos, §6).

---

## 7. Fases — el orden importa

| Fase | Qué | Por qué en este orden |
|---|---|---|
| **1** | **Devoluciones entiende el formato nuevo**: filas NUEVO sin emparejar solas, las tres salidas, observación con el estimado | Se publica primero. Mientras nadie genere archivos con NUEVO, **no cambia nada** para nadie |
| **2** | **La remisión propone nuevos** y escribe las 7 columnas | Si saliera antes que la 1, el cargador de hoy emparejaría una fila NUEVO con un artículo parecido y la cargaría **como ese otro** (sección 2) |
| 3 *(opcional)* | En "Movimientos por fecha", distinguir los ingresos de artículos nuevos; y un informe "Artículos creados desde remisión" | Para auditar los estimados después |

Cada fase se prueba antes del commit (el push publica): analyze del proyecto
entero, pruebas (formato por nombre de columna, compatibilidad con archivos
de 2 y 3 columnas, que un NUEVO con nombre casi igual a otro **no** se cargue
como ese otro, permisos por rol), consulta contra la API real, build y
revisión del diff.

---

## 8. Riesgos

| Riesgo | Cómo se ataja |
|---|---|
| Duplicados en el catálogo ("Válvula mariposa 4" y "Valvula mariposa 4 pulg") | La base solo impide el nombre **idéntico**. Los parecidos se muestran dos veces: al proponer (ingeniero) y al resolver (bodega) |
| Un estimado inflado infla la valorización | Lo revisa quien carga, queda escrito quién lo estimó y a cuánto se cargó; opcional: avisar si el estimado es muy distinto del de los artículos parecidos |
| El nuevo se carga como otro artículo parecido | Regla 1 y el orden de las fases |
| Editar el CSV a mano rompe el formato | El lector ubica columnas por nombre; una fila NUEVO incompleta se muestra con su error y no se carga |
| "ESTIMADO POR" se puede escribir a mano en el Excel | Es una firma **declarada**, no probada. Si hace falta probarla, ver D4 |

---

## 9. Decisiones que te tocan

> **Decidido el 2026-09-11:** D1 = **B** (sí abona: entra como devolución,
> igual que las demás filas). D2, D3 y D4 como se recomendaron.

**D1. ¿Un artículo nuevo le abona al centro de costo de origen?**
Hoy toda fila de Devoluciones es una **devolución**: le resta consumo al
centro de origen en "Neto por Centro de Costo". Pero un artículo que nunca
existió en el catálogo **nunca salió de la bodega** hacia ese centro. Si se
le abona, el centro muestra devoluciones de algo que nunca se le despachó, y
su valor neto baja por un número **estimado**.
- **A (recomendada): entra sin abono.** Entra a la bodega con su centro
  destino, como un ingreso, y el centro de origen queda escrito en la
  observación para saber de dónde vino.
- **B: entra como devolución**, igual que las demás filas. Tiene sentido si
  esos materiales se le cobraron al proyecto por fuera del sistema y hay que
  devolverle ese valor.

**D2. ¿Quién tiene la última palabra sobre el costo?** Recomendado: quien
carga en la bodega puede corregir el estimado antes de cargar, y quedan los
dos números escritos (regla 3).

**D3. ¿Solo admin y coordinador crean el artículo?** Recomendado: sí, como
hoy en la base. El ingeniero propone.

**D4. ¿Basta con la firma en el CSV?**
- **A (recomendada para empezar):** la columna `ESTIMADO POR` la llena la
  app con el correo de quien genera la remisión. Rápido, sin tablas nuevas,
  pero se puede editar en Excel.
- **B:** guardar la remisión en la base (número, fecha, ingeniero, líneas).
  La firma pasa a ser real y Devoluciones cargaría "la remisión 0042" en vez
  de un archivo. Es más trabajo (tabla nueva, permisos, sin señal) y
  resuelve también que hoy una remisión se pierde si se cierra la pantalla.

---

## 10. Decisiones descartadas

| Idea | Por qué no |
|---|---|
| Que el ingeniero cree el artículo desde la remisión | El catálogo lo gobiernan admin y coordinador (la base ya lo exige); sin señal no se puede crear; y es la vía más corta a los duplicados |
| Crear los artículos automáticamente al cargar | Sin una persona que mire los parecidos, se llena el catálogo de casi-duplicados, sin material ni categoría |
| Un artículo comodín ("MATERIAL VARIO") con el estimado | Mezcla cosas distintas en un solo costo promedio, que deja de significar nada |
| Poner el estimado en la columna COSTO PROMEDIO | Una columna con dos significados (sección 3) |
