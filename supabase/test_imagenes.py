#!/usr/bin/env python3
# Prueba de la función de imagen por elemento:
# quién puede subir, quién no, y que la URL pública sirva la imagen.
import os, re, json, sys, struct, zlib, requests

HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE, ".env"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); os.environ.setdefault(k.strip(), v.strip())
URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
cfg = open(os.path.join(HERE, "..", "lib", "config.dart"), encoding="utf-8").read()
PUB = re.search(r"supabasePublishableKey\s*=\s*'([^']+)'", cfg).group(1)
SVC = {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}", "Content-Type": "application/json"}
BALDE = "elementos-img"

def png_minimo():
    """Genera un PNG 1x1 válido sin librerías externas."""
    def chunk(tipo, datos):
        c = tipo + datos
        return struct.pack(">I", len(datos)) + c + struct.pack(">I", zlib.crc32(c))
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\xff\x00\x00")
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

ok = fail = 0
def check(nombre, cond, extra=""):
    global ok, fail
    print(("  ✅ " if cond else "  ❌ ") + nombre + (f"  {extra}" if extra else ""))
    if cond: ok += 1
    else: fail += 1

usuarios = []; elem = None
try:
    r = requests.post(f"{URL}/rest/v1/elementos",
        headers={**SVC, "Prefer": "return=representation"},
        data=json.dumps({"nombre": "ZZZ IMAGEN prueba", "unidad": "UND"}))
    elem = r.json()[0]["id"]

    def crear_user(email, rol):
        r = requests.post(f"{URL}/auth/v1/admin/users", headers=SVC,
            data=json.dumps({"email": email, "password": "Test123456",
                             "email_confirm": True}))
        uid = r.json()["id"]; usuarios.append(uid)
        requests.post(f"{URL}/rest/v1/usuario_roles", headers=SVC,
            data=json.dumps({"usuario_id": uid, "rol": rol}))
        r = requests.post(f"{URL}/auth/v1/token?grant_type=password",
            headers={"apikey": PUB, "Content-Type": "application/json"},
            data=json.dumps({"email": email, "password": "Test123456"}))
        return r.json()["access_token"]

    img = png_minimo()
    def subir(token, nombre_archivo):
        return requests.post(f"{URL}/storage/v1/object/{BALDE}/{nombre_archivo}",
            headers={"apikey": PUB, "Authorization": f"Bearer {token}",
                     "Content-Type": "image/png", "x-upsert": "true"}, data=img)

    print("\n== Permisos de subida ==")
    t_op = crear_user("test-img-operario@proplas.test", "operario_menos")
    r = subir(t_op, f"{elem}.png")
    check("operario NO puede subir imagen", r.status_code >= 300,
          f"(status {r.status_code})")

    t_co = crear_user("test-img-coord@proplas.test", "coordinador")
    r = subir(t_co, f"{elem}.png")
    check("coordinador SÍ puede subir imagen", r.status_code < 300,
          f"(status {r.status_code})")

    print("\n== La URL pública sirve la imagen ==")
    pub_url = f"{URL}/storage/v1/object/public/{BALDE}/{elem}.png"
    r = requests.get(pub_url)
    check("imagen accesible sin sesión", r.status_code == 200,
          f"(status {r.status_code})")
    check("tipo de contenido es imagen",
          r.headers.get("content-type", "").startswith("image/"),
          f"({r.headers.get('content-type')})")

    print("\n== Guardar la URL en el elemento ==")
    requests.patch(f"{URL}/rest/v1/elementos?id=eq.{elem}", headers=SVC,
                   data=json.dumps({"imagen_url": pub_url}))
    e = requests.get(f"{URL}/rest/v1/elementos?id=eq.{elem}&select=imagen_url",
                     headers=SVC).json()[0]
    check("imagen_url quedó guardada", e["imagen_url"] == pub_url)

    print("\n== Auditoría del cambio de foto ==")
    r = requests.post(f"{URL}/rest/v1/rpc/historial_registro", headers=SVC,
        data=json.dumps({"p_tabla": "elementos", "p_id": elem}))
    campos = [h["campo"] for h in r.json() if h["accion"] == "UPDATE"]
    check("el cambio de imagen quedó auditado", "imagen_url" in campos,
          f"(campos: {campos})")

    print("\n== Borrado por operario ==")
    r = requests.delete(f"{URL}/storage/v1/object/{BALDE}/{elem}.png",
        headers={"apikey": PUB, "Authorization": f"Bearer {t_op}"})
    check("operario NO puede borrar imágenes", r.status_code >= 300,
          f"(status {r.status_code})")

finally:
    print("\n== LIMPIEZA ==")
    if elem:
        requests.delete(f"{URL}/storage/v1/object/{BALDE}/{elem}.png",
                        headers={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"})
        requests.delete(f"{URL}/rest/v1/elementos?id=eq.{elem}", headers=SVC)
    for uid in usuarios:
        requests.delete(f"{URL}/auth/v1/admin/users/{uid}", headers=SVC)
    print(f"  elemento e imagen borrados · {len(usuarios)} usuarios de prueba borrados")

print(f"\n===== RESULTADO: {ok} OK, {fail} fallos =====")
sys.exit(1 if fail else 0)
