# Especificación — Inventario PROPLAS (Spec-Driven Development)

> Documento de especificación funcional y técnica de la aplicación **Inventario PROPLAS**.
> Cubre toda la app: desde el **login** hasta la **última función** construida.
> Última versión desplegada al redactar: **v7.3**.

---

## 1. Visión general

**Inventario PROPLAS** es una aplicación de gestión de inventario **multi-bodega**, **offline-first**, para controlar entradas, salidas, existencias y valorización de ~960 elementos y 9 centros de costo (migrados de un Excel `.xlsm`).

- **Plataformas:** Web (PWA) y Android (APK). Un mismo código Flutter.
- **Web de producción:** https://inventario-proplas.pages.dev (Cloudflare Pages, gratis).
- **Usuarios:** personal de bodega y administración de PROPLAS/RPCI; una persona la usa en remoto desde iPhone vía web.

### Objetivos
1. Reemplazar el control de inventario en Excel por una base compartida en la nube.
2. Registrar movimientos con **costo promedio ponderado móvil** por bodega.
3. Funcionar **sin conexión** y sincronizar al volver la red.
4. Control de acceso por **roles** (RBAC).
5. Trazabilidad total (kardex + auditoría).

---

## 2. Arquitectura y stack

| Capa | Tecnología |
|---|---|
| **Frontend** | Flutter 3.44 / Dart 3.12 (Material 3) |
| **Backend** | Supabase (PostgreSQL + Auth + Storage + PostgREST) |
| **Hosting web** | Cloudflare Pages (wrangler, carga directa) |
| **Distribución móvil** | APK release (compileSdk 36) |
| **Persistencia local** | `shared_preferences` (caché + cola offline) |

### Dependencias clave (`pubspec.yaml`)
`supabase_flutter`, `intl`, `image_picker`, `shared_preferences`, `connectivity_plus`, `mobile_scanner`, `csv`, `file_saver`, `image`, `file_picker`, `excel`, `url_launcher`.

### Estructura del código (`lib/`)
- `main.dart` — arranque, tema (seed `#00695C`), `AuthGate` (escucha sesión y recuperación de contraseña).
- `data.dart` — **capa de datos**: modelos + `InventarioService` (todas las operaciones contra Supabase).
- `config.dart` — URL y claves públicas de Supabase.
- `local_store.dart` — caché de catálogo y **cola de movimientos** offline.
- `sync_service.dart` — sincronización online/offline.
- `ajustes.dart` — configuración regional de CSV por usuario.
- `reportes.dart` — generación/descarga de informes CSV.
- `phash.dart` — huella perceptual (dHash) para reconocimiento por foto.
- `util/` — `picker` (input de archivo web nativo), `imagen_picker`, `tiempo` (hora Colombia), `adjuntos_gate`.
- `widgets/` — `barra_sync`, `galeria_elemento`, `imagen_elemento`.
- `screens/` — 22 pantallas (ver §6).

### Principio de diseño recurrente
El **caché de PostgREST** de este proyecto no siempre refresca tras cambios de esquema (DDL). Patrón adoptado: preferir **operaciones directas sobre las tablas** (con RLS) en lugar de RPC cuando el RPC falla por caché; tras aplicar DDL, recargar el esquema (`notify pgrst`).

---

## 3. Roles y permisos (RBAC)

Roles en la tabla `usuario_roles` (un usuario puede tener varios):

| Rol | Etiqueta | Permite |
|---|---|---|
| `admin` | Administrador | Todo: crear/editar elementos, bodegas, centros, usuarios, roles, **anular** movimientos, informes, config. |
| `coordinador` | Coordinador | Gestión (elementos, bodegas, centros, config, informes) salvo usuarios y anulación. |
| `operario_mas` | Operario + | Registrar **entradas**. |
| `operario_menos` | Operario − | Registrar **salidas**. |
| `exportar` | Exportar informes | Acceso a **Informes**. |

Helpers de seguridad en la base (SECURITY DEFINER): `es_admin()`, `tiene_rol(rol)`. Las políticas **RLS** de cada tabla se apoyan en ellos.

---

## 4. Modelo de datos (PostgreSQL)

### Tablas
| Tabla | Descripción |
|---|---|
| `profiles` | Perfil del usuario (id = auth.users.id, email, nombre). |
| `usuario_roles` | Roles por usuario (usuario_id, rol). |
| `elementos` | Catálogo. Campos denormalizados `existencia`, `costo_promedio` (mantenidos por trigger), `stock_minimo`, `activo`, `serializado`, `codigo_barras`, `phash`, `imagen_url`, `busqueda` (columna generada para búsqueda). |
| `categorias` | Categorías de elemento (clasificación de catálogo). |
| `bodegas` | Bodegas físicas (nombre, codigo, activo). |
| `centros_costo` | Centros de costo (codigo, nombre, activo). |
| `existencias` | Existencia y costo promedio **por (elemento, bodega)**. PK compuesta. |
| `movimientos` | Log de movimientos: tipo (`inicial`/`entrada`/`salida`/`ajuste`), elemento, bodega, cantidad, costo_unitario, centro_costo, referencia, observacion, usuario_id, fecha (UTC), device_id, local_id, traslado_id. |
| `series` | Una fila = una unidad **serializada** (serial, bodega, estado `disponible`/`consumido`, costo, movimiento_ingreso/salida). |
| `movimiento_series` | Junction: qué seriales tocó cada movimiento. |
| `elemento_imagenes` | Galería de fotos por elemento (máx. 3), una principal. |
| `movimiento_adjuntos` | Adjuntos por movimiento (nombre, ruta, url, tipo, tamaño). *Backend listo; subida deshabilitada en la app (ver §6.9).* |
| `auditoria` | Bitácora genérica (tabla, registro, acción, campo, valor anterior/nuevo, usuario, fecha). |

### Storage (buckets)
- `elementos-img` (público, ≤2 MB, jpg/png) — fotos de elementos.
- `adjuntos-mov` (público, ≤10 MB, pdf/xlsx/xls/csv/img) — adjuntos de movimientos (uso deshabilitado en la app).

### Reglas de negocio en la base (triggers/RPC principales)
- `aplicar_movimiento()` (**AFTER INSERT** en `movimientos`, SECURITY DEFINER): actualiza existencia y **costo promedio ponderado móvil** por bodega y el total en `elementos`. Bloquea salidas sin existencia. Para elementos serializados no toca stock (lo maneja el trigger de series).
- `fn_sync_existencia_serie()` (en `series`): recalcula existencia/costo de serializados como conteo de seriales disponibles.
- `anular_movimiento(mov, motivo)` (solo admin): inserta un `ajuste` inverso (reversa); nada se borra.
- `buscar_elementos(q)`: búsqueda inteligente (palabras en cualquier orden, sin tildes, letras sueltas como palabra completa).
- `fn_auditoria()`: bitácora en INSERT/UPDATE/DELETE de tablas auditadas + **UPDATE de movimientos** (edición de observación).
- `fn_mov_solo_observacion()` (**BEFORE UPDATE** en `movimientos`): **candado** — impide cambiar cualquier campo que no sea `observacion`.
- Otros: `trasladar`, `serializar_elemento`, `mover_serie` (abandonado por caché → se usan ops directas), `resumen_inventario`, `ultimos_movimientos`, `kardex_elemento`, `imagenes_elemento`, `listar_usuarios`, `historial_registro`, `auditoria_reciente`.

---

## 5. Requisitos no funcionales

1. **Offline-first:** el catálogo se cachea localmente; los movimientos se **encolan** sin red y se suben al reconectar (llave `device_id + local_id` evita duplicados). Antes de encolar una salida se valida el stock local.
2. **Seguridad:** RLS en todas las tablas; escritura sensible solo vía roles. Claves públicas (anon) en el cliente; `service_role` nunca va al cliente.
3. **Costeo:** promedio ponderado móvil por bodega (contable). Los serializados usan costo específico por serial.
4. **Zona horaria:** las fechas se guardan en **UTC** y se muestran en **hora Colombia (UTC−5 fijo)** vía `horaColombia()`. Todo el histórico previo se corrigió (+5 h).
5. **PWA:** instalable; service worker con auto-recarga; `_headers` con no-cache en `index.html`/SW para servir siempre la última versión.
6. **Consumo (plan gratis Supabase):** BD ~14 MB / 500 MB; Storage 0 / 1 GB; el recurso a vigilar es el **egress** (5 GB/mes) por descarga del paquete web.

---

## 6. Especificación funcional (pantalla por pantalla)

> Formato por función: **Actores** · **Precondiciones** · **Flujo** · **Reglas/validaciones** · **Casos borde**.

### 6.1 Login (`login_page.dart`)
- **Actores:** cualquiera con cuenta.
- **Flujo:** ingresa correo + contraseña → `signInWithPassword`. `AuthGate` detecta la sesión y entra. Muestra el **logo de los 10 años de RPCI** arriba.
- **Reglas:** errores de credenciales y de conexión se muestran en texto.
- **Extra:** enlace **"¿Olvidaste tu contraseña?"** → `resetPasswordForEmail` con `redirectTo` a la web de producción.

### 6.2 Recuperar / Nueva contraseña (`nueva_password_page.dart`, `AuthGate`)
- **Flujo:** el correo de recuperación abre la app en modo `passwordRecovery`; `AuthGate` muestra la pantalla para fijar **nueva contraseña** (`cambiarPassword`).

### 6.3 Home / navegación (`home_page.dart`)
- **Encabezado permanente (AppBar):** **logo de letras RPCI** (azul/verde) + "Inventario · [pantalla]", visible en toda la app (APK y web).
- **Barra inferior** dinámica según roles: Inicio, Existencias, (Salida si operario−/admin), (Entrada si operario+/admin), Alertas.
- **Menú lateral (Drawer):** sección GESTIÓN (Bodegas, Traslados[admin], Centros de costo, Auditoría, Configuración) si admin/coordinador; Informes si `exportar`/admin; Usuarios y roles si admin; Trabajo sin conexión; Mi perfil.
- **Barra de sincronización** (`BarraSync`) arriba del contenido.

### 6.4 Inicio / Dashboard (`dashboard_page.dart`)
- **Muestra:** resumen (`resumen_inventario`): total de elementos, valorización total, bajo mínimo, total de movimientos; y **últimos movimientos** (con hora Colombia).

### 6.5 Existencias (`elementos_page.dart`)
- **Buscar:** búsqueda inteligente (palabras en cualquier orden). Suffix con: limpiar, **escanear código** (abre elemento asociado), **reconocer por foto**, y **＋ crear** (admin/coordinador).
- **Lista:** foto, nombre, existencia + costo promedio + material; ícono ⚠ si bajo mínimo; lápiz para editar (admin/coordinador); toque abre el **Kardex**.
- **Refresco:** se recarga ante cualquier cambio de inventario (`revision`).

### 6.6 Crear / Editar elemento (`editar_elemento_page.dart`)
- **Actores:** admin/coordinador.
- **Campos:** nombre*, material, SCH, unidad, stock mínimo, código de barras (con escáner), activo (solo edición), galería de fotos.
- **Copiar de otro artículo** (al crear): pre-llena nombre/material/SCH/unidad desde un elemento similar (no copia el código de barras).
- **Serializado (al crear):** switch **"Maneja seriales"**. Si se activa:
  - Aparece "Unidades iniciales": bodega + cantidad + seriales (uno por unidad) + costo por serial.
  - **Validación:** exige tantos seriales como la cantidad; si no cuadra o falta bodega, **no deja guardar**.
  - Si no es serializado: existencia inicial por cantidad + costo (opcional).
- **Casos borde:** no permite seriales repetidos; la existencia serializada la deriva el trigger.

### 6.7 Kardex / detalle de elemento (`kardex_page.dart`)
- **Muestra:** fotos, existencia/costo/valorización, **desglose por bodega**, seriales (si serializado), y el **kardex** (movimientos con fecha en hora Colombia).
- **Anular** (solo admin, no anulaciones): crea reversa (`anular_movimiento`).
- **Convertir a serializado** (si no lo es): registra los seriales de las unidades actuales.
- **Detalle de movimiento** (toque en un movimiento) → hoja inferior:
  - Ver datos del movimiento (hora Colombia).
  - **Editar observación** si admin/coordinador/autor (candado en base: solo cambia la observación; queda **auditado**).
  - **Adjuntar archivo** → muestra el aviso del §6.9.

### 6.8 Movimientos: Entrada / Salida (`movimiento_page.dart`)
- **Actores:** entrada = operario+/admin; salida = operario−/admin.
- **Común:** seleccionar elemento (buscador o escáner), bodega, observación.
- **Entrada normal:** cantidad + costo unitario.
- **Salida normal:** cantidad + **centro de costo** (obligatorio); usa costo promedio automático.
- **Serializado — entrada:** agregar seriales nuevos (chips) + costo.
- **Serializado — salida:** checklist de seriales disponibles en la bodega.
- **Botón "Devoluciones (cargar Excel/CSV)"** (solo en Entrada, **en azul**) → §6.10.
- **Botón "Adjuntar archivo"** → aviso del §6.9.
- **Validaciones:** cantidad > 0; salida no supera existencia (validado también offline).

### 6.9 Adjuntos (deshabilitado — `adjuntos_gate.dart`)
- Para **no gastar Storage**, al tocar "Adjuntar archivo" (en Entrada/Salida o en el detalle del movimiento) — **a cualquier usuario, incluido admin** — se muestra:
  > **Función de pago** — *Te hacen falta créditos en SUPABASE para adjuntar archivos. Transfiere el billete para darte los permisos 💸*
- El backend (tabla `movimiento_adjuntos` + bucket `adjuntos-mov` + métodos) queda listo por si se habilita.

### 6.10 Devoluciones — carga masiva (`devoluciones_page.dart`)
- **Actores:** operario+/admin (acceso desde Entrada).
- **Flujo:** elegir **bodega** física → subir **Excel/CSV** con columnas **ELEMENTO** y **CANTIDAD** → la app crea la columna **EMPAREJAMIENTO** con coincidencia **aproximada** (normaliza tildes/mayúsculas, similitud por palabras + Levenshtein) → las no emparejadas quedan en blanco para elegir a mano con el buscador → **CARGAR** registra una entrada por fila, valorizada al **costo promedio actual**.
- **Colores por fila:** verde (match fuerte), naranja (aproximado), rojo (sin emparejar), morado (serializado, se omite).
- **Validación de archivo inválido:** si faltan columnas ELEMENTO/CANTIDAD, si está vacío o no es Excel/CSV → diálogo **"Archivo inválido"** con el formato esperado. Columnas de más se ignoran.
- **Web:** el diálogo de archivo usa un **input HTML nativo** (evita el bloqueo de `file_picker` en web).
- **Resumen final:** cargados, a costo 0, sin emparejar (omitidos), serializados (omitidos).

### 6.11 Traslados (`traslados_page.dart`)
- **Actores:** admin.
- **Flujo:** elemento + bodega origen + bodega destino + cantidad (o **seriales** si serializado). Registra salida+entrada (referencia `TRASLADO`) manteniendo el costo.
- **Validación:** no traslada más de lo que hay en el origen; origen ≠ destino.

### 6.12 Serializar (`serializar_page.dart`)
- Convierte un elemento por cantidad en **serializado**, registrando el serial + bodega + costo de cada unidad existente.

### 6.13 Reconocer por foto (`reconocer_page.dart`, `phash.dart`)
- Toma/elige una foto y compara **huellas perceptuales (dHash)** contra las fotos de los elementos; devuelve los parecidos (mejor primero). En web, la selección de imagen usa el input nativo.

### 6.14 Alertas (`alertas_page.dart`)
- Dos pestañas:
  - **Stock mínimo:** elementos con existencia ≤ mínimo.
  - **Costo 0:** elementos con existencia pero **costo promedio 0** (no valorizados).

### 6.15 Bodegas (`bodegas_page.dart`)
- **Actores:** admin/coordinador. Crear/editar/desactivar/reactivar bodegas.

### 6.16 Centros de costo (`centros_page.dart`)
- **Actores:** admin/coordinador. Crear/editar/desactivar/reactivar centros de costo.

### 6.17 Configuración (`configuracion_page.dart`, `ajustes.dart`)
- **Actores:** admin/coordinador. Formato regional de exportación CSV (separador de campo y decimal) **por usuario** (en `profiles`). Buscador de usuarios para editar su config.

### 6.18 Informes (`reportes_page.dart`, `reportes.dart`)
- **Actores:** admin o rol `exportar`.
- **Informes CSV** (se abren en Excel): existencias valorizadas, movimientos por rango de fechas, consumo por centro de costo, bajo mínimo. Dinero como **enteros**; cantidades con decimales. Fechas en hora Colombia. Separadores según config regional del usuario.

### 6.19 Usuarios y roles (`gestion_usuarios_page.dart`)
- **Actores:** admin. Listar/buscar usuarios, asignar/quitar roles, **crear usuario** (Edge Function / servicio).

### 6.20 Auditoría / Historial (`historial_page.dart`)
- **Actores:** admin/coordinador. Ver quién cambió qué y cuándo (global o por registro), en hora Colombia.

### 6.21 Sincronización / offline (`sincronizacion_page.dart`, `sync_service.dart`, `local_store.dart`)
- Descargar catálogo para trabajar sin señal y subir pendientes; muestra última sincronización (hora Colombia).

### 6.22 Mi perfil (`perfil_page.dart`)
- Ver datos de la cuenta y **cambiar contraseña**.

### 6.23 Galería de imágenes (`widgets/galeria_elemento.dart`)
- Hasta 3 fotos por elemento, marcar principal, borrar. En **web** la opción "Elegir imagen del computador" usa el **input nativo** (comprime la imagen); la cámara usa `image_picker`. En móvil, todo con `image_picker`.

---

## 7. Reglas de negocio transversales

1. **Costo promedio ponderado móvil por bodega** — recalculado por trigger en cada entrada.
2. **Salidas** — bloqueadas si no hay existencia (en base y offline).
3. **Anulación** — nunca borra; genera reversa `ajuste`.
4. **Serializados** — existencia = conteo de seriales disponibles; costo específico por serial.
5. **Edición de movimientos** — solo la observación (candado + auditoría).
6. **Dinero en informes** — enteros.
7. **Fechas** — UTC en base, hora Colombia (UTC−5) en pantalla e informes.

---

## 8. Despliegue

Rutina fija tras **cada** cambio:
1. `flutter analyze lib/`
2. `flutter build web --release` + copiar `_headers`
3. `flutter build apk --release` → copiar APK versionado a Descargas
4. `wrangler pages deploy build/web` (Cloudflare)
5. `git commit` + `git push`

DDL de base: vía **Management API** de Supabase + recargar esquema PostgREST.

---

## 9. Backlog / pendiente

### 9.1 Categorías fiscales (EN DISEÑO — no implementado)
Nueva dimensión fiscal por cantidad: **Usados / Activos / Baja**, con **doble valorización** (contable = promedio; fiscal = 0 para Baja). El mismo elemento en la misma bodega puede tener cantidad en varias categorías. Decisiones tomadas: Baja **no reversible**; Usados/Activos solo son **etiquetas fiscales**; aplica **también a serializados**. Diseño: separar cantidad de costo con una tabla `existencias_categoria` + columna `categoria` en `movimientos` y `series`; acción **Reclasificar / Dar de baja**; informe fiscal. Fases: A (backend), B (app), C (informe). *Pendiente confirmar: las compras entran como "Usados".*

### 9.2 Adjuntos de movimientos
Backend listo; subida deshabilitada (aviso del §6.9). Se activaría cuando se disponga de Storage.

---

## 10. Historial de versiones (resumen)
- **v1–v5:** base online, roles, offline, fotos, código de barras, multi-bodega, informes, recuperación de contraseña, reconocimiento por foto.
- **v6.x:** inventario serializado; copiar de otro artículo; botón de crear visible; serializado al crear; **Devoluciones** (carga masiva Excel/CSV + emparejamiento + validación); alertas por costo 0; editar observación + adjuntos (gated); **hora Colombia**.
- **v7.x:** logo 10 años en login; logo RPCI en el encabezado permanente; botón Devoluciones en azul.
