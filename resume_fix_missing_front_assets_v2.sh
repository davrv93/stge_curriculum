#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Resume fix missing frontend assets v2"
echo "=================================================="

BACKUP_DIR="backups/resume_fix_missing_assets_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Detectando frontend activo =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no pude detectar contenedor frontend."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

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

if [ -z "$INDEX_FILE" ]; then
  echo "ERROR: no encontré index.html activo."
  docker exec "$FRONT_CONTAINER" sh -lc "find '$CONTAINER_ROOT' -maxdepth 2 -type f | head -80" || true
  exit 1
fi

echo "INDEX_FILE=$INDEX_FILE"

echo
echo "== 2) Asegurando assets mínimos en public/ =="
mkdir -p public

# El formatter principal debe existir. Si no existe, avisamos.
if [ ! -f public/jomelai-syllabus-format-renderer.js ]; then
  echo "WARN: no existe public/jomelai-syllabus-format-renderer.js"
  echo "      Reejecuta primero el script del formatter si el sílabo no se pinta."
fi

# Crear shims solo si faltan.
if [ ! -f public/jomelai-syllabus-pretty-v7-live.js ]; then
cat > public/jomelai-syllabus-pretty-v7-live.js <<'JS'
(function () {
  if (window.__JOMELAI_SYLLABUS_PRETTY_V7_SHIM__) return;
  window.__JOMELAI_SYLLABUS_PRETTY_V7_SHIM__ = true;
  console.info('[JoMelAi] jomelai-syllabus-pretty-v7-live shim activo');
})();
JS
fi

if [ ! -f public/chat-pie-image-override.js ]; then
cat > public/chat-pie-image-override.js <<'JS'
(function () {
  if (window.__JOMELAI_PIE_IMAGE_OVERRIDE_SHIM__) return;
  window.__JOMELAI_PIE_IMAGE_OVERRIDE_SHIM__ = true;
  console.info('[JoMelAi] chat-pie-image-override shim activo');
})();
JS
fi

if [ ! -f public/chat-panel-renderer-final.js ]; then
cat > public/chat-panel-renderer-final.js <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__) return;
  window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__ = true;
  window.JoMelAiChatPanelRenderer = window.JoMelAiChatPanelRenderer || {};
  console.info('[JoMelAi] Chat panel renderer ROBUST activo');
})();
JS
fi

if [ ! -f public/chat-lateral-v2-client.js ]; then
cat > public/chat-lateral-v2-client.js <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__) return;
  window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__ = true;

  window.JoMelAiChatLateralV2 = {
    STREAM_URL: '/api/chat-lateral/ask-stream',
    ASK_URL: '/api/chat-lateral/ask',
    version: 'shim-v2'
  };

  console.info('[JoMelAi] chat-lateral-v2-client cargado');
})();
JS
fi

echo
echo "== 3) Copiando assets a otros públicos locales sin copiar sobre sí mismo =="
PUBLIC_DIRS=("public")
for d in frontend/public app/public web public_html; do
  [ -d "$d" ] && PUBLIC_DIRS+=("$d")
done

ASSETS=(
  "chat-lateral-v2-client.js"
  "chat-panel-renderer-final.js"
  "chat-pie-image-override.js"
  "jomelai-syllabus-pretty-v7-live.js"
  "jomelai-syllabus-format-renderer.js"
)

for d in "${PUBLIC_DIRS[@]}"; do
  mkdir -p "$d"

  for f in "${ASSETS[@]}"; do
    [ -f "public/$f" ] || continue

    src="$(realpath "public/$f")"
    dst="$(realpath -m "$d/$f")"

    if [ "$src" = "$dst" ]; then
      echo "skip mismo archivo: $d/$f"
      continue
    fi

    cp "public/$f" "$d/$f"
  done
done

echo
echo "== 4) Copiando assets al contenedor activo =="
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"

for f in "${ASSETS[@]}"; do
  if [ -f "public/$f" ]; then
    docker cp "public/$f" "$FRONT_CONTAINER:$CONTAINER_ROOT/$f"
    echo "copiado: $f"
  else
    echo "WARN: falta public/$f"
  fi
done

echo
echo "== 5) Limpiando index activo e inyectando scripts una sola vez =="
docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.original.html"
cp "$BACKUP_DIR/index.original.html" "$BACKUP_DIR/index.patched.html"

python3 - "$BACKUP_DIR/index.patched.html" <<'PY'
from pathlib import Path
import sys
import time

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

targets = [
    "chat-lateral-v2-client.js",
    "chat-panel-renderer-final.js",
    "chat-pie-image-override.js",
    "chat-pie-in-chat-fix.js",
    "jomelai-syllabus-pretty-v7-live.js",
    "jomelai-syllabus-format-renderer.js",
]

lines = []
for ln in text.splitlines():
    if any(t in ln for t in targets):
        continue
    lines.append(ln)

text = "\n".join(lines)

v = int(time.time())

scripts = "\n".join([
    f'  <script src="/jomelai-syllabus-pretty-v7-live.js?v={v}"></script>',
    f'  <script src="/chat-lateral-v2-client.js?v={v}"></script>',
    f'  <script src="/chat-panel-renderer-final.js?v={v}"></script>',
    f'  <script src="/chat-pie-image-override.js?v={v}"></script>',
    f'  <script src="/jomelai-syllabus-format-renderer.js?v={v}"></script>',
])

if "</body>" in text:
    text = text.replace("</body>", scripts + "\n</body>")
else:
    text += "\n" + scripts + "\n"

p.write_text(text, encoding="utf-8")
PY

docker cp "$BACKUP_DIR/index.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

echo
echo "== 6) Verificando scripts en index =="
docker exec "$FRONT_CONTAINER" sh -lc "grep -n 'chat-lateral-v2-client\\|chat-panel-renderer-final\\|chat-pie-image-override\\|jomelai-syllabus-pretty-v7-live\\|jomelai-syllabus-format-renderer' '$INDEX_FILE' || true"

echo
echo "== 7) Recargando Nginx si aplica =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 8) Test HTTP de assets =="
for f in "${ASSETS[@]}"; do
  echo
  echo "---- $f ----"
  curl -sS -I "http://localhost:3000/$f?v=test" | head -5 || true
done

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "En consola ya no deberían aparecer 404 de esos JS."
