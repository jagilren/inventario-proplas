#!/usr/bin/env python3
# Crea 'inicial' de apertura para artículos que tienen salida pero sin stock,
# por la cantidad exacta de la salida. Marcado como MIGRACION-APERTURA.
# Luego re-ejecuta migrar.py para insertar esas salidas.
import os, json, requests, openpyxl
HERE = os.path.dirname(os.path.abspath(__file__))
for line in open(os.path.join(HERE, ".env"), encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); os.environ.setdefault(k.strip(), v.strip())
URL = os.environ["SUPABASE_URL"].rstrip("/"); KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
H = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

FAIL = {7, 8, 9, 10, 11, 12, 34, 35, 40, 55}
wb = openpyxl.load_workbook(os.path.join(HERE, "..", "Inventario PROPLAS 21042026.xlsm"),
                            read_only=True, data_only=True)
# mapa nombre->id
idmap = {}
r = requests.get(f"{URL}/rest/v1/elementos?select=id,nombre", headers=H); r.raise_for_status()
for d in r.json():
    idmap[str(d["nombre"])] = d["id"]

apert = []
for i, row in enumerate(wb["SALIDAS"].iter_rows(values_only=True)):
    if i in FAIL:
        nom = str(row[1]).strip()
        apert.append({
            "tipo": "inicial",
            "elemento_id": idmap.get(nom),
            "cantidad": float(row[2]),
            "costo_unitario": float(row[4]) if row[4] is not None else 0,
            "fecha": "2026-04-20T00:00:00",
            "referencia": "MIGRACION-APERTURA",
            "observacion": "Apertura automática: salida sin stock inicial en Excel",
            "device_id": "EXCEL", "local_id": f"apertura-{i}",
        })
r = requests.post(f"{URL}/rest/v1/movimientos?on_conflict=device_id,local_id",
                  headers={**H, "Prefer": "resolution=ignore-duplicates,return=minimal"},
                  data=json.dumps(apert))
print("Aperturas creadas:", len(apert), "| status", r.status_code, r.text[:200])
