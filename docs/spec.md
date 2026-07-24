# spec.md — Inventario PROPLAS

> **Artefacto SDD 1/3 — El QUÉ y el PORQUÉ.**
> Requisitos como **historias de usuario** con **criterios de aceptación** (Dado/Cuando/Entonces), verificables.
> Complementos: [`plan.md`](plan.md) (el cómo técnico) · [`tasks.md`](tasks.md) (desglose y trazabilidad).
> Estado global: implementado hasta **v7.3**, salvo lo marcado *(pendiente)*.

---

## 1. Visión de producto

Reemplazar el control de inventario en Excel de PROPLAS por una app **multi-bodega, offline-first**, en la nube, con control de acceso por roles y trazabilidad total (kardex + auditoría). Web (PWA) y Android (APK) con un solo código.

## 2. Personas / roles

| Rol | Descripción | Necesidad principal |
|---|---|---|
| **Administrador** | Dueño del sistema | Configurar todo, anular, gestionar usuarios. |
| **Coordinador** | Jefe de bodega | Gestionar catálogo, bodegas, informes. |
| **Operario +** | Recibe mercancía | Registrar entradas rápido. |
| **Operario −** | Despacha mercancía | Registrar salidas rápido. |
| **Exportar** | Administración/contabilidad | Descargar informes. |

## 3. Glosario

- **Existencia:** cantidad disponible de un elemento en una bodega.
- **Costo promedio ponderado móvil:** costo recalculado en cada entrada `(valor_actual + valor_entrada) / (cant_actual + cant_entrada)`.
- **Kardex:** historial de movimientos de un elemento.
- **Serializado:** elemento cuyas unidades tienen serial único (ej. Blowers).
- **Anular:** revertir un movimiento con un asiento inverso (nunca se borra).

---

## 4. Historias de usuario y criterios de aceptación

> Convención: `US-<epic>.<n>`. Criterios `AC-*` en **Dado / Cuando / Entonces**. Estado: ✅ hecho · 🔲 pendiente.

### EPIC 1 — Autenticación y cuenta

**US-1.1 — Iniciar sesión** ✅
Como usuario, quiero ingresar con correo y contraseña para acceder a la app.
- AC-1.1.1 · Dado un correo/clave válidos, cuando presiono *Ingresar*, entonces entro a la pantalla de Inicio.
- AC-1.1.2 · Dado un correo/clave inválidos, cuando presiono *Ingresar*, entonces veo el mensaje de error y no entro.
- AC-1.1.3 · Dado que no hay conexión, cuando intento entrar, entonces veo "Error de conexión".

**US-1.2 — Recuperar contraseña** ✅
Como usuario que olvidó su clave, quiero recibir un enlace por correo para restablecerla.
- AC-1.2.1 · Dado mi correo, cuando pido recuperación, entonces recibo un correo con enlace y veo confirmación en pantalla.
- AC-1.2.2 · Dado el enlace del correo, cuando lo abro, entonces la app me pide fijar una nueva contraseña.

**US-1.3 — Cambiar contraseña / ver perfil** ✅
Como usuario autenticado, quiero cambiar mi contraseña y ver mis datos.
- AC-1.3.1 · Dado que estoy autenticado, cuando fijo una nueva contraseña válida, entonces queda guardada y puedo entrar con ella.

### EPIC 2 — Navegación y marca

**US-2.1 — Encabezado permanente con marca** ✅
Como usuario, quiero ver la marca RPCI en toda la app para identificarla.
- AC-2.1.1 · Dado cualquier pantalla, cuando la veo, entonces el encabezado muestra el logo RPCI + "Inventario · [pantalla]".
- AC-2.1.2 · Dado un ancho reducido, cuando el título no cabe, entonces se recorta con "…" sin romper la barra.

**US-2.2 — Navegación según rol** ✅
Como usuario, quiero ver solo las opciones que me corresponden por rol.
- AC-2.2.1 · Dado rol operario+, cuando abro la barra inferior, entonces veo *Entrada* pero no necesariamente *Salida*.
- AC-2.2.2 · Dado que no soy admin/coordinador, cuando abro el menú, entonces no veo la sección GESTIÓN.

**US-2.3 — Tablero de inicio** ✅
Como usuario, quiero un resumen del inventario al entrar.
- AC-2.3.1 · Dado que entro a Inicio, cuando carga, entonces veo total de elementos, valorización total, bajo mínimo y últimos movimientos (en hora Colombia).

### EPIC 3 — Catálogo de elementos

**US-3.1 — Buscar elementos** ✅
Como usuario, quiero buscar por palabras en cualquier orden.
- AC-3.1.1 · Dado "tubo 6", cuando busco, entonces aparecen elementos que contienen ambas palabras sin importar el orden ni las tildes.
- AC-3.1.2 · Dado una sola letra, cuando busco, entonces se trata como palabra completa (no coincide dentro de otras).

**US-3.2 — Crear elemento** ✅
Como admin/coordinador, quiero crear elementos.
- AC-3.2.1 · Dado el botón ＋ (visible solo para admin/coordinador), cuando lo toco, entonces se abre el formulario de creación.
- AC-3.2.2 · Dado un nombre vacío, cuando guardo, entonces se bloquea con "El nombre es obligatorio".

**US-3.3 — Copiar de otro artículo** ✅
Como admin/coordinador, quiero pre-llenar un elemento nuevo desde otro similar.
- AC-3.3.1 · Dado que elijo un elemento existente, cuando confirmo, entonces se copian nombre/material/SCH/unidad pero **no** el código de barras.

**US-3.4 — Editar / dar de baja lógica** ✅
Como admin/coordinador, quiero editar un elemento o marcarlo inactivo.
- AC-3.4.1 · Dado un elemento inactivo, cuando busco, entonces no aparece, pero conserva su kardex.

**US-3.5 — Galería de fotos** ✅
Como admin/coordinador, quiero subir hasta 3 fotos por elemento.
- AC-3.5.1 · Dado que ya hay 3 fotos, cuando intento agregar otra, entonces se bloquea con aviso de límite.
- AC-3.5.2 · Dado que estoy en **web**, cuando elijo "imagen del computador", entonces se abre el diálogo nativo y la imagen se comprime antes de subir.

### EPIC 4 — Movimientos

**US-4.1 — Registrar entrada** ✅
Como operario+/admin, quiero registrar entradas con costo.
- AC-4.1.1 · Dado elemento, bodega, cantidad>0 y costo≥0, cuando guardo, entonces sube la existencia y se **recalcula el costo promedio ponderado** de esa bodega.

**US-4.2 — Registrar salida** ✅
Como operario−/admin, quiero registrar salidas hacia un centro de costo.
- AC-4.2.1 · Dado un centro de costo seleccionado y cantidad ≤ existencia, cuando guardo, entonces baja la existencia y se valoriza al costo promedio.
- AC-4.2.2 · Dado cantidad > existencia, cuando guardo, entonces se rechaza con "existencia insuficiente".
- AC-4.2.3 · Dado que falta el centro de costo, cuando guardo, entonces se bloquea.

**US-4.3 — Ver kardex** ✅
Como usuario, quiero el historial de movimientos de un elemento.
- AC-4.3.1 · Dado un elemento, cuando abro su kardex, entonces veo movimientos (con hora Colombia), desglose por bodega y valorización.

**US-4.4 — Anular movimiento** ✅
Como admin, quiero anular un movimiento sin borrar historial.
- AC-4.4.1 · Dado un movimiento no anulado, cuando lo anulo, entonces se crea una reversa (`ajuste`) y el original permanece.
- AC-4.4.2 · Dado que no soy admin, cuando veo un movimiento, entonces no tengo la opción de anular.

**US-4.5 — Editar observación de un movimiento** ✅
Como admin/coordinador/autor, quiero corregir la observación de un movimiento.
- AC-4.5.1 · Dado que soy admin/coordinador/autor, cuando edito la observación y guardo, entonces se actualiza y queda **auditada** (quién y cuándo).
- AC-4.5.2 · Dado que intento cambiar cantidad/costo por otra vía, cuando se ejecuta el UPDATE, entonces la base lo **rechaza** (solo se permite la observación).
- AC-4.5.3 · Dado que no soy admin/coordinador/autor, cuando abro el detalle, entonces la observación es de solo lectura.

### EPIC 5 — Inventario serializado

**US-5.1 — Crear elemento serializado con unidades iniciales** ✅
Como admin/coordinador, quiero marcar un elemento como serializado al crearlo.
- AC-5.1.1 · Dado el switch "Maneja seriales" activo y cantidad inicial N, cuando guardo, entonces exijo N seriales y una bodega; si no cuadra, no deja guardar.

**US-5.2 — Entrada/Salida serializada** ✅
Como operario, quiero mover unidades por su serial.
- AC-5.2.1 · Dado un elemento serializado en entrada, cuando registro, entonces agrego los seriales nuevos (uno por unidad).
- AC-5.2.2 · Dado una salida serializada, cuando registro, entonces elijo de una lista de seriales **disponibles en la bodega**.

**US-5.3 — Convertir a serializado** ✅
Como admin/coordinador, quiero serializar un elemento existente registrando los seriales de sus unidades actuales.

### EPIC 6 — Multi-bodega

**US-6.1 — Gestionar bodegas** ✅
Como admin/coordinador, quiero crear/editar/activar/desactivar bodegas.

**US-6.2 — Trasladar entre bodegas** ✅
Como admin, quiero mover stock (o seriales) de una bodega a otra.
- AC-6.2.1 · Dado cantidad ≤ existencia del origen y origen≠destino, cuando traslado, entonces baja en origen y sube en destino **manteniendo el costo**.

**US-6.3 — Ver existencia por bodega** ✅
- AC-6.3.1 · Dado un elemento en varias bodegas, cuando abro su kardex, entonces veo el desglose por bodega.

### EPIC 7 — Devoluciones (carga masiva)

**US-7.1 — Cargar devoluciones desde Excel/CSV** ✅
Como operario+/admin, quiero subir un archivo y cargar muchas entradas de devolución de una.
- AC-7.1.1 · Dado un archivo con columnas ELEMENTO y CANTIDAD, cuando lo subo, entonces la app crea la columna EMPAREJAMIENTO con coincidencia aproximada.
- AC-7.1.2 · Dado una fila sin coincidencia, cuando reviso, entonces queda en blanco y puedo elegir el elemento con el buscador.
- AC-7.1.3 · Dado que presiono CARGAR, cuando se procesa, entonces cada fila emparejada genera una entrada valorizada al **costo promedio actual** y veo un resumen (cargados, costo 0, sin emparejar, serializados omitidos).
- AC-7.1.4 · Dado un archivo sin las columnas requeridas / vacío / no Excel-CSV, cuando lo subo, entonces veo el diálogo "Archivo inválido" con el formato esperado. Columnas de más se ignoran.
- AC-7.1.5 · Dado que estoy en **web**, cuando elijo el archivo, entonces se abre el diálogo nativo (sin el bloqueo de file_picker).

### EPIC 8 — Alertas

**US-8.1 — Ver alertas por stock mínimo y costo 0** ✅
Como usuario, quiero ver qué necesita atención.
- AC-8.1.1 · Dado un elemento con existencia ≤ mínimo, cuando abro Alertas › Stock mínimo, entonces aparece.
- AC-8.1.2 · Dado un elemento con existencia pero costo promedio 0, cuando abro Alertas › Costo 0, entonces aparece.

### EPIC 9 — Reconocimiento por foto

**US-9.1 — Reconocer elemento por foto** ✅
Como usuario, quiero identificar un elemento tomándole/eligiendo una foto.
- AC-9.1.1 · Dado que tomo una foto, cuando busco, entonces veo los elementos más parecidos (por huella perceptual), el mejor primero.

### EPIC 10 — Informes y configuración regional

**US-10.1 — Descargar informes CSV** ✅
Como admin/rol exportar, quiero informes que se abran en Excel.
- AC-10.1.1 · Dado que genero un informe, cuando lo descargo, entonces el dinero va en **enteros**, las cantidades con decimales y las fechas en hora Colombia.

**US-10.2 — Configurar formato regional CSV** ✅
Como admin/coordinador, quiero definir separadores de campo y decimal por usuario.
- AC-10.2.1 · Dado que cambio los separadores, cuando exporto, entonces el CSV usa mi configuración.

### EPIC 11 — Administración

**US-11.1 — Gestionar centros de costo** ✅
**US-11.2 — Gestionar usuarios y roles** ✅
- AC-11.2.1 · Dado que soy admin, cuando creo un usuario, entonces queda con perfil y puedo asignarle roles.
- AC-11.2.2 · Dado que no soy admin, cuando abro el menú, entonces no veo "Usuarios y roles".

**US-11.3 — Auditoría** ✅
- AC-11.3.1 · Dado un cambio en un registro auditado, cuando abro la auditoría, entonces veo quién cambió qué y cuándo (hora Colombia).

### EPIC 12 — Offline y sincronización

**US-12.1 — Trabajar sin conexión** ✅
Como operario, quiero registrar movimientos aunque no haya red.
- AC-12.1.1 · Dado que no hay red, cuando registro un movimiento, entonces se **encola** y se ajusta la existencia local.
- AC-12.1.2 · Dado que vuelve la red, cuando sincronizo, entonces los pendientes se suben sin duplicarse (llave device_id+local_id).
- AC-12.1.3 · Dado que no hay red, cuando intento una salida mayor al stock local, entonces se rechaza.

### EPIC 13 — Adjuntos (gated)

**US-13.1 — Adjuntar archivos a un movimiento** 🔲 *(deshabilitado a propósito)*
Como usuario, quiero adjuntar PDF/Excel a un movimiento.
- AC-13.1.1 · Dado que toco "Adjuntar archivo" (en Entrada/Salida o en el detalle), cuando se ejecuta, entonces —a cualquier usuario, incluido admin— aparece el aviso "Función de pago / faltan créditos en Supabase". No se sube nada.
- *Nota:* backend (tabla + bucket) listo para habilitar.

### EPIC 14 — Aprovechamientos (trozos/retazos a $0)

**US-14.1 — Registrar trozos aprovechables** ✅
Como operario+/admin, quiero registrar trozos sobrantes de un elemento, a $0, sin afectar el inventario oficial.
- AC-14.1.1 · Dado un elemento, una longitud y una ubicación, cuando ingreso un trozo, entonces se guarda como disponible y **no cambia ninguna existencia ni valorización oficial**.

**US-14.2 — Consumir trozos por sub-segmentos (parcial)** ✅
Como operario−/admin, quiero usar parte de un trozo y que el resto quede disponible.
- AC-14.2.1 · Dado un trozo de 5 m, cuando uso 3 m hacia un centro de costo, entonces quedan 2 m disponibles.
- AC-14.2.2 · Dado que intento usar más de lo que queda, cuando confirmo, entonces se rechaza.
- AC-14.2.3 · Dado que uso exactamente lo que queda, cuando confirmo, entonces el trozo queda consumido.

**US-14.3 — Ver los trozos disponibles** ✅
Como usuario, quiero ver por elemento cuántos trozos y cuánto queda.
- AC-14.3.1 · Dado varios trozos, cuando abro la pestaña Aprovechamientos, entonces veo por elemento el conteo y el total disponible, con el sello **"$0 · no valoriza"**.

**US-14.4 — Trazabilidad e histórico del trozo** ✅
Como usuario, quiero ver la historia de un trozo: su longitud inicial y cómo se ha ido diezmando.
- AC-14.4.1 · Dado un trozo, cuando abro su historial, entonces veo el ingreso (longitud inicial, quién y cuándo) y cada salida (cantidad, centro de costo, quién, cuándo) con el **saldo corriendo**.
- AC-14.4.2 · Dado el detalle de un elemento, cuando abro la pestaña **Histórico**, entonces veo también los trozos ya consumidos.
- AC-14.4.3 · Toda creación y salida guarda **usuario y fecha** en la base (aunque no siempre se muestre).

---

## 5. Requisitos no funcionales (como criterios)

- **RNF-1 Seguridad:** toda tabla tiene RLS; la escritura sensible exige el rol correcto. La `service_role` nunca llega al cliente.
- **RNF-2 Offline-first:** el catálogo se cachea; los movimientos se encolan sin red.
- **RNF-3 Costeo:** la valorización contable usa promedio ponderado móvil por bodega; los serializados, costo por serial.
- **RNF-4 Zona horaria:** se guarda en UTC y se muestra en hora Colombia (UTC−5 fijo) en toda la app e informes.
- **RNF-5 PWA:** instalable; siempre sirve la última versión (no-cache en index/SW).
- **RNF-6 Multiplataforma:** mismo comportamiento en Web y APK; los diálogos de archivo en web usan input nativo.
- **RNF-7 Costos de nube:** operar dentro del plan gratis de Supabase (Storage de adjuntos deshabilitado).

---

## 6. Backlog *(pendiente — se especifica aparte)*

- **Categorías fiscales** (Usados/Activos/Baja, doble valorización) — *en diseño; será el primer feature construido con SDD estricto (spec-first).*
- **Adjuntos de movimientos** — habilitar cuando haya Storage disponible.
