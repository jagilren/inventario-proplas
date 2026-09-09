# Cómo restaurar el respaldo de la base de datos

Guía para el día malo: la base se corrompió, alguien borró algo grande, o el
proyecto de Supabase desapareció.

**No necesitas instalar nada.** Se usa Docker, que ya está en el equipo, para
correr `psql` sin instalarlo.

---

## Lo que necesitas antes de empezar

1. **La clave del respaldo** (`BACKUP_PASSPHRASE`). Debe estar en tu gestor de
   contraseñas. Copia local: `~/.backup_passphrase`.
   **Sin ella el respaldo es un archivo inútil y nadie puede recuperarla.**
2. **Acceso a GitHub** para descargar el artefacto.
3. **Un proyecto de Supabase** donde restaurar. Lee la advertencia de abajo
   antes de decidir si es el mismo o uno nuevo.

> ### Antes de tocar nada
>
> Restaurar **sobrescribe**. Si el problema es que se borraron unos datos pero
> el resto está bien, **no restaures encima**: crea un proyecto nuevo, restaura
> ahí, y copia solo lo que falta. Restaurar sobre una base viva puede convertir
> un problema pequeño en la pérdida de todo lo registrado desde el último
> respaldo (hasta 7 días de trabajo).

---

## Paso 1 — Descargar el respaldo

1. Ve a `github.com/jagilren/inventario-proplas` → pestaña **Actions**.
2. Abre el flujo **"Respaldo semanal de la base de datos"**.
3. Elige la corrida del día que quieras recuperar.
4. Abajo, en **Artifacts**, descarga `respaldo-bd`.

Se baja un `.zip` que contiene un `.tar.gz.gpg`.

> Los respaldos **caducan a los 90 días**. Si necesitas uno más viejo, ya no
> está: es el precio de que no se acumulen para siempre.

---

## Paso 2 — Descifrar y abrir

```bash
cd ~/Descargas
unzip respaldo-bd.zip

# Pide la clave (BACKUP_PASSPHRASE)
gpg --decrypt respaldo-2026-09-09.tar.gz.gpg > respaldo.tar.gz

tar xzf respaldo.tar.gz
ls
```

Deben aparecer cuatro archivos:

| Archivo | Qué trae |
|---|---|
| `esquema.sql` | Tablas, funciones, triggers y políticas de seguridad |
| `cuentas.sql` | Los usuarios que pueden entrar a la app |
| `datos.sql` | Todo el inventario |
| `roles.sql` | Roles del servidor |

---

## Paso 3 — Restaurar

Consigue la cadena de conexión del proyecto **destino**: Supabase →
*Project Settings* → *Database* → *Connection string* → **Session pooler**.

> Si la contraseña trae símbolos, hay que codificarlos en la cadena:
> `#` → `%23`, `@` → `%40`, `/` → `%2F`.

**El orden importa y no es opcional:**

```bash
URL='postgresql://postgres.XXXX:CLAVE@aws-0-ca-central-1.pooler.supabase.com:5432/postgres'

# 1) Estructura: sin esto no hay dónde meter los datos
docker run --rm -i -v "$PWD:/w" -w /w postgres:17 psql "$URL" -f esquema.sql

# 2) Cuentas: ANTES que los datos, porque `profiles` apunta a los usuarios
docker run --rm -i -v "$PWD:/w" -w /w postgres:17 psql "$URL" -f cuentas.sql

# 3) El inventario
docker run --rm -i -v "$PWD:/w" -w /w postgres:17 psql "$URL" -f datos.sql
```

**Por qué las cuentas van antes que los datos:** la tabla `profiles` tiene una
llave foránea contra los usuarios de `auth`. Si cargas los datos primero, esa
parte falla porque los usuarios todavía no existen.

`datos.sql` empieza con `SET session_replication_role = replica`, que **apaga
los triggers durante la carga**. Es a propósito: sin eso, al reinsertar los
movimientos se volverían a recalcular existencias sobre existencias ya
cargadas, y los saldos quedarían al doble.

---

## Paso 4 — Comprobar que quedó bien

No des por hecho que funcionó porque no salieron errores. Cuenta:

```bash
docker run --rm -i -v "$PWD:/w" -w /w postgres:17 psql "$URL" -c "
select 'elementos' t, count(*) from elementos
union all select 'movimientos', count(*) from movimientos
union all select 'existencias', count(*) from existencias
union all select 'usuarios', count(*) from auth.users
order by 1;"
```

Compara con lo que había el día del respaldo. Al 9 de septiembre de 2026 eran:
**1.028 elementos, 1.024 movimientos, 880 existencias, 4 usuarios.**

Después entra a la app y verifica lo que de verdad importa: que el inventario
valorizado cuadre y que puedas iniciar sesión.

---

## Paso 5 — Apuntar la app al proyecto nuevo

Solo si restauraste en un proyecto **distinto**. Hay que cambiar dos valores en
`lib/config.dart` (la URL y la llave publicable del proyecto nuevo), compilar y
desplegar. También hay que actualizar el secreto `SUPABASE_DB_URL` en GitHub
para que el respaldo siga apuntando al sitio correcto.

---

## Al terminar

**Borra los archivos descifrados.** Quedan en el disco con costos, precios,
clientes y hashes de contraseñas:

```bash
rm -f esquema.sql datos.sql cuentas.sql roles.sql respaldo.tar.gz
```

---

## Lo que este respaldo NO cubre

- **Las fotos de los elementos.** Viven en Supabase Storage, no en la base. Un
  respaldo de la base no las trae; las referencias quedarían apuntando a
  imágenes que ya no existen.
- **Lo registrado desde el último respaldo.** Corre los lunes: en el peor caso
  se pierden hasta 7 días. Si eso es demasiado, hay que subir la frecuencia o
  pagar el Point-in-Time Recovery de Supabase.
- **Las Edge Functions.** Están en `supabase/functions/` dentro del
  repositorio, así que se recuperan de ahí, no del respaldo.

---

## Nunca se ha probado una restauración de verdad

Se verificó que el respaldo **se descifra y trae los datos correctos**, pero
nunca se ha cargado en un proyecto vacío. Vale la pena hacerlo una vez, con
calma, contra un proyecto de prueba gratuito — no el día de la emergencia.
