#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="backups/sync_docker_runtime_to_host_$TS"

echo "=================================================="
echo " Sync Docker runtime files -> host project root"
echo "=================================================="
echo "PROJECT_ROOT=$PROJECT_ROOT"
echo "BACKUP_DIR=$BACKUP_DIR"

if [ ! -f "docker-compose.yml" ] && [ ! -f "compose.yml" ] && [ ! -f "docker-compose.yaml" ] && [ ! -f "compose.yaml" ]; then
  echo "ERROR: ejecuta este script desde la carpeta donde esta docker-compose.yml o compose.yml"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
mkdir -p public

echo
echo "== 1) Detectando contenedores activos =="

docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"

echo
echo "== 2) Detectando frontend container =="

FRONT_CONTAINERS="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|frontend|front|nginx|web|vite|node' \
  | grep -vi 'ollama' \
  | grep -vi 'data_engine' \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINERS" ]; then
  echo "WARN: no detecte frontend container."
else
  echo "$FRONT_CONTAINERS" | nl -ba
fi

echo
echo "== 3) Detectando backend container =="

BACKEND_CONTAINERS="$(docker ps --format '{{.Names}} {{.Image}}' \
  | grep -Ei 'backend|laravel|php|apache|api|server' \
  | grep -vi 'frontend' \
  | grep -vi 'front' \
  | awk '{print $1}' || true)"

if [ -z "$BACKEND_CONTAINERS" ]; then
  echo "WARN: no detecte backend container."
else
  echo "$BACKEND_CONTAINERS" | nl -ba
fi

echo
echo "== 4) Sincronizando JS/assets desde frontend runtime =="

ASSETS="
jomelai-syllabus-institutional-v5.js
jomelai-syllabus-qwen-v4.js
jomelai-syllabus-stream-progress-v3.js
jomelai-syllabus-pretty-v7-live.js
chat-lateral-v2-client.js
chat-panel-renderer-final.js
chat-pie-image-override.js
"

sync_asset_to_host() {
  local tmp_file="$1"
  local asset="$2"

  echo "Sincronizando asset: $asset"

  for dest in "public/$asset" "$asset"; do
    if [ -f "$dest" ]; then
      mkdir -p "$BACKUP_DIR/$(dirname "$dest")"
      cp "$dest" "$BACKUP_DIR/$dest.bak" 2>/dev/null || true
    fi
    cp "$tmp_file" "$dest"
    echo "  -> $dest"
  done

  for d in ./frontend/public ./front/public ./client/public ./app/public ./web/public ./src/public; do
    if [ -d "$d" ]; then
      mkdir -p "$BACKUP_DIR/$d"
      if [ -f "$d/$asset" ]; then
        cp "$d/$asset" "$BACKUP_DIR/$d/$asset.bak" 2>/dev/null || true
      fi
      cp "$tmp_file" "$d/$asset"
      echo "  -> $d/$asset"
    fi
  done
}

if [ -n "$FRONT_CONTAINERS" ]; then
  echo "$FRONT_CONTAINERS" | while read c; do
    [ -n "$c" ] || continue
    echo
    echo "FRONT_CONTAINER=$c"

    ROOTS="$(docker exec "$c" sh -lc '
      for d in /usr/share/nginx/html /app/dist /app/build /app/public /app /var/www/html; do
        [ -d "$d" ] && echo "$d"
      done
    ' || true)"

    if [ -z "$ROOTS" ]; then
      ROOTS="/usr/share/nginx/html"
    fi

    for asset in $ASSETS; do
      found=""

      while read r; do
        [ -n "$r" ] || continue
        candidate="$r/$asset"

        if docker exec "$c" sh -lc "[ -f '$candidate' ]"; then
          found="$candidate"
          break
        fi
      done <<< "$ROOTS"

      if [ -n "$found" ]; then
        tmp="$BACKUP_DIR/runtime_${c}_${asset}"
        docker cp "$c:$found" "$tmp"
        sync_asset_to_host "$tmp" "$asset"
      else
        echo "  WARN: no encontre $asset dentro de $c"
      fi
    done

    echo
    echo "Buscando index.html runtime en $c"

    INDEX_FILES="$(docker exec "$c" sh -lc '
      for f in /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html /app/index.html /var/www/html/index.html; do
        [ -f "$f" ] && echo "$f"
      done
    ' || true)"

    if [ -n "$INDEX_FILES" ]; then
      echo "$INDEX_FILES" | while read idx; do
        [ -n "$idx" ] || continue
        safe="$(echo "$c$idx" | tr '/:' '__')"
        docker cp "$c:$idx" "$BACKUP_DIR/$safe.runtime.index.html" || true
        echo "  runtime index guardado: $BACKUP_DIR/$safe.runtime.index.html"
      done
    fi
  done
fi

echo
echo "== 5) Sincronizando PHP real desde backend runtime =="

if [ -n "$BACKEND_CONTAINERS" ]; then
  echo "$BACKEND_CONTAINERS" | while read c; do
    [ -n "$c" ] || continue
    echo
    echo "BACKEND_CONTAINER=$c"

    RUNTIME_PHP_LIST="$(docker exec "$c" sh -lc "
      for d in /var/www/html /app /srv/app /var/www /usr/share/nginx/html; do
        [ -d \"\$d\" ] && grep -Rsl 'function jm_handle_syllabus_stream' \"\$d\" 2>/dev/null || true
      done
    " || true)"

    if [ -z "$RUNTIME_PHP_LIST" ]; then
      echo "  WARN: no encontre PHP runtime con jm_handle_syllabus_stream dentro de $c"
      continue
    fi

    echo "$RUNTIME_PHP_LIST" | while read runtime_php; do
      [ -n "$runtime_php" ] || continue

      base="$(basename "$runtime_php")"
      tmp="$BACKUP_DIR/runtime_${c}_${base}"

      echo "  copiando runtime PHP:"
      echo "    $c:$runtime_php"
      docker cp "$c:$runtime_php" "$tmp"

      mapfile -t LOCAL_CANDIDATES < <(find . \
        -type f \
        -name "$base" \
        ! -path './.git/*' \
        ! -path './vendor/*' \
        ! -path './node_modules/*' \
        ! -path './backups/*' \
        ! -path './data/*' \
        ! -path './datasets/*' \
        ! -path './sync_docker_to_host_*/*' \
        ! -path './_docker_runtime_export*/*' \
        -exec grep -l "function jm_handle_syllabus_stream" {} \; \
        2>/dev/null || true)

      if [ "${#LOCAL_CANDIDATES[@]}" -eq 0 ]; then
        mkdir -p docker_runtime_backend
        cp "$tmp" "docker_runtime_backend/$base"
        echo "    WARN: no encontre candidato local. Copiado a docker_runtime_backend/$base"
      else
        for local_file in "${LOCAL_CANDIDATES[@]}"; do
          mkdir -p "$BACKUP_DIR/$(dirname "$local_file")"
          cp "$local_file" "$BACKUP_DIR/$local_file.bak" 2>/dev/null || true
          cp "$tmp" "$local_file"
          echo "    -> $local_file"
        done
      fi
    done
  done
fi

echo
echo "== 6) Parcheando index.html locales para cargar V5 =="

python3 <<'PY'
from pathlib import Path
import re

script = "jomelai-syllabus-institutional-v5.js"
tag = f'  <script src="/{script}?v=institutional-v5"></script>'

candidates = []
for pattern in [
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
]:
    p = Path(pattern)
    if p.exists() and p.is_file():
        candidates.append(p)

for p in candidates:
    text = p.read_text(encoding="utf-8", errors="ignore")

    old = text

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

    if text != old:
        p.write_text(text, encoding="utf-8")
        print("parchado:", p)
PY

echo
echo "== 7) Verificando que no queden referencias JS sin archivo local =="

for ref in \
  jomelai-syllabus-institutional-v5.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  if [ -f "public/$ref" ]; then
    echo "OK public/$ref"
  else
    echo "WARN falta public/$ref"
  fi
done

echo
echo "== 8) Verificando endpoint local si APP_PORT existe =="

APP_PORT="$(python3 - <<'PY'
from pathlib import Path
port = "3000"
p = Path(".env")
if p.exists():
    for line in p.read_text(errors="ignore").splitlines():
        if line.startswith("APP_PORT="):
            port = line.split("=", 1)[1].strip() or "3000"
print(port)
PY
)"

echo "APP_PORT=$APP_PORT"

for ref in \
  jomelai-syllabus-institutional-v5.js \
  jomelai-syllabus-pretty-v7-live.js \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js
do
  echo
  echo "---- http://localhost:${APP_PORT}/$ref ----"
  curl -sS -I "http://localhost:${APP_PORT}/$ref?v=sync-check" | head -5 || true
done

echo
echo "== 9) Git status =="

git status --short || true

echo
echo "=================================================="
echo " SINCRONIZACION COMPLETADA"
echo "=================================================="
echo "Backups:"
echo "  $BACKUP_DIR"
echo
echo "Revisa cambios:"
echo "  git diff --stat"
echo "  git diff"
echo
echo "Luego:"
echo "  git add ."
echo "  git commit -m \"sync runtime docker changes to host project\""
