#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TARGET_MODEL="${1:-llama3.2:1b}"

echo "=================================================="
echo " Resume dynamic syllabus fix after sed error"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "TARGET_MODEL=$TARGET_MODEL"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/resume_dynamic_syllabus_after_sed_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Buscando PHP real, excluyendo exports/backups =="

PHP_FILE="${PHP_FILE_OVERRIDE:-}"

if [ -z "$PHP_FILE" ]; then
  PHP_FILE="$(find . \
    -type f \
    -name '*.php' \
    ! -path './.git/*' \
    ! -path './vendor/*' \
    ! -path './node_modules/*' \
    ! -path './backups/*' \
    ! -path './data/*' \
    ! -path './datasets/*' \
    ! -path './sync_docker_to_host_*/*' \
    ! -path './_docker_runtime_export*/*' \
    ! -path './_runtime_*/*' \
    -exec grep -l "function jm_handle_syllabus_stream" {} \; \
    2>/dev/null | head -1 || true)"
fi

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontre el PHP real con jm_handle_syllabus_stream."
  echo "Puedes forzar:"
  echo "  PHP_FILE_OVERRIDE=./public/jomelai_stream_routes.php ./resume_dynamic_syllabus_after_sed_error.sh"
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"

if echo "$PHP_FILE" | grep -qE 'sync_docker_to_host_|_docker_runtime_export|backups/'; then
  echo "ERROR: el PHP detectado parece export/backup:"
  echo "  $PHP_FILE"
  echo "Usa PHP_FILE_OVERRIDE con la ruta real."
  exit 1
fi

echo
echo "== 2) Verificando que el patch dinamico quedo aplicado =="

grep -n "semantic_discipline_inference_no_static_rules\|INFERENCIA DISCIPLINAR DINAMICA\|jm_dyn_syl_" "$PHP_FILE" | head -30 || true

if grep -q "strpos(\$courseLower" "$PHP_FILE" 2>/dev/null; then
  echo "ERROR: aun existe logica estatica tipo strpos(\$courseLower)."
  echo "Vuelve a ejecutar el script V2 corregido o fuerza PHP_FILE_OVERRIDE."
  exit 1
fi

echo "OK: no se detecto strpos(\$courseLower)."

echo
echo "== 3) Validando PHP =="

if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host; se validara en contenedor/runtime."
fi

echo
echo "== 4) Actualizando .env de forma portable sin sed -i =="

touch .env
cp .env "$BACKUP_DIR/.env.bak"

python3 - "$TARGET_MODEL" <<'PY'
from pathlib import Path
import sys

target_model = sys.argv[1]
env_path = Path(".env")

updates = {
    "SYLLABUS_OLLAMA_MODEL": target_model,
    "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE": "0",
    "SYLLABUS_QUALITY_REPAIR": "1",
    "SYLLABUS_NUM_CTX": "4096",
    "SYLLABUS_NUM_PREDICT": "3200",
    "SYLLABUS_TEMPERATURE": "0.34",
    "SYLLABUS_TOP_P": "0.90",
    "SYLLABUS_NUM_THREAD": "2",
    "SYLLABUS_KEEP_ALIVE": "30m",
}

lines = []
if env_path.exists():
    lines = env_path.read_text(encoding="utf-8", errors="ignore").splitlines()

seen = set()
out = []

for line in lines:
    raw = line.strip()

    if not raw or raw.startswith("#") or "=" not in line:
        out.append(line)
        continue

    key = line.split("=", 1)[0].strip()

    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)

for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")

env_path.write_text("\n".join(out) + "\n", encoding="utf-8")

print("ENV actualizado:")
for key in updates:
    print(f"  {key}={updates[key]}")
PY

echo
echo "== 5) Copiando .env junto al PHP si aplica =="

PHP_DIR="$(dirname "$PHP_FILE")"

if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
  echo "copiado: $PHP_DIR/.env"
fi

echo
echo "== 6) Rebuild/restart sin borrar volumenes =="

docker compose up -d --build

sleep 6

echo
echo "== 7) Verificacion rapida =="

APP_PORT="$(python3 - <<'PY'
from pathlib import Path
p = Path(".env")
port = "3000"
if p.exists():
    for line in p.read_text(errors="ignore").splitlines():
        if line.startswith("APP_PORT="):
            port = line.split("=", 1)[1].strip() or "3000"
print(port)
PY
)"

echo "APP_PORT=$APP_PORT"

curl -sS -N -m 180 -X POST "http://localhost:${APP_PORT}/api/assistant/generate-syllabus-stream" \
  -H "Content-Type: application/json" \
  -d '{
    "course": "Cálculo Diferencial",
    "program": "Ingeniería de Sistemas",
    "credits": "4",
    "cycle": "3",
    "weeks": "16",
    "modality": "Presencial",
    "graduate_profile": "Analiza problemas de ingeniería, modela situaciones reales y toma decisiones sustentadas con razonamiento matemático y tecnológico.",
    "competency": "Aplica conceptos matemáticos para modelar, analizar y resolver problemas de cambio, variación y optimización en contextos de ingeniería.",
    "start_date": "",
    "sessions_per_week": "1"
  }' | grep -E "model_resolved|config|quality_repair|semantic_discipline|contenido real|resultado de aprendizaje real|tema real|Juan|teoria de los numeros|teoría de los números|deriv|limite|límite|funcion|función|optimiz" | head -100 || true

echo
echo "== 8) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Si todo esta bien, en el stream debe aparecer:"
echo "  strategy: semantic_discipline_inference_no_static_rules"
echo
echo "Y no debe aparecer:"
echo "  contenido real"
echo "  resultado de aprendizaje real"
echo "  tema real"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
