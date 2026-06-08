#!/usr/bin/env bash
set -euo pipefail

APP_FILE="data-engine/app.py"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${APP_FILE}.bak_${TS}"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ]; then
  echo "ERROR: Ejecuta este script desde la raiz del proyecto, donde esta docker-compose.yml o compose.yml."
  exit 1
fi

if [ ! -f "$APP_FILE" ]; then
  echo "ERROR: No existe $APP_FILE"
  exit 1
fi

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

echo "==> Backup: $BACKUP_FILE"
cp "$APP_FILE" "$BACKUP_FILE"

echo "==> Aplicando fix de filtro por sede en _forced_loaded_programs_intent()..."

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("data-engine/app.py")
text = path.read_text(encoding="utf-8")

replacement = r'''def _forced_loaded_programs_intent(question: str, table: str = DEFAULT_TABLE) -> Optional[Dict[str, Any]]:
    """
    Regla cerrada:
    - "qué carreras tienes cargadas"
    - "qué programas tienes cargados"
    - "cuál carrera de sede lima tienes"
    - "qué carreras tienes en la sede Juliaca"

    Debe listar carreras/programas y respetar filtros explícitos como sede.
    Nunca debe inventar Sistemas ni convertir esto en COUNT(*).
    """
    q = _forced_norm_text(question)

    asks_programs = any(x in q for x in [
        "carrera", "carreras",
        "programa", "programas",
        "escuela", "escuelas"
    ])

    asks_loaded = any(x in q for x in [
        "cargada", "cargadas",
        "cargado", "cargados",
        "tienes",
        "disponible", "disponibles",
        "registrada", "registradas",
        "registrado", "registrados"
    ])

    asks_what = any(x in q for x in [
        "que", "cual", "cuales",
        "lista", "listar",
        "listame", "listarme", "muestrame",
        "mostrar", "dame", "ver"
    ])

    asks_courses = any(x in q for x in [
        "curso", "cursos", "asignatura", "asignaturas"
    ])

    # Si pide cursos, no responder carreras aquí.
    if asks_courses:
        return None

    if not (asks_programs and (asks_loaded or asks_what)):
        return None

    cols = _forced_table_column_names(table)

    preferred = [
        "programa_estudio",
        "facultad",
        "modalidad_estudio",
        "sede",
    ]

    selected = [c for c in preferred if c in cols]

    if "programa_estudio" not in selected:
        return None

    select_sql = ", ".join(q_ident(c) for c in selected)

    conditions = [
        f"{q_ident('programa_estudio')} IS NOT NULL",
        f"TRIM(CAST({q_ident('programa_estudio')} AS VARCHAR)) <> ''",
    ]

    filters = []

    # Filtro explícito por sede.
    if "sede" in cols:
        sede_map = {
            "lima": "Lima",
            "juliaca": "Juliaca",
            "tarapoto": "Tarapoto",
        }

        for token, label in sede_map.items():
            if token in q:
                conditions.append(f"{q_ident('sede')} ILIKE {q_str('%' + label + '%')}")
                filters.append({
                    "column": "sede",
                    "operator": "ILIKE",
                    "value": "%" + label + "%"
                })
                break

    where_sql = " WHERE " + " AND ".join(conditions)

    sql = (
        f"SELECT DISTINCT {select_sql} "
        f"FROM {q_ident(table)} "
        f"{where_sql} "
        f"ORDER BY {q_ident('programa_estudio')} "
        f"LIMIT 300"
    )

    title = "Carreras cargadas"
    if filters:
        title = "Carreras cargadas por sede"

    return {
        "ok": True,
        "mode": "sql",
        "report_intent": "list_programs",
        "chart_type": None,
        "confidence": 1.0,
        "table": table,
        "dimensions": ["programa_estudio"],
        "metrics": [],
        "filters": filters,
        "sql": sql,
        "x": None,
        "y": None,
        "title": title,
        "engine": "forced_loaded_programs_rule",
    }


'''

pattern = re.compile(
    r'def _forced_loaded_programs_intent\(question: str, table: str = DEFAULT_TABLE\) -> Optional\[Dict\[str, Any\]\]:.*?(?=\n@api\.post\("/intent/resolve"\))',
    re.S
)

new_text, count = pattern.subn(replacement, text, count=1)

if count != 1:
    print("ERROR: No pude encontrar/reemplazar _forced_loaded_programs_intent().")
    print("Revisa si el archivo data-engine/app.py cambió de estructura.")
    sys.exit(1)

path.write_text(new_text, encoding="utf-8")
print("OK: Funcion _forced_loaded_programs_intent() reemplazada.")
PY

echo "==> Validando sintaxis Python..."
python3 -m py_compile "$APP_FILE"

echo "==> Confirmando que el patch quedo en el archivo..."
grep -n "Carreras cargadas por sede\|sede_map\|ILIKE.*label" "$APP_FILE" | head -20

echo "==> Reconstruyendo solo data-engine..."
$DC build data-engine

echo "==> Levantando data-engine..."
$DC up -d data-engine

echo "==> Estado actual de contenedores..."
$DC ps

echo "==> Probando health interno de data-engine..."
$DC exec -T data-engine python - <<'PY'
import requests
r = requests.get("http://localhost:8090/health", timeout=15)
print("STATUS:", r.status_code)
print(r.text[:500])
PY

echo "==> Probando /intent/resolve con sede Lima..."
$DC exec -T data-engine python - <<'PY'
import requests, json

payload = {
    "question": "cual carrera de sede lima tienes ?",
    "table": "silabos"
}

r = requests.post(
    "http://localhost:8090/intent/resolve",
    json=payload,
    timeout=60
)

print("STATUS:", r.status_code)
data = r.json()
print(json.dumps(data, ensure_ascii=False, indent=2)[:4000])

sql = str(data.get("sql", ""))
if "sede" not in sql.lower() or "lima" not in sql.lower():
    raise SystemExit("ERROR: El SQL aun no contiene filtro por sede Lima.")

if "tarapoto" in sql.lower() or "juliaca" in sql.lower():
    raise SystemExit("ERROR: El SQL contiene sedes no solicitadas.")

print("OK: El SQL contiene filtro por sede Lima.")
PY

echo "==> Probando ejecucion DuckDB del SQL generado..."
$DC exec -T data-engine python - <<'PY'
import requests, json

intent = requests.post(
    "http://localhost:8090/intent/resolve",
    json={"question": "cual carrera de sede lima tienes ?", "table": "silabos"},
    timeout=60
).json()

sql = intent["sql"]

r = requests.post(
    "http://localhost:8090/duckdb/query",
    json={"sql": sql, "limit": 300},
    timeout=60
)

print("STATUS:", r.status_code)
data = r.json()
print(json.dumps(data, ensure_ascii=False, indent=2)[:4000])

rows = data.get("rows") or data.get("data") or []
bad = []
for row in rows:
    sede = str(row.get("sede", ""))
    if sede and "lima" not in sede.lower():
        bad.append(row)

if bad:
    raise SystemExit("ERROR: Hay filas que no son Lima: " + json.dumps(bad[:3], ensure_ascii=False))

print("OK: Resultado DuckDB filtrado por Lima.")
PY

echo "==> FIX COMPLETADO."
echo "Backup disponible en: $BACKUP_FILE"
echo ""
echo "Prueba externa sugerida:"
echo "curl -s -X POST http://localhost:3000/api/ask \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"question\":\"cual carrera de sede lima tienes ?\",\"context\":\"user\",\"options\":{\"table\":\"silabos\"}}' | jq ."
