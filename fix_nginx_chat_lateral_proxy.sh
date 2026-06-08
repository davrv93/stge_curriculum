#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
cd "$PROJECT_DIR"

echo "=================================================="
echo " Fix Nginx proxy /api/chat-lateral -> Data Engine"
echo "=================================================="

BACKUP_DIR="backups/nginx_chat_lateral_proxy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Verificando Data Engine directo =="
docker exec jomelai_data_engine python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8090/health", timeout=5).read().decode()[:300])'

echo
echo "== 2) Detectando contenedor frontend/Nginx =="
FRONT_CONTAINER="${FRONT_CONTAINER:-}"

if [ -z "$FRONT_CONTAINER" ]; then
  FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
    | grep -Ei '38764|3000|frontend|nginx|web' \
    | grep -vi 'data_engine' \
    | head -1 \
    | awk '{print $1}' || true)"
fi

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no pude detectar contenedor frontend."
  echo "Contenedores:"
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

FRONT_SERVICE="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.service" }}' "$FRONT_CONTAINER" 2>/dev/null || true)"
echo "FRONT_SERVICE=${FRONT_SERVICE:-NO_DETECTADO}"

echo
echo "== 3) Buscando configuración Nginx dentro del frontend =="
NGINX_CONF="$(docker exec "$FRONT_CONTAINER" sh -lc '
for f in /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* /etc/nginx/nginx.conf; do
  [ -f "$f" ] || continue
  if grep -q "server" "$f" 2>/dev/null; then
    echo "$f"
    exit 0
  fi
done
' || true)"

if [ -z "$NGINX_CONF" ]; then
  echo "ERROR: no encontré configuración Nginx dentro de $FRONT_CONTAINER."
  echo "Probablemente el frontend no usa Nginx. Muestro procesos:"
  docker exec "$FRONT_CONTAINER" sh -lc 'cat /proc/1/cmdline | tr "\000" " "; echo' || true
  exit 1
fi

echo "NGINX_CONF=$NGINX_CONF"

TMP_CONF="/tmp/nginx_chat_lateral_$(date +%s).conf"
docker cp "$FRONT_CONTAINER:$NGINX_CONF" "$TMP_CONF"
cp "$TMP_CONF" "$BACKUP_DIR/nginx_container_original.conf"

echo
echo "== 4) Parcheando Nginx dentro del contenedor =="
python3 - "$TMP_CONF" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

start = "    # CHAT LATERAL V2 PROXY START"
end = "    # CHAT LATERAL V2 PROXY END"

block = r'''
    # CHAT LATERAL V2 PROXY START
    location ^~ /api/chat-lateral/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 180s;
        proxy_send_timeout 180s;
        chunked_transfer_encoding off;

        add_header X-Accel-Buffering no always;

        proxy_pass http://data-engine:8090/chat-lateral/;
    }
    # CHAT LATERAL V2 PROXY END
'''.rstrip()

# Elimina bloque viejo si existe.
if "CHAT LATERAL V2 PROXY START" in text and "CHAT LATERAL V2 PROXY END" in text:
    text = re.sub(
        r"\s*# CHAT LATERAL V2 PROXY START.*?# CHAT LATERAL V2 PROXY END",
        "\n" + block,
        text,
        flags=re.S,
    )
else:
    # Inserta justo después del primer server { para que gane antes de location /api.
    m = re.search(r"server\s*\{", text)
    if not m:
        raise SystemExit("No encontré bloque server { en Nginx config")

    insert_at = m.end()
    text = text[:insert_at] + "\n" + block + "\n" + text[insert_at:]

path.write_text(text, encoding="utf-8")
PY

docker cp "$TMP_CONF" "$FRONT_CONTAINER:$NGINX_CONF"

echo
echo "== 5) Validando y recargando Nginx =="
docker exec "$FRONT_CONTAINER" nginx -t
docker exec "$FRONT_CONTAINER" nginx -s reload

echo
echo "== 6) Parche persistente en archivos Nginx del proyecto, si existen =="
python3 - "$BACKUP_DIR" <<'PY'
import re
import shutil
import sys
import time
from pathlib import Path

backup_root = Path(sys.argv[1])
timestamp = time.strftime("%Y%m%d_%H%M%S")

block = r'''
    # CHAT LATERAL V2 PROXY START
    location ^~ /api/chat-lateral/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 180s;
        proxy_send_timeout 180s;
        chunked_transfer_encoding off;

        add_header X-Accel-Buffering no always;

        proxy_pass http://data-engine:8090/chat-lateral/;
    }
    # CHAT LATERAL V2 PROXY END
'''.rstrip()

candidates = []
for p in Path(".").rglob("*"):
    if not p.is_file():
        continue

    s = str(p)
    if any(x in s for x in ["/.git/", "/data/", "/node_modules/", "/vendor/", "/backups/"]):
        continue

    if p.suffix not in {".conf", ".nginx"} and p.name not in {"nginx.conf", "default.conf"}:
        continue

    if "nginx" not in s.lower() and "default.conf" not in p.name:
        continue

    try:
        text = p.read_text(encoding="utf-8")
    except Exception:
        continue

    if "server" in text and "location" in text:
        candidates.append(p)

for p in candidates:
    text = p.read_text(encoding="utf-8")
    new = text

    if "CHAT LATERAL V2 PROXY START" in new and "CHAT LATERAL V2 PROXY END" in new:
        new = re.sub(
            r"\s*# CHAT LATERAL V2 PROXY START.*?# CHAT LATERAL V2 PROXY END",
            "\n" + block,
            new,
            flags=re.S,
        )
    else:
        m = re.search(r"server\s*\{", new)
        if not m:
            continue
        new = new[:m.end()] + "\n" + block + "\n" + new[m.end():]

    if new != text:
        dest = backup_root / (str(p).replace("/", "__") + f".bak.{timestamp}")
        shutil.copy2(p, dest)
        p.write_text(new, encoding="utf-8")
        print("Parche persistente:", p)
PY

echo
echo "== 7) Corrigiendo .env y referencias a puerto 8090 =="
touch .env

if grep -q '^DATA_ENGINE_URL=' .env; then
  sed -i 's#^DATA_ENGINE_URL=.*#DATA_ENGINE_URL=http://data-engine:8090#g' .env
else
  echo 'DATA_ENGINE_URL=http://data-engine:8090' >> .env
fi

if grep -q '^SILABO_ENGINE_URL=' .env; then
  sed -i 's#^SILABO_ENGINE_URL=.*#SILABO_ENGINE_URL=http://data-engine:8090#g' .env
else
  echo 'SILABO_ENGINE_URL=http://data-engine:8090' >> .env
fi

sed -i \
  -e 's#http://data-engine:8000#http://data-engine:8090#g' \
  -e 's#localhost:8000#localhost:8090#g' \
  .env docker-compose.yml docker-compose.override.yml routes/api.php backend/routes/api.php 2>/dev/null || true

echo
echo "== 8) Test desde host por puertos públicos =="
echo
echo "-- Probando 38764 --"
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2500 || true

echo
echo
echo "-- Probando 3000 --"
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2500 || true

echo
echo
echo "== 9) Test desde dentro del frontend container =="
docker exec "$FRONT_CONTAINER" sh -lc '
if command -v curl >/dev/null 2>&1; then
  curl -sS -N -m 20 -X POST http://127.0.0.1/api/chat-lateral/ask-stream \
    -H "Content-Type: application/json" \
    -d "{\"question\":\"qué carreras tienes cargadas\",\"table\":\"silabos\",\"collection\":\"silabos\",\"n_results\":2,\"allow_ollama\":false}" | head -c 2000
elif command -v wget >/dev/null 2>&1; then
  echo "wget disponible, pero este test POST/SSE se omite."
else
  echo "Sin curl/wget dentro del contenedor frontend."
fi
' || true

echo
echo
echo "== 10) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo "Frontend container: $FRONT_CONTAINER"
echo "Nginx config: $NGINX_CONF"
echo
echo "Ruta pública corregida:"
echo "  /api/chat-lateral/ask-stream"
echo
echo "Debe proxyear a:"
echo "  http://data-engine:8090/chat-lateral/ask-stream"
