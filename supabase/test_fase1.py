#!/usr/bin/env python3
# Prueba end-to-end de la FASE 1: simula lo que hace la app contra Supabase.
# Crea datos de prueba, valida lógica y permisos, y limpia todo al final.
import os, re, json, sys, requests

HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE, ".env"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); os.environ.setdefault(k.strip(), v.strip())
URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

# anon key desde lib/config.dart
cfg = open(os.path.join(HERE, "..", "lib", "config.dart"), encoding="utf-8").read()
ANON = re.search(r"supabaseAnonKey\s*=\s*'([^']+)'", cfg).group(1)

def hdr(key, token=None):
    return {"apikey": key, "Authorization": f"Bearer {token or key}",
            "Content-Type": "application/json"}

SVC = hdr(SERVICE)
ok = 0; fail = 0
def check(nombre, cond, extra=""):
    global ok, fail
    print(("  ✅ " if cond else "  ❌ ") + nombre + (f"  {extra}" if extra else ""))
    if cond: ok += 1
    else: fail += 1

created_users = []
test_elem = None
try:
    print("\n== 1) ELEMENTO y TRIGGER de costo promedio móvil ==")
    r = requests.post(f"{URL}/rest/v1/elementos",
        headers={**SVC, "Prefer": "return=representation"},
        data=json.dumps({"nombre": "ZZZ TEST BORRAR fase1", "unidad": "UND"}))
    test_elem = r.json()[0]["id"]
    check("crear elemento de prueba", r.status_code < 300)

    def mov(tipo, cant, costo=None):
        return requests.post(f"{URL}/rest/v1/movimientos", headers=SVC,
            data=json.dumps({"tipo": tipo, "elemento_id": test_elem,
                             "cantidad": cant, "costo_unitario": costo}))

    mov("entrada", 10, 100)   # exist 10, costo 100
    mov("entrada", 10, 200)   # exist 20, costo 150 (promedio ponderado)
    mov("salida", 5)          # exist 15, costo 150
    e = requests.get(f"{URL}/rest/v1/elementos?id=eq.{test_elem}&select=existencia,costo_promedio",
                     headers=SVC).json()[0]
    check("existencia = 15", float(e["existencia"]) == 15, f"(={e['existencia']})")
    check("costo promedio = 150", float(e["costo_promedio"]) == 150, f"(={e['costo_promedio']})")

    print("\n== 2) BLOQUEO de existencias negativas ==")
    r = mov("salida", 9999)
    check("salida > existencia es rechazada", r.status_code >= 300,
          f"(status {r.status_code})")

    print("\n== 3) BÚSQUEDA inteligente (palabras en cualquier orden) ==")
    r = requests.post(f"{URL}/rest/v1/rpc/buscar_elementos", headers=SVC,
                      data=json.dumps({"q": "borrar fase1 test"}))
    nombres = [x["nombre"] for x in r.json()]
    check("encuentra el elemento con palabras desordenadas",
          any("ZZZ TEST BORRAR" in n for n in nombres))

    print("\n== 4) KARDEX ==")
    r = requests.post(f"{URL}/rest/v1/rpc/kardex_elemento", headers=SVC,
                      data=json.dumps({"p_elemento": test_elem}))
    check("kardex devuelve los 3 movimientos", len(r.json()) == 3, f"(={len(r.json())})")

    print("\n== 5) PERMISOS por rol (RLS real, como la app) ==")
    # crear operario_menos de prueba
    def crear_user(email, roles):
        r = requests.post(f"{URL}/auth/v1/admin/users", headers=SVC,
            data=json.dumps({"email": email, "password": "Test123456",
                             "email_confirm": True}))
        uid = r.json()["id"]; created_users.append(uid)
        for rol in roles:
            requests.post(f"{URL}/rest/v1/usuario_roles", headers=SVC,
                data=json.dumps({"usuario_id": uid, "rol": rol}))
        return uid

    def login(email):
        r = requests.post(f"{URL}/auth/v1/token?grant_type=password",
            headers={"apikey": ANON, "Content-Type": "application/json"},
            data=json.dumps({"email": email, "password": "Test123456"}))
        return r.json()["access_token"]

    uid_menos = crear_user("test-operario-menos@proplas.test", ["operario_menos"])
    tok = login("test-operario-menos@proplas.test")
    H = hdr(ANON, tok)

    # operario_menos SÍ puede salida
    r = requests.post(f"{URL}/rest/v1/movimientos", headers=H,
        data=json.dumps({"tipo": "salida", "elemento_id": test_elem, "cantidad": 1}))
    check("operario_menos PUEDE registrar salida", r.status_code < 300,
          f"(status {r.status_code})")
    # operario_menos NO puede entrada
    r = requests.post(f"{URL}/rest/v1/movimientos", headers=H,
        data=json.dumps({"tipo": "entrada", "elemento_id": test_elem,
                         "cantidad": 1, "costo_unitario": 50}))
    check("operario_menos NO puede registrar entrada (RLS lo bloquea)",
          r.status_code >= 300, f"(status {r.status_code})")
    # operario_menos NO puede editar elementos
    r = requests.patch(f"{URL}/rest/v1/elementos?id=eq.{test_elem}", headers=H,
        data=json.dumps({"stock_minimo": 5}))
    # PostgREST devuelve 200 con 0 filas si RLS no deja; validamos que NO cambió
    e = requests.get(f"{URL}/rest/v1/elementos?id=eq.{test_elem}&select=stock_minimo",
                     headers=SVC).json()[0]
    check("operario_menos NO puede editar elementos", float(e["stock_minimo"]) == 0)

    print("\n== 6) EDGE FUNCTION crear-usuario (requiere admin) ==")
    # un operario NO debe poder crear usuarios
    r = requests.post(f"{URL}/functions/v1/crear-usuario", headers=H,
        data=json.dumps({"email": "hacker@x.com", "password": "x123456", "roles": []}))
    check("operario NO puede crear usuarios (403)", r.status_code == 403,
          f"(status {r.status_code})")

finally:
    print("\n== LIMPIEZA ==")
    if test_elem:
        requests.delete(f"{URL}/rest/v1/movimientos?elemento_id=eq.{test_elem}", headers=SVC)
        requests.delete(f"{URL}/rest/v1/elementos?id=eq.{test_elem}", headers=SVC)
        print("  elemento y movimientos de prueba borrados")
    for uid in created_users:
        requests.delete(f"{URL}/auth/v1/admin/users/{uid}", headers=SVC)
    print(f"  {len(created_users)} usuario(s) de prueba borrado(s)")

print(f"\n===== RESULTADO: {ok} OK, {fail} fallos =====")
sys.exit(1 if fail else 0)
