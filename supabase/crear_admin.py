#!/usr/bin/env python3
# Crea un usuario administrador en Supabase Auth (email confirmado) y le pone rol=admin.
# Uso: python3 crear_admin.py correo@ejemplo.com "ContraseñaFuerte"
import os, sys, json, requests
HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE, ".env"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); os.environ.setdefault(k.strip(), v.strip())
URL = os.environ["SUPABASE_URL"].rstrip("/"); KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
H = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

if len(sys.argv) < 3:
    sys.exit('Uso: python3 crear_admin.py correo@ejemplo.com "Contraseña"')
email, password = sys.argv[1], sys.argv[2]

# 1) crear usuario con email confirmado
r = requests.post(f"{URL}/auth/v1/admin/users", headers=H, data=json.dumps({
    "email": email, "password": password, "email_confirm": True,
    "user_metadata": {"nombre": email.split("@")[0]},
}))
if r.status_code >= 300 and "already been registered" not in r.text:
    sys.exit(f"Error creando usuario: {r.status_code} {r.text[:300]}")
print("Usuario listo:", email)

# 2) obtener su id
r = requests.get(f"{URL}/auth/v1/admin/users", headers=H)
uid = next((u["id"] for u in r.json().get("users", []) if u["email"] == email), None)
if not uid:
    sys.exit("No se encontró el usuario recién creado.")

# 3) ponerle rol=admin en profiles (el trigger ya creó el perfil como bodeguero)
r = requests.patch(f"{URL}/rest/v1/profiles?id=eq.{uid}",
                   headers={**H, "Prefer": "return=minimal"},
                   data=json.dumps({"rol": "admin"}))
print("Rol admin asignado:", r.status_code)
