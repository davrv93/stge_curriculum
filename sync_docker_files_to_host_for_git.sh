#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

EXPORT_DIR="_docker_runtime_export_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EXPORT_DIR"

echo "=================================================="
echo " Sync Docker runtime files to host"
echo "=================================================="
echo "EXPORT_DIR=$EXPORT_DIR"

copy_from_container() {
  local container="$1"
  local src="$2"
  local dest="$3"

  echo
  echo "== Copiando $container:$src -> $dest =="

  mkdir -p "$dest"

  docker exec "$container" sh -lc "[ -d '$src' ]" || {
    echo "WARN: no existe $src en $container"
    return 0
  }

  docker exec "$container" sh -lc "
    cd '$src' && tar \
      --exclude='./node_modules' \
      --exclude='./vendor' \
      --exclude='./storage/logs' \
      --exclude='./storage/framework/cache' \
      --exclude='./storage/framework/sessions' \
      --exclude='./storage/framework/views' \
      --exclude='./bootstrap/cache/*.php' \
      --exclude='./.git' \
      --exclude='./data' \
      --exclude='./datasets' \
      --exclude='./backups' \
      --exclude='./ollama' \
      --exclude='./models' \
      -cf - .
  " | tar -xf - -C "$dest"
}

echo
echo "== 1) Detectando contenedores =="

FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

BACKEND_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'backend|laravel|php|apache' \
  | head -1 \
  | awk '{print $1}' || true)"

DATA_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'data_engine|data-engine|python|uvicorn|fastapi' \
  | head -1 \
  | awk '{print $1}' || true)"

echo "FRONT_CONTAINER=${FRONT_CONTAINER:-NO_DETECTADO}"
echo "BACKEND_CONTAINER=${BACKEND_CONTAINER:-NO_DETECTADO}"
echo "DATA_CONTAINER=${DATA_CONTAINER:-NO_DETECTADO}"

echo
echo "== 2) Exportando frontend activo =="

if [ -n "${FRONT_CONTAINER:-}" ]; then
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

  copy_from_container "$FRONT_CONTAINER" "$FRONT_ROOT" "$EXPORT_DIR/frontend"

  echo
  echo "== 3) Sincronizando JS/HTML frontend al host public/ =="
  mkdir -p public

  # Copia assets puntuales que hemos ido inyectando/parchando.
  for f in \
    index.html \
    jomelai-syllabus-model-sync.js \
    jomelai-syllabus-format-renderer.js \
    jomelai-syllabus-pretty-v7-live.js \
    chat-lateral-v2-client.js \
    chat-panel-renderer-final.js \
    chat-pie-image-override.js
  do
    if [ -f "$EXPORT_DIR/frontend/$f" ]; then
      cp "$EXPORT_DIR/frontend/$f" "public/$f"
      echo "copiado a host: public/$f"
    fi
  done
else
  echo "WARN: no se detecto frontend."
fi

echo
echo "== 4) Exportando backend si existe =="

if [ -n "${BACKEND_CONTAINER:-}" ]; then
  BACKEND_ROOT="$(docker exec "$BACKEND_CONTAINER" sh -lc '
    for d in /var/www/html /app /srv/app /var/www; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /app
  ' || true)"

  echo "BACKEND_ROOT=$BACKEND_ROOT"
  copy_from_container "$BACKEND_CONTAINER" "$BACKEND_ROOT" "$EXPORT_DIR/backend"
else
  echo "WARN: no se detecto backend."
fi

echo
echo "== 5) Exportando data-engine si existe =="

if [ -n "${DATA_CONTAINER:-}" ]; then
  DATA_ROOT="$(docker exec "$DATA_CONTAINER" sh -lc '
    for d in /app /srv/app /workspace; do
      [ -d "$d" ] && echo "$d" && exit 0
    done
    echo /app
  ' || true)"

  echo "DATA_ROOT=$DATA_ROOT"
  copy_from_container "$DATA_CONTAINER" "$DATA_ROOT" "$EXPORT_DIR/data-engine"
else
  echo "WARN: no se detecto data-engine."
fi

echo
echo "== 6) Resumen de archivos exportados =="
find "$EXPORT_DIR" -maxdepth 3 -type f | sed -n '1,120p'

echo
echo "== 7) Estado Git =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Export runtime:"
echo "  $EXPORT_DIR"
echo
echo "Archivos frontend sincronizados al host:"
echo "  public/"
echo
echo "Revisa cambios:"
echo "  git status"
echo "  git diff -- public"
echo
echo "Para agregar al Git:"
echo "  git add public"
echo
echo "No agregues modelos, data, backups ni export pesado si no corresponde."
