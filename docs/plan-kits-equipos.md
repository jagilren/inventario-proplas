# Plan: Referencias KITZABLES

**Estado:** diseñado 2026-09-10 · **Fase 1 (SQL) en producción el 2026-09-10**
(`schema_v64_kits_fase1`) · Fases 2 a 6 pendientes.
**Extiende:** el Módulo de Equipos (`docs/plan-modulo-equipos.md`).
**Sigue la plantilla de 10 secciones de** `docs/sdd-modulo-equipos.md`.

---

## 0. Qué cambió del diseño al construir la Fase 1

El plan de abajo se escribió en la mañana del 2026-09-10. Esa misma tarde, el
Módulo de Equipos tuvo siete errores reales (SDD §9), y varias de esas
lecciones cambiaron esta Fase 1 **antes** de escribir el SQL. Se dejan
anotadas aquí, sin borrar el plan original, porque *por qué cambió* enseña más
que el resultado.

| Del plan original | Cómo quedó | Por qué |
|---|---|---|
| Crear un componente = insertar componente + insertar su movimiento de alta | **Una sola función**, `agregar_componente()`, hace las dos cosas | Error 9.7: una regla que debe cumplirse siempre va en la base. Dos inserciones desde la app pueden quedar a medias con un corte de red: un componente en cero, sin historia |
| El signo de cada movimiento se deduce del tipo al calcular | Cada movimiento **guarda su signo** al insertarse (`signo` = +1 / −1) | La anulación necesita el signo **contrario al original**. Guardado, la cantidad es solo `suma(signo × cantidad)` |
| Anular sin tipo propio | Tipo **`anulacion`**, que copia cantidad y valor del original y toma el signo opuesto | Deshace exactamente lo que hizo el original. No se puede anular dos veces ni anular una anulación |
| Candado de inmutabilidad "como el de los movimientos" | Candado propio que nombra **todas** sus columnas | `schema_v63`: una lista incompleta deja editable lo que falte |
| — | Un kit **entregado** no admite componentes ni movimientos | Regla 3 del SDD: ya no es nuestro |
| — | La observación de un movimiento de componente solo la editan admin y coordinador | `schema_v62`, con la misma función |
| — | `plantilla_kit(referencia)` en la base | La "repetición" (§6.2) necesita la composición del kit más reciente; es una consulta, no lógica de pantalla |
| — | El usuario de cada movimiento lo pone la base (`auth.uid()`) | La app no puede firmar a nombre de otro |

**De paso**, al extender `auditoria_clasificada` para las dos tablas nuevas
apareció que `activo_observaciones` (creada ese mismo día en `schema_v54`)
**nunca se había agregado** a la categoría "Equipos" de la auditoría: sus
cambios no salían en ese filtro. Quedó arreglado en la misma migración.

**Cómo se probó.** En una transacción que se deshace al final, ejerciendo
todo **como un usuario con solo el rol `equipos`** (lección de `schema_v62`:
probar el rol, no a la persona). 24 casos, 24 correctos:

- Con el ejemplo real: 3 componentes → **$1.540.000**; al 70% → **$1.078.000**;
  se dañan 3 telas → **$1.405.000**; se anula el daño → vuelve; se vende una
  guía a un tercero → **$1.525.000**.
- Lo que debe fallar, falla con un mensaje claro: vender sin tercero, anular
  dos veces, anular una anulación, sacar más de lo que hay, quitarle `es_kit`
  a una referencia con equipos, poner componentes a un equipo que no es kit,
  editar un movimiento, mover componentes de un kit entregado, y que el rol
  `equipos` edite una observación.
- Lo que no se debe poder hacer a escondidas, se corrige solo: escribir la
  cantidad o el valor de un kit a mano se sobreescribe con la suma verdadera.
- **Lo que ya funcionaba sigue igual**: un equipo que no es kit sigue
  aceptando su valor escrito a mano, y los dos equipos reales quedaron con el
  mismo valor que tenían.

Después, contra la API real: HTTP 200 en todas las consultas nuevas, sin
PGRST201.

---

## 1. Objetivo y alcance

Hay equipos que **nacen armados**: un "KIT FILTROS 636" no es una máquina que
se compra, es un conjunto de telas y guías que valen, sumadas, lo que vale el
kit. Hoy el sistema obliga a escribir un único `valor_nuevo` a mano, y esa cifra
no dice de qué está hecho el equipo ni qué pasa cuando le sacan una pieza.

Este plan agrega tres cosas:

1. Marcar una referencia como **kit**.
2. Que el equipo liste sus **componentes** (nombre, cantidad, valor unitario) y
   valga la suma de ellos.
3. Que esa composición **tenga vida**: se dañan tres telas, se vende un
   componente, se lleva otro como garantía — y todo eso queda registrado.

Más una comodidad que decide si el módulo es usable o no: al crear el kit número
2 de 50, **la composición se propone sola**.

### Fuera de alcance, a propósito

- **Los componentes NO salen del inventario.** El valor unitario se escribe a
  mano; no se toma del costo promedio móvil de `elementos`. La frontera del
  Módulo de Equipos hacia el módulo de Inventario **sigue cerrada** (ver §10).
- Los componentes **no llevan serial propio**. Son cantidades, no unidades. Si
  algo necesita serial, es un equipo, no un componente.
- **No entran a modo offline.** El alta de equipos tampoco lo está hoy; abrir
  ese frente aquí duplicaría el trabajo sin pedirlo nadie.
- No hay porcentaje de valorización por componente (ver §4).

---

## 2. Relación con lo existente

### Momento de hacerlo

Medido el 2026-09-10 en producción:

| | |
|---|---:|
| Referencias de equipos | 2 |
| Equipos con serial | 2 |
| Movimientos de equipos | 4 |
| Piezas registradas | 0 |
| Referencias con `ficha_tipica` usada | **0** |
| Equipos con `ficha` usada | **0** |

Dos conclusiones. La primera: **este es el momento**. Cambiar de dónde sale
`valor_nuevo` con 2 equipos es trivial; con 500 kits ya cargados sería una
migración de datos con riesgo real. La segunda: `ficha_tipica` (jsonb en
`activo_referencias`) está **sin estrenar**, así que no hay nada que respetar
ahí — pero ver §10, porque tampoco es donde va la plantilla.

### Qué comparte y qué no

| Comparte | No comparte |
|---|---|
| `activo_terceros` — el destino de una venta o garantía | Nada de `elementos` / `movimientos` |
| `fn_auditoria()` y `auditoria_clasificada` | El concepto de "existencia" |
| `f_unaccent`, el patrón de índice único normalizado | El kardex y el costo promedio móvil |
| Las políticas RLS del módulo (admin / coordinador / equipos) | |

### `activo_componentes` NO es `activo_piezas`

Es la confusión más peligrosa de todo el plan, porque las dos tablas se
describen casi igual en una frase. Son opuestas:

| | `activo_componentes` (nuevo) | `activo_piezas` (existe) |
|---|---|---|
| Qué representa | De qué **está hecho** el equipo | En qué **quedó** al desarmarlo |
| Cuándo se ve | Referencia marcada como kit | Estado `baja` o `repuestos` |
| Tiene cantidad y valor | Sí | No |
| Afecta el valor del equipo | **Sí, lo define** | No |

Las dos fichas **nunca aparecen a la vez**, porque un kit operativo no está en
baja. Si algún día lo estuviera, la de Piezas gana: ya se desarmó.

---

## 3. Modelo de datos

### 3.1 El flag va en la referencia

```sql
alter table activo_referencias
  add column es_kit boolean not null default false;
```

**Por qué en la referencia y no en el equipo:** ser kit es propiedad del
*modelo*. Todo "KIT FILTROS 636" es kit. Así el formulario de alta sabe qué
mostrar antes de que se escriba el serial, y no se puede tener un equipo kit y
otro no-kit de la misma referencia.

**`default false` es lo que garantiza que nada se rompa:** las referencias que
existen hoy y las que se creen sin tocar el switch se comportan exactamente
igual que ahora. Todo lo demás en este plan cuelga de `es_kit = true`.

### 3.2 Los componentes

```sql
create table activo_componentes (
  id             uuid primary key default extensions.uuid_generate_v4(),
  activo_id      uuid not null references activos(id),
  nombre         text not null,
  valor_unitario numeric not null default 0 check (valor_unitario >= 0),
  -- cantidad NO se escribe a mano: la mantiene un trigger desde los movimientos
  cantidad       numeric not null default 0 check (cantidad >= 0),
  subtotal       numeric generated always as
                   (round(cantidad * valor_unitario, 2)) stored,
  orden          int not null default 0,
  creado_por     uuid,
  creado_email   text,
  creado_en      timestamptz not null default now()
);

-- Misma normalización que activo_referencias_uniq y activo_terceros_uniq.
create unique index activo_componentes_uniq on activo_componentes
  (activo_id, upper(regexp_replace(btrim(nombre), '\s+', ' ', 'g')));

create index idx_activo_comp_activo on activo_componentes (activo_id, orden);
```

`subtotal` **sí** puede ser columna generada: solo mira su propia fila.

El índice único no es opcional. Sin él se pueden crear "TELA MEDIOS" y
"tela  medios" como dos componentes distintos del mismo kit — el error 3 del
SDD, otra vez, en una tabla nueva.

### 3.3 La vida del kit: los movimientos de componente

```sql
create table activo_componente_movimientos (
  id             uuid primary key default extensions.uuid_generate_v4(),
  componente_id  uuid not null references activo_componentes(id),
  tipo           text not null check (tipo in (
                   'alta','aumento','disminucion',
                   'salida_venta','salida_garantia','baja_dano')),
  cantidad       numeric not null check (cantidad > 0),
  valor_unitario numeric not null check (valor_unitario >= 0), -- estampado
  tercero_id     uuid references activo_terceros(id),
  anula_movimiento_id uuid references activo_componente_movimientos(id),
  observacion    text,
  usuario_id     uuid,
  usuario_email  text,
  fecha          timestamptz not null default now(),
  creado_en      timestamptz not null default now()
);

-- Un movimiento se anula UNA sola vez (copiado de activo_movimientos_anula_uniq).
create unique index activo_comp_mov_anula_uniq
  on activo_componente_movimientos (anula_movimiento_id)
  where anula_movimiento_id is not null;

-- Regla de históricos del proyecto: siempre del más reciente al más antiguo.
create index idx_activo_comp_mov on activo_componente_movimientos
  (componente_id, fecha desc);
```

**Por qué una tabla de movimientos y no simplemente editar `cantidad`.**
Editar la cantidad de 24 a 21 deja constancia en la auditoría de *que* cambió,
pero no de **por qué** ni **para quién**. Y el "por qué" aquí **es** el dato del
negocio: no es lo mismo que se hayan dañado tres telas a que se hayan vendido, o
a que se hayan ido como garantía a un tercero.

Es exactamente la lección del error 1 del SDD (lo de MetalAndes): un cambio de
estado que no deja rastro. Aquí se resuelve desde el diseño y no seis meses
después.

**Los tipos y su signo:**

| Tipo | Signo | Cuándo |
|---|:---:|---|
| `alta` | + | Al crear el kit |
| `aumento` | + | Se le agrega más de un componente que ya tiene |
| `disminucion` | − | Corrección o retiro sin destino |
| `salida_venta` | − | Se vendió — `tercero_id` obligatorio |
| `salida_garantia` | − | Se fue como garantía — `tercero_id` obligatorio |
| `baja_dano` | − | Se dañó |

---

## 4. Reglas de negocio, y dónde vive cada una

### 4.1 El valor: `valor_actual` NO se toca

Hoy:

```sql
valor_actual  numeric generated always as
                (round(valor_nuevo * porcentaje_valor / 100, 2)) stored
```

Se queda **idéntica**. La consumen 6 funciones (`valorizado_total_por_bodega`,
`fn_estampar_valor_activo_salida`, `fn_auditoria`, `auditoria_clasificada`,
`auditoria_reciente`, `historial_registro`) y ninguna se entera de que existen
los kits. Eso es deliberado: es la garantía de que no se estropea lo que ya
funciona.

Lo único que cambia es **quién escribe `valor_nuevo`**:

- Referencia normal → lo escribe el usuario, como siempre.
- Referencia kit → lo escribe un **trigger**, con `sum(subtotal)`.

**Por qué un trigger y no una columna generada:** una columna generada no puede
leer otra tabla ni hacer agregados. Es una restricción de Postgres, no una
preferencia.

### 4.2 No hay porcentaje por componente

Porque ponderar cada componente y sumar da **el mismo número** que ponderar el
total:

| Componente | Cant. | Vr. unit. | 100% | 70% |
|---|---:|---:|---:|---:|
| Tela filtros de los extremos | 2 | $50.000 | $100.000 | $70.000 |
| Tela filtros de los medios | 24 | $45.000 | $1.080.000 | $756.000 |
| Guías filtro medios | 24 | $15.000 | $360.000 | $252.000 |
| | | | **$1.540.000** | **$1.078.000** |

$1.540.000 × 70% = $1.078.000. Idéntico por los dos caminos.

Y aplicar el porcentaje **una sola vez al total** es además más preciso: evita
el arrastre de 24 redondeos individuales.

### 4.3 La cadena de recálculo

```
movimiento de componente
   └→ trigger: recalcula activo_componentes.cantidad = sum(signo × cantidad)
        └→ subtotal se recalcula solo (columna generada)
             └→ trigger: recalcula activos.valor_nuevo = sum(subtotal)
                  └→ valor_actual se recalcula solo (columna generada)
```

Más un **trigger BEFORE INSERT/UPDATE sobre `activos`** que, si la referencia es
kit, fuerza `valor_nuevo` al total de los componentes. No es redundante: es lo
que impide que queden **dos fuentes de verdad** para el mismo número si alguien
escribe por la API o corrige a mano en SQL.

> ⚠️ **Riesgo de esta cadena:** son triggers en cascada, y el de `activos` se
> dispara desde el de `componentes`. Converge (el BEFORE de `activos` no escribe
> en `componentes`), pero **hay que probarlo explícitamente**, incluyendo el
> caso de anular un movimiento.

### 4.4 Dónde vive cada regla

| Regla | Dónde | Por qué ahí |
|---|---|---|
| La cantidad nunca queda negativa | Trigger + `check` | Debe cumplirse venga de donde venga |
| `valor_nuevo` de un kit = suma | Trigger | Idem — no puede depender de la app |
| Nombre de componente único por equipo | Índice único | Idem |
| Un movimiento se anula una sola vez | Índice único parcial | Un `if exists` se puede ganar una carrera |
| `es_kit` inmutable con equipos | Trigger | Protege el valor de equipos existentes |
| `tercero_id` obligatorio en venta/garantía | `check` | Es el dato que da sentido al movimiento |
| Proponer la composición del kit anterior | La app | Es una sugerencia, no una ley |

---

## 5. Las inmutabilidades

El usuario pidió expresamente cuidarlas. Son cinco:

**5.1 `es_kit` no se puede cambiar si la referencia ya tiene equipos.**
Es la que sostiene todo lo demás. Marcar como kit una referencia con equipos
existentes les pondría `valor_nuevo` en $0 al primer recálculo. Y quitarle el
flag a un kit dejaría sus componentes huérfanos y su valor congelado en un
número que ya nadie mantiene.

```sql
create or replace function fn_es_kit_inmutable() returns trigger
language plpgsql as $$
begin
  if new.es_kit is distinct from old.es_kit
     and exists (select 1 from activos where referencia_id = old.id) then
    raise exception
      'No se puede cambiar si la referencia es un kit: ya tiene equipos creados';
  end if;
  return new;
end $$;
```

Si te equivocaste, se crea otra referencia. Igual que la regla de "con
movimientos no se borra, se inactiva".

**5.2 Los movimientos de componente no se editan ni se borran.**
Se corrigen con un movimiento contrario que apunta al original por
`anula_movimiento_id`, y el índice único parcial garantiza que eso pase una sola
vez. Copiado tal cual de `activo_movimientos`.

**5.3 El `valor_unitario` estampado en un movimiento no cambia nunca.**
Aunque después se corrija el valor vigente del componente. Mismo principio que
`fn_estampar_valor_activo_salida`: lo que pasó, pasó a ese precio.

**5.4 `activo_componentes.cantidad` no se escribe a mano.**
Es derivada de los movimientos. Si la app intenta escribirla, el trigger la
sobreescribe. Es la aplicación de la regla del SDD §3: todo dato derivable se
deriva.

**5.5 Un componente con movimientos no se borra.**
Se lleva a cantidad 0 con un movimiento de salida. Borrar la fila borraría el
historial de por qué desapareció. Antes de tener movimientos (mientras se está
armando el alta), eliminarlo sí es libre.

---

## 6. Interfaz — móvil primero

Es una app de Flutter que se usa en tablet y celular. Nada de esto puede
depender de una pantalla ancha. Piso: **360 px sin scroll horizontal**.

### 6.1 Formulario de referencia

Un `SwitchListTile`:

> **Es un kit compuesto por varios componentes**
> El equipo valdrá la suma de sus componentes

Deshabilitado, con la razón visible, cuando la referencia ya tiene equipos
(inmutabilidad 5.1). Nunca un switch que se deja oprimir y después falla.

### 6.2 Alta del equipo — aquí vive la repetición

Cuando la referencia es kit:

1. El campo **Valor nuevo** sale bloqueado, con la nota *"Se calcula a partir
   de los componentes"*. Nunca editable y calculado a la vez.
2. Debajo aparece la sección **Componentes**, y **si ya existe otro equipo de
   esa referencia, llega precargada con su composición.**

**De cuál equipo se copia:** del **más reciente** de esa referencia, no del
primero. Si en el kit 7 se ajustó la composición, los kits 8 al 50 deben heredar
la versión buena, no la original. Se copian `nombre`, `cantidad` y
`valor_unitario` vigentes.

**La copia es una sugerencia, no un vínculo.** Cada equipo es dueño de sus
componentes. Si fueran un vínculo vivo, editar un kit cambiaría en silencio los
otros 49 — y ese es justo el tipo de acción a distancia que produce bugs que
nadie logra reproducir.

Un aviso discreto lo dice: *"Composición tomada del kit ABC-123. Puedes
agregar o quitar antes de guardar."* Con la lista completamente editable.

Si es el primer kit de esa referencia, la lista arranca vacía.

Al guardar, cada componente nace con su movimiento `alta`.

### 6.3 Ficha "Componentes" en el detalle

Visible **solo si la referencia es kit** — mismo criterio que ya se aplicó a
"Piezas" con baja/repuestos.

Nada de tablas: en 360 px una tabla de 4 columnas es ilegible. Cada componente
es una tarjeta:

```
┌──────────────────────────────────────┐
│ TELA FILTROS DE LOS MEDIOS           │
│ 24 × $45.000            $1.080.000   │
│ al 70%                    $756.000   │
└──────────────────────────────────────┘
```

- Total al pie, fijo, siempre visible al hacer scroll.
- La línea "al 70%" solo aparece si `porcentaje_valor < 100`.
- Cifras a la derecha con `tabular-nums`, en el formato de dinero del proyecto
  (`$1.080.000`), nunca `toStringAsFixed`.
- Un componente en cantidad 0 se muestra atenuado y al final: se fue, pero su
  historial sigue ahí.
- Si el kit no tiene componentes, un aviso claro con botón para agregarlos. No
  se bloquea en la base: al crear el equipo todavía no existen.

### 6.4 Mover un componente

Toque en la tarjeta → hoja inferior **con X para cerrar** (convención ya
establecida en las 6 hojas del módulo):

- Chips de tipo: Agregar · Retirar · Vender · Garantía · Daño.
- Cantidad, con el máximo disponible visible.
- Selector de tercero **con lupa**, obligatorio en venta y garantía — con
  buscador desde el principio, no cuando ya haya mil talleres.
- Observación.

Y una ficha de historial, **del más reciente al más antiguo**, con fecha y
usuario responsable, como manda la regla del proyecto.

---

## 7. Permisos

Las dos tablas nuevas reciben las **mismas políticas RLS** que el resto del
módulo: `admin`, `coordinador` y `equipos`. Se hace cumplir en la base, no
escondiendo botones.

Trigger `fn_auditoria()` en ambas, y `auditoria_clasificada` extendida para que
esas filas se lean por el serial del equipo y no como UUIDs sueltos — categoría
nueva `equipos_comp`.

---

## 8. Fases

| Fase | Qué | Entrega valor sola | Riesgo |
|:---:|---|:---:|---|
| 1 ✔ | SQL: `es_kit`, las 2 tablas, triggers, RLS, auditoría — **hecha el 2026-09-10** (`schema_v64`, ver §0) | No | **Alto** — la cadena de recálculo |
| 2 | `ActivosService`: modelos y CRUD | No | Bajo |
| 3 | Switch en referencias + ficha Componentes (solo lectura) | **Sí** | Bajo |
| 4 | Alta con plantilla del kit anterior | **Sí** | Medio |
| 5 | Movimientos de componente (la vida del kit) | **Sí** | Medio |
| 6 | Valorizado con desglose de kits | Sí | Bajo |

**La fase peligrosa es la 1**, y hay que tratarla distinto: probar la cadena
completa dentro de `BEGIN … ROLLBACK` antes de aplicar, incluyendo alta,
aumento, retiro total y **anulación**.

Las fases 3 a 5 se pueden desplegar de a una. La 3 sin la 5 ya sirve: muestra de
qué está hecho el kit aunque todavía no se le puedan mover piezas.

---

## 9. Riesgos

| Riesgo | Mitigación | Revisar en |
|---|---|---|
| Triggers en cascada con efectos raros al anular | Pruebas explícitas de anulación en fase 1 | Fase 1 |
| `valor_nuevo` con dos fuentes de verdad | Trigger BEFORE en `activos` que lo fuerza | Fase 1 |
| **PGRST201** al hacer embed de componentes | `activo_componentes!activo_componentes_activo_id_fkey(...)` y **probar con curl contra la API real, no solo en SQL** | Fase 2 |
| Confundir Componentes con Piezas | Nombres, tabla comparativa (§2) y visibilidad excluyente | Fase 3 |
| Cifras ilegibles o scroll horizontal en 360 px | Tarjetas, no tablas; formato de dinero del proyecto | Fase 3 |
| Alguien marca kit una referencia con equipos | Inmutabilidad 5.1 | Fase 1 |
| Doble contabilización si algún día los componentes salen del inventario | **Hoy no aplica**: se teclean a mano, no salen de `elementos`. Si se abre esa puerta, hay que resolverlo antes | Ver §10 |

---

## 10. Decisiones descartadas

**Reutilizar `activo_piezas`.** Es el concepto contrario (§2), no tiene cantidad
ni valor, y su ficha solo aparece en baja/repuestos.

**Guardar la plantilla en `activo_referencias.ficha_tipica`.** Está libre y era
la opción obvia. Se descartó porque obliga a un paso extra ("guardar como
plantilla") que el usuario no pidió, y crea una tercera copia de la verdad que
puede quedar desactualizada respecto a los kits reales. Copiar del último equipo
creado no necesita mantenimiento: la plantilla *es* el último kit que se armó.

**Porcentaje de valorización por componente.** Da el mismo resultado con más
complejidad y peor redondeo (§4.2).

**`cantidad` editable directamente.** Más simple de programar, pero pierde el
motivo y el destino del movimiento — que es el dato del negocio (§3.3).

**Tomar los componentes del inventario (`elementos`), descontando existencias y
valorizando con el costo promedio móvil.** Es probablemente hacia donde esto
tiende — el archivo original se llama *EQUIPOS_FABRICACIONES*. Se descartó
**para esta entrega** porque abre la frontera que el SDD del módulo declaró
cerrada con una medición, cambia quién decide el valor unitario (el kardex, no
el usuario), y exige resolver la **doble contabilización**: si se arma un kit
con 24 telas y no se les da salida del inventario, esas telas quedan valorizadas
en la bodega **y además** dentro del kit. El mismo material contado dos veces, y
cada módulo por separado cuadrando bien.

Cuando se retome, ese es el problema a resolver primero.
