#!/usr/bin/env bash
set -euo pipefail

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

APP="data-engine/app.py"

if [ ! -f "$APP" ]; then
  echo "ERROR: No existe $APP"
  exit 1
fi

BACKUP="${APP}.bak_block_advice_sql_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "Backup: $BACKUP"

python3 - <<'PY'
from pathlib import Path
import re
import sys

path = Path("data-engine/app.py")
text = path.read_text(encoding="utf-8")

helper = r'''

def _forced_curricular_advice_intent(question: str, table: str = DEFAULT_TABLE) -> Optional[Dict[str, Any]]:
    """
    Bloquea que solicitudes pedagógicas/curriculares abiertas se conviertan en SQL.

    Ejemplos:
    - Sugiere actividades para un curso de investigación.
    - Crea una rúbrica para trabajo en equipo.
    - Propón estrategias para enseñanza semipresencial.
    - Diseña actividades de aprendizaje.
    - Qué verbos usar en resultados de aprendizaje.
    """
    q = _forced_norm_text(question) if "_forced_norm_text" in globals() else _norm_question(question)

    advisory_actions = [
        "sugiere", "sugerir", "recomienda", "recomendar",
        "crea", "crear", "disena", "disenar", "diseña", "diseñar",
        "elabora", "elaborar", "propone", "proponer",
        "plantea", "plantear", "formula", "formular",
        "redacta", "redactar", "orientame", "orientar",
        "ayudame", "ayudar", "explica", "explicar",
        "que verbos", "verbos usar", "verbos para",
        "estrategias", "actividades", "rubrica", "rúbrica",
    ]

    curricular_domain = [
        "curso", "cursos", "asignatura", "asignaturas",
        "investigacion", "investigación",
        "aprendizaje", "ensenanza", "enseñanza",
        "resultado", "resultados", "competencia", "competencias",
        "rubrica", "rúbrica", "evaluacion", "evaluación",
        "semipresencial", "didactica", "didáctica",
        "malla", "perfil de egreso", "silabo", "sílabo",
    ]

    data_intent = [
        "cuantos", "cuantas", "cantidad", "conteo", "total",
        "listar", "lista", "muestrame", "muéstrame",
        "por sede", "por facultad", "por programa",
        "grafico", "gráfico", "grafica", "gráfica",
        "barras", "pie", "pastel", "ranking", "top"
    ]

    has_action = any(a in q for a in advisory_actions)
    has_domain = any(d in q for d in curricular_domain)
    is_data = any(d in q for d in data_intent)

    if has_action and has_domain and not is_data:
        return {
            "ok": True,
            "mode": "assistant",
            "report_intent": "curricular_advice",
            "chart_type": None,
            "confidence": 1.0,
            "table": table,
            "dimensions": [],
            "metrics": [],
            "filters": [],
            "sql": None,
            "x": None,
            "y": None,
            "title": "Asesoría curricular",
            "engine": "forced_curricular_advice_guard",
            "answer_hint": "La solicitud pide diseño, orientación o propuesta curricular; no debe ejecutarse DuckDB ni FastIntent SQL."
        }

    return None

'''

if "def _forced_curricular_advice_intent(" not in text:
    marker = "\n@api.post(\"/intent/resolve\")"
    if marker not in text:
        print("ERROR: No encontré @api.post(\"/intent/resolve\")")
        sys.exit(1)
    text = text.replace(marker, helper + marker, 1)
    print("OK: Helper _forced_curricular_advice_intent agregado.")
else:
    print("INFO: Helper ya existía.")

old = '''    forced_loaded_programs = _forced_loaded_programs_intent(question, table)
    if forced_loaded_programs:
        result = forced_loaded_programs
    else:
'''

new = '''    forced_curricular_advice = _forced_curricular_advice_intent(question, table)
    if forced_curricular_advice:
        result = forced_curricular_advice
    else:
        forced_loaded_programs = _forced_loaded_programs_intent(question, table)
        if forced_loaded_programs:
            result = forced_loaded_programs
        else:
'''

if old in text and "forced_curricular_advice = _forced_curricular_advice_intent(question, table)" not in text:
    text = text.replace(old, new, 1)
    print("OK: Guard curricular insertado antes de forced_loaded_programs.")
elif "forced_curricular_advice = _forced_curricular_advice_intent(question, table)" in text:
    print("INFO: Guard curricular ya estaba insertado.")
else:
    print("ERROR: No encontré bloque forced_loaded_programs esperado.")
    sys.exit(1)

path.write_text(text, encoding="utf-8")
PY

echo "Validando sintaxis Python..."
python3 -m py_compile "$APP"

echo "Reconstruyendo data-engine..."
$DC build data-engine
$DC up -d data-engine

echo "Esperando data-engine..."
sleep 4

echo "Probando /intent/resolve..."
$DC exec -T data-engine python - <<'PY'
import requests, json, sys

q = "Sugiere actividades para un curso de investigación."
r = requests.post(
    "http://localhost:8090/intent/resolve",
    json={"question": q, "table": "silabos"},
    timeout=60
)

print("STATUS:", r.status_code)
data = r.json()
print(json.dumps(data, ensure_ascii=False, indent=2))

if data.get("sql"):
    raise SystemExit("ERROR: Esta solicitud no debe devolver SQL.")

if data.get("mode") != "assistant":
    raise SystemExit("ERROR: Esta solicitud debe ir a mode=assistant.")

print("OK: La solicitud curricular ya no cae en SQL.")
PY

echo "FIX DATA-ENGINE COMPLETADO."
