#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="/home/ubuntu/jomelai"
cd "$PROJECT_ROOT"

echo "=================================================="
echo " Sync Docker runtime files directly to project root"
echo "=================================================="

BACKUP_DIR="backups/sync_docker_to_root_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Detectando frontend activo =="

FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no detecté contenedor frontend."
  docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Image}}'
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
  if command -v nginx >/dev/null 2>&1; then
    nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
  fi
' || true)"

if [ -z "$FRONT_ROOT" ]; then
  FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    for d in /usr/share/nginx/html /app/dist /app/build /app/public /var/www/html; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /usr/share/nginx/html
  ' || true)"
fi

echo "FRONT_ROOT=$FRONT_ROOT"

echo
echo "== 2) Haciendo backup de public/ actual =="
if [ -d public ]; then
  mkdir -p "$BACKUP_DIR/public_before"
  tar \
    --exclude='node_modules' \
    --exclude='.git' \
    -cf - public | tar -xf - -C "$BACKUP_DIR/public_before"
fi

echo
echo "== 3) Copiando frontend runtime a public/ del proyecto =="

mkdir -p public

docker exec "$FRONT_CONTAINER" sh -lc "
  cd '$FRONT_ROOT' && tar \
    --exclude='./node_modules' \
    --exclude='./.git' \
    --exclude='./data' \
    --exclude='./datasets' \
    --exclude='./models' \
    --exclude='./ollama' \
    --exclude='./backups' \
    --exclude='./*.map' \
    -cf - .
" | tar -xf - -C public

echo "Frontend runtime copiado a:"
echo "  $PROJECT_ROOT/public"

echo
echo "== 4) Sincronizando assets importantes también en raíz si existen =="

for f in \
  jomelai-syllabus-model-sync.js \
  jomelai-syllabus-format-renderer.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  if [ -f "public/$f" ]; then
    cp "public/$f" "./$f"
    echo "copiado a raíz: ./$f"
  fi
done

if [ -f "public/index.html" ]; then
  cp "public/index.html" "./index.html"
  echo "copiado a raíz: ./index.html"
fi

echo
echo "== 5) Detectando backend y data-engine para copiar cambios puntuales =="

BACKEND_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'backend|laravel|php|apache' \
  | head -1 \
  | awk '{print $1}' || true)"

DATA_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'data_engine|data-engine|python|uvicorn|fastapi' \
  | head -1 \
  | awk '{print $1}' || true)"

echo "BACKEND_CONTAINER=${BACKEND_CONTAINER:-NO_DETECTADO}"
echo "DATA_CONTAINER=${DATA_CONTAINER:-NO_DETECTADO}"

if [ -n "${BACKEND_CONTAINER:-}" ]; then
  echo
  echo "== 6) Exportando PHP runtime del backend a _runtime_backend_tmp =="

  TMP_BACKEND="_runtime_backend_tmp"
  rm -rf "$TMP_BACKEND"
  mkdir -p "$TMP_BACKEND"

  BACKEND_ROOT="$(docker exec "$BACKEND_CONTAINER" sh -lc '
    for d in /var/www/html /app /srv/app /var/www; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /app
  ' || true)"

  echo "BACKEND_ROOT=$BACKEND_ROOT"

  docker exec "$BACKEND_CONTAINER" sh -lc "
    cd '$BACKEND_ROOT' && tar \
      --exclude='./vendor' \
      --exclude='./node_modules' \
      --exclude='./storage/logs' \
      --exclude='./storage/framework/cache' \
      --exclude='./storage/framework/sessions' \
      --exclude='./storage/framework/views' \
      --exclude='./bootstrap/cache/*.php' \
      --exclude='./.git' \
      --exclude='./data' \
      --exclude='./datasets' \
      --exclude='./backups' \
      -cf - .
  " | tar -xf - -C "$TMP_BACKEND"

  echo
  echo "Copiando solo archivos PHP/JS/HTML/CONF del backend a la raíz, preservando estructura..."
  find "$TMP_BACKEND" -type f \
    \( -name '*.php' -o -name '*.js' -o -name '*.html' -o -name '*.conf' -o -name '*.json' -o -name '*.env.example' \) \
    | while read src; do
        rel="${src#$TMP_BACKEND/}"

        # Evitar pisar .env real.
        if [ "$rel" = ".env" ]; then
          continue
        fi

        mkdir -p "$(dirname "$rel")"

        if [ -f "$rel" ]; then
          mkdir -p "$BACKUP_DIR/root_before/$(dirname "$rel")"
          cp "$rel" "$BACKUP_DIR/root_before/$rel" || true
        fi

        cp "$src" "$rel"
        echo "backend -> raíz: $rel"
      done

  rm -rf "$TMP_BACKEND"
fi

if [ -n "${DATA_CONTAINER:-}" ]; then
  echo
  echo "== 7) Exportando data-engine runtime a la raíz, preservando estructura =="

  TMP_DATA="_runtime_data_engine_tmp"
  rm -rf "$TMP_DATA"
  mkdir -p "$TMP_DATA"

  DATA_ROOT="$(docker exec "$DATA_CONTAINER" sh -lc '
    for d in /app /srv/app /workspace; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /app
  ' || true)"

  echo "DATA_ROOT=$DATA_ROOT"

  docker exec "$DATA_CONTAINER" sh -lc "
    cd '$DATA_ROOT' && tar \
      --exclude='./__pycache__' \
      --exclude='./.pytest_cache' \
      --exclude='./venv' \
      --exclude='./.venv' \
      --exclude='./node_modules' \
      --exclude='./data' \
      --exclude='./datasets' \
      --exclude='./models' \
      --exclude='./backups' \
      --exclude='./.git' \
      -cf - .
  " | tar -xf - -C "$TMP_DATA"

  find "$TMP_DATA" -type f \
    \( -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.json' -o -name '*.yml' -o -name '*.yaml' -o -name '*.txt' \) \
    | while read src; do
        rel="${src#$TMP_DATA/}"

        mkdir -p "$(dirname "$rel")"

        if [ -f "$rel" ]; then
          mkdir -p "$BACKUP_DIR/root_before/$(dirname "$rel")"
          cp "$rel" "$BACKUP_DIR/root_before/$rel" || true
        fi

        cp "$src" "$rel"
        echo "data-engine -> raíz: $rel"
      done

  rm -rf "$TMP_DATA"
fi

echo
echo "== 8) Limpiando basura que no debe ir a Git =="
find . -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true

echo
echo "== 9) Estado Git =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Los archivos quedaron directamente en:"
echo "  $PROJECT_ROOT"
echo
echo "Backup antes de sobrescribir:"
echo "  $BACKUP_DIR"
echo
echo "Revisa:"
echo "  git status"
echo "  git diff --stat"
echo
echo "Para agregar:"
echo "  git add ."
echo
echo "Antes de commit revisa que NO entren:"
echo "  .env"
echo "  backups/"
echo "  data/"
echo "  datasets/"
echo "  ollama/"
echo "  models/"
