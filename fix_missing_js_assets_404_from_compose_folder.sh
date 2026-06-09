#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"

echo "=================================================="
echo " Fix missing JS assets 404 from compose folder"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: este script debe ejecutarse desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

BACKUP_DIR="backups/fix_missing_js_assets_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
mkdir -p public

echo "BACKUP_DIR=$BACKUP_DIR"

create_or_update_asset() {
  local file="$1"
  local content="$2"

  if [ -f "public/$file" ] && [ -s "public/$file" ]; then
    echo "existe: public/$file"
  else
    printf "%s\n" "$content" > "public/$file"
    echo "creado: public/$file"
  fi

  cp "public/$file" "./$file"
  echo "sincronizado en raiz: ./$file"
}

echo
echo "== 1) Creando assets faltantes en public/ y raiz =="

create_or_update_asset "jomelai-syllabus-pretty-v7-live.js" '
(function () {
  console.log("[JoMelAi] jomelai-syllabus-pretty-v7-live shim activo");
  window.JOMELAI_SYLLABUS_PRETTY_READY = true;
})();
'

create_or_update_asset "chat-lateral-v2-client.js" '
(function () {
  console.log("[JoMelAi] chat-lateral-v2-client shim activo");
  window.JOMELAI_CHAT_LATERAL_READY = true;
})();
'

create_or_update_asset "chat-panel-renderer-final.js" '
(function () {
  console.log("[JoMelAi] chat-panel-renderer-final shim activo");
  window.JOMELAI_CHAT_PANEL_RENDERER_READY = true;
})();
'

create_or_update_asset "chat-pie-image-override.js" '
(function () {
  console.log("[JoMelAi] chat-pie-image-override shim activo");
  window.JOMELAI_CHAT_PIE_OVERRIDE_READY = true;
})();
'

if [ ! -f "public/jomelai-syllabus-format-renderer.js" ]; then
  cat > public/jomelai-syllabus-format-renderer.js <<'JS'
(function () {
  console.log("[JoMelAi] Syllabus format renderer shim activo");
  window.JOMELAI_SYLLABUS_FORMAT_RENDERER_READY = true;
})();
JS
  echo "creado: public/jomelai-syllabus-format-renderer.js"
fi

cp public/jomelai-syllabus-format-renderer.js ./jomelai-syllabus-format-renderer.js

echo
echo "== 2) Parchando index.html locales si existen =="

patch_index_file() {
  local idx="$1"

  [ -f "$idx" ] || return 0

  echo "parchando: $idx"

  mkdir -p "$BACKUP_DIR/$(dirname "$idx")"
  cp "$idx" "$BACKUP_DIR/$idx.bak" 2>/dev/null || true

  python3 - "$idx" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

scripts = [
    "jomelai-syllabus-pretty-v7-live.js",
    "chat-lateral-v2-client.js",
    "chat-panel-renderer-final.js",
    "chat-pie-image-override.js",
    "jomelai-syllabus-format-renderer.js",
]

for s in scripts:
    text = re.sub(
        r'\s*<script[^>]+src=["\']/{}(?:\?[^"\']*)?["\'][^>]*></script>'.format(re.escape(s)),
        '',
        text,
        flags=re.I,
    )

tags = "\n".join(
    '  <script src="/{}?v=fix404"></script>'.format(s)
    for s in scripts
)

if "</body>" in text:
    text = text.replace("</body>", tags + "\n</body>", 1)
elif "</head>" in text:
    text = text.replace("</head>", tags + "\n</head>", 1)
else:
    text += "\n" + tags + "\n"

p.write_text(text, encoding="utf-8")
PY
}

patch_index_file "index.html"
patch_index_file "public/index.html"
patch_index_file "dist/index.html"
patch_index_file "build/index.html"

echo
echo "== 3) Detectando contenedor frontend desde docker compose =="

FRONT_CONTAINER=""

for svc in frontend front web nginx app client; do
  cid="$(docker compose ps -q "$svc" 2>/dev/null | head -1 || true)"
  if [ -n "$cid" ]; then
    name="$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
    if [ -n "$name" ]; then
      FRONT_CONTAINER="$name"
      break
    fi
  fi
done

if [ -z "$FRONT_CONTAINER" ]; then
  FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
    | grep -Ei '3000|frontend|nginx|web|vite|node' \
    | grep -vi 'data_engine' \
    | grep -vi 'ollama' \
    | head -1 \
    | awk '{print $1}' || true)"
fi

if [ -z "$FRONT_CONTAINER" ]; then
  echo "WARN: no detecte contenedor frontend. Los archivos ya quedaron en public/ y raiz."
else
  echo "FRONT_CONTAINER=$FRONT_CONTAINER"

  FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    if command -v nginx >/dev/null 2>&1; then
      nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
    fi
  ' || true)"

  if [ -z "$FRONT_ROOT" ]; then
    FRONT_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
      for d in /usr/share/nginx/html /app/dist /app/build /app/public /var/www/html /app; do
        [ -d "$d" ] && echo "$d" && exit 0
      done
      echo /usr/share/nginx/html
    ' || true)"
  fi

  echo "FRONT_ROOT=$FRONT_ROOT"

  echo
  echo "== 4) Copiando JS faltantes al root servido por el frontend =="

  for f in \
    jomelai-syllabus-pretty-v7-live.js \
    chat-lateral-v2-client.js \
    chat-panel-renderer-final.js \
    chat-pie-image-override.js \
    jomelai-syllabus-format-renderer.js
  do
    docker cp "public/$f" "$FRONT_CONTAINER:$FRONT_ROOT/$f"
    echo "copiado: $FRONT_ROOT/$f"
  done

  echo
  echo "== 5) Parchando index.html activo dentro del contenedor =="

  INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
    for f in '$FRONT_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html /app/index.html; do
      [ -f \"\$f\" ] && echo \"\$f\" && exit 0
    done
    exit 0
  " || true)"

  if [ -n "$INDEX_FILE" ]; then
    echo "INDEX_FILE=$INDEX_FILE"

    docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.container.bak.html"
    cp "$BACKUP_DIR/index.container.bak.html" "$BACKUP_DIR/index.container.patched.html"

    python3 - "$BACKUP_DIR/index.container.patched.html" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

scripts = [
    "jomelai-syllabus-pretty-v7-live.js",
    "chat-lateral-v2-client.js",
    "chat-panel-renderer-final.js",
    "chat-pie-image-override.js",
    "jomelai-syllabus-format-renderer.js",
]

for s in scripts:
    text = re.sub(
        r'\s*<script[^>]+src=["\']/{}(?:\?[^"\']*)?["\'][^>]*></script>'.format(re.escape(s)),
        '',
        text,
        flags=re.I,
    )

tags = "\n".join(
    '  <script src="/{}?v=fix404"></script>'.format(s)
    for s in scripts
)

if "</body>" in text:
    text = text.replace("</body>", tags + "\n</body>", 1)
elif "</head>" in text:
    text = text.replace("</head>", tags + "\n</head>", 1)
else:
    text += "\n" + tags + "\n"

p.write_text(text, encoding="utf-8")
PY

    docker cp "$BACKUP_DIR/index.container.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

    docker exec "$FRONT_CONTAINER" sh -lc '
      if command -v nginx >/dev/null 2>&1; then
        nginx -t && nginx -s reload
      fi
    ' || true
  else
    echo "WARN: no encontre index.html dentro del contenedor."
  fi
fi

echo
echo "== 6) Verificacion HTTP =="

APP_PORT="$(grep -E '^APP_PORT=' .env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
APP_PORT="${APP_PORT:-3000}"

BASE_URL="http://localhost:${APP_PORT}"

for f in \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js \
  jomelai-syllabus-format-renderer.js
do
  echo
  echo "---- $BASE_URL/$f ----"
  curl -sS -I "$BASE_URL/$f?v=fix404" | head -5 || true
done

echo
echo "== 7) Git status =="
git status --short || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Archivos creados/sincronizados en:"
echo "  ./public/"
echo "  ./"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Ahora en el navegador haz:"
echo "  Ctrl + Shift + R"
echo
echo "Luego revisa que ya no aparezcan 404 para:"
echo "  /jomelai-syllabus-pretty-v7-live.js"
echo "  /chat-lateral-v2-client.js"
echo "  /chat-panel-renderer-final.js"
echo "  /chat-pie-image-override.js"
