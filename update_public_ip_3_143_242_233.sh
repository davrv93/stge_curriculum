#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Update JoMelAi public IP"
echo "=================================================="

NEW_IP="3.143.242.233"
NEW_BASE_URL="http://${NEW_IP}:3000"

OLD_IPS=(
  "3.143.242.233"
  "3.143.242.233"
)

BACKUP_DIR="backups/update_public_ip_${NEW_IP}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "NEW_IP=$NEW_IP"
echo "NEW_BASE_URL=$NEW_BASE_URL"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Actualizando .env =="
touch .env
cp .env "$BACKUP_DIR/.env.bak"

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s#^${key}=.*#${key}=${value}#g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "PUBLIC_IP" "$NEW_IP"
set_env "PUBLIC_BASE_URL" "$NEW_BASE_URL"
set_env "APP_URL" "$NEW_BASE_URL"
set_env "VITE_PUBLIC_BASE_URL" "$NEW_BASE_URL"
set_env "VITE_APP_URL" "$NEW_BASE_URL"
set_env "VITE_API_BASE_URL" "/api"
set_env "VITE_API_URL" "/api"
set_env "VITE_ASSISTANT_SYLLABUS_STREAM_URL" "/api/assistant/generate-syllabus-stream"
set_env "VITE_CHAT_LATERAL_STREAM_URL" "/api/chat-lateral/ask-stream"

for old in "${OLD_IPS[@]}"; do
  sed -i "s#http://${old}:3000#${NEW_BASE_URL}#g" .env
  sed -i "s#${old}:3000#${NEW_IP}:3000#g" .env
  sed -i "s#${old}#${NEW_IP}#g" .env
done

echo
echo "== 2) Reemplazando IP antigua en archivos de configuración/código =="
TARGET_FILES="$(find . \
  -type f \
  \( \
    -name '*.js' -o \
    -name '*.ts' -o \
    -name '*.html' -o \
    -name '*.php' -o \
    -name '*.env' -o \
    -name '.env' -o \
    -name '*.yml' -o \
    -name '*.yaml' -o \
    -name '*.json' -o \
    -name '*.conf' -o \
    -name '*.sh' \
  \) \
  ! -path './.git/*' \
  ! -path './node_modules/*' \
  ! -path './vendor/*' \
  ! -path './data/*' \
  ! -path './backups/*' \
  ! -name '*.bak*' \
  2>/dev/null || true)"

if [ -n "$TARGET_FILES" ]; then
  echo "$TARGET_FILES" | while read f; do
    [ -f "$f" ] || continue

    if grep -qE '18\.216\.120\.103|18\.191\.127\.254' "$f" 2>/dev/null; then
      safe_name="$(echo "$f" | sed 's#^\./##' | tr '/' '_')"
      cp "$f" "$BACKUP_DIR/${safe_name}.bak"

      for old in "${OLD_IPS[@]}"; do
        sed -i "s#http://${old}:3000#${NEW_BASE_URL}#g" "$f"
        sed -i "s#https://${old}:3000#${NEW_BASE_URL}#g" "$f"
        sed -i "s#${old}:3000#${NEW_IP}:3000#g" "$f"
        sed -i "s#${old}#${NEW_IP}#g" "$f"
      done

      echo "actualizado: $f"
    fi
  done
fi

echo
echo "== 3) Detectando frontend activo =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "WARN: no pude detectar frontend activo."
else
  echo "FRONT_CONTAINER=$FRONT_CONTAINER"

  CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
  if command -v nginx >/dev/null 2>&1; then
    nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
  fi
  ' || true)"

  if [ -z "$CONTAINER_ROOT" ]; then
    CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    for d in /usr/share/nginx/html /app/dist /app/build /app/public /app/frontend/dist /app/frontend/public; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /usr/share/nginx/html
    ' || true)"
  fi

  echo "CONTAINER_ROOT=$CONTAINER_ROOT"

  INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
  for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
    [ -f \"\$f\" ] && echo \"\$f\" && exit 0
  done
  exit 0
  " || true)"

  if [ -n "$INDEX_FILE" ]; then
    echo "INDEX_FILE=$INDEX_FILE"

    docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.active.original.html"

    cp "$BACKUP_DIR/index.active.original.html" "$BACKUP_DIR/index.active.patched.html"

    python3 - "$BACKUP_DIR/index.active.patched.html" "$NEW_IP" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
new_ip = sys.argv[2]
new_base = f"http://{new_ip}:3000"

text = p.read_text(encoding="utf-8")

old_ips = [
    "3.143.242.233",
    "3.143.242.233",
]

for old in old_ips:
    text = text.replace(f"http://{old}:3000", new_base)
    text = text.replace(f"https://{old}:3000", new_base)
    text = text.replace(f"{old}:3000", f"{new_ip}:3000")
    text = text.replace(old, new_ip)

p.write_text(text, encoding="utf-8")
PY

    docker cp "$BACKUP_DIR/index.active.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

    echo
    echo "== 4) Verificando index activo =="
    docker exec "$FRONT_CONTAINER" sh -lc "grep -nE '18\\.216\\.120\\.103|18\\.191\\.127\\.254|${NEW_IP}' '$INDEX_FILE' || true"
  fi

  echo
  echo "== 5) Recargando Nginx si aplica =="
  docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true
fi

echo
echo "== 6) Reiniciando servicios sin borrar volúmenes =="
docker compose up -d --build

sleep 5

echo
echo "== 7) Tests públicos =="
echo
echo "-- Frontend --"
curl -sS -I "${NEW_BASE_URL}/" | head -8 || true

echo
echo "-- Sílabo stream endpoint --"
curl -sS -I "${NEW_BASE_URL}/api/assistant/generate-syllabus-stream" | head -8 || true

echo
echo "-- Assets JS importantes --"
for f in \
  jomelai-syllabus-format-renderer.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js
do
  echo
  echo "---- $f ----"
  curl -sS -I "${NEW_BASE_URL}/$f?v=test" | head -5 || true
done

echo
echo "== 8) Búsqueda final de IP antigua =="
grep -R "3.143.242.233\|3.143.242.233" -n . \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude-dir=data \
  --exclude-dir=backups \
  2>/dev/null | head -40 || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Nueva URL pública:"
echo "  ${NEW_BASE_URL}"
echo
echo "Generador de sílabo:"
echo "  ${NEW_BASE_URL}/api/assistant/generate-syllabus-stream"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Ahora abre:"
echo "  ${NEW_BASE_URL}/#silabos"
echo
echo "Y haz hard refresh:"
echo "  Ctrl + Shift + R"
