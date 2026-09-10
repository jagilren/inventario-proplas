# SDD del Módulo de Equipos — y cómo escribir uno

Este documento hace dos cosas a la vez:

1. **Es** el Documento de Diseño de Software (SDD) del Módulo de Equipos.
2. **Enseña** a escribir uno, usando este módulo como ejemplo trabajado.

Cada sección trae primero **qué va ahí y por qué**, y después **el contenido
real** del módulo. Los ejemplos de errores son de verdad: pasaron en este
desarrollo, en septiembre de 2026. Un tutorial con ejemplos inventados no
enseña; los tropiezos reales sí.

---

## Antes de empezar: qué es y qué NO es un SDD

Un SDD responde **"cómo va a estar construido esto y por qué así"**. Se escribe
*antes* de programar y se corrige *durante*.

**No es** un manual de usuario, ni la documentación del código (esa la da el
código bien escrito), ni una lista de tareas.

**La prueba de fuego:** si dentro de un año alguien pregunta *"¿por qué esto se
hizo así y no de la otra forma?"*, el SDD debe responderlo. Si solo dice **qué**
se hizo, es documentación redundante — eso ya lo dice el código.

> ### La regla que más valor da
> **Escribe el PORQUÉ, no solo el QUÉ.**
>
> Malo: *"activo_ubicaciones guarda la ubicación física."*
> Bueno: *"activo_ubicaciones es una tabla aparte y no una columna en `activos`
> porque hay que conservar el historial: dónde estuvo el equipo, desde cuándo y
> quién lo movió. Una columna solo guarda el presente."*
>
> El primero lo deduces leyendo el código. El segundo no.

---

## 1. Objetivo y alcance

**Qué va aquí:** el problema que se resuelve, en lenguaje del negocio. Y —tan
importante como eso— **lo que queda FUERA**. Un alcance sin fronteras se
desborda solo.

**El del Módulo de Equipos:**

Controlar las máquinas de RPCI (bombas, sopladores, motores) que hoy no están en
ningún sistema: dónde están, en qué estado, cuánto valen y a quién se
entregaron.

**Fuera de alcance, a propósito:**
- No maneja consumibles ni repuestos sueltos — eso es el módulo de Inventario.
- No es un sistema de mantenimiento preventivo con alertas por horas de uso.
- Los terceros (talleres, clientes) **no** son usuarios de la app; nunca inician
  sesión. Son datos de catálogo.

> **Por qué escribir lo que queda fuera:** durante el desarrollo surgió tres
> veces la tentación de meterle cosas del módulo de Inventario. Tener la
> frontera escrita permitió decir "eso no va aquí" sin discutirlo de nuevo cada
> vez.

---

## 2. Relación con lo que ya existe

**Qué va aquí:** qué comparte y qué NO comparte con el resto del sistema. Es la
sección que evita el error más caro: reutilizar algo que se parece pero no es lo
mismo.

**El del módulo:**

| Comparte | No comparte |
|---|---|
| Bodegas, centros de costo, usuarios y roles | Tablas de inventario (`elementos`, `movimientos`) |
| El mecanismo de auditoría (`fn_auditoria`) | Los informes (familia propia) |
| Los widgets de la interfaz | El concepto de "existencia" |

**La decisión clave, y su porqué:** el módulo **no tiene ninguna llave foránea
hacia `elementos`**. La tentación era modelar un equipo como "un elemento
serializado más", reutilizando toda la maquinaria de inventario.

Se descartó por una **medición, no por intuición**: se contaron las bombas y
motores en el catálogo de elementos y había **cero**. Los equipos nunca
estuvieron ahí. Forzar la reutilización habría contaminado el inventario de
piping con reglas que no le aplican.

> **Lección de método:** cuando dudes entre reutilizar y separar, **busca un dato
> que decida**. "Cero equipos en el catálogo actual" cerró una discusión que
> podía durar una semana.

---

## 3. Modelo de datos

**Qué va aquí:** las tablas, sus campos, y **la justificación de cada decisión
que no sea obvia**. No hay que documentar que un nombre es texto; sí hay que
documentar por qué algo es una tabla aparte, por qué un campo es obligatorio, o
por qué existe un índice único.

**El del módulo — 10 tablas y 2 vistas:**

```
activo_referencias   los modelos (catálogo)
activos              cada unidad física, siempre con serial
activo_terceros      talleres, clientes, proveedores
activo_ubicaciones   historial de DÓNDE ESTÁ (no toca inventario)
activo_movimientos   entradas y salidas REALES (sí tocan inventario)
activo_piezas        piezas buenas/malas de un equipo desarmado
activo_mantenimientos hoja de vida
activo_observaciones  notas sueltas que no tienen otra casa
activo_componentes            de qué está hecho un KIT (extensión)
activo_componente_movimientos la vida de cada componente (extensión)

activos_disponibilidad      qué hay disponible por referencia
activo_observaciones_todas  las 3 fuentes de observaciones, unidas
```

> Las dos últimas tablas son la extensión **Referencias KITZABLES**: una
> referencia marcada como kit vale la suma de sus componentes, y cada
> componente tiene su propia historia (daño, venta, garantía, anulación).
> Tienen su propio documento de diseño, `docs/plan-kits-equipos.md`, que
> sigue la plantilla de la sección 10 de este SDD — y su sección 0 cuenta qué
> cambió del diseño al construirlas, a la luz de los errores de la §9.

**Las cinco decisiones que hay que justificar:**

**a) `condicion` y `estado` son campos distintos.** Parecen lo mismo y no lo son:

- `condicion` = clasificación comercial (nuevo, usado, repuestos, baja) → decide
  **cuánto vale**.
- `estado` = disponibilidad operativa (operativo, mantenimiento, entregado) →
  decide **si se puede usar**.

Una bomba *usada* puede estar perfectamente *operativa*. Juntarlos en un campo
obliga a inventar valores como "usado-pero-funcionando".

**b) `activo_ubicaciones` es una tabla, no una columna.** Porque hay que
conservar el historial con fecha y responsable. Una columna solo guarda el
presente y pierde el pasado.

**c) `valor_actual` es una columna GENERADA** (`valor_nuevo × porcentaje / 100`),
no un campo que la app calcula. Si la app lo calculara, dos pantallas podrían
mostrar números distintos del mismo equipo. La base es la única fuente.

**d) Las observaciones se UNEN en una vista, no se copian a una tabla.**
*(Agregado el 2026-09-10.)*

La ficha mostraba **una sola** observación, la del alta. Los comentarios que el
usuario escribía al cambiar el estado o la ubicación no se veían por ninguna
parte: el de ubicación quedaba enterrado en `activo_ubicaciones.detalle`, y el
de estado no tenía ni dónde guardarse.

Lo obvio era crear `activo_observaciones` y que **todas** las pantallas
escribieran ahí. Se descartó: el texto de un cambio de ubicación ya vive en
`activo_ubicaciones.detalle`, que es lo que muestra el historial de ubicaciones.
Escribirlo también en otra tabla serían **dos copias del mismo texto** que se
desincronizan a la primera corrección.

Lo que se hizo: una tabla **solo para lo que no tenía casa** (el comentario de
un cambio de estado) y una **vista** que une los tres orígenes:

```sql
create view activo_observaciones_todas
with (security_invoker = true) as
  select ... from activo_observaciones            -- origen 'estado' / 'manual'
  union all
  select ... from activo_ubicaciones              -- origen 'ubicacion'
   where detalle is not null and btrim(detalle) <> ''
  union all
  select ... from activos where observacion <> '' -- origen 'alta'
```

Cada texto sigue teniendo **un solo dueño**. Y hubo un premio inesperado: al
crear la vista aparecieron de una **8 observaciones de ubicación y 2 de alta**
que ya existían y nadie estaba viendo. Cero migración de datos.

> `security_invoker = true` no es decorativo: sin eso la vista corre con los
> permisos de su dueño y se salta la RLS de las tablas de abajo. Misma
> convención que `activos_disponibilidad`.

> **Patrón general:** todo dato que se pueda DERIVAR, se deriva — nunca se
> guarda a mano. Aplica a `valor_actual`, a `disponible`, y ahora al listado
> de observaciones.

**e) Observaciones editables, sin reescribir la historia.** *(2026-09-10,
`schema_v60`.)*

El usuario pidió poder **editar** cada observación, y que quedara una
auditoría con **fecha, diferencia y usuario**.

La tentación era una tabla nueva de "versiones de observaciones". No hizo
falta, y la razón es la decisión (d): como cada texto tiene **un solo dueño**,
editarlo es un `UPDATE` en su tabla de origen — y las tres tablas ya tenían el
trigger `fn_auditoria`, que guarda por cada cambio el campo, el valor anterior,
el nuevo, el usuario y la fecha. **La auditoría ya existía. Lo que faltaba era
poder verla desde la ficha.**

Ahí apareció el problema de verdad: `auditoria` solo la leen **admin y
coordinador**. Y así tiene que seguir — guarda los cambios de **todo** el
sistema, incluidos costos de inventario. Abrírsela al rol `equipos` para que
viera el historial de una nota sería regalarle mucho más de lo que pidió.

La salida es una función `SECURITY DEFINER`:

| | Función normal | `SECURITY DEFINER` |
|---|---|---|
| Corre con los permisos de | Quien la llama | El dueño de la función |
| Lee `auditoria` el rol `equipos` | No | Sí, pero **solo lo que la función devuelve** |

`observacion_historial(origen, id)` lee la auditoría con permisos de dueño,
pero **devuelve únicamente** los cambios del texto de **una** observación, y
solo si quien la llama tiene acceso al módulo. Es una ventana del tamaño
exacto de lo pedido.

> Una función `SECURITY DEFINER` es **una llave maestra**. Tres reglas que no
> se negocian: fijarle el `search_path` (si no, alguien puede meterle una
> función con el mismo nombre en otro esquema), revisar los permisos **adentro**
> y no confiar en quién la llama, y quitársela a `anon` y a `public` con
> `revoke`. Las tres están en la `v60`.

En pantalla, cada observación tiene un **lápiz** para editarla, y si ya se
editó dice **"Editada · ver cambios"**, que abre cada cambio con su fecha, su
usuario, lo que decía **antes** (tachado) y lo que dice **después**. Una nota
no se puede dejar vacía al editarla: la haría desaparecer del listado sin
dejar rastro visible.

> **Lección:** antes de construir un sistema de auditoría, **mira si ya lo
> tienes**. El trabajo aquí no fue guardar los cambios —eso ya pasaba— sino
> abrir una ventana segura para mirarlos.

---

## 4. Las reglas de negocio

**Qué va aquí:** las reglas en lenguaje del negocio, ANTES de decidir cómo se
programan. Y **dónde vive cada una**.

**La regla central del módulo**, que costó trabajo formular:

> **Cambiar la UBICACIÓN física no toca el inventario. Un MOVIMIENTO sí.**

| | Cambiar ubicación | Entrada / Salida |
|---|---|---|
| Cuándo | Préstamo, taller, temporal | Compra, entrega definitiva |
| ¿Afecta el inventario? | **No.** Sigue siendo nuestro | **Sí** |
| Ejemplo | Bomba en el taller de Lucho | Bomba entregada al centro NP00034 |

**La segunda regla central: qué significa "disponible".**
*(Escrita el 2026-09-10, después de tres errores seguidos por no tenerla.)*

`estado` y `condicion` son campos distintos (§3a), pero para **disponibilidad
mandan los dos a la vez**:

> Un equipo está **disponible para entregar** si está `operativo`, **su
> condición no es `repuestos` ni `baja`**, y está **físicamente en una bodega**.

Las tres partes importan, y cada una tapa un hueco real:

| Parte | Qué tapa |
|---|---|
| `estado = 'operativo'` | No se entrega algo que está en mantenimiento |
| `condicion not in ('repuestos','baja')` | Una bomba marcada **para repuestos** aparecía como lista para entregar |
| Está en una bodega | No se entrega algo que está en el taller de un tercero |

Y de ahí sale la regla que unifica la pantalla de estado con la de ubicación:

> Poner un equipo en **"Operativo (listo para entregar)"** significa que
> **volvió a su bodega**. Si estaba en un taller, ese regreso es un movimiento
> físico real y va al historial. Marcarlo **de baja** o **para repuestos** no
> lo devuelve a estar disponible, aunque esté en la bodega.

**Dónde vive:** en la vista `activos_disponibilidad`, porque se **deriva** y no
se guarda nunca. Pero está **duplicada a propósito en dos sitios más**, y eso
hay que saberlo:

| Copia | Para qué |
|---|---|
| `lib/local_store.dart` (`ajustarEstadoActivoLocal`) | Que las listas offline no contradigan a las de línea |
| La hoja "Estado y condición" | Avisar al usuario qué va a pasar **antes** de guardar |

> **Cuándo se permite duplicar una regla:** cuando las copias no *deciden* nada
> —solo predicen— y la base sigue siendo la única que manda. Las dos copias de
> arriba se pueden equivocar sin corromper un dato. Aun así van comentadas
> apuntando a `schema_v55`, porque una fórmula en tres sitios se desincroniza
> sola si nadie dejó dicho dónde están las otras dos.

**La tercera regla central: entregar es salir del inventario, de verdad.**
*(Escrita el 2026-09-10.)*

Cuando un equipo se entrega a un centro de costo **deja de ser nuestro**. Eso
tiene consecuencias en cuatro sitios, y solo una estaba programada:

| Consecuencia | ¿Estaba? |
|---|---|
| `estado = 'entregado'` | Sí |
| Se **cierra** su ubicación vigente | **No** — la ficha seguía diciendo "Está en: Bodega RPCI" |
| No se le puede cambiar la **ubicación** a mano | **No** — el botón seguía activo |
| No se le puede cambiar el **estado** a mano | Sí |

Y al revés, **al reingresarlo**:

> El equipo vuelve a ser nuestro **con la condición con la que regresó**. Si
> salió `nuevo` y vuelve `usado`, su ficha dice `usado` — y por lo tanto se
> valoriza como usado.

Eso tampoco estaba: `fn_aplicar_activo_movimiento` usaba `new.condicion` para
decidir el **estado**, pero nunca la copiaba a `activos.condicion`. Una bomba
que salió nueva y volvió usada se seguía valorizando como nueva.

**Los cuatro caminos, ahora completos** (`schema_v57`):

```
salida             -> entregado · se CIERRA la ubicación
entrada            -> estado según condición · se COPIA la condición
                      · se ABRE ubicación en la bodega
anular una salida  -> operativo · se REABRE en su bodega dueña
anular una entrada -> entregado · se CIERRA la ubicación
```

> **La lección del 9.6, aplicada antes de que muerda:** los cuatro caminos se
> escribieron y se **probaron en transacción con rollback**, incluidas las dos
> anulaciones — que son la mitad que siempre se olvida porque nadie las ejerce
> hasta que toca deshacer algo un viernes.

**Reingresar "para repuestos".** *(2026-09-10, `schema_v58`.)* Un equipo que
salió entero a un centro de costo puede volver desarmado. El diseño original
lo prohibía a propósito —*"nunca 'repuestos' en un movimiento: es una
reclasificación posterior"*— y el alta mandaba `usado` en su lugar.

Esa decisión se revirtió, y la razón vale la pena: **dos decisiones que por
separado eran correctas se volvieron un bug al juntarse.** El truco del alta
("mandar usado en vez de repuestos") era inofensivo mientras la entrada no
tocara la condición de la ficha. En cuanto `schema_v57` hizo que la entrada
copiara su condición, ese mismo truco habría dejado como "usado" un alta que
era "para repuestos". Nadie lo reportó; se encontró leyendo el código antes de
tocarlo.

Qué estado queda, y por qué **no** `baja`:

| Opción | Problema |
|---|---|
| `estado = 'baja'` | El valorizado **excluye** los de baja, y un donante de piezas **sí vale** |
| Un estado nuevo `no_disponible` | Duplica lo que ya calcula la vista de disponibilidad |
| **`estado = 'operativo'`** ✔ | Está en la bodega y fuera de mantenimiento; la vista lo marca **no disponible** por su condición |

En pantalla, un equipo operativo pero para repuestos o de baja **no dice
"Operativo"**: dice **"No disponible"**, en gris. Y no se le puede dar salida
— ni desde su ficha ni desde la pestaña Movimientos, que antes lo mandaba
directo a la pantalla de entrega por ser "operativo".

> **Lección:** cuando cambies lo que hace un trigger, busca **quién le estaba
> mandando datos pensando en el comportamiento viejo.** El alta no se tocó en
> la `v57`, y aun así se rompió por ella.

**Una entrada no es siempre lo mismo: el REINGRESO.** *(2026-09-10,
`schema_v63`.)* Una entrada puede ser el **alta** de un equipo nuevo o el
**reingreso** de uno que se había entregado a un centro de costo y vuelve. En
la ficha y en los informes las dos decían solo "Entrada". Ahora un reingreso
dice **"Entrada · REINGRESO"**, con su propio ícono y en otro color, y el
informe de movimientos lo trae así en la columna *Tipo* — filtrable en Excel.

La decisión de diseño, y por qué:

| Opción | Problema |
|---|---|
| Derivarlo al consultar ("¿hubo una salida antes?") | Se complica con las anulaciones, y cada informe repetiría la lógica |
| **Estamparlo al insertar** ✔ | Es un hecho del momento — igual que el valor de una salida, que ya se estampa así |

El criterio: **es reingreso si el equipo estaba `entregado` en el momento de
entrar.** Funciona por un detalle del orden de los triggers: el que cambia el
estado (`fn_aplicar_activo_movimiento`) corre **AFTER** insert, así que uno
**BEFORE** todavía ve el estado viejo. Y lo decide siempre la base: si la app
manda la marca, se sobreescribe. Se probó mandando `false` en un reingreso
real y `true` en un alta: la base corrigió las dos.

**El detalle que casi se escapa.** El candado de inmutabilidad de los
movimientos (`fn_activo_mov_solo_observacion`) nombra las columnas **una por
una**. Una columna nueva que no esté en esa lista queda **editable sin que
nadie se entere** — la app podría haber volteado la marca después. Se agregó
a la lista y se probó que voltearla falla.

> **Lección:** cuando agregues una columna a una tabla con candado, **revisa
> el candado**. Una lista explícita de columnas protege lo que había el día
> que se escribió, no lo que se agregue después.

La etiqueta ("Entrada · REINGRESO") se define **en un solo sitio**
(`ActivoMovimiento.etiquetaTipo`) y la usan la ficha y el informe. Si cada uno
armara la suya, tarde o temprano dirían cosas distintas.

**Dónde vive cada regla — y esto es diseño, no detalle:**

| Regla | Dónde | Por qué ahí |
|---|---|---|
| Serial único | Índice en la base | Debe cumplirse aunque falle la app |
| "Disponible" | Vista SQL | Se deriva; nunca se guarda |
| Estado tras una entrada | Trigger | Debe pasar siempre, venga de donde venga |
| Sugerir 70% para un usado | La app | Es una sugerencia, no una ley |
| Los componentes de un kit nuevo entran **todos o ninguno** *(2026-09-10)* | Función de la base (`agregar_componentes`) | Con una llamada por componente, un corte de red deja un kit a medias valiendo menos, **sin que nadie lo note** |
| Proponer la composición del kit anterior *(2026-09-10)* | La base la consulta (`plantilla_kit`), la app la ofrece | Es una sugerencia editable: el kit nuevo no queda amarrado al anterior |
| El desglose de los kits va en un **informe aparte** *(2026-09-10)* | Informe "Composición de kits" | Con el kit y sus componentes en el mismo archivo, sumar la columna de valor en Excel **cuenta cada kit dos veces** |

> **Criterio:** si la regla debe cumplirse **siempre**, va en la base. Si es una
> ayuda al usuario, va en la app. Poner una regla dura solo en la app significa
> que una carga masiva o una corrección manual pueden violarla.

---

## 5. Interfaz

**Qué va aquí:** cómo navega el usuario y **por qué esa forma y no otra**. No
hacen falta mockups bonitos; hace falta la lógica.

**El del módulo:** cuatro pestañas — Por referencia, Movimiento, Disponibles, En
mantenimiento.

**La decisión que hay que justificar:** en Inventario hay botones separados de
*Entrada* y *Salida*. Aquí **no**. ¿Por qué?

Porque un tornillo es **fungible** —da igual cuál— así que primero eliges la
acción y después el elemento. Un equipo **no**: es un objeto individual. Primero
buscas *esa* bomba, y **su estado decide** si lo que cabe es una entrada o una
salida. El usuario no tiene que saberlo de antemano.

> **Lección:** cuando una pantalla nueva se parece a una que ya existe, pregunta
> si el **objeto** es el mismo tipo de cosa. Copiar la forma sin copiar la
> naturaleza produce interfaces que "se sienten raras" sin que nadie sepa
> explicar por qué.

**Condición no negociable de este proyecto:** todo tiene que verse bien en un
celular de 360 px. Área táctil de 48 dp, nada de anchos fijos, máximo 4 botones
en la barra inferior.

### 5.1 Buscar un equipo: por lo que el usuario se sabe, no por lo que la base guarda

*(2026-09-10, `schema_v59`.)* La pestaña Movimientos buscaba **solo por
serial**. El que no se sabía el serial de memoria —casi todo el mundo— no
encontraba el equipo.

Ahora busca por **serial, nombre de la referencia, marca, modelo y tipo**, sin
importar mayúsculas ni tildes, y **cada palabra por separado**: *"grundfos
diafragma"* encuentra la bomba de diafragma marca Grundfos, aunque una palabra
esté en la marca y la otra en el nombre.

**Por qué se hizo en la base y no en la app.** La referencia vive en **otra
tabla**. Filtrar *"serial O nombre de referencia"* desde la app obligaría a
bajar primero las referencias que coinciden y mandarlas de vuelta como
`IN(id1, id2, …)`. Con miles de referencias eso **revienta el largo de la
URL**. Una función SQL (`buscar_activos`) lo resuelve en un solo viaje, y
devuelve `setof activos` para que PostgREST siga pudiendo paginar, filtrar y
hacer *embeds* encima.

**Y el hallazgo de paso:** el serial ya tenía un índice, pero de tipo prefijo
(`text_pattern_ops`), que **no sirve** para un `LIKE '%texto%'`. O sea que hasta
la búsqueda por serial de antes recorría la tabla entera. Con 2 equipos no se
nota; con 20.000, sí. Se agregaron índices de **trigramas** (`pg_trgm`) a los
dos campos.

Tres detalles de pantalla que completan la idea:

- Cada resultado muestra **referencia · marca**. Si alguien busca "grundfos",
  tiene que ver de una por qué salió ese equipo.
- El caché **offline** guarda también marca, modelo y tipo, y filtra con la
  misma regla de "cada palabra". Sin eso, la búsqueda funcionaría distinto con
  y sin internet.
- El texto de ayuda dice lo que de verdad busca: *"Serial, referencia, marca o
  tipo…"*, no *"Buscar por serial…"*.

> **Lección:** un buscador se diseña desde **lo que el usuario recuerda**, no
> desde la llave que tiene la tabla. Nadie se sabe el serial; todo el mundo se
> sabe que es "la bomba Grundfos".

### 5.2 Origen ➡️ destino: el formato ya existía

*(2026-09-10.)* El listado de movimientos de un equipo mostraba **solo el
centro de costo de origen**. El destino no aparecía por ninguna parte.

El proyecto **ya tenía resuelto** cómo mostrarlo: `flujoMovimiento()` en
`util/movimiento_fmt.dart`, que usa el Kardex de Inventario —
`🎯 NP00034 ➡️ 🎯 NP00039`, con `🏬` para las bodegas. El listado de Equipos
simplemente no la usaba. Ahora sí, y con un ajuste: las salidas de equipos no
guardan bodega en el movimiento, así que se le pasa la **bodega dueña** del
equipo para que no salga `🏬 — ➡️ 🎯 NP00034`.

> **Lección:** es el error 9.3 otra vez — *mirar al lado antes de escribir*. La
> diferencia es que esta vez se buscó antes de programar, y en vez de inventar
> un formato nuevo se reutilizó el que el usuario ya reconoce del Kardex.

### 5.3 Accesibilidad: medida, no supuesta

*(2026-09-10, pantallas de los kits.)* "Se ve bien en mi pantalla" no es una
verificación. Flutter trae pruebas automáticas de accesibilidad, y las piezas
visuales de los kits (`lib/widgets/kit_componentes.dart`) las pasan **en el
CI, antes de cada publicación** (`test/kit_componentes_widget_test.dart`):

| Qué se mide | Por qué importa aquí |
|---|---|
| Todo lo que se toca mide **48 dp** (Android e iOS) | Se usa con el dedo en una tablet de bodega, a veces con guantes |
| Todo lo que se toca tiene **nombre** para el lector de pantalla | Un botón que solo es un ícono, para quien no ve, no existe |
| **Contraste** del texto, con el tema real de la app | Un componente agotado va en el gris del tema, **no con opacidad**: la opacidad baja el contraste por debajo de lo legible |
| **360 px con la letra al doble**, sin desbordes | Así usa el celular quien agranda la letra en Ajustes |

Y cuatro decisiones de diseño que salen de lo mismo:

- **Una frase, no cifras sueltas.** Cada tarjeta le dice al lector de pantalla
  *"Tela filtros de los medios. 24 unidades a $45.000 cada una. Subtotal
  $1.080.000. Al 70 por ciento, $756.000"* — en vez de leer "24 por 45.000" y
  tres números sin decir qué es cada uno.
- **Nunca solo color.** Un kit se marca con ícono **y** la palabra KIT; un
  agotado dice "Agotado". Quien no distingue colores, o no ve, también se entera.
- **Un control deshabilitado dice por qué.** El interruptor "Es un kit" de una
  referencia con equipos no solo se apaga: explica que ya tiene equipos y qué
  hacer. Lo mismo el valor bloqueado en el alta de un kit.
- **Los números, como se escriben en Colombia.** "45.000" en un campo decimal se
  lee como 45. El valor unitario solo acepta dígitos y muestra en vivo cómo quedó
  entendido. (El campo "Valor a nuevo" del alta, que ya existía, **sí** tiene ese
  problema — "1.540.000" queda en $0 — y está anotado como pendiente.)

> **Lección:** una verificación que nunca ha fallado no demuestra que sepa
> detectar un fallo. Antes de confiar en estas pruebas se corrieron tres
> controles **dañados a propósito** —un botón de 20 px, texto gris claro sobre
> blanco, una fila más ancha que la pantalla— y las tres verificaciones los
> atraparon.

---

## 6. Permisos

**Qué va aquí:** quién puede hacer qué, y **dónde se hace cumplir**.

**El del módulo:** un rol nuevo, `equipos`, que da acceso completo. `admin` y
`coordinador` entran por defecto.

Se aplica en **RLS de la base de datos**, no en la app. Ocultar un botón no es
seguridad: cualquiera con el token puede llamar la API igual.

**Una excepción al "acceso completo".** *(2026-09-10, `schema_v62`.)*

| Acción | admin | coordinador | equipos |
|---|:---:|:---:|:---:|
| Agregar una observación | ✔ | ✔ | ✔ |
| **Modificar** una observación ya escrita | ✔ | ✔ | **✘** |
| **Anular** un movimiento de equipo o de componente de un kit | ✔ | **✘** | **✘** |

Los roles de operario (`operario_mas`, `operario_menos`) son del Inventario y
**no entran** al módulo de Equipos. Hoy los tres bodegueros entran porque
también son coordinadores — y por eso sí editan.

**Cómo se hace cumplir una regla sobre UNA columna.** No se puede quitarle el
permiso de `UPDATE` al rol `equipos` sobre esas tablas: lo necesita para
cambiar el estado, cerrar ubicaciones, etc. Lo que se bloquea es cambiar una
columna concreta, con un trigger `before update of <columna>` que solo se
dispara si esa columna viene en el `UPDATE`. Una sola función para las tres
tablas: el nombre de la columna le llega como argumento del trigger.

El lápiz de editar tampoco se le muestra al rol `equipos`. Pero eso **no** es
el candado — es cortesía, para no ofrecerle un botón que la base le va a
rechazar.

**El hueco que apareció al probarlo.** Para probar la regla había que darle el
rol `equipos` a un usuario de prueba… y **la base no lo dejó**. La restricción
de `usuario_roles` tenía seis roles y **le faltaba `equipos`**. Quedó así desde
la Fase 1: el rol se agregó a la app (`Roles.todos`) y a todas las políticas
RLS del módulo, pero no a la lista de valores permitidos. **Nadie podía
tenerlo.** Si el admin intentaba asignárselo a alguien desde la app, fallaba.

No se había notado porque los tres usuarios que entran a Equipos lo hacen como
coordinadores.

> **Lección:** una prueba de permisos tiene que probar **el rol**, no a una
> persona. Si se hubiera probado con un usuario que tuviera *solo* el rol
> `equipos`, esto habría saltado el día que se creó el módulo. Probar con los
> usuarios que ya existen solo prueba los roles que ya se usan.

---

## 7. Fases de entrega

**Qué va aquí:** el orden, y **qué desbloquea cada fase**. Ordenar por
dependencia, no por lo que se ve más bonito.

| Fase | Qué | Por qué en ese orden |
|---|---|---|
| 1 | SQL | Sin tablas no hay nada |
| 2 | Capa de datos | Aísla la app de la base |
| 3 | Navegación | Riesgo alto: toca el login de todos |
| 4 | Pantallas | Lo más largo |
| 5 | Informes | Necesitan datos reales |
| 6 | Despliegue | |

> **Lección de la Fase 3:** era la única que tocaba el login de **todos** los
> usuarios. Se desplegó primero en una URL de prueba y solo pasó a producción
> tras confirmarlo. Marcar en el SDD **cuál fase es la peligrosa** hace que se
> trate distinto llegado el momento.

---

## 8. Riesgos

**Qué va aquí:** qué puede salir mal, dicho **antes** de que salga mal. Esta
sección es la que más se omite y la que más vale.

**Los que se anotaron y se cumplieron:**

| Riesgo anotado | Qué pasó |
|---|---|
| Cambiar el `AuthGate` rompe el login de todos | Se probó aparte. No pasó nada |
| El texto libre en `mantenimiento_actor` se va a chocar con `activo_ubicaciones` | **Se cumplió.** Ver abajo |

---

## 9. Los siete errores reales, los que se atajaron — y qué enseña cada uno

Esta es la sección más útil del documento. **Un SDD también sirve para escribir
lo que salió mal**, no solo lo que se planeó.

### 9.1 El error que el SDD SÍ había previsto

`mantenimiento_actor` se dejó como **texto libre** por decisión explícita. Al
escribir el diseño se anotó: *"posible solapamiento futuro con
activo_ubicaciones, vigilar"*.

Se cumplió exactamente. El usuario llevó una bomba al taller MetalAndes usando
"Cambiar estado" y **no apareció en el historial de ubicaciones**, porque ese
campo no crea registro. Había dos caminos para la misma acción y no se hablaban.

**Agravante:** el catálogo de terceros estaba vacío, así que el camino correcto
ni siquiera ofrecía opciones. La app empujaba al único camino que no dejaba
rastro.

> **Lección:** anotar un riesgo **no lo evita**. Si al escribir el diseño dices
> "esto puede chocar", o lo resuelves ahí, o pones una fecha para revisarlo.
> Un riesgo anotado y olvidado es igual que no haberlo anotado.

### 9.2 El error que ninguna prueba de base detectó

Las consultas a la vista `activos_disponibilidad` fallaban con **PGRST201**: la
vista llega a `bodegas` por dos caminos y hay que decir cuál.

Todas las pruebas SQL pasaban. **Porque las pruebas SQL no pasan por PostgREST**,
que es la capa por la que habla la app de verdad.

> **Lección:** prueba en la **misma capa** por la que va a pasar el usuario. Una
> prueba en la capa equivocada da una confianza falsa, que es peor que no probar.

### 9.3 El error de no mirar al lado

`materiales` llevaba años con un índice único normalizado para que no se
duplicaran nombres. A `activo_referencias` no se le puso. Resultado: se podían
crear "BOMBA CENTRIFUGA" y "bomba  centrifuga" como dos referencias distintas.

El mismo descuido apareció tres veces más: topes de 200 registros en selectores,
formato de dinero sin separador de miles, y desplegables sin buscador — todas
cosas que el resto de la app **ya tenía resueltas**.

> **Lección:** antes de escribir una pantalla nueva, **mira cómo resolvió el
> proyecto el problema equivalente**. El SDD debería incluir una lista de
> "convenciones que ya existen y hay que respetar".

### 9.4 El error de la regla escrita mal

En el diseño quedó escrito un SQL que excluía los aprovechamientos poniendo la
condición en el `ON` de un `LEFT JOIN`. Ahí **no excluye nada**: la fila
sobrevive igual. Va en un `FILTER`.

Se detectó comparando el resultado contra un informe que ya existía y daba el
número correcto.

> **Lección doble:** (1) el SQL de un documento de diseño **no está probado** —
> trátalo como borrador. (2) Cuando calcules una cifra nueva, **compárala contra
> una que ya sea confiable**.

### 9.5 El error que introdujo el arreglo del 9.1

*Detectado el 2026-09-10, corregido el mismo día.*

El 9.1 se arregló unificando estado y ubicación: mandar un equipo a un taller
pasó a ser **una sola acción**, y para eso la hoja empezó a exigir que se
eligiera el taller del catálogo.

La regla quedó escrita así:

```dart
bool get _faltaTaller =>
    _estado == 'mantenimiento_externo' && _taller == null;
```

Léela con un equipo que **ya estaba** en un taller. El usuario abre la hoja solo
para cambiar la condición de *usado* a *para repuestos*. `_estado` arranca en
`mantenimiento_externo` — no lo cambió nadie, ya era así — y `_taller` arranca
en `null`, porque nunca se precargaba. Entonces `_faltaTaller` es verdadero, y
`_guardar()` se devolvía en su primera línea:

```dart
if (_faltaTaller) { setState(() {}); return; }
```

**Sin guardar y sin decir nada.** El usuario oprimía Guardar y no pasaba
absolutamente nada. Ni error, ni cierre de la hoja, ni cambio en la ficha.

Dos defectos distintos en cuatro líneas:

1. **La condición confundió "estar" con "entrar".** Se exige el taller cuando el
   equipo **entra** a un taller, no mientras esté en uno. Corregido comparando
   contra el estado con el que se abrió la hoja:
   `_estado == 'mantenimiento_externo' && widget.activo.estado != 'mantenimiento_externo'`.
2. **Falló en silencio.** `setState(() {})` repinta el campo en rojo, pero la
   hoja está scrolleada y el usuario nunca ve el rojo. Ahora hay un
   `SnackBar` que dice qué falta.

**Y el arreglo casi introduce un tercero.** Al precargar el taller para que
quedara seleccionado, guardar un simple cambio de condición habría vuelto a
llamar `cambiarUbicacion()` — registrando **otra vez la misma ubicación** y
llenando de filas repetidas justo el historial que el 9.1 vino a arreglar. Se
cerró guardando el taller original y comparando: solo se registra ubicación si
el taller **cambió**.

> **Lección triple:**
> (1) **El arreglo de un error es código nuevo, y puede traer su propio error.**
> El 9.1 y el 9.5 son la misma pantalla, con seis días de diferencia.
> (2) **Un campo obligatorio hay que leerlo en el estado que ya existe**, no
> solo en el flujo feliz de crear algo desde cero. La pregunta que faltó fue:
> *"¿y si el equipo ya está así?"*.
> (3) **Nada puede fallar en silencio.** Si una acción no se puede completar,
> tiene que decirlo. Un botón que no hace nada es peor que un error.

**Post-scriptum del mismo día:** al buscar el patrón en el resto del archivo
apareció **el mismo `return` mudo** en la hoja de "Cambiar ubicación", que
nadie había reportado todavía:

```dart
if (_enBodega && _bodega == null) return;
if (!_enBodega && _tercero == null) return;
```

Corregido igual, con su mensaje. **Cuando encuentres un defecto, búscalo en
todo el archivo antes de darlo por cerrado** — es la misma lección del 9.3, y
el usuario ya la había tenido que dar una vez ("le pusiste la X a 2 de 6
hojas").

### 9.6 El error de arreglar solo la mitad de un camino

*Detectado el 2026-09-10 por el usuario, sobre el equipo `A9772113810000036 P12209`.*

Este es el 9.1 **otra vez**, en la dirección contraria.

El 9.1 se arregló haciendo que mandar un equipo a un taller registrara la
ubicación. Se probó, funcionó, se dio por cerrado. Pero solo se programó la
**ida**:

```dart
if (_estado == 'mantenimiento_externo' && _taller != null) {
  await ActivosService.cambiarUbicacion(...);   // va al taller
}
// ...y no hay ningún else. Volver no registra nada.
```

El usuario devolvió la bomba a Bodega RPCI cambiando el estado de "En un
taller externo" a "Operativo" — que es exactamente lo que significa que
regresó — y **no se registró nada**. El historial siguió diciendo que el
equipo estaba en TALLER METALANDES.

Los datos quedaron contándose dos historias distintas:

| Fuente | Decía |
|---|---|
| `activo_ubicaciones` (vigente) | TALLER METALANDES, desde las 15:13 |
| La ficha del equipo | Operativo, en Bodega RPCI |

**La regla que faltaba escribir**, y que ahora está en el código:

> El estado y la ubicación tienen que contar la **misma** historia, en las
> **dos** direcciones. Si `estado = mantenimiento_externo`, el equipo está en
> un tercero. Si deja de estarlo, volvió a su bodega — y eso es un movimiento
> físico real que va al historial con su fecha y su responsable.

De paso se corrigieron dos cosas más de la misma pantalla:

- La preselección del taller ahora sale de **la ubicación vigente**, no de
  adivinar partiendo el texto de `mantenimiento_actor`. El dato duro estaba
  ahí desde el principio y se estaba usando el blando.
- La ventana ahora **dice qué va a pasar** antes de guardar: *"El equipo
  vuelve a Bodega RPCI. Queda en el historial de ubicaciones."* La ambigüedad
  entre esta pantalla y "Cambiar ubicación" es lo que produjo el error.

> **Lección:** cuando arregles un camino, **recórrelo en los dos sentidos**.
> Un cambio de estado que implica un movimiento físico lo implica también al
> revés, y la mitad que no se programa no falla con un error: falla
> **callada**, dejando los datos mintiendo.
>
> **Y la lección de segundo orden, que es la que más duele:** el 9.1, el 9.5
> y el 9.6 son **la misma pantalla y el mismo tema**, en seis días. Dar por
> cerrado un arreglo sin preguntarse *"¿qué otro camino toca esto mismo?"* es
> lo que hace que un error vuelva con otra cara.

**Cómo se corrigió el dato que ya estaba mal.** Arreglar el código evita que
vuelva a pasar, pero no arregla la bomba que ya había quedado descuadrada — y
esa, además, **no aparecía en la lista de disponibles**, porque su ubicación
vigente seguía siendo un taller. Se corrigió directo en la base, con dos
detalles que vale la pena copiar:

- **La hora se sacó de la auditoría, no se inventó.** `auditoria` tenía el
  instante exacto en que el estado pasó de `mantenimiento_externo` a
  `operativo` (15:35:44). El registro de ubicación se puso con esa hora, no
  con la de la corrección. Si se hubiera usado `now()`, el historial diría que
  el equipo estuvo 40 minutos más en el taller de lo que estuvo.
- **La nota de corrección va en el propio registro.** El `detalle` dice qué
  pasó, que es una corrección y por qué. Quien lea el historial en un año no
  tiene que adivinar por qué hay una fila que no creó la app.

> **Lección:** la auditoría no es solo para buscar culpables. Es la fuente
> para **reconstruir la verdad** cuando un camino del código falló en
> silencio. Por eso vale la pena tenerla encendida en todas las tablas desde
> el día uno.

### 9.7 El error de unificar desde una sola puerta

*Reportado por el usuario el 2026-09-10, el mismo día que el 9.6, sobre el
mismo equipo.*

Después del 9.6 quedó escrita la regla: *el estado y la ubicación cuentan la
misma historia, en las dos direcciones.* Y se programó — **en la ventana de
Estado**. Mandar a un taller desde ahí registraba la ubicación; volver,
también.

Pero había **otra puerta**. La ventana de **"Cambiar ubicación"** llama a la
función `cambiar_ubicacion_activo`, y esa función solo movía la ubicación. **No
miraba el estado nunca.** El usuario mandó la bomba al TALLER JUAN GABRIEL
MONTOYA por ahí, y la ficha siguió diciendo **"Operativo"** en verde.

| Puerta | Ida al taller | Regreso |
|---|---|---|
| Ventana de Estado | ✔ (arreglado en 9.1) | ✔ (arreglado en 9.6) |
| Ventana de Ubicación | **✘ nunca tocó el estado** | **✘ nunca tocó el estado** |

Tres errores seguidos (9.1, 9.6, 9.7) y **los tres se arreglaron en la
pantalla**. Por eso volvían: cada arreglo tapaba una puerta y dejaba abierta
la de al lado.

**El arreglo de verdad fue sacar la regla de la pantalla y meterla en la
base** (`schema_v61`). Ahora es `cambiar_ubicacion_activo` la que decide:

```
a un tercero tipo 'taller'  -> estado mantenimiento_externo
                               + el taller en mantenimiento_actor
a una bodega, desde taller  -> estado operativo, sin mantenimiento_actor
un equipo entregado         -> se rechaza: ya no es nuestro
```

Así, **no importa por qué puerta entre el usuario**: la regla vive en un solo
sitio y las dos pantallas pasan por ella. La de Estado sigue funcionando igual
porque pone el estado *antes* de llamar a la función, y al llegar no queda nada
por cambiar — así que no pisa lo que el usuario eligió (por ejemplo, volver
del taller directo a mantenimiento interno).

Dos detalles más de la misma función:

- `select ... for update` al leer el estado: si dos personas mueven el mismo
  equipo a la vez, ninguna puede dejar el estado de una y la ubicación de la
  otra.
- Un equipo **entregado** ya no se puede mover ni por la API. Antes solo se
  escondía el botón (regla 3), que es lo que un error de la sección 6 dice que
  **no** es seguridad.

Y la ficha dejó de decir "Operativo" en verde para cualquier equipo que no se
pueda entregar: si está para repuestos, de baja, **o fuera de la bodega** (un
préstamo a un cliente), dice **"No disponible"** en gris. La ventana de
ubicación, igual que la de estado, avisa **antes** de guardar qué va a pasar:
*"Al guardar: pasa a 'En mantenimiento (externo)' en TALLER JUAN GABRIEL
MONTOYA. NO queda disponible mientras esté allá."*

La bomba se corrigió en la base con la nota obligatoria en sus observaciones,
y se verificó con una consulta que **ningún otro equipo** quedara en la misma
contradicción.

> **Lección — la más importante de toda esta sección:** si una regla de
> negocio tiene que cumplirse **siempre**, no puede vivir en una pantalla.
> Una pantalla es **una** puerta; la base es **la casa**. El SDD lo decía desde
> la sección 4 (*"si la regla debe cumplirse siempre, va en la base"*) y aun
> así se programó tres veces en la pantalla. **Escribir un principio no es lo
> mismo que aplicarlo.**

### 9.8 Los que se atajaron antes de publicar

*2026-09-10, Fase 2 de Referencias KITZABLES.*

Los siete errores de arriba llegaron a producción. Estos dos **no**, y vale la
pena contarlos porque enseñan lo mismo desde el otro lado: **qué verificación
los paró**. En este proyecto el push a `main` publica solo (CI/CD), así que lo
que no se ataje antes del commit lo ve el usuario.

**a) El arreglo que rompía una pantalla que funcionaba.** Para que el usuario
viera mensajes claros y no `PostgrestException(message: …, code: 23505)`, se
envolvió `editarReferencia()` para traducir los errores. Parecía una mejora
sin riesgo. Pero la pantalla de referencias **ya existía**, y reconoce un
nombre duplicado buscando el texto `activo_referencias_uniq` o `23505`
**dentro del error crudo**. Con la traducción, esas palabras desaparecían: el
aviso de "ya existe" habría dejado de salir y el usuario habría visto un error
genérico.

Se atajó con una búsqueda de un minuto — `grep "23505\|_uniq"` sobre la
pantalla — antes de seguir. La traducción quedó solo en las funciones nuevas
de kits, que nadie más lee todavía.

> **Lección:** antes de cambiar **cómo sale** un error, busca **quién lee** ese
> error. Un mensaje de error no es solo texto: a veces es la entrada de otro
> código.

**b) El error que el análisis no vio porque se analizaba la carpeta
equivocada.** Durante todo el día se corrió `flutter analyze lib/`. Una prueba
nueva tenía una variable llamada `daño` — y Dart no acepta la `ñ` en nombres.
El archivo estaba en `test/`, no en `lib/`, así que el análisis salía limpio.
Lo detectó `flutter test`. El CI corre `flutter analyze` sobre **todo** el
proyecto: allá habría fallado y frenado la publicación, pero después del
commit.

> **Lección:** verifica **exactamente lo mismo que verifica el CI**, con los
> mismos comandos. Una verificación local "parecida" da una confianza que no
> corresponde.

**c) La regla que no se copió al concepto hermano.** Al diseñar la pantalla
para anular movimientos de componentes de un kit (Fase 5), se revisó quién
anula un movimiento de **equipo**: la base solo se lo deja al administrador.
La Fase 1 de los kits había copiado de los movimientos de equipo casi todo —la
anulación con movimiento contrario, el índice que impide anular dos veces, el
candado que no deja editarlos— **menos el permiso**. Un coordinador podía anular
un movimiento de componente pero no uno de equipo: dos reglas distintas para lo
mismo, en el mismo módulo. Se corrigió en la base (`schema_v66`) antes de que
existiera la pantalla que lo usaría.

> **Lección:** cuando construyas algo **paralelo** a lo que ya existe (aquí,
> movimientos de componente al lado de movimientos de equipo), haz la lista de
> **todas** las reglas del hermano —cómo se valida, cómo se anula, qué candado
> tiene y **quién puede**— y revisa una por una. El permiso es la que más se
> olvida, porque no se ve en el código de la tabla sino en el de la función.

Y un detalle de método que se agregó ese día al validar consultas contra la
API: además de las 8 consultas nuevas (HTTP 200), se mandó **una dañada a
propósito**, que respondió 400. Una prueba que nunca ha fallado no demuestra
que sepa detectar un fallo.

---

## 10. Plantilla para el próximo módulo

```
1. Objetivo y alcance          ← incluye lo que queda FUERA
2. Relación con lo existente   ← qué comparte y qué no, con datos
3. Modelo de datos             ← justifica lo no obvio
4. Reglas de negocio           ← y DÓNDE vive cada una
5. Interfaz                    ← por qué esa forma
6. Permisos                    ← dónde se hacen cumplir
7. Fases                       ← ordenadas por dependencia
8. Riesgos                     ← con fecha de revisión
9. Convenciones a respetar     ← lo que el proyecto YA resolvió
10. Decisiones descartadas     ← qué se pensó y por qué no
```

**La sección 10 es la que nadie escribe y la que más se agradece.** Cuando dentro
de un año alguien proponga "¿y si los equipos fueran elementos serializados?",
la respuesta ya está escrita, con la medición que la sustenta.

---

## 11. Cómo mantenerlo vivo

Un SDD que no se corrige se vuelve mentira, y una mentira documentada es peor que
no tener nada — porque la gente le cree.

**Reglas simples:**
- Cuando una decisión cambie, **corrige el documento en el mismo commit**.
- Cuando un riesgo se cumpla, **anótalo** — es lo que enseña al siguiente.
- Cuando algo se descarte, **escribe por qué**.
- Tachar lo superado (~~así~~) y dejarlo visible enseña más que borrarlo.

En este proyecto, `plan-modulo-equipos.md` se corrigió durante todo el
desarrollo: fases tachadas al completarse, el SQL mal escrito corregido con una
nota de por qué estaba mal, y las desviaciones del plan anotadas con su
justificación.

---

**Ver también:** [`plan-modulo-equipos.md`](plan-modulo-equipos.md) es el
documento de diseño real, con el detalle completo. Este SDD es la versión
enseñable.
