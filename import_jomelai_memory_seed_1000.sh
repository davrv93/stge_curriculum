#!/usr/bin/env bash
set -euo pipefail

DATASET="${1:-jomelai_memory_seed_1000.jsonl}"

if [ ! -f "$DATASET" ]; then
  echo "ERROR: No existe el archivo: $DATASET"
  echo "Uso: ./import_jomelai_memory_seed_1000.sh /ruta/jomelai_memory_seed_1000.jsonl"
  exit 1
fi

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

echo "==> Copiando dataset al contenedor data-engine..."
CONTAINER_ID="$($DC ps -q data-engine)"

if [ -z "$CONTAINER_ID" ]; then
  echo "ERROR: data-engine no está corriendo."
  exit 1
fi

docker cp "$DATASET" "$CONTAINER_ID:/tmp/jomelai_memory_seed_1000.jsonl"

echo "==> Importando registros a jomelai_memory..."
$DC exec -T data-engine python - <<'PY'
import json
import requests
from pathlib import Path
import time

path = Path("/tmp/jomelai_memory_seed_1000.jsonl")
base = "http://localhost:8090"

if not path.is_file():
    raise SystemExit("No existe /tmp/jomelai_memory_seed_1000.jsonl dentro del contenedor.")

ok = 0
fail = 0

with path.open("r", encoding="utf-8") as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue

        rec = json.loads(line)

        payload = {
            "question": rec["question"],
            "answer": rec["answer"],
            "collection": rec.get("collection", "jomelai_memory"),
            "intent": rec.get("intent", "curricular_advice"),
            "topic": rec.get("topic", ""),
            "artifact_type": rec.get("artifact_type", "curricular_generated_answer"),
            "approved": bool(rec.get("approved", True)),
            "metadata": rec.get("metadata", {}),
        }

        try:
            r = requests.post(base + "/memory/upsert", json=payload, timeout=180)
            if r.ok and r.json().get("ok"):
                ok += 1
            else:
                fail += 1
                print("FAIL", i, r.status_code, r.text[:300])
        except Exception as exc:
            fail += 1
            print("EXC", i, exc)

        if i % 50 == 0:
            print(f"Progreso {i}: ok={ok} fail={fail}")

print({"ok": ok, "fail": fail})

print("\n==> Prueba de búsqueda:")
for q in [
    "Cómo distribuir créditos en una malla de 10 ciclos",
    "Sugiere actividades para un curso de investigación",
    "Qué verbos usar en resultados de aprendizaje",
    "Cómo alinear el perfil de egreso con los cursos",
    "Crea una rúbrica de evaluación",
    "lectura guiada",
    "caso práctico",
]:
    r = requests.post(base + "/memory/search", json={"query": q, "collection": "jomelai_memory", "n_results": 3}, timeout=60)
    print("\nQUERY:", q)
    print(json.dumps(r.json(), ensure_ascii=False, indent=2)[:1800])
PY

echo "==> Importación terminada."
