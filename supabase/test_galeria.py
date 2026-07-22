#!/usr/bin/env python3
# Prueba la galería de hasta 3 fotos por elemento.
import os, re, json, sys, struct, zlib, requests

HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE, ".env"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); os.environ.setdefault(k.strip(), v.strip())
URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
SVC = {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}", "Content-Type": "application/json"}

ok = fail = 0
def check(nombre, cond, extra=""):
    global ok, fail
    print(("  ✅ " if cond else "  ❌ ") + nombre + (f"  {extra}" if extra else ""))
    if cond: ok += 1
    else: fail += 1

elem = None
try:
    r = requests.post(f"{URL}/rest/v1/elementos",
        headers={**SVC, "Prefer": "return=representation"},
        data=json.dumps({"nombre": "ZZZ GALERIA prueba", "unidad": "UND"}))
    elem = r.json()[0]["id"]

    def add(n):
        return requests.post(f"{URL}/rest/v1/elemento_imagenes", headers=SVC,
            data=json.dumps({"elemento_id": elem,
                             "url": f"https://ejemplo/{n}.jpg",
                             "ruta": f"{elem}/{n}.jpg"}))

    print("\n== Límite de 3 fotos ==")
    for i in range(1, 4):
        r = add(i)
        check(f"foto {i} aceptada", r.status_code < 300, f"(status {r.status_code})")
    r = add(4)
    check("la 4a foto es RECHAZADA", r.status_code >= 300, f"(status {r.status_code})")
    if r.status_code >= 300:
        print("     motivo:", json.loads(r.text).get("message", "")[:70])

    print("\n== Foto principal ==")
    fotos = requests.post(f"{URL}/rest/v1/rpc/imagenes_elemento", headers=SVC,
        data=json.dumps({"p_elemento": elem})).json()
    principales = [f for f in fotos if f["principal"]]
    check("hay exactamente UNA principal", len(principales) == 1,
          f"({len(principales)})")
    check("la principal va primero en la lista", fotos[0]["principal"])

    e = requests.get(f"{URL}/rest/v1/elementos?id=eq.{elem}&select=imagen_url",
                     headers=SVC).json()[0]
    check("elementos.imagen_url apunta a la principal",
          e["imagen_url"] == principales[0]["url"])

    print("\n== Cambiar la principal ==")
    otra = [f for f in fotos if not f["principal"]][0]
    requests.patch(f"{URL}/rest/v1/elemento_imagenes?id=eq.{otra['id']}",
                   headers=SVC, data=json.dumps({"principal": True}))
    fotos = requests.post(f"{URL}/rest/v1/rpc/imagenes_elemento", headers=SVC,
        data=json.dumps({"p_elemento": elem})).json()
    principales = [f for f in fotos if f["principal"]]
    check("sigue habiendo UNA sola principal", len(principales) == 1)
    check("la nueva principal es la elegida", principales[0]["id"] == otra["id"])
    e = requests.get(f"{URL}/rest/v1/elementos?id=eq.{elem}&select=imagen_url",
                     headers=SVC).json()[0]
    check("imagen_url se actualizó sola", e["imagen_url"] == otra["url"])

    print("\n== Borrar la principal: otra debe ascender ==")
    requests.delete(f"{URL}/rest/v1/elemento_imagenes?id=eq.{otra['id']}", headers=SVC)
    fotos = requests.post(f"{URL}/rest/v1/rpc/imagenes_elemento", headers=SVC,
        data=json.dumps({"p_elemento": elem})).json()
    check("quedan 2 fotos", len(fotos) == 2, f"({len(fotos)})")
    check("una asumió como principal", any(f["principal"] for f in fotos))

    print("\n== Tras borrar la principal, hay cupo otra vez ==")
    r = add(9)
    check("se puede agregar una nueva foto", r.status_code < 300,
          f"(status {r.status_code})")

    print("\n== Auditoría de la galería ==")
    r = requests.get(f"{URL}/rest/v1/auditoria?tabla=eq.elemento_imagenes&select=accion&limit=20",
                     headers=SVC)
    check("los cambios de fotos quedan auditados", len(r.json()) > 0,
          f"({len(r.json())} registros)")

finally:
    print("\n== LIMPIEZA ==")
    if elem:
        requests.delete(f"{URL}/rest/v1/elementos?id=eq.{elem}", headers=SVC)
        print("  elemento borrado (sus fotos se borran en cascada)")

print(f"\n===== RESULTADO: {ok} OK, {fail} fallos =====")
sys.exit(1 if fail else 0)
