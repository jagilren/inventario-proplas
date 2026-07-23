# tasks.md — Inventario PROPLAS

> **Artefacto SDD 3/3 — El DESGLOSE.** Tareas trazables a las historias de [`spec.md`](spec.md) y a la técnica de [`plan.md`](plan.md).
> Estado: ✅ hecho · 🔲 pendiente. `→ US-x`: historia que satisface.

---

## Tareas completadas (v1 → v7.3)

### Autenticación y cuenta
- ✅ T-1.1 Pantalla de login + `AuthGate` → US-1.1
- ✅ T-1.2 Recuperar contraseña por correo (`resetPasswordForEmail`) → US-1.2
- ✅ T-1.3 Pantalla de nueva contraseña (modo recovery) → US-1.2
- ✅ T-1.4 Perfil + cambiar contraseña → US-1.3

### Navegación y marca
- ✅ T-2.1 Home con barra inferior por rol + Drawer de gestión → US-2.2
- ✅ T-2.2 Encabezado permanente con logo RPCI (letras) → US-2.1
- ✅ T-2.3 Dashboard (resumen + últimos movimientos) → US-2.3

### Catálogo
- ✅ T-3.1 Búsqueda inteligente (`buscar_elementos`) → US-3.1
- ✅ T-3.2 Crear/editar elemento + botón ＋ visible → US-3.2, US-3.4
- ✅ T-3.3 Copiar de otro artículo → US-3.3
- ✅ T-3.4 Galería de fotos (máx. 3, principal) → US-3.5
- ✅ T-3.5 Web: elegir imagen con input nativo + compresión → US-3.5, RNF-6

### Movimientos
- ✅ T-4.1 Entrada (cantidad + costo, trigger de promedio) → US-4.1
- ✅ T-4.2 Salida (centro de costo, validación de stock) → US-4.2
- ✅ T-4.3 Kardex + desglose por bodega → US-4.3
- ✅ T-4.4 Anular (reversa `ajuste`, solo admin) → US-4.4
- ✅ T-4.5 Editar observación + candado `fn_mov_solo_observacion` + auditoría → US-4.5

### Serializado
- ✅ T-5.1 Crear serializado con unidades iniciales (validación N seriales) → US-5.1
- ✅ T-5.2 Entrada/Salida serializada (ops directas por caché) → US-5.2
- ✅ T-5.3 Convertir a serializado → US-5.3

### Multi-bodega
- ✅ T-6.1 CRUD de bodegas → US-6.1
- ✅ T-6.2 Traslados (cantidad y seriales) → US-6.2
- ✅ T-6.3 Existencias por bodega → US-6.3

### Devoluciones
- ✅ T-7.1 Carga masiva Excel/CSV + emparejamiento aproximado → US-7.1
- ✅ T-7.2 Corrección manual con buscador → US-7.1
- ✅ T-7.3 Validación de archivo inválido → US-7.1
- ✅ T-7.4 Web: diálogo de archivo nativo → US-7.1, RNF-6
- ✅ T-7.5 Botón de acceso (azul) desde Entrada → US-7.1

### Alertas / reconocimiento
- ✅ T-8.1 Alertas: Stock mínimo + Costo 0 → US-8.1
- ✅ T-9.1 Reconocer por foto (dHash) → US-9.1

### Informes / config
- ✅ T-10.1 Informes CSV (dinero entero, hora Colombia) → US-10.1
- ✅ T-10.2 Config regional CSV por usuario → US-10.2

### Administración
- ✅ T-11.1 CRUD centros de costo → US-11.1
- ✅ T-11.2 Usuarios y roles + crear usuario → US-11.2
- ✅ T-11.3 Auditoría / historial → US-11.3

### Offline
- ✅ T-12.1 Caché de catálogo + cola de movimientos → US-12.1
- ✅ T-12.2 Sincronización y anti-duplicado → US-12.1

### Plataforma / calidad
- ✅ T-P.1 Multi-bodega en trigger de costo (por bodega)
- ✅ T-P.2 Fix zona horaria (UTC en base, hora Colombia en UI) + backfill → RNF-4
- ✅ T-P.3 PWA + service worker + `_headers` → RNF-5
- ✅ T-P.4 `compileSdk 36` (por file_picker)
- ✅ T-P.5 Logo 10 años en login

### Adjuntos (parcial)
- ✅ T-13.1 Backend de adjuntos (tabla `movimiento_adjuntos` + bucket `adjuntos-mov`)
- ✅ T-13.2 Gate "Función de pago" en Entrada/Salida y detalle → US-13.1

---

## Tareas pendientes

### Adjuntos
- 🔲 T-13.3 Habilitar subida real (quitar gate, usar `file_picker`/input nativo, `agregarAdjunto`) → US-13.1

### Épica futura: Categorías fiscales *(se especificará con SDD estricto)*
- 🔲 T-F.A Backend: tabla `existencias_categoria`, columna `categoria` en `movimientos` y `series`, triggers, migración de todo a "Usados"
- 🔲 T-F.B App: elegir categoría en entrada/salida, pantalla Reclasificar/Dar de baja, desglose por categoría en kardex
- 🔲 T-F.C Informe fiscal por categoría (Usados/Activos/Baja) + fiscal vs contable
- 🔲 T-F.0 Confirmar regla: las compras entran como "Usados"

---

## Convenciones de trazabilidad
- Cada tarea referencia su(s) historia(s) `US-x` de `spec.md`.
- Al construir una épica nueva: primero `spec.md` (historias + criterios), luego `plan.md` (técnica), luego tareas aquí, y **al final** el código. Nada se programa sin su historia y criterios.
