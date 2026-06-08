#!/usr/bin/env bash
set -euo pipefail

APP_FILE="data-engine/app.py"
TS="$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$APP_FILE" ]; then
  echo "ERROR: No existe $APP_FILE"
  exit 1
fi

echo "==> Backup"
cp "$APP_FILE" "$APP_FILE.bak.$TS"
echo "Backup creado: $APP_FILE.bak.$TS"

echo "==> Parcheando data-engine/app.py"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("data-engine/app.py")
s = p.read_text(encoding="utf-8")


def find_function_bounds(src: str, func_name: str):
    m = re.search(rf"(?m)^def\s+{re.escape(func_name)}\s*\(", src)
    if not m:
        return None

    start = m.start()
    next_def = re.search(r"(?m)^(?:@api\.|def\s+|class\s+)", src[m.end():])
    if not next_def:
        return start, len(src)

    end = m.end() + next_def.start()
    return start, end


forced_code = r'''
def _forced_norm_text(value: str) -> str:
    repl = str.maketrans("áéíóúüñÁÉÍÓÚÜÑ", "aeiouunAEIOUUN")
    value = str(value or "").lower().translate(repl)
    value = re.sub(r"[^a-z0-9_ %.-]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def _forced_table_column_names(table: str) -> List[str]:
    try:
        return [str(c.get("name")) for c in table_columns(table)]
    except Exception:
        return []


def _forced_loaded_programs_intent(question: str, table: str = DEFAULT_TABLE) -> Optional[Dict[str, Any]]:
    """
    Regla cerrada:
    - "qué carreras tienes cargadas"
    - "qué programas tienes cargados"
    - "lista las escuelas cargadas"
    Nunca debe filtrar por Sistemas ni contar cursos.
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
        "que", "cuales", "lista", "listar",
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
        # Si no existe la columna, dejamos que el flujo normal lo intente.
        return None

    select_sql = ", ".join(q_ident(c) for c in selected)

    sql = (
        f"SELECT DISTINCT {select_sql} "
        f"FROM {q_ident(table)} "
        f"WHERE {q_ident('programa_estudio')} IS NOT NULL "
        f"AND TRIM(CAST({q_ident('programa_estudio')} AS VARCHAR)) <> '' "
        f"ORDER BY {q_ident('programa_estudio')} "
        f"LIMIT 300"
    )

    return {
        "ok": True,
        "mode": "sql",
        "report_intent": "list_programs",
        "chart_type": None,
        "confidence": 1.0,
        "table": table,
        "dimensions": ["programa_estudio"],
        "metrics": [],
        "filters": [],
        "sql": sql,
        "x": None,
        "y": None,
        "title": "Carreras cargadas",
        "engine": "forced_loaded_programs_rule",
    }
'''.strip()


# Insertar regla antes del endpoint intent_resolve.
if "def _forced_loaded_programs_intent(" not in s:
    marker = '@api.post("/intent/resolve")'
    idx = s.find(marker)
    if idx == -1:
        raise SystemExit('No encontré @api.post("/intent/resolve").')
    s = s[:idx] + forced_code + "\n\n\n" + s[idx:]
    print("OK regla forced_loaded_programs_rule insertada")
else:
    print("OK regla forced_loaded_programs_rule ya existía")


# Reemplazar intent_resolve completo.
bounds = find_function_bounds(s, "intent_resolve")
if not bounds:
    raise SystemExit("No encontré def intent_resolve().")

start, end = bounds

new_intent_resolve = r'''def intent_resolve(req: IntentResolveRequest) -> Dict[str, Any]:
    question = (req.question or "").strip()
    if not question:
        raise HTTPException(status_code=422, detail="La pregunta esta vacia.")

    table = req.table or DEFAULT_TABLE

    forced_loaded_programs = _forced_loaded_programs_intent(question, table)
    if forced_loaded_programs:
        result = forced_loaded_programs
    else:
        # Compatibilidad con routers ya agregados por parches anteriores.
        feedback = None
        if "_feedback_academic_intent" in globals():
            try:
                feedback = _feedback_academic_intent(question, table)
            except Exception:
                feedback = None

        if feedback:
            result = feedback
        else:
            forced_academic = None
            if "_forced_academic_intent" in globals():
                try:
                    forced_academic = _forced_academic_intent(question, table)
                except Exception:
                    forced_academic = None

            if forced_academic:
                result = forced_academic
            else:
                result = resolve_intent_by_policy(question, table)

    sql = result.get("sql")
    if sql:
        try:
            result["sql"] = patch_numeric_sql(
                repair_sql_for_table(safe_select_sql(str(sql)), table),
                table
            )
        except TypeError:
            # Compatibilidad con versiones antiguas de patch_numeric_sql(sql)
            result["sql"] = patch_numeric_sql(
                repair_sql_for_table(safe_select_sql(str(sql)), table)
            )
        except Exception:
            result["sql"] = safe_select_sql(str(sql))

    return result
'''

s = s[:start] + new_intent_resolve + "\n\n" + s[end:]

p.write_text(s, encoding="utf-8")
print("OK intent_resolve reemplazado")
PY

echo "==> Validando sintaxis"
python3 -m py_compile "$APP_FILE"

echo "==> Reconstruyendo data-engine"
docker compose build --no-cache data-engine
docker compose up -d --force-recreate data-engine

echo "==> Esperando data-engine"
for i in $(seq 1 60); do
  if docker compose exec -T data-engine python - <<'PY' >/dev/null 2>&1
import requests
try:
    r = requests.get("http://localhost:8090/health", timeout=2)
    raise SystemExit(0 if r.status_code == 200 else 1)
except Exception:
    raise SystemExit(1)
PY
  then
    echo "data-engine listo."
    break
  fi

  if [ "$i" -eq 60 ]; then
    echo "ERROR: data-engine no respondió."
    docker compose logs --tail=120 data-engine
    exit 1
  fi

  sleep 2
done

echo "==> Probando /intent/resolve directamente"

docker compose exec -T data-engine python - <<'PY'
import requests, json

payload = {
    "question": "que carreras tienes cargadas",
    "table": "silabos"
}

r = requests.post("http://localhost:8090/intent/resolve", json=payload, timeout=60)

print("STATUS:", r.status_code)
data = r.json()
print(json.dumps({
    "ok": data.get("ok"),
    "mode": data.get("mode"),
    "report_intent": data.get("report_intent"),
    "engine": data.get("engine"),
    "sql": data.get("sql"),
}, ensure_ascii=False, indent=2))
PY

echo "==> Probando ejecución de SQL"

docker compose exec -T data-engine python - <<'PY'
import requests, json

spec = requests.post(
    "http://localhost:8090/intent/resolve",
    json={"question": "que carreras tienes cargadas", "table": "silabos"},
    timeout=60
).json()

r = requests.post(
    "http://localhost:8090/duckdb/query",
    json={"sql": spec["sql"], "limit": 300},
    timeout=60
)

print("STATUS:", r.status_code)
data = r.json()
print(json.dumps({
    "ok": data.get("ok"),
    "row_count": data.get("row_count"),
    "rows": data.get("rows", [])[:10],
}, ensure_ascii=False, indent=2))
PY

echo ""
echo "============================================================"
echo "Patch aplicado."
echo "Ahora prueba nuevamente desde la web/API:"
echo '{"question":"que carreras tienes cargadas","mode":"auto","table":"silabos"}'
echo "============================================================"
