#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="backups/sync_runtime_to_host_clean_$TS"

echo "=================================================="
echo " Sync runtime Docker -> raiz del proyecto"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "BACKUP_DIR=$BACKUP_DIR"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
mkdir -p public

echo
echo "== 1) Contenedores activos =="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"

echo
echo "== 2) Detectando frontend =="

FRONT_CONTAINERS="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|frontend|front|nginx|web|vite|node' \
  | grep -vi 'ollama' \
  | grep -vi 'data_engine' \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINERS" ]; then
  echo "WARN: no detecte frontend container."
else
  echo "$FRONT_CONTAINERS"
fi

echo
echo "== 3) Detectando backend =="

BACKEND_CONTAINERS="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'backend|laravel|php|apache|api|server' \
  | grep -vi 'frontend' \
  | grep -vi 'front' \
  | awk '{print $1}' || true)"

if [ -z "$BACKEND_CONTAINERS" ]; then
  echo "WARN: no detecte backend container."
else
  echo "$BACKEND_CONTAINERS"
fi

ASSETS="jomelai-syllabus-institutional-v5.js
jomelai-syllabus-qwen-v4.js
jomelai-syllabus-stream-progress-v3.js
jomelai-syllabus-pretty-v7-live.js
chat-lateral-v2-client.js
chat-panel-renderer-final.js
chat-pie-image-override.js"

echo
echo "== 4) Copiando JS vivos del frontend Docker hacia host =="

if [ -n "$FRONT_CONTAINERS" ]; then
  echo "$FRONT_CONTAINERS" | while read -r C; do
    [ -n "$C" ] || continue

    echo
    echo "FRONT_CONTAINER=$C"

    ROOTS="$(docker exec "$C" sh -lc '
      for d in /usr/share/nginx/html /app/dist /app/build /app/public /app /var/www/html; do
        [ -d "$d" ] && echo "$d"
      done
    ' || true)"

    if [ -z "$ROOTS" ]; then
      ROOTS="/usr/share/nginx/html"
    fi

    echo "$ASSETS" | while read -r ASSET; do
      [ -n "$ASSET" ] || continue

      FOUND=""

      echo "$ROOTS" | while read -r R; do
        [ -n "$R" ] || continue
        if docker exec "$C" sh -lc "[ -f '$R/$ASSET' ]"; then
          echo "$R/$ASSET"
          break
        fi
      done > "$BACKUP_DIR/found_asset_path.tmp"

      FOUND="$(cat "$BACKUP_DIR/found_asset_path.tmp" || true)"

      if [ -z "$FOUND" ]; then
        echo "  WARN: no encontre $ASSET en $C"
        continue
      fi

      TMP="$BACKUP_DIR/runtime_${C}_${ASSET}"
      docker cp "$C:$FOUND" "$TMP"

      echo "  $C:$FOUND"

      for DEST in "public/$ASSET" "$ASSET"; do
        if [ -f "$DEST" ]; then
          mkdir -p "$BACKUP_DIR/$(dirname "$DEST")"
          cp "$DEST" "$BACKUP_DIR/$DEST.bak" 2>/dev/null || true
        fi
        cp "$TMP" "$DEST"
        echo "    -> $DEST"
      done

      for D in ./frontend/public ./front/public ./client/public ./app/public ./web/public ./src/public; do
        if [ -d "$D" ]; then
          mkdir -p "$BACKUP_DIR/$D"
          if [ -f "$D/$ASSET" ]; then
            cp "$D/$ASSET" "$BACKUP_DIR/$D/$ASSET.bak" 2>/dev/null || true
          fi
          cp "$TMP" "$D/$ASSET"
          echo "    -> $D/$ASSET"
        fi
      done
    done
  done
fi

echo
echo "== 5) Copiando PHP vivo del backend Docker hacia host =="

if [ -n "$BACKEND_CONTAINERS" ]; then
  echo "$BACKEND_CONTAINERS" | while read -r C; do
    [ -n "$C" ] || continue

    echo
    echo "BACKEND_CONTAINER=$C"

    docker exec "$C" sh -lc '
      for d in /var/www/html /app /srv/app /var/www /usr/share/nginx/html; do
        [ -d "$d" ] && grep -Rsl "function jm_handle_syllabus_stream" "$d" 2>/dev/null || true
      done
    ' > "$BACKUP_DIR/runtime_php_list_$C.txt" || true

    if [ ! -s "$BACKUP_DIR/runtime_php_list_$C.txt" ]; then
      echo "  WARN: no encontre PHP runtime con jm_handle_syllabus_stream en $C"
      continue
    fi

    while read -r RUNTIME_PHP; do
      [ -n "$RUNTIME_PHP" ] || continue

      BASE="$(basename "$RUNTIME_PHP")"
      TMP="$BACKUP_DIR/runtime_${C}_${BASE}"

      echo "  $C:$RUNTIME_PHP"
      docker cp "$C:$RUNTIME_PHP" "$TMP"

      find . \
        -type f \
        -name "$BASE" \
        ! -path './.git/*' \
        ! -path './vendor/*' \
        ! -path './node_modules/*' \
        ! -path './backups/*' \
        ! -path './data/*' \
        ! -path './datasets/*' \
        ! -path './sync_docker_to_host_*/*' \
        ! -path './_docker_runtime_export*/*' \
        -exec grep -l "function jm_handle_syllabus_stream" {} \; \
        2>/dev/null > "$BACKUP_DIR/local_php_candidates_$BASE.txt" || true

      if [ ! -s "$BACKUP_DIR/local_php_candidates_$BASE.txt" ]; then
        mkdir -p docker_runtime_backend
        cp "$TMP" "docker_runtime_backend/$BASE"
        echo "    WARN: no encontre archivo fuente equivalente."
        echo "    -> docker_runtime_backend/$BASE"
      else
        while read -r LOCAL_FILE; do
          [ -n "$LOCAL_FILE" ] || continue
          mkdir -p "$BACKUP_DIR/$(dirname "$LOCAL_FILE")"
          cp "$LOCAL_FILE" "$BACKUP_DIR/$LOCAL_FILE.bak" 2>/dev/null || true
          cp "$TMP" "$LOCAL_FILE"
          echo "    -> $LOCAL_FILE"
        done < "$BACKUP_DIR/local_php_candidates_$BASE.txt"
      fi
    done < "$BACKUP_DIR/runtime_php_list_$C.txt"
  done
fi

echo
echo "== 6) Asegurando script institucional V5 en index.html locales =="

python3 <<'PY'
from pathlib import Path
import re

script = "jomelai-syllabus-institutional-v5.js"
tag = f'  <script src="/{script}?v=institutional-v5"></script>'

paths = [
    "index.html",
    "public/index.html",
    "dist/index.html",
    "build/index.html",
    "frontend/index.html",
    "frontend/public/index.html",
    "frontend/dist/index.html",
    "frontend/build/index.html",
    "client/index.html",
    "client/public/index.html",
    "client/dist/index.html",
    "app/index.html",
    "web/index.html",
]

for path in paths:
    p = Path(path)
    if not p.exists() or not p.is_file():
        continue

    text = p.read_text(encoding="utf-8", errors="ignore")
    original = text

    text = re.sub(
        r'\s*<script[^>]+src=["\']/?' + re.escape(script) + r'(?:\?[^"\']*)?["\'][^>]*></script>',
        "",
        text,
        flags=re.I
    )

    if "</body>" in text:
        text = text.replace("</body>", tag + "\n</body>", 1)
    elif "</head>" in text:
        text = text.replace("</head>", tag + "\n</head>", 1)
    else:
        text += "\n" + tag + "\n"

    if text != original:
        p.write_text(text, encoding="utf-8")
        print("parchado:", p)
PY

echo
echo "== 7) Verificando archivos sincronizados =="

for F in \
  public/jomelai-syllabus-institutional-v5.js \
  public/jomelai-syllabus-pretty-v7-live.js \
  public/chat-lateral-v2-client.js \
  public/chat-panel-renderer-final.js \
  public/chat-pie-image-override.js
do
  if [ -f "$F" ]; then
    echo "OK $F"
  else
    echo "WARN falta $F"
  fi
done

echo
echo "== 8) Git status =="

git status --short || true

echo
echo "=================================================="
echo " SINCRONIZACION LISTA"
echo "=================================================="
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Revisa antes de subir:"
echo "  git diff --stat"
echo "  git diff"
echo
echo "Luego:"
echo "  git add ."
echo "  git commit -m \"sync docker runtime changes to host\""
