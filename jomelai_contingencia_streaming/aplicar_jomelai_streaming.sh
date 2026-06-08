#!/usr/bin/env bash
set -eu

FRONTEND_CONTAINER="${FRONTEND_CONTAINER:-jomelai_frontend}"
LOCAL_JS="${LOCAL_JS:-jomelai_contingencia_streaming/jomelai-stream-pretty-full.js}"

if [ ! -f "$LOCAL_JS" ]; then
  echo "ERROR: no existe $LOCAL_JS"
  exit 1
fi

echo "=== Copiando JS al contenedor $FRONTEND_CONTAINER ==="
docker cp "$LOCAL_JS" "$FRONTEND_CONTAINER:/tmp/jomelai-stream-pretty-full.js"

echo "=== Instalando JS en el frontend ==="
docker exec -i "$FRONTEND_CONTAINER" sh <<'IN'
set -eu

DIR=""

for d in /usr/share/nginx/html /app/dist /app/public; do
  if [ -f "$d/index.html" ]; then DIR="$d"; break; fi
done

if [ -z "$DIR" ]; then
  echo "ERROR: no encontre index.html en el contenedor"
  exit 1
fi

cd "$DIR"

cp index.html "index.html.bak.contingency_streaming.$(date +%Y%m%d%H%M%S)"

if [ -f app.js ]; then
  cp app.js "app.js.bak.before_contingency_streaming.$(date +%Y%m%d%H%M%S)"
fi

cp /tmp/jomelai-stream-pretty-full.js "$DIR/jomelai-stream-pretty-full.js"

# Quitar scripts experimentales o anteriores para evitar competencia.
sed -i '/jomelai-ask-stream-ui.js/d' index.html
sed -i '/jomelai-stream-pretty-full.js/d' index.html
sed -i '/jomelai-chat-force-continue.js/d' index.html
sed -i '/jomelai-chat-continue-ui.js/d' index.html
sed -i '/jomelai-continue-format-stable.js/d' index.html
sed -i '/jomelai-continue-lock-dedupe.js/d' index.html
sed -i '/jomelai-final-continue-manager.js/d' index.html
sed -i '/jomelai-chat-resource-continue-v2.js/d' index.html
sed -i '/jomelai-chat-resource-continue-v3.js/d' index.html

STAMP="$(date +%s)"

if grep -q '</body>' index.html; then
  sed -i "s#</body>#<script src=\"/jomelai-stream-pretty-full.js?v=$STAMP\"></script>\n</body>#" index.html
else
  echo "<script src=\"/jomelai-stream-pretty-full.js?v=$STAMP\"></script>" >> index.html
fi

nginx -t
nginx -s reload 2>/dev/null || true

echo "OK instalado en $DIR"
grep -n "jomelai-stream-pretty-full.js" index.html || true
IN

echo "=== Reiniciando frontend ==="
docker compose restart frontend 2>/dev/null || docker restart "$FRONTEND_CONTAINER"

echo ""
echo "Listo. Recarga el navegador con Ctrl+F5."
echo "Archivo local de contingencia: $LOCAL_JS"
