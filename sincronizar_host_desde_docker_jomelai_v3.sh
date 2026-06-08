#!/usr/bin/env bash
set -eu

FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-jomelai_frontend}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-jomelai_backend}"

# Si el detector encuentra varias rutas, ejecuta indicando:
# HOST_FRONTEND_DIR=./frontend
# HOST_BACKEND_PUBLIC_DIR=./backend/public
HOST_FRONTEND_DIR="${HOST_FRONTEND_DIR:-}"
HOST_BACKEND_PUBLIC_DIR="${HOST_BACKEND_PUBLIC_DIR:-}"

STAMP="$(date +%Y%m%d_%H%M%S)"
WORK_DIR="sync_docker_to_host_$STAMP"

mkdir -p "$WORK_DIR/docker_frontend" "$WORK_DIR/docker_backend_public" "$WORK_DIR/backups"

echo "============================================================"
echo " SINCRONIZAR HOST DESDE DOCKER - JoMelAi v3"
echo "============================================================"
echo "Frontend container: $FRONTEND_CONTAINER"
echo "Backend container:  $BACKEND_CONTAINER"
echo "Work dir:           $WORK_DIR"
echo ""

echo "=== 1. Detectar rutas reales dentro de Docker ==="

DOCKER_FRONT_DIR="$(docker exec "$FRONTEND_CONTAINER" sh -c '
for d in /usr/share/nginx/html /app/dist /app/public; do
  if [ -f "$d/index.html" ]; then echo "$d"; exit 0; fi
done
exit 1
')"

DOCKER_BACK_PUBLIC_DIR="$(docker exec "$BACKEND_CONTAINER" sh -c '
for d in /var/www/app/public /var/www/html/public /app/public /srv/app/public /usr/src/app/public /var/www/html; do
  if [ -f "$d/index.php" ]; then echo "$d"; exit 0; fi
done
exit 1
')"

echo "Docker frontend dir:       $DOCKER_FRONT_DIR"
echo "Docker backend public dir: $DOCKER_BACK_PUBLIC_DIR"
echo ""

echo "=== 2. Rescatar archivos actuales desde Docker ==="

docker cp "$FRONTEND_CONTAINER:$DOCKER_FRONT_DIR/." "$WORK_DIR/docker_frontend/"
docker cp "$BACKEND_CONTAINER:$DOCKER_BACK_PUBLIC_DIR/." "$WORK_DIR/docker_backend_public/"

echo "Frontend rescatado:"
find "$WORK_DIR/docker_frontend" -maxdepth 1 -type f | sed 's#^#  - #'

echo ""
echo "Backend public rescatado:"
find "$WORK_DIR/docker_backend_public" -maxdepth 1 -type f | sed 's#^#  - #'
echo ""

echo "=== 3. Detectar rutas del host ==="

if [ -z "$HOST_FRONTEND_DIR" ]; then
  FRONT_CANDIDATES="$(find . \
    -path './node_modules' -prune -o \
    -path './vendor' -prune -o \
    -path './sync_docker_to_host_*' -prune -o \
    -path './rescate_*' -prune -o \
    -path './.git' -prune -o \
    -type f -name 'index.html' -print | sed 's#/index.html$##' | sort -u)"

  COUNT_FRONT="$(printf "%s\n" "$FRONT_CANDIDATES" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [ "$COUNT_FRONT" = "1" ]; then
    HOST_FRONTEND_DIR="$FRONT_CANDIDATES"
  else
    echo "ERROR: encontré varias o ninguna carpeta frontend con index.html."
    echo ""
    echo "Candidatas:"
    printf "%s\n" "$FRONT_CANDIDATES" | sed 's#^#  - #'
    echo ""
    echo "Ejecuta indicando la ruta exacta, ejemplo:"
    echo "HOST_FRONTEND_DIR=./frontend HOST_BACKEND_PUBLIC_DIR=./backend/public bash sincronizar_host_desde_docker_jomelai_v3.sh"
    exit 1
  fi
fi

if [ -z "$HOST_BACKEND_PUBLIC_DIR" ]; then
  BACK_CANDIDATES="$(find . \
    -path './node_modules' -prune -o \
    -path './vendor' -prune -o \
    -path './sync_docker_to_host_*' -prune -o \
    -path './rescate_*' -prune -o \
    -path './.git' -prune -o \
    -type f -path '*/public/index.php' -print | sed 's#/index.php$##' | sort -u)"

  COUNT_BACK="$(printf "%s\n" "$BACK_CANDIDATES" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [ "$COUNT_BACK" = "1" ]; then
    HOST_BACKEND_PUBLIC_DIR="$BACK_CANDIDATES"
  else
    echo "ERROR: encontré varias o ninguna carpeta backend public con index.php."
    echo ""
    echo "Candidatas:"
    printf "%s\n" "$BACK_CANDIDATES" | sed 's#^#  - #'
    echo ""
    echo "Ejecuta indicando la ruta exacta, ejemplo:"
    echo "HOST_FRONTEND_DIR=./frontend HOST_BACKEND_PUBLIC_DIR=./backend/public bash sincronizar_host_desde_docker_jomelai_v3.sh"
    exit 1
  fi
fi

if [ ! -f "$HOST_FRONTEND_DIR/index.html" ]; then
  echo "ERROR: no existe $HOST_FRONTEND_DIR/index.html"
  exit 1
fi

if [ ! -f "$HOST_BACKEND_PUBLIC_DIR/index.php" ]; then
  echo "ERROR: no existe $HOST_BACKEND_PUBLIC_DIR/index.php"
  exit 1
fi

echo "Host frontend dir:       $HOST_FRONTEND_DIR"
echo "Host backend public dir: $HOST_BACKEND_PUBLIC_DIR"
echo ""

echo "=== 4. Backup completo del host antes de sobrescribir ==="

tar -czf "$WORK_DIR/backups/host_frontend_backup_$STAMP.tgz" -C "$HOST_FRONTEND_DIR" .
tar -czf "$WORK_DIR/backups/host_backend_public_backup_$STAMP.tgz" -C "$HOST_BACKEND_PUBLIC_DIR" .

echo "Backup frontend: $WORK_DIR/backups/host_frontend_backup_$STAMP.tgz"
echo "Backup backend:  $WORK_DIR/backups/host_backend_public_backup_$STAMP.tgz"
echo ""

echo "=== 5. Copiar frontend Docker -> host ==="

find "$WORK_DIR/docker_frontend" -maxdepth 1 -type f \( \
  -name '*.html' -o \
  -name '*.js' -o \
  -name '*.css' -o \
  -name '*.svg' -o \
  -name '*.png' -o \
  -name '*.jpg' -o \
  -name '*.jpeg' -o \
  -name '*.webp' -o \
  -name '*.ico' \
\) -print | while read -r f; do
  base="$(basename "$f")"
  cp -f "$f" "$HOST_FRONTEND_DIR/$base"
  echo "  OK frontend: $base"
done

for dir in assets img images fonts js css; do
  if [ -d "$WORK_DIR/docker_frontend/$dir" ]; then
    rm -rf "$HOST_FRONTEND_DIR/$dir"
    cp -a "$WORK_DIR/docker_frontend/$dir" "$HOST_FRONTEND_DIR/$dir"
    echo "  OK frontend dir: $dir"
  fi
done

echo ""
echo "=== 6. Copiar backend public Docker -> host ==="

find "$WORK_DIR/docker_backend_public" -maxdepth 1 -type f \( \
  -name 'index.php' -o \
  -name '.htaccess' -o \
  -name 'jomelai*.php' \
\) -print | while read -r f; do
  base="$(basename "$f")"
  cp -f "$f" "$HOST_BACKEND_PUBLIC_DIR/$base"
  echo "  OK backend: $base"
done

echo ""
echo "=== 7. Validaciones rápidas ==="

echo "--- Scripts en index.html host ---"
grep -nE 'app\.js|tech-routes\.js|jomelai\.js|jomelai-index-bridge|jomelai-stream|jomelai-syllabus|jomelai-syllabus-pretty-v6' "$HOST_FRONTEND_DIR/index.html" || true

echo ""
echo "--- Backend rutas streaming host ---"
grep -nE 'jomelai_stream_routes|ask-stream|generate-syllabus-stream|jm_handle_syllabus_stream' "$HOST_BACKEND_PUBLIC_DIR/index.php" "$HOST_BACKEND_PUBLIC_DIR"/jomelai*.php 2>/dev/null || true

echo ""
echo "--- Archivos clave sincronizados ---"

for f in \
  "$HOST_FRONTEND_DIR/index.html" \
  "$HOST_FRONTEND_DIR/app.js" \
  "$HOST_FRONTEND_DIR/jomelai-syllabus-pretty-v6.js" \
  "$HOST_BACKEND_PUBLIC_DIR/index.php" \
  "$HOST_BACKEND_PUBLIC_DIR/jomelai_stream_routes.php"
do
  if [ -f "$f" ]; then
    echo "  OK existe: $f"
  else
    echo "  AVISO falta: $f"
  fi
done

echo ""
echo "--- PHP lint host si PHP existe localmente ---"
if command -v php >/dev/null 2>&1; then
  php -l "$HOST_BACKEND_PUBLIC_DIR/index.php"
  if [ -f "$HOST_BACKEND_PUBLIC_DIR/jomelai_stream_routes.php" ]; then
    php -l "$HOST_BACKEND_PUBLIC_DIR/jomelai_stream_routes.php"
  fi
else
  echo "PHP no está instalado en host. Omitiendo php -l."
fi

echo ""
echo "============================================================"
echo " SINCRONIZACIÓN TERMINADA"
echo "============================================================"
echo "Frontend host actualizado:       $HOST_FRONTEND_DIR"
echo "Backend public host actualizado: $HOST_BACKEND_PUBLIC_DIR"
echo ""
echo "Backups:"
echo "  $WORK_DIR/backups/host_frontend_backup_$STAMP.tgz"
echo "  $WORK_DIR/backups/host_backend_public_backup_$STAMP.tgz"
echo ""
echo "Recomendado ahora:"
echo "  docker compose restart frontend backend"
echo ""
echo "Si reconstruyes imágenes desde host:"
echo "  docker compose build frontend backend"
echo "  docker compose up -d frontend backend"
echo ""
