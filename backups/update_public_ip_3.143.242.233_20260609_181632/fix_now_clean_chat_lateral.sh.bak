#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " CLEAN FIX Chat Lateral"
echo "=================================================="

echo
echo "== 1) Estado Docker =="
docker compose ps

echo
echo "== 2) Esperando servicios =="
sleep 10

echo
echo "== 3) Test Data Engine host 8090 =="
curl -sS -m 10 http://localhost:8090/health | head -c 600 || true
echo

echo
echo "== 4) Test Frontend host 3000 =="
curl -sS -m 10 http://localhost:3000/ | head -c 200 || true
echo

echo
echo "== 5) Reparando proxy Nginx /api/chat-lateral/ =="
FRONT_CONTAINER="jomelai_frontend"

NGINX_CONF="$(docker exec "$FRONT_CONTAINER" sh -lc '
for f in /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/*.conf /etc/nginx/nginx.conf; do
  [ -f "$f" ] || continue
  if grep -q "server" "$f" 2>/dev/null; then
    echo "$f"
    exit 0
  fi
done
' || true)"

if [ -z "$NGINX_CONF" ]; then
  echo "ERROR: no encontre Nginx conf"
  exit 1
fi

echo "NGINX_CONF=$NGINX_CONF"

TMP_CONF="/tmp/jomelai_nginx_clean.conf"
docker cp "$FRONT_CONTAINER:$NGINX_CONF" "$TMP_CONF"

python3 - "$TMP_CONF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

block = """
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
""".rstrip()

if "CHAT LATERAL V2 PROXY START" in text and "CHAT LATERAL V2 PROXY END" in text:
    text = re.sub(
        r"\\s*# CHAT LATERAL V2 PROXY START.*?# CHAT LATERAL V2 PROXY END",
        "\\n" + block,
        text,
        flags=re.S,
    )
else:
    m = re.search(r"server\\s*\\{", text)
    if not m:
        raise SystemExit("No encontre server { en nginx conf")
    text = text[:m.end()] + "\\n" + block + "\\n" + text[m.end():]

path.write_text(text, encoding="utf-8")
PY

docker cp "$TMP_CONF" "$FRONT_CONTAINER:$NGINX_CONF"
docker exec "$FRONT_CONTAINER" nginx -t
docker exec "$FRONT_CONTAINER" nginx -s reload

echo
echo "== 6) Test ask-stream por frontend 3000 =="
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"que carreras tienes?","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 3000 || true

echo
echo
echo "== 7) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Abre:"
echo "  http://18.191.127.254:3000"
echo
echo "Luego hard refresh:"
echo "  Ctrl + Shift + R"
