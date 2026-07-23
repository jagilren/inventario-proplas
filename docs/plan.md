# plan.md — Inventario PROPLAS

> **Artefacto SDD 2/3 — El CÓMO.** Arquitectura y decisiones técnicas que implementan [`spec.md`](spec.md).
> Desglose de tareas: [`tasks.md`](tasks.md).

---

## 1. Arquitectura general

Cliente **Flutter** (Web + Android) → **Supabase** (PostgreSQL + Auth + Storage + PostgREST). Sin backend propio: la lógica de negocio vive en **triggers y RPC** de Postgres, protegida por **RLS**. Hosting web en **Cloudflare Pages**.

```
Flutter (Web PWA / APK)
  └─ InventarioService (lib/data.dart)  ── HTTPS ──►  Supabase
        ├─ caché + cola offline (local_store.dart / shared_preferences)      ├─ Auth
        └─ SyncService (online/offline)                                       ├─ PostgREST (tablas/RPC + RLS)
                                                                              └─ Storage (buckets)
```

## 2. Stack y versiones

Flutter 3.44 / Dart 3.12 · Material 3 (seed `#00695C`) · Android `compileSdk 36`.
Paquetes: `supabase_flutter`, `intl`, `image_picker`, `shared_preferences`, `connectivity_plus`, `mobile_scanner`, `csv`, `file_saver`, `image`, `file_picker`, `excel`, `url_launcher`.

## 3. Organización del código (`lib/`)

| Archivo/Carpeta | Responsabilidad |
|---|---|
| `main.dart` | Arranque, tema, `AuthGate` (sesión + recuperación de clave). |
| `data.dart` | Modelos + `InventarioService` (única puerta a Supabase). |
| `config.dart` | URL/clave anon de Supabase. |
| `local_store.dart` | Caché de catálogo + cola de movimientos offline. |
| `sync_service.dart` | Estado de conexión y subida de pendientes. |
| `ajustes.dart` | Config regional CSV por usuario. |
| `reportes.dart` | Generación/descarga de CSV. |
| `phash.dart` | dHash para reconocimiento por foto. |
| `util/picker*.dart` | Selección de archivo: input HTML nativo en web / `file_picker` en móvil. |
| `util/imagen_picker.dart` | Selección + compresión de imagen (nativo en web). |
| `util/tiempo.dart` | `horaColombia()` (UTC−5 fijo). |
| `util/adjuntos_gate.dart` | Aviso "Función de pago" de adjuntos. |
| `widgets/` | `barra_sync`, `galeria_elemento`, `imagen_elemento`. |
| `screens/` | 22 pantallas (una por función). |

## 4. Modelo de datos

**Tablas:** `profiles`, `usuario_roles`, `elementos`, `categorias`, `bodegas`, `centros_costo`, `existencias` (PK elemento+bodega), `movimientos`, `series`, `movimiento_series`, `elemento_imagenes`, `movimiento_adjuntos`, `auditoria`.

**Buckets Storage:** `elementos-img` (público, ≤2 MB, jpg/png), `adjuntos-mov` (público, ≤10 MB, pdf/xlsx/xls/csv/img — deshabilitado en app).

**Lógica en base (triggers/RPC):**
- `aplicar_movimiento()` — AFTER INSERT en `movimientos`, SECURITY DEFINER: existencia + costo promedio ponderado por bodega; bloquea salidas sin stock; en serializados no toca stock.
- `fn_sync_existencia_serie()` — deriva existencia/costo de serializados desde `series`.
- `fn_mov_solo_observacion()` — BEFORE UPDATE en `movimientos`: candado (solo `observacion` puede cambiar).
- `fn_auditoria()` — bitácora en tablas auditadas + UPDATE de `movimientos`.
- `anular_movimiento`, `buscar_elementos`, `trasladar`, `serializar_elemento`, `resumen_inventario`, `ultimos_movimientos`, `kardex_elemento`, `imagenes_elemento`, `listar_usuarios`, `historial_registro`, `auditoria_reciente`, helpers `es_admin()`/`tiene_rol()`.

## 5. Decisiones técnicas transversales

1. **RLS en todo.** Las políticas usan `es_admin()`/`tiene_rol()` (SECURITY DEFINER). Escrituras directas desde la app cuando el RPC falla por caché.
2. **Caché de PostgREST poco fiable.** Tras DDL: aplicar por Management API + `notify pgrst, 'reload schema'`. Cuando un RPC con firma nueva da 404/42883, se reemplaza por **operaciones directas sobre tablas** (patrón usado en `trasladar` y `mover_serie`).
3. **Costeo.** Promedio ponderado móvil en el trigger; se mantiene el costo real en la BD siempre (base para el futuro fiscal).
4. **Offline.** Cola con llave `device_id + local_id` (anti-duplicado); ajuste de stock local; validación de stock antes de encolar salidas.
5. **Zona horaria.** Guardar `DateTime.now().toUtc()`; mostrar con `horaColombia()` (UTC−5 fijo, sin DST). Histórico previo corregido (+5 h) una sola vez.
6. **Archivos en web.** `file_picker`/`image_picker` no abren el diálogo de forma fiable en web (user-activation). Solución: **input HTML nativo** (`util/picker_web.dart`) en web; `file_picker`/`image_picker` en móvil (APK intacto).
7. **Adjuntos gated.** Backend listo; la UI muestra el aviso de "créditos" para no gastar Storage.

## 6. Seguridad

- Cliente solo con clave **anon**; `service_role` y token de Management fuera del cliente (en `supabase/.env`).
- RLS por rol; `movimiento_adjuntos` y edición de observación permiten admin/coordinador/autor.
- Storage público con rutas no adivinables (uuid); adjuntos verificados por carpeta = id del movimiento.

## 7. Despliegue

Rutina fija por cambio: `flutter analyze` → `build web` (+`_headers`) → `build apk` (copia a Descargas, versionada) → `wrangler pages deploy` → `git push`. DDL por Management API + recarga de esquema.

## 8. Riesgos técnicos

| Riesgo | Mitigación |
|---|---|
| Caché de PostgREST tras DDL | Ops directas + recarga de esquema. |
| Egress web (plan gratis) | SW + no-cache solo en index/SW; bundle liviano. |
| Diálogos de archivo en web | Input nativo. |
| Crecimiento de auditoría | Auditar solo UPDATE en movimientos; purga futura opcional. |
