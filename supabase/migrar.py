#!/usr/bin/env python3
# =====================================================================
#  Migración del Excel PROPLAS -> Supabase
#  Lee 'Inventario PROPLAS 21042026.xlsm' y carga:
#    centros_costo -> categorias(no) -> elementos -> movimientos
#  Idempotente: usa upsert por claves naturales; se puede re-ejecutar.
#
#  Uso:
#    1) cp .env.example .env  y rellena SUPABASE_URL y SERVICE_ROLE_KEY
#    2) python3 migrar.py
# =====================================================================
import os, re, sys, json, datetime
import requests
import openpyxl

HERE = os.path.dirname(os.path.abspath(__file__))
XLSM = os.path.join(HERE, "..", "Inventario PROPLAS 21042026.xlsm")

# ---- cargar .env (sin dependencias externas) ------------------------
def load_env():
    path = os.path.join(HERE, ".env")
    if not os.path.exists(path):
        sys.exit("ERROR: falta el archivo .env (copia .env.example a .env y rellénalo).")
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

load_env()
URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
if not URL or not KEY or "xxxx" in URL or KEY.startswith("eyJ...") or KEY == "":
    sys.exit("ERROR: completa SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY en .env")

H = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json",
}

def rest(method, path, **kw):
    r = requests.request(method, f"{URL}/rest/v1/{path}", headers={**H, **kw.pop("headers", {})}, **kw)
    if r.status_code >= 300:
        raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:400]}")
    return r

def upsert(table, rows, on_conflict):
    """Inserta/actualiza en lotes, ignorando duplicados por on_conflict."""
    if not rows:
        return
    hdr = {"Prefer": "resolution=ignore-duplicates,return=minimal"}
    for i in range(0, len(rows), 200):
        chunk = rows[i:i+200]
        rest("POST", f"{table}?on_conflict={on_conflict}", headers=hdr, data=json.dumps(chunk, default=str))

def fetch_map(table, key_col, val_col="id"):
    """Devuelve {key_col: val_col} paginando (por si hay >1000 filas)."""
    out, offset = {}, 0
    while True:
        r = rest("GET", f"{table}?select={val_col},{key_col}",
                 headers={"Range-Unit": "items", "Range": f"{offset}-{offset+999}"})
        data = r.json()
        for d in data:
            out[str(d[key_col])] = d[val_col]
        if len(data) < 1000:
            break
        offset += 1000
    return out

def iso(v):
    if isinstance(v, (datetime.datetime, datetime.date)):
        return v.isoformat()
    return None

def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

CODE_RE = re.compile(r"\s*([A-Za-z]+\d+)")
def cc_code(txt):
    if not txt:
        return None
    m = CODE_RE.match(str(txt))
    return m.group(1) if m else None

# =====================================================================
print("Leyendo Excel...")
wb = openpyxl.load_workbook(XLSM, read_only=True, data_only=True)

def rows(sheet, skip=1):
    for i, r in enumerate(wb[sheet].iter_rows(values_only=True)):
        if i < skip:
            continue
        yield i, r

# ---- 1) CENTROS DE COSTO -------------------------------------------
cc_rows = []
for i, r in rows("CC"):
    cod = (str(r[0]).strip() if r[0] else None)
    if not cod:
        continue
    cc_rows.append({"codigo": cod,
                    "descripcion": (str(r[1]).strip() if len(r) > 1 and r[1] else None),
                    "cliente": (str(r[2]).strip() if len(r) > 2 and r[2] else None)})
print(f"Centros de costo: {len(cc_rows)}")
upsert("centros_costo", cc_rows, "codigo")

# ---- 2) ELEMENTOS (maestro BD + faltantes de movimientos) ----------
elems = {}   # nombre -> dict
def add_elem(nombre, material=None, sch=None, unidad=None):
    nombre = str(nombre).strip()
    if not nombre:
        return
    if nombre not in elems:
        elems[nombre] = {"nombre": nombre, "material": material, "sch": sch,
                         "unidad": (unidad or "UND")}

for i, r in rows("BD"):
    if r[0]:
        add_elem(r[0],
                 str(r[1]).strip() if len(r) > 1 and r[1] else None,
                 str(r[2]).strip() if len(r) > 2 and r[2] else None,
                 str(r[3]).strip() if len(r) > 3 and r[3] else None)

# faltantes desde inventario inicial (tiene material/sch/unidad)
for i, r in rows("INVENTARIO_INICIAL21042026"):
    if r[0]:
        add_elem(r[0],
                 str(r[1]).strip() if len(r) > 1 and r[1] else None,
                 str(r[2]).strip() if len(r) > 2 and r[2] else None,
                 str(r[4]).strip() if len(r) > 4 and r[4] else None)
# faltantes desde salidas (solo nombre)
for i, r in rows("SALIDAS"):
    if len(r) > 1 and r[1]:
        add_elem(r[1])

print(f"Elementos a cargar (maestro + faltantes): {len(elems)}")
upsert("elementos", list(elems.values()), "nombre")

# ---- mapas de ids ---------------------------------------------------
print("Leyendo ids asignados...")
id_elem = fetch_map("elementos", "nombre")   # nombre -> uuid
id_cc = fetch_map("centros_costo", "codigo")  # codigo -> uuid
print(f"  elementos en BD: {len(id_elem)} | CC: {len(id_cc)}")

# ---- 3) MOVIMIENTOS: inventario inicial -----------------------------
mov_ini = []
for i, r in rows("INVENTARIO_INICIAL21042026"):
    nom = str(r[0]).strip() if r[0] else None
    cant = num(r[3]) if len(r) > 3 else None
    if not nom or cant is None:
        continue
    mov_ini.append({
        "tipo": "inicial",
        "elemento_id": id_elem.get(nom),
        "cantidad": cant,
        "costo_unitario": num(r[5]) if len(r) > 5 else 0 or 0,
        "fecha": (iso(r[7]) if len(r) > 7 else None) or "2026-04-21T00:00:00",
        "referencia": str(r[8]).strip() if len(r) > 8 and r[8] else None,
        "device_id": "EXCEL", "local_id": f"ini-{i}",
    })
# costo nulo -> 0 (el trigger exige costo en 'inicial')
for m in mov_ini:
    if m["costo_unitario"] is None:
        m["costo_unitario"] = 0
print(f"Movimientos INICIAL: {len(mov_ini)}")
upsert("movimientos", mov_ini, "device_id,local_id")

# ---- 4) MOVIMIENTOS: salidas (una a una, para capturar errores) -----
sal = []
for i, r in rows("SALIDAS"):
    nom = str(r[1]).strip() if len(r) > 1 and r[1] else None
    cant = num(r[2]) if len(r) > 2 else None
    if not nom or cant is None:
        continue
    sal.append((r[0], {
        "tipo": "salida",
        "elemento_id": id_elem.get(nom),
        "centro_costo_id": id_cc.get(cc_code(r[3]) if len(r) > 3 else None),
        "cantidad": cant,
        "costo_unitario": num(r[4]) if len(r) > 4 else None,
        "fecha": iso(r[0]) or "2026-06-21T00:00:00",
        "observacion": str(r[6]).strip() if len(r) > 6 and r[6] else None,
        "device_id": "EXCEL", "local_id": f"sal-{i}",
    }))
# ordenar por fecha para no chocar con existencias
sal.sort(key=lambda t: (t[0] is None, t[0]))
print(f"Movimientos SALIDA: {len(sal)}")
errores = []
for fecha, m in sal:
    try:
        rest("POST", "movimientos?on_conflict=device_id,local_id",
             headers={"Prefer": "resolution=ignore-duplicates,return=minimal"},
             data=json.dumps(m, default=str))
    except RuntimeError as e:
        errores.append((m["local_id"], str(e)[:160]))

print("\n===== RESUMEN =====")
print(f"  Centros de costo: {len(cc_rows)}")
print(f"  Elementos:        {len(elems)}")
print(f"  Mov. inicial:     {len(mov_ini)}")
print(f"  Mov. salida:      {len(sal)}  (errores: {len(errores)})")
for lid, err in errores:
    print(f"    ! {lid}: {err}")
print("Migración terminada.")
