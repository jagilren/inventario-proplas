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

**El del módulo — 8 tablas y 2 vistas:**

```
activo_referencias   los modelos (catálogo)
activos              cada unidad física, siempre con serial
activo_terceros      talleres, clientes, proveedores
activo_ubicaciones   historial de DÓNDE ESTÁ (no toca inventario)
activo_movimientos   entradas y salidas REALES (sí tocan inventario)
activo_piezas        piezas buenas/malas de un equipo desarmado
activo_mantenimientos hoja de vida
activo_observaciones  notas sueltas que no tienen otra casa

activos_disponibilidad      qué hay disponible por referencia
activo_observaciones_todas  las 3 fuentes de observaciones, unidas
```

**Las cuatro decisiones que hay que justificar:**

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

**Dónde vive cada regla — y esto es diseño, no detalle:**

| Regla | Dónde | Por qué ahí |
|---|---|---|
| Serial único | Índice en la base | Debe cumplirse aunque falle la app |
| "Disponible" | Vista SQL | Se deriva; nunca se guarda |
| Estado tras una entrada | Trigger | Debe pasar siempre, venga de donde venga |
| Sugerir 70% para un usado | La app | Es una sugerencia, no una ley |

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

---

## 6. Permisos

**Qué va aquí:** quién puede hacer qué, y **dónde se hace cumplir**.

**El del módulo:** un rol nuevo, `equipos`, que da acceso completo. `admin` y
`coordinador` entran por defecto.

Se aplica en **RLS de la base de datos**, no en la app. Ocultar un botón no es
seguridad: cualquiera con el token puede llamar la API igual.

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

## 9. Los cinco errores reales — y qué enseña cada uno

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
