# Plan: Módulo de Equipos (Activos)

> Diseño acordado en sesión de trabajo (2026-09-09). Documento de planeación —
> nada de esto está implementado todavía. Complementa [`plan.md`](plan.md) y
> [`spec.md`](spec.md), pero es un módulo nuevo, no un cambio a lo existente.
>
> **No confundir con:**
> - La etiqueta fiscal "Activos" del plan de categorías fiscales (Usados/Activos/Baja,
>   doble valorización contable/fiscal) — es un tema completamente distinto, en pausa.
> - El `schema_v19_activos.sql` que quedó como borrador suelto en el repo (nunca se
>   aplicó ni se comiteó) — este documento lo reemplaza por completo.

## 0. Condiciones no negociables (aplican a TODO lo de este documento)

**Visibilidad en móvil (2026-09-09, pedido explícito del usuario).** Cada pantalla,
componente o mockup que se construya para este módulo tiene que verse **perfectamente
en un celular** — no es un "nice to have", es una condición dura para cualquier objeto
visual nuevo. Coherente con la arquitectura real de la app
(`inventario-app-arquitectura.md`: offline-first, uso en campo, tablet Android 5 no
sirve — mínimo Android 7). Reglas concretas:
- Área táctil mínima de 48dp en cualquier botón/ícono tocable (ya es el estándar en el
  resto de la app — ver comentarios de `selector_recargable.dart`).
- Nada de layouts de ancho fijo que no reacomoden en una pantalla angosta; texto que
  se trunca o se corta en vez de reflow es un defecto, no un detalle menor.
- La barra inferior de Equipos se queda en 4 botones (sección 7.0) a propósito — más
  de 5 empieza a apretarse en un teléfono normal.
- Cualquier mockup que se entregue debe probarse mentalmente (o con un artifact real)
  en un ancho de ~360-390px antes de darlo por bueno, no solo verse bien en una
  pantalla ancha de escritorio.

## 0.1 Qué tan seguro es esto de no romper lo que ya funciona (2026-09-09)

Pregunta explícita del usuario. Respuesta honesta, no optimismo genérico:

**Riesgo prácticamente cero** (aditivo puro): las 7 tablas/vista nuevas de Equipos, sus
RLS, el rol `equipos`, los archivos Dart nuevos, `valorizado_total_por_bodega()` — nada
de esto modifica una tabla, política o pantalla existente. Al día de hoy, cero líneas
de código de Equipos están escritas — todo este documento es diseño, el riesgo real
empieza cuando arranque la Fase 1.

**Los 3 puntos donde SÍ se toca algo que ya funciona:**
1. **`AuthGate` (`main.dart`)** — cambiar `HomePage` por `ModuloSelectorPage` es el
   cambio de mayor impacto posible: un bug ahí tumba el login de **todos**, no solo de
   Equipos. El punto que más cuidado exige de todo el plan.
2. **Reubicar `SyncService.alSesionIniciada()`/`RealtimeService.iniciar()`** de
   `HomePage.initState()` al selector — hay que verificar que `RealtimeService.iniciar()`
   sea idempotente antes de confiar en el cambio (si no lo es, "Cambiar de módulo" de
   ida y vuelta podría suscribir dos veces).
3. **Ítems de Drawer compartidos** (Bodegas, Centros de Costo, etc. en los dos
   módulos) — reutilizan las pantallas existentes sin tocarlas; el riesgo está solo en
   la lógica de armado del Drawer, no en esas pantallas.

**Prueba de aceptación #1, antes de mirar cualquier otra cosa**: un usuario **sin**
acceso a Equipos (el 100% de los usuarios reales hoy) no debe notar ninguna diferencia
— mismo login, mismo `HomePage`, misma velocidad.

**Por qué no es más riesgoso de lo normal**: se sigue la misma rutina que ya evitó
regresiones toda la sesión — `flutter analyze` + `flutter test` en cada cambio (ahora
automático vía CI/CD), simular contra datos reales antes de confiar en un cambio de
base de datos, todo en git y reversible.

---

## 1. Objetivo y alcance

Llevar el control de los **equipos físicos** de RPCI/PROPLAS (motores, bombas,
instrumentos de control, etc.) — activos serializados de alto valor, con hoja de vida,
condición variable, y que a veces salen de las bodegas propias (préstamos, talleres,
entregas a centros de costo) y deben regresar.

Es un módulo **aparte** del inventario de venta: no afecta existencias ni valorización
de los `elementos` consumibles.

---

## 2. Relación con los otros dos módulos existentes

| | Inventario (elementos) | Aprovechamientos (trozos) | **Equipos (activos)** |
|---|---|---|---|
| Qué controla | Stock consumible, se vende/consume | Retazos de material, valorizados a $0 | Equipos físicos serializados, con valor real |
| Tabla de movimientos | `movimientos` | `aprovechamiento_trozos` / `aprovechamiento_salidas` | `activo_movimientos` (nueva) |
| ¿Comparte con los otros? | — | bodegas, centros_costo, usuarios/roles, auditoría | bodegas, centros_costo, usuarios/roles, auditoría |
| Relación (FK) con `elementos` | — | — | **Ninguna.** `activos-no-son-elementos.md`: 0 bombas/motores en el catálogo hoy; nunca debe depender de `elemento_id`. |
| Cómo se entra | Ficha "Inventario" en el selector post-login | Bottom nav, dentro de Inventario | Ficha "Equipos" en el selector post-login (sección 8) |
| Informes | Consumo/Neto por Centro, Movimientos por fecha | Movimientos de Aprovechamientos | Familia propia (sección 7) |

Los tres módulos son independientes a nivel de datos y de informes. Solo comparten
catálogos de negocio (bodegas, centros de costo) e infraestructura (roles, auditoría) —
nunca existencia ni valorización entre sí.

---

## 3. Modelo de datos

### 3.1 `activo_referencias` — catálogo de modelos

Evita que "Bomba Grundfos DNA30" se fragmente en variantes de texto con los años —
misma lección que ya aprendimos con `elementos.material` (fase previa a la maestra
`materiales`).

```sql
activo_referencias
  id, nombre, marca, modelo, tipo, ficha_tipica jsonb, activo boolean
```

### 3.2 `activos` — cada unidad física, individual y **siempre serializada**

> ⚠️ **Regla de diseño fija**: un equipo **siempre** tiene serial propio. No existe
> "entrada de 3 equipos" como cantidad genérica — son 3 filas distintas, 3 seriales
> distintos, igual que ya funciona `moverSerie()` para elementos serializados hoy. El
> formulario de entrada debe soportar agregar varios seriales en una sola sesión
> (mismo patrón de `_serialesNuevos` que ya existe en `editar_elemento_page.dart`).

```sql
activos
  id, referencia_id -> activo_referencias(id)
  serial
  condicion  ('nuevo' | 'usado' | 'repuestos' | 'baja')
  estado     ('operativo' | 'mantenimiento_interno' | 'mantenimiento_externo'
              | 'entregado' | 'baja')
  mantenimiento_actor text null   -- SOLO si estado='mantenimiento_externo': taller o
                                    -- persona que lo tiene, TEXTO LIBRE (a propósito,
                                    -- ver nota más abajo)
  bodega_id  -> bodegas(id)        -- bodega DUEÑA (RPCI o PROPLAS), la que cuenta
  valor_nuevo       numeric
  porcentaje_valor  numeric(5,2) default 100   -- lo define quien tenga permiso, por equipo particular
  valor_actual      GENERATED ALWAYS AS (valor_nuevo * porcentaje_valor / 100) STORED
  ficha jsonb, observacion
  creado_por, creado_email, creado_en
```

> ⚠️ **Nota de diseño (2026-09-09)**: `mantenimiento_actor` es **texto libre a
> propósito** — el usuario lo pidió así explícitamente, sin pasar por el catálogo
> `activo_terceros` (a diferencia de `activo_ubicaciones`, que sí usa catálogo). Es una
> decisión consciente, no un descuido: para "está en mantenimiento" se prioriza rapidez
> sobre normalización. Vale la pena vigilar que esto no termine duplicando información
> con `activo_ubicaciones` si en la práctica "mantenimiento externo" y "está en un
> taller" terminan siendo siempre la misma situación — se puede revisar más adelante
> con uso real.

**Acciones sobre el estado de mantenimiento** (no pasan por `activo_movimientos`, son
edición directa del equipo, admin/coordinador):
- **"Marcar en mantenimiento"** — elige interno o externo; si externo, pide
  `mantenimiento_actor` (texto libre).
- **"Marcar mantenimiento terminado"** — vuelve a preguntar ¿usable? (sí/no), igual que
  en una entrada: si sí, `estado='operativo'`; si no, se queda en mantenimiento o pasa
  a `baja` si ya no vale la pena seguir intentando.

`condicion` vs `estado`: son dos preguntas distintas.
- `condicion` = clasificación comercial (¿qué tan nuevo es?).
- `estado` = disponibilidad operativa (¿se puede usar HOY?).

`'repuestos'` en `condicion` es una **reclasificación posterior** que hace un
admin/coordinador cuando decide tratar un equipo como fuente de piezas — no es una
opción que se ofrezca durante una entrada (ver sección 4).

### 3.3 `activo_terceros` — catálogo de talleres/clientes/proveedores externos

Mismo criterio que `activo_referencias`: catálogo, no texto libre.

```sql
activo_terceros
  id, nombre ("Taller de Lucho"), tipo ('taller'|'cliente'|'proveedor'|'otro'), contacto, activo
```

### 3.4 `activo_ubicaciones` — historial de ubicación FÍSICA (no afecta inventario)

Un kardex de ubicación: cada cambio abre una fila nueva y cierra la anterior, nunca se
edita una fila existente.

```sql
activo_ubicaciones
  id, activo_id -> activos(id)
  bodega_id  -> bodegas(id)         null   -- si está en bodega PROPIA, cuál (RPCI/PROPLAS)
  tercero_id -> activo_terceros(id)  null   -- si está afuera, con quién
  detalle text
  fecha_desde, fecha_hasta   -- null en fecha_hasta = la ubicación ACTUAL
  usuario_id, usuario_email, creado_en

  check ( (bodega_id is not null and tercero_id is null)
       or (bodega_id is null and tercero_id is not null) )
```

**Estructural, no por convención**: "propia" es cualquier fila que apunte a la tabla
real `bodegas` (conjunto cerrado: RPCI, PROPLAS); todo lo demás **tiene que** apuntar a
`activo_terceros`. El `check` no deja guardar una fila ambigua.

Mecanismo (función RPC, cierra+abre en un solo paso):

```sql
cambiar_ubicacion_activo(p_activo, p_bodega_id, p_tercero_id, p_detalle)
```

Y un botón de un toque **"Marcar regreso a bodega"** — llama la misma función con
`p_bodega_id` = la bodega dueña del equipo, sin formulario.

### 3.5 `activo_piezas` — lista libre de piezas buenas/malas

```sql
activo_piezas
  id, activo_id -> activos(id)
  nombre, estado ('buena'|'mala'|'desconocido'), observacion
  actualizado_por, actualizado_email, actualizado_en
```

Decisión tomada: **lista libre**, no integrable a Existencias por ahora (evita el
trabajo de decidir a qué elemento del catálogo corresponde cada pieza salvada, valorizarla
y registrar el movimiento — se puede revisar más adelante si hace falta).

### 3.6 `activo_mantenimientos` — hoja de vida

```sql
activo_mantenimientos
  id, activo_id -> activos(id)
  fecha, tipo, descripcion, responsable, costo
  usuario_id, usuario_email, creado_en
```

### 3.7 `activo_movimientos` — entrada/salida REAL (sí afecta inventario)

Unificada (no dos tablas separadas) para ser consistente con cómo ya funciona
`movimientos`: un campo cambia de rol según el `tipo`.

```sql
activo_movimientos
  id, activo_id -> activos(id) not null
  tipo  ('entrada' | 'salida' | 'ajuste')  not null
  anula_movimiento_id -> activo_movimientos(id)   -- solo en tipo='ajuste'

  centro_costo_id           -> centros_costo(id)   -- SALIDA: a quién se entrega (obligatorio, resta inventario)
                                                     -- ENTRADA: de dónde viene (obligatorio, ver sección 4)
  centro_costo_destino_id   -> centros_costo(id)    -- Solo ENTRADA: a quién queda atribuido (interno, informativo)
  bodega_id                 -> bodegas(id)          -- Solo ENTRADA: bodega física donde entra

  condicion  ('nuevo'|'usado'|'baja')   -- Solo ENTRADA: snapshot en ese momento (nunca 'repuestos' aquí, ver 3.2)
  usable     boolean                     -- Solo ENTRADA, solo si condicion='usado'

  valor numeric, observacion
  usuario_id, usuario_email, fecha, creado_en
```

Inmutable (mismo candado que `movimientos`: solo se puede editar `observacion` después
de creado) + trigger de auditoría (`fn_auditoria()`, reutilizado).

**Trigger al insertar:**
- `tipo='salida'` → `activos.estado = 'entregado'`.
- `tipo='entrada'` → dos efectos en un solo paso:
  1. `activos.estado` = `'operativo'` si `condicion='nuevo'` o (`condicion='usado'` y
     `usable=true`); `'mantenimiento_interno'` si `usado` y `usable=false` (llega a
     bodega propia, se evalúa ahí primero); `'baja'` si `condicion='baja'`. Si más
     adelante se decide mandarlo a un taller externo, eso es la acción aparte "Marcar
     en mantenimiento" descrita en 3.2, no algo que decida la entrada misma.
  2. Abre automáticamente la fila correspondiente en `activo_ubicaciones`
     (`bodega_id` = la bodega destino de la entrada), cerrando la anterior — una sola
     acción del usuario, dos tablas consistentes.

**Anulación — RESUELTO (2026-09-09).** Dos niveles, igual que en el resto de la app:

- **Error de captura simple** (el movimiento sí ocurrió, se equivocaron de centro/
  condición/bodega) → corrección directa en base de datos, mismo patrón ya validado
  con Tintexa (desactivar candado, `UPDATE` puntual + nota en observación, reactivar).
  No requiere botón de anular.
- **Movimiento que nunca debió pasar** (salida por error, entrada duplicada) →
  `anular_activo_movimiento(p_mov, p_motivo)`, calcado de `anular_movimiento()`: solo
  admin, no se anula dos veces (índice único), inserta `tipo='ajuste'` enlazado por
  `anula_movimiento_id`, nunca borra el original. El trigger revierte `estado` según
  qué se anuló:
  - Anular una **salida** → `estado` vuelve a `'operativo'`.
  - Anular una **entrada de reingreso** → `estado` vuelve a `'entregado'`.
  - Anular la **entrada de un alta nueva** (primer y único movimiento del equipo) → no
    hay "estado anterior": se aplica la regla general de la app, **borrar vs.
    inactivar** — se borra de verdad si no tiene ninguna actividad posterior (piezas,
    ubicaciones, mantenimientos), se inactiva si ya la tiene.

### 3.8 Vista `activos_disponibilidad` — regla derivada, nunca un campo manual

```sql
create view activos_disponibilidad as
select a.*,
  au.bodega_id  as ubicacion_actual_bodega_id,
  au.tercero_id as ubicacion_actual_tercero_id,
  au.fecha_desde as ubicacion_actual_desde,
  (a.estado = 'operativo' and au.bodega_id is not null) as disponible
from activos a
left join activo_ubicaciones au
  on au.activo_id = a.id and au.fecha_hasta is null;
```

Nunca se marca "disponible" a mano — se calcula solo a partir de `estado` +
dónde está la ubicación vigente. Igual que `existencia` en `elementos`, que tampoco se
edita directo.

---

## 4. Reglas de negocio de ENTRADA (los dos escenarios, confirmados)

Ambos casos usan `tipo='entrada'` en `activo_movimientos`. El **Centro de Costo Origen
siempre está presente** en los dos — la diferencia es de dónde sale ese valor.

### 4.1 Escenario A — Compra (equipo nuevo, directo de proveedor)

- **Centro de Costo Origen**: **fijo**, no editable por el usuario. Ya existe en la base
  y se verificó en esta sesión: código `COMPRA`, descripción `DIRECTO PROVEEDOR`,
  `es_interno = false`. El formulario lo autocompleta, no se elige.
- **Centro de Costo Destino**: uno marcado `es_interno = true` (obligatorio).
- **Bodega destino**: normalmente Bodega interna PROPLAS o RPCI.
- **Condición**: lo normal es `'nuevo'` (el formulario lo sugiere por defecto, sin
  bloquear otras opciones si de verdad se compra algo usado directo).
- **Disponibilidad**: como va a bodega interna y condición nuevo → automáticamente
  **disponible** (estado = operativo).

### 4.2 Escenario B — Devolución (equipo que regresa desde un centro de costo)

- **Centro de Costo Destino**: uno marcado `es_interno = true` (igual que en toda
  entrada).
- **Centro de Costo Origen**: **cualquiera que NO sea interno** (`es_interno = false`)
  — selector libre, mismo filtro que ya usamos para elementos. Aplica tanto para un
  equipo que se da de alta la primera vez como para un **reingreso** de un equipo que
  ya existía y estaba `estado='entregado'` (en ese caso se pre-sugiere el mismo centro
  al que había salido, pero queda editable).
- **Condición**: puede ser `Nuevo`, `Usado`, o `Baja`.
  - `Nuevo` → disponible.
  - `Usado` → se pregunta **¿usable?** (sí/no) → disponible si sí, `mantenimiento` si no.
  - `Baja` → el formulario **no** pregunta "usable" (no aplica) → `estado='baja'`
    directo, nunca disponible.
- **Disponibilidad**: depende 100% de la condición elegida, como se describe arriba.
- **Inventario**: al ser una entrada, **suma** al inventario (o revive un equipo que
  había salido, según sea alta nueva o reingreso).
- **Valorizado**: puede variar según la condición — se ajusta `porcentaje_valor` en
  este mismo formulario (queda editable, con valores sugeridos según la condición
  elegida, pero el usuario con permiso decide el número final para ESE equipo
  particular, como ya quedó definido en la sección de valorización).

---

## 5. Salida (real, hacia un Centro de Costo) — resta del inventario

`tipo='salida'` en `activo_movimientos`.

- **Centro de Costo** (único campo, como en una salida normal de elementos):
  obligatorio, `es_interno = false` (a quién se entrega). Resta del inventario:
  `activos.estado = 'entregado'`, deja de contar como disponible.
- No pasa por `activo_ubicaciones` en el mismo sentido que un préstamo/taller — una vez
  entregado a un centro de costo, deja de ser "nuestro problema" trackear su ubicación
  física del mismo modo (punto abierto, ver sección 10).
- Corrección/anulación: **RESUELTO**, ver el mecanismo en la sección 3.7.

---

## 6. La diferencia clave: ubicación física vs. entrada/salida real

Esta distinción es el corazón del módulo — dos cosas que suenan parecidas pero son
completamente distintas:

| | `activo_ubicaciones` (Cambiar ubicación) | `activo_movimientos` (Entrada/Salida) |
|---|---|---|
| ¿Cuándo se usa? | Préstamo, taller externo, proyecto — **temporal** | Compra, devolución, entrega definitiva a un centro |
| ¿Afecta el inventario/existencia? | **No.** Sigue contando en la bodega dueña. | **Sí.** Entrada suma, salida resta. |
| ¿Afecta Centro de Costo / reportes de valorización? | No | Sí |
| Ejemplo | Bomba Grundfos en "Taller de Lucho" por reparación | Bomba Grundfos entregada definitivamente al centro NP00034 |

---

## 7. Interfaz — 3 niveles de vista

### 7.0 Barra inferior del módulo (RESUELTO 2026-09-09)

Mismo criterio que ya usa Inventario: la barra inferior es para lo frecuente/primario,
el Drawer del módulo para lo ocasional/secundario.

**Barra inferior (`NavigationBar`), 4 botones — RESUELTO (2026-09-09, con acceso
directo agregado):**

| Botón | Qué muestra |
|---|---|
| **Por referencia** | Nivel 1 — el resumen agregado (pantalla con la que se entra al módulo) |
| **Movimiento** | **Nuevo** — acceso directo para registrar entrada/salida sin navegar por niveles (detalle abajo) |
| **Disponibles** | Nivel 3 — vista global cruzando todas las referencias |
| **En mantenimiento** | Todo lo que está `mantenimiento_interno`/`mantenimiento_externo` ahora mismo, sin importar la referencia. Mismo espíritu que "Alertas" en Inventario |

**Drawer del módulo (secundario, no en la barra):** Informes (sección 9), catálogos
administrativos `activo_referencias` y `activo_terceros`, más los ítems **compartidos**
con el Drawer de Inventario (Bodegas, Centros de Costo, Auditoría, Configuración,
Usuarios y roles, Trabajo sin conexión) — clasificación completa, item por item, en la
**sección 8.3**. "Cambiar de módulo" (vuelve al selector de la sección 8) y Mi perfil
cierran la lista.

Además de la gestión completa (compartida), el Centro de Costo Origen/Destino de un
formulario de entrada/salida trae el botón "+" inline (`SelectorRecargable.onAgregar`,
mismo mecanismo que ya usa `movimiento_page.dart`) para crear uno sin salir de la
pantalla — ambos accesos solo para admin/coordinador (verificado en la RLS real de
`centros_costo`: `cud_cc` exige `admin` o `coordinador`, el rol `equipos` por sí solo
no alcanza).

**Cerrar sesión** (RESUELTO 2026-09-09, pregunta explícita del usuario): vive dentro de
**"Mi perfil"** (`perfil_page.dart`, ya existe hoy con el ListTile "Cerrar sesión") — es
la **misma pantalla compartida** entre Inventario y Equipos, no se duplica. Correo,
roles, cambiar contraseña y cerrar sesión son de la cuenta, no del módulo, así que no
tiene sentido tener dos "Mi perfil" distintos. El mecanismo de cierre
(`Navigator.popUntil((r) => r.isFirst)` + `signOut()`) sigue funcionando igual con el
`ModuloSelectorPage` de por medio — verificado, no requiere ningún ajuste.

**Por qué NO hay botones separados "Entrada"/"Salida" como en Inventario** (pregunta
explícita del usuario, 2026-09-09): los `elementos` son **fungibles** (un tornillo es
igual a otro) — por eso ahí sí tiene sentido un botón fijo por tipo de movimiento,
donde se busca el elemento después. Un equipo **no es fungible**: es un objeto
serializado individual. Por eso Equipos tiene **un solo** botón "Movimiento" (no dos) —
se busca primero el equipo, y el tipo de acción (entrada o salida) lo decide el estado
actual de ESE equipo, no lo elige el usuario de antemano.

### 7.0.1 "Movimiento" — el acceso directo (RESUELTO)

Pantalla de una sola búsqueda, sin pasar por Nivel 1 → Nivel 2:

```
🔍 Buscar por serial o referencia…

DNA30-SN0012 · Bomba Grundfos DNA30 · usada         🔴 Taller de Lucho
DNA30-SN0019 · Bomba Grundfos DNA30 · usada         🔴 Cliente Topaco
DNA30-SN0007 · Bomba Grundfos DNA30 · usada         🟢 Disponible
```

Al tocar un resultado, la pantalla que se abre depende del **estado actual** de ese
equipo — el usuario no tiene que saber de antemano si va a hacer una entrada o una
salida, el sistema ya lo sabe:

- `estado='entregado'` → abre el formulario de **Entrada (Reingreso)** — Centro
  Origen/Destino, Bodega, Condición, Usable (sección 4.2).
- `estado='operativo'` (disponible) → abre el formulario de **Salida** — Centro de
  Costo (sección 5).
- `mantenimiento_interno` / `mantenimiento_externo` / `baja` → no aplica una entrada o
  salida directa; el resultado lleva al **detalle del equipo** en cambio (ahí están las
  acciones de mantenimiento/ubicación que sí le corresponden a ese estado).

La **alta nueva** (Compra) sigue siendo aparte, con el FAB "+ Nuevo equipo" del Nivel
1 — no pasa por este buscador porque el equipo todavía no existe, no hay nada que
encontrar.

**Nivel 1 — Resumen por referencia** (pantalla de entrada al módulo): una fila por
modelo, contador agregado en SQL (`GROUP BY referencia_id`, nunca bajando todas las
unidades a Dart — lección ya aprendida corrigiendo el resumen de Aprovechamientos).

```
Bomba Grundfos DNA30          30 unidades
🟢 18 disponibles · 🔴 12 no disponibles
```

**Nivel 2 — Unidades de una referencia**: al tocar la fila, lista de las 30 bombas
individuales con filtros rápidos (`Todas` / `Disponibles` / `No disponibles`).

**Nivel 3 — "Disponibles ahora" (vista global)**: lista plana cruzando **todas** las
referencias, para armar un kit de proyecto sin entrar modelo por modelo. Reutiliza la
misma vista `activos_disponibilidad`, sin agrupar por referencia.

**Detalle de un equipo** (al entrar a una unidad): datos generales, condición + valor
(`valor_nuevo` × `porcentaje_valor` = `valor_actual`), ubicación actual destacada +
botón "Ver historial de ubicaciones", botones "Cambiar ubicación" / "Marcar regreso a
bodega", lista de piezas, hoja de mantenimientos, e historial de entradas/salidas reales.

---

## 8. Acceso y navegación

**REDISEÑO (2026-09-09) — cambia la arquitectura de navegación, no solo el permiso.**
En vez de "Equipos" como una entrada más dentro del Drawer de Inventario, se convierte
en un **módulo hermano**, al mismo nivel: tras el login, una pantalla de selección con
fichas deja elegir a cuál entrar. Tiene sentido porque Equipos ya es un módulo completo
(3 niveles de navegación, informes propios, permisos propios) — no una pantalla
secundaria que quepa bien en un menú lateral pensado para "Bodegas"/"Configuración".

### 8.0 El camino completo, desde cero

Verificado contra el código real de `main.dart`:

```dart
// AuthGate.build(), línea 81 — ANTES:
if (session != null) return const HomePage();

// AHORA:
if (session != null) return const ModuloSelectorPage();
```

1. **Pantalla de login** (`AuthGate`, sin sesión) — igual que siempre, es lo primero
   que carga la app. Sin sesión activa no se entra a nada.
2. Login exitoso → Supabase Auth crea la sesión → `AuthGate` la detecta
   (`onAuthStateChange`) y muestra `ModuloSelectorPage` (pantalla nueva) en vez de ir
   directo a `HomePage`.
3. `ModuloSelectorPage.initState()` hace dos cosas:
   - Pide `InventarioService.misRoles()`.
   - Corre el arranque de sesión que hoy vive en `HomePage.initState()`
     (`SyncService.alSesionIniciada()`, `RealtimeService.iniciar()`) — se **reubica**
     aquí para que corra una sola vez, sin importar qué módulo se termine eligiendo.
     (`SyncService.iniciar()` y `Ajustes.cargar()` ya corrían antes, en `main()`, sin
     sesión — esos no se tocan.)
4. Con los roles cargados, dos caminos:
   - **Sin acceso a Equipos** (no es admin/coordinador ni tiene el rol `equipos`) → la
     selección **ni se muestra**: pasa directo a `HomePage` (Inventario), como
     funciona hoy. No tiene sentido una pantalla de "elegir entre 1 opción".
   - **Con acceso a Equipos** → se ven **2 fichas**: "Inventario (Piping)" y "Equipos",
     con un resumen chiquito arriba — "PROPLAS: $X · RPCI: $Y" (`valorizado_total_por_bodega()`,
     sección 9.1) — vistazo ejecutivo antes de elegir. Tocar una ficha entra a
     `HomePage` o a `EquiposHomePage` según cuál se eligió.
5. **Cambiar de módulo sin cerrar sesión**: dentro de cada módulo, un ícono en el
   AppBar ("Cambiar de módulo") regresa a `ModuloSelectorPage` — visible solo para
   quien de verdad tiene los dos módulos disponibles (si solo tiene Inventario, no
   tiene sentido mostrar un botón para "cambiar" a algo que no existe para él).

**Los terceros (`activo_terceros`) NO son usuarios de la app.** "Taller de Lucho", los
clientes, los proveedores — nunca inician sesión aquí. Son solo datos de catálogo que
un usuario NUESTRO (con cuenta y roles) usa para registrar dónde está un equipo. No hay
ningún acceso externo/público contemplado en este diseño — si más adelante se quisiera
que un tercero consultara el estado de lo suyo sin pedir el favor, sería una
funcionalidad nueva y aparte, no algo que ya esté cubierto.

### 8.1 Cambios de código que implica (resumen técnico)

| Archivo | Cambio |
|---|---|
| `main.dart` | `AuthGate` devuelve `ModuloSelectorPage` en vez de `HomePage` |
| `screens/modulo_selector_page.dart` | **Nuevo.** Fichas + arranque de sesión (ver 8.0.3) |
| `screens/home_page.dart` | Quita el arranque de sesión de su `initState` (se movió); quita "Equipos" del Drawer (ya no vive ahí); agrega ícono "Cambiar de módulo" en el AppBar (solo si `_puedeEquipos`) |
| `screens/equipos_home_page.dart` (o el nombre final del Nivel 1) | **Nuevo.** Mismo ícono "Cambiar de módulo" en su AppBar |

### 8.2 Rediseño de permisos (2026-09-09) — ya NO es "cualquier autenticado"

Se agrega un **rol nuevo**, exactamente con el mismo patrón que ya usan `exportar` y
`remisiones` en `class Roles` (`lib/data.dart`): un permiso independiente de
admin/coordinador que habilita una función puntual completa.

```dart
class Roles {
  ...
  static const equipos = 'equipos';          // NUEVO

  static const todos = [
    admin, coordinador, operarioMas, operarioMenos, exportar, remisiones,
    equipos,                                  // NUEVO
  ];

  static String etiqueta(String rol) => switch (rol) {
    ...
    equipos => 'Módulo de Equipos',           // NUEVO
    _ => rol,
  };
}
```

**Regla de acceso**: `admin` y `coordinador` siguen teniendo acceso automático a todo
(como ya lo tienen a "GESTIÓN"). Cualquier otro usuario **necesita el rol `equipos`
asignado explícitamente** — sin él, la ficha de Equipos ni siquiera se muestra en el
selector (sección 8.0). A diferencia del diseño anterior, el rol `equipos` da acceso
**completo** al módulo (ver + registrar entrada/salida/ubicación/mantenimiento), no
solo lectura — mismo criterio que `remisiones`, que también habilita trabajar en su
función, no solo mirarla.

```dart
// ModuloSelectorPage — decide si se muestran las 2 fichas o se salta directo a Inventario.
// Reutilizada también en home_page.dart y equipos_home_page.dart para el ícono
// "Cambiar de módulo" (solo tiene sentido mostrarlo si hay más de un módulo disponible).
bool get _puedeEquipos => _admin || _coord || _roles.contains(Roles.equipos);
```

RLS de las 7 tablas/vista de la sección 3 — cambia de `using (true)` en SELECT a lo
mismo que ya rige INSERT/UPDATE/DELETE:

```sql
using (public.es_admin() or public.tiene_rol('coordinador') or public.tiene_rol('equipos'))
```

**Asignación**: se marca como cualquier otro rol, desde "Gestión de usuarios → Roles"
(checkbox "Módulo de Equipos" en la lista que ya existe, junto a "Exportar informes" y
"Remisiones de devolución").

### 8.3 Clasificación completa: qué ítem del Drawer va en cuál módulo (RESUELTO 2026-09-09)

Repasado ítem por ítem contra el Drawer real de `home_page.dart`. Criterio: un ítem es
**COMPARTIDO** si administra un catálogo/dato que de verdad usan los dos módulos (no
solo "podría ser útil verlo desde los dos"); si es exclusivo de los datos de
`elementos`/`movimientos`, se queda **solo en Inventario**.

| Ítem del Drawer | Gate hoy (sin cambios) | ¿Comparte datos con Equipos? | Dónde vive ahora |
|---|---|---|---|
| **Bodegas** | `_gestiona` | Sí — `activos.bodega_id`, `activo_ubicaciones.bodega_id` | **Ambos** |
| Traslados | `_admin` | No — mueve `elementos` vía `movimientos`; Equipos tiene su propio mecanismo aparte (`activo_ubicaciones`, sección 3.4) | Solo Inventario |
| **Centros de costo** | `_gestiona` | Sí — `activo_movimientos.centro_costo_id/_destino_id` | **Ambos** |
| Materiales | `_gestiona` | No — maestra de `elementos.material_id` (piping); Equipos tiene la suya propia, `activo_referencias` (sección 3.1), sin relación | Solo Inventario |
| Catálogo completo | `_admin` | No — CRUD total de `elementos` | Solo Inventario |
| **Auditoría de cambios** | `_gestiona` | Sí — misma tabla `auditoria`, mismo trigger `fn_auditoria()` reutilizado en `activos`/`activo_movimientos` (sección 3.7) | **Ambos** |
| **Configuración** | `_gestiona` | Sí — el formato de exportación (separador CSV/decimal) aplica a los informes de cualquier módulo, incluidos los 2 nuevos de Equipos (sección 9) | **Ambos** |
| Informes | `_puedeExportar` | Cada módulo muestra **sus propios** informes (no se mezclan, sección 2) — pero el **rol** `exportar` que lo habilita es el mismo en los dos | Entrada propia en cada Drawer, mismo rol |
| Remisión de devolución | `_puedeRemisiones` | No — arma listas de devolución de `elementos` | Solo Inventario |
| **Usuarios y roles** | `_admin` | Sí — es justo donde se asigna el rol `equipos` (sección 8.2); un admin trabajando en Equipos necesita poder gestionar usuarios sin cambiar de módulo | **Ambos** |
| **Trabajo sin conexión** | sin gate | Genérico de sesión, no de módulo (aunque el caché offline hoy solo cubre `elementos`/`centros_costo` — si Equipos necesita su propio soporte offline es aparte, fase futura, no resuelto aquí) | **Ambos** |
| **Mi perfil** (con Cerrar sesión) | sin gate | Cuenta, no módulo — ya resuelto arriba | **Ambos** |

**Exclusivos de Equipos** (no existen en Inventario, mismo gate `_puedeEquipos` que la
ficha del selector — no `_gestiona`, porque el rol `equipos` da acceso completo al
módulo, sección 8.2): catálogo de **Referencias** (`activo_referencias`) y catálogo de
**Terceros** (`activo_terceros`).

```dart
// Gates reutilizados en AMBOS Drawer, sin duplicar la lógica de roles:
bool get _gestiona => _admin || _coord;                                   // ya existe
bool get _puedeExportar => _admin || _roles.contains(Roles.exportar);     // ya existe
bool get _puedeEquipos => _admin || _coord || _roles.contains(Roles.equipos); // nuevo, sección 8.2
```

---

## 9. Informes (familia propia, no se mezclan con los de Inventario/Aprovechamientos)

**RESUELTO (2026-09-09) — para Fase 1, solo 2 informes en Excel/CSV:**

1. **Movimientos de Equipos por fecha** — entradas y salidas juntas, un movimiento por
   fila: Fecha, Tipo, Referencia, Serial, Centro Origen, Centro Destino, Bodega,
   Condición, Usable, Valor, Usuario, Observación, Estado (ANULADO/ANULACIÓN si
   aplica) — calcado del "Movimientos por fecha" de elementos.
2. **Valorización de Activos** — foto del estado actual, fila por equipo: Referencia,
   Serial, Condición, Estado, Bodega dueña, Ubicación actual, Valor nuevo, %, Valor
   actual, Disponible — con fila TOTAL, calcado de "Existencias valorizadas".

**"Equipos disponibles ahora" queda fuera de esta lista a propósito**: un Excel de
disponibilidad se desactualiza en el instante en que alguien mueve un equipo. Ya está
cubierto como vista en vivo (Nivel 3 de la sección 7), no como export.

**Para más adelante** (cuando haya uso real y contabilidad confirme que lo necesita):
un informe de valorización/movimiento agregado por Centro de Costo, análogo a
Consumo/Neto de elementos — no se diseña a ciegas ahora.

Todos con fecha + usuario, como exige la regla general de informes de esta app.

### 9.1 Valorizado Total por Bodega — la ÚNICA excepción a "no se mezclan" (RESUELTO 2026-09-09)

Pregunta del usuario: si Inventario (`existencias`) y Equipos (`activos`) viven en
tablas completamente distintas, ¿cómo se sabe el valorizado total de la Bodega PROPLAS
o RPCI? Respuesta: **nunca se unen las tablas** — son formas de datos incompatibles
(cantidad × costo promedio por elemento vs. un valor fijo por unidad serializada).
Forzar un `JOIN` fila a fila sería el mismo error que ya evitamos con Aprovechamientos.

**La forma correcta**: dos agregaciones independientes, cada una simple dentro de su
propio mundo, unidas al final **solo por `bodega_id`** — se combinan los totales ya
calculados, nunca las filas crudas.

```sql
create function public.valorizado_total_por_bodega()
returns table(bodega text, valorizado_inventario numeric, valorizado_equipos numeric, valorizado_total numeric)
language sql stable as $$
  with inv as (
    -- CORREGIDO al implementar (2026-09-09): la exclusión de aprovechamientos
    -- va en un FILTER, NO en el ON del left join. Puesta en el ON, la fila de
    -- `existencias` sobrevive igual al left join (con `e` en null) y se
    -- terminaba sumando — justo lo contrario de lo que se buscaba.
    select b.id, b.nombre,
      coalesce(sum(x.existencia * x.costo_promedio)
               filter (where not coalesce(e.es_aprovechamiento, false)), 0) as valor
    from bodegas b
    left join existencias x on x.bodega_id = b.id
    left join elementos e on e.id = x.elemento_id
    where b.activo
    group by b.id, b.nombre
  ),
  eq as (
    select b.id,
      coalesce(sum(a.valor_actual), 0) as valor
    from bodegas b
    left join activos a on a.bodega_id = b.id and a.estado <> 'entregado'
    group by b.id
  )
  select inv.nombre, inv.valor, eq.valor, inv.valor + eq.valor
  from inv join eq using (id)
  order by inv.nombre;
$$;
```

**Detalles de la lógica:**
- **Aprovechamientos queda fuera a propósito** — valorizado a $0 por diseño, no un
  descuido.
- En Equipos se excluye `estado='entregado'` (ya no es inventario nuestro, sección 5).
  Todo lo demás (operativo, mantenimiento interno/externo, incluso de baja) sí cuenta —
  sigue siendo propiedad física de esa bodega, coherente con el requisito original: "en
  existencias de RPCI/PROPLAS siguen contando" aunque estén en un tercero.

**Dónde se muestra**: un resumen chiquito en `ModuloSelectorPage` (la pantalla de
fichas, sección 8) — "PROPLAS: $X · RPCI: $Y" — vistazo ejecutivo antes de elegir
módulo. Además, informe exportable propio, accesible desde el Drawer de cualquiera de
los dos módulos (mismo criterio que Bodegas/Centros de Costo, sección 8.3).

---

## 10. Puntos abiertos (a confirmar antes de programar)

~~1. ¿Se puede anular una salida/entrada de equipo?~~ **RESUELTO** — ver sección 3.7.

~~2. Informes de Fase 1~~ **RESUELTO** — ver sección 9.

~~3. Cuando un equipo está `entregado`, ¿seguimos trackeando su ubicación?~~
**RESUELTO (2026-09-09)** — no. Una vez `entregado`, `activo_ubicaciones` se congela en
su última fila (la bodega desde la que salió) y no se le agregan más cambios. Ya no es
responsabilidad de RPCI/PROPLAS trackear dónde queda físicamente dentro del proyecto
del cliente. Vuelve a tener sentido registrar ubicación solo si el equipo hace
**reingreso** (entrada tipo devolución, sección 4.2), que abre una fila nueva otra vez.

~~4. `condicion = 'repuestos'`: ¿reclasificación posterior o elegible en la entrada?~~
**RESUELTO (2026-09-09)** — exclusivamente reclasificación manual posterior. El
formulario de entrada nunca ofrece "Repuestos" (solo Nuevo/Usado/Baja, como ya estaba en
la sección 4.2). Un admin/coordinador la asigna después, editando el equipo directo
desde su detalle, en cualquier momento — no requiere un movimiento de por medio.

~~5. Mantenimiento: ¿distinguir interno vs. externo?~~ **RESUELTO (2026-09-09)** — sí
se separan (`mantenimiento_interno` / `mantenimiento_externo`), y si es externo se
captura el taller/actor como **texto libre** (`mantenimiento_actor`), a propósito sin
pasar por el catálogo `activo_terceros`. Ver el detalle completo en la sección 3.2.

**Todos los puntos de la sección 10 quedaron resueltos.** El diseño está completo —
listo para pasar a la Fase 1 (SQL) cuando se confirme.

---

## 11. Fases de desarrollo

1. ~~**SQL** — las 7 tablas/vista de la sección 3, RLS (con el rol `equipos`, sección
   8.2), triggers de auditoría e inmutabilidad, función `cambiar_ubicacion_activo`.~~
   **COMPLETADA 2026-09-09** (`supabase/schema_v46_equipos_fase1.sql`, migración
   `schema_v46_equipos_fase1` aplicada en producción). Incluye, además de lo previsto:
   `fn_estampar_valor_activo_salida()` (estampa `valor` en una salida desde
   `activos.valor_actual`, mismo criterio que `fn_estampar_costo_salida`) y
   `anular_activo_movimiento()` (mismo patrón que `anular_movimiento()`: nunca borra,
   inserta un `tipo='ajuste'` enlazado, índice único `activo_movimientos_anula_uniq`
   evita anular dos veces; rechaza explícitamente anular el primer movimiento de un
   equipo — "alta nueva" — indicando borrar/inactivar el equipo en su lugar). Probado
   con un `DO $test$` completo dentro de una transacción revertida (alta, entrada
   usado-no-usable → mantenimiento_interno, salida con valor auto-estampado, anulación,
   doble anulación bloqueada, inmutabilidad de campos, rechazo de anular la alta) antes
   de aplicar la migración real. `flutter analyze`/build/deploy no aplica a este paso —
   es SQL puro, cero cambios en `lib/`.
2. ~~**Capa de datos en Flutter** — archivo propio `lib/activos_service.dart` (como ya
   se separó `reportes.dart` de `data.dart`), clases + CRUD **paginado desde el día 1**.~~
   **COMPLETADA 2026-09-09** (`lib/activos_service.dart`). 7 clases de modelo
   (`ActivoReferencia`, `ActivoTercero`, `Activo`, `ActivoDisponibilidad`,
   `ActivoUbicacion`, `ActivoPieza`, `ActivoMantenimiento`, `ActivoMovimiento`) +
   `ActivosService` con todo el CRUD paginado, `revision` (mismo patrón que
   `InventarioService.revision`), y los dos RPC (`cambiar_ubicacion_activo`,
   `anular_activo_movimiento`). Los nombres de las FK para el join de centros de costo
   se verificaron contra `pg_constraint` real antes de escribirlos, para no repetir el
   error PGRST201 de `pgrst201-doble-fk-centros-costo.md`. **Ningún archivo existente
   fue modificado** — el archivo nuevo todavía no lo importa nadie, así que la app
   desplegada se comporta exactamente igual que antes (`flutter analyze`: los mismos 29
   avisos info de siempre, cero nuevos).
3. ~~**Navegación** — `ModuloSelectorPage` nueva (sección 8.1), ajustes en
   `home_page.dart`, rol `equipos` en `class Roles` y en "Gestión de usuarios".~~
   **COMPLETADA 2026-09-09**, probada por el usuario en un despliegue de vista previa
   (`fase3-equipos.inventario-proplas.pages.dev`) antes de tocar producción, porque el
   cambio del `AuthGate` afecta el login de todos. Archivos:
   `screens/modulo_selector_page.dart` y `screens/equipos_home_page.dart` (nuevos),
   `main.dart` (AuthGate → `ModuloSelectorPage`), `home_page.dart` (se le quitó el
   arranque de sesión, se le agregó "Cambiar de módulo"), `data.dart` (`Roles.equipos`).
   Verificado antes de editar: `RealtimeService.iniciar()` **sí** es idempotente
   (`if (_canal != null) return;`), `HomePage` solo se alcanzaba desde `main.dart` (así
   que mover el arranque de sesión al selector cubre todos los caminos), y la UI de
   roles se genera desde `Roles.todos` (el checkbox del rol nuevo salió solo).
   **Desviación consciente del plan:** `EquiposHomePage` entró como listado real de
   equipos con su Drawer, NO con las 4 pestañas de la sección 7.0 — esas, junto con los
   formularios, son la Fase 4. Se prefirió eso antes que dejar pestañas vacías.
   El resumen "PROPLAS: $X · RPCI: $Y" del selector (sección 8.0.4) tampoco se incluyó:
   depende de `valorizado_total_por_bodega()`, que es Fase 5.
4. ~~**Pantallas del módulo** — los 3 niveles de listado, detalle de equipo, formularios
   de entrada/salida/ubicación/mantenimiento.~~ **COMPLETADA 2026-09-09.** Pantallas
   nuevas: `activo_referencias_page.dart`, `activo_terceros_page.dart`,
   `activo_alta_page.dart`, `activo_detalle_page.dart` (4 pestañas: ficha, piezas,
   mantenimiento, movimientos), `activo_movimiento_page.dart`,
   `activos_de_referencia_page.dart` (Nivel 2), y `equipos_home_page.dart` rehecha con
   las 4 pestañas de la sección 7.0. Se agregó la función SQL
   `activos_resumen_por_referencia()` (migración `schema_v47`) para que el Nivel 1
   cuente en la base y no bajando todas las unidades a Dart.
   Verificado con un recorrido completo en transacción revertida contra la base real,
   pasando por RLS como usuario autenticado: alta por compra → disponible; resumen del
   Nivel 1; piezas; mantenimiento; préstamo a un tercero → deja de contar como
   disponible **sin** cambiar el estado ni tocar inventario; regreso a bodega → vuelve a
   estar disponible; salida → entregado con el valorizado estampado; reingreso usado y
   no usable → mantenimiento interno con el valor recalculado al 60%; y anulación.
   **Pendiente de Fase 5:** reclasificar un equipo a condición `repuestos` desde la
   ficha (hay `ActivosService.cambiarCondicion()` pero todavía no se expone en la UI).
5. ~~**Informes** — los 2 de la sección 9 (Movimientos de Equipos, Valorización de
   Activos).~~ **COMPLETADA 2026-09-09.** Quedaron **3**: los 2 previstos más
   "Valorizado total por bodega" (sección 9.1), que se implementó ya y no más adelante
   porque el selector de módulos lo necesitaba para su resumen. Archivos:
   `screens/equipos_reportes_page.dart` (nuevo, con rango de fechas y "desde el
   principio de los tiempos"), 3 métodos nuevos en `reportes.dart`, enlace "Informes" en
   el Drawer del módulo, y el resumen "Valorizado en bodega" en `ModuloSelectorPage`.
   Migración `schema_v48_valorizado_total_por_bodega`.

   **Dos errores encontrados y corregidos al implementar:**
   - El SQL que estaba escrito en la sección 9.1 de este documento tenía un bug: excluía
     los aprovechamientos en el `ON` del `LEFT JOIN`, donde **no** los excluye (la fila
     de `existencias` sobrevive igual y se suma). Va en un `FILTER`. Ya está corregido
     arriba, y el resultado se verificó contra el cálculo directo del informe
     "Existencias valorizadas" que ya existía: da exactamente el mismo número.
   - **PGRST201 en la vista `activos_disponibilidad`**: la vista llega a `bodegas` por
     DOS caminos (la bodega dueña vía `activos_bodega_id_fkey` y la de la ubicación
     vigente vía `activo_ubicaciones_bodega_id_fkey`), así que un `bodegas(nombre)` sin
     calificar rompe con HTTP 300. Mismo error que ya documenta
     `pgrst201-doble-fk-centros-costo.md`, ahora en la vista nueva. **Lección: las
     pruebas SQL en transacción NO detectan esto, porque no pasan por PostgREST.** Se
     verificaron con `curl` contra la API real las 11 consultas del módulo, todas 200.
6. **Pruebas y despliegue** — `flutter analyze` + `flutter test`; con el CI/CD ya
   armado, el deploy a Cloudflare y el Release del APK salen solos al mezclar a `main`.

---

## 12. Ideas para fases futuras (fuera de alcance de esta Fase 1)

### 12.1 Roles con permisos distintos por módulo (2026-09-09)

Hoy los roles (`admin`, `coordinador`, etc.) son **globales** — el mismo poder aplica
igual en Inventario y en Equipos, vía `tiene_rol(rol)` en TODA la RLS de la app, no
solo en las tablas nuevas de Equipos. Granularizar esto ("coordinador con poder
distinto en cada módulo") es posible pero es un **refactor del sistema de permisos
completo**, no una feature aislada de Equipos — toca revisar cada política RLS
existente, no solo escribir las nuevas.

Dos formas de hacerlo cuando haga falta:
- **A. Roles con alcance por módulo** — columna `modulo` en `usuario_roles` + función
  `tiene_rol_en(rol, modulo)`. Correcto y escalable, pero implica repasar todas las
  políticas RLS existentes de Inventario, no solo las de Equipos.
- **B. Roles con sufijo por módulo** (`coordinador_inventario` / `coordinador_equipos`)
  — más barato, no toca nada existente, pero "coordinador" deja de ser un concepto
  único y no escala si aparece un tercer módulo.

**Recomendación**: diferir hasta que haya una necesidad real y concreta (alguien que
sea coordinador y necesite tener MENOS poder en un módulo específico). El diseño actual
ya cubre la mitad del problema sin este costo: el rol `equipos` (sección 8.2) le da a
alguien que NO es admin/coordinador acceso completo a Equipos sin tocar Inventario. El
hueco pendiente es el caso inverso — quitarle poder a alguien que YA es admin/coordinador
en uno de los dos módulos.
