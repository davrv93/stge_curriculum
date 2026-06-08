#!/usr/bin/env bash
set -eu

FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-jomelai_frontend}"
HOST_WEB_DIR="${HOST_WEB_DIR:-./frontend}"
STAMP="$(date +%s)"

if [ ! -f "$HOST_WEB_DIR/index.html" ]; then
  echo "ERROR: no existe $HOST_WEB_DIR/index.html"
  echo "Usa: HOST_WEB_DIR=/ruta/a/frontend bash reparar_inyeccion_silabo_pretty_v5.sh"
  exit 1
fi

if [ ! -f "$HOST_WEB_DIR/jomelai-syllabus-pretty-v5.js" ]; then
  echo "ERROR: no existe $HOST_WEB_DIR/jomelai-syllabus-pretty-v5.js"
  echo "Primero verifica si el instalador anterior llegó a crear el archivo."
  exit 1
fi

echo "=== Backup index.html host ==="
cp "$HOST_WEB_DIR/index.html" "$HOST_WEB_DIR/index.html.bak.fix_sed_v5_$(date +%Y%m%d%H%M%S)"

echo "=== Limpiar inyecciones previas sin sed -i ==="
awk '
  index($0, "jomelai-syllabus-full-structure.js") == 0 &&
  index($0, "jomelai-syllabus-pretty-v5.js") == 0
' "$HOST_WEB_DIR/index.html" > "$HOST_WEB_DIR/index.html.tmp"

mv "$HOST_WEB_DIR/index.html.tmp" "$HOST_WEB_DIR/index.html"

echo "=== Inyectar jomelai-syllabus-pretty-v5.js en host ==="

awk -v stamp="$STAMP" '
  index($0, "<script src=\"/tech-routes.js\"></script>") {
    print $0
    print "    <script src=\"/jomelai-syllabus-pretty-v5.js?v=" stamp "\"></script>"
    next
  }
  index($0, "</body>") {
    print "    <script src=\"/jomelai-syllabus-pretty-v5.js?v=" stamp "\"></script>"
    print $0
    next
  }
  { print $0 }
' "$HOST_WEB_DIR/index.html" > "$HOST_WEB_DIR/index.html.tmp"

mv "$HOST_WEB_DIR/index.html.tmp" "$HOST_WEB_DIR/index.html"

echo "=== Copiar al Docker si el contenedor existe ==="

if docker ps --format '{{.Names}}' | grep -q "^${FRONTEND_CONTAINER}$"; then
  docker cp "$HOST_WEB_DIR/index.html" "$FRONTEND_CONTAINER:/tmp/index.html.fixed_v5"
  docker cp "$HOST_WEB_DIR/jomelai-syllabus-pretty-v5.js" "$FRONTEND_CONTAINER:/tmp/jomelai-syllabus-pretty-v5.js"

  docker exec -i "$FRONTEND_CONTAINER" sh <<'IN'
set -eu

DIR=""

for d in /usr/share/nginx/html /app/dist /app/public; do
  if [ -f "$d/index.html" ]; then DIR="$d"; break; fi
done

if [ -z "$DIR" ]; then
  echo "ERROR: no encontre index.html en contenedor"
  exit 1
fi

cd "$DIR"

cp index.html "index.html.bak.fix_sed_v5.$(date +%Y%m%d%H%M%S)"
cp /tmp/index.html.fixed_v5 "$DIR/index.html"
cp /tmp/jomelai-syllabus-pretty-v5.js "$DIR/jomelai-syllabus-pretty-v5.js"

nginx -t
nginx -s reload 2>/dev/null || true

echo "OK actualizado en contenedor: $DIR"
grep -n "jomelai-syllabus-pretty-v5" index.html || true
IN

  docker compose restart frontend 2>/dev/null || docker restart "$FRONTEND_CONTAINER"
else
  echo "AVISO: $FRONTEND_CONTAINER no está corriendo. Solo se actualizó el host."
fi

echo ""
echo "=== Verificación host ==="
grep -n "jomelai-syllabus-pretty-v5" "$HOST_WEB_DIR/index.html" || true

echo ""
echo "Listo. Recarga con Ctrl+F5."
