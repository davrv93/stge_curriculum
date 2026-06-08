#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " FIX 502 Chat Lateral / Data Engine / Nginx"
echo "=================================================="

BACKUP_DIR="backups/fix_502_chat_lateral_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

ENGINE_FILE="data-engine/app.py"

echo
echo "== 1) Estado actual =="
docker compose ps || true
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

echo
echo "== 2) Logs actuales Data Engine =="
docker logs --tail=120 jomelai_data_engine 2>/dev/null || true

echo
echo "== 3) Reparando app.py si quedó con SyntaxError =="
if [ ! -f "$ENGINE_FILE" ]; then
  echo "ERROR: no existe $ENGINE_FILE"
  exit 1
fi

cp "$ENGINE_FILE" "$BACKUP_DIR/app.py.before_fix_502.bak"

python3 - "$ENGINE_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

safe_func = '''def _cl_fast_answer(rows: List[Dict[str, Any]], title: str = "Resultado") -> str:
    if not rows:
        return "No encontré registros para esa consulta."

    total = len(rows)
    sample = rows[:20]

    if not sample or not isinstance(sample[0], dict):
        return f"{title}: encontré {total} registros."

    headers = list(sample[0].keys())

    def _fmt(v):
        s = "" if v is None else str(v)
        s = s.replace("\\\\n", " ").replace("\\\\r", " ").replace("|", "/").strip()
        return s[:120]

    out_lines = []
    out_lines.append(f"{title}: encontré {total} registros.")
    out_lines.append("")
    out_lines.append("| " + " | ".join(headers) + " |")
    out_lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for row in sample:
        out_lines.append("| " + " | ".join(_fmt(row.get(h)) for h in headers) + " |")

    if total > len(sample):
        out_lines.append("")
        out_lines.append(f"Mostrando {len(sample)} de {total} registros.")

    return "\\\\n".join(out_lines)


'''

start = text.find("def _cl_fast_answer(")

if start == -1:
    marker_candidates = [
        "def _cl_route(",
        "def _cl_rag_context(",
        '@api.post("/chat-lateral/route")',
    ]

    insert_at = -1
    for marker in marker_candidates:
        insert_at = text.find(marker)
        if insert_at != -1:
            break

    if insert_at == -1:
        raise SystemExit("No encontré _cl_fast_answer ni punto de inserción.")

    text = text[:insert_at] + safe_func + text[insert_at:]
    path.write_text(text, encoding="utf-8")
    print("INSERTED _cl_fast_answer")
    raise SystemExit(0)

# Buscar un marcador seguro posterior.
markers = [
    "\ndef _cl_route(",
    "\ndef _cl_rag_context(",
    "\ndef _cl_generate(",
    '\n@api.post("/chat-lateral/route")',
    '\n@api.post("/chat-lateral/ask")',
    '\n@api.post("/chat-lateral/ask-stream")',
    "\n# === CHAT LATERAL V2 SAFE END ===",
]

positions = []
for marker in markers:
    pos = text.find(marker, start + 1)
    if pos != -1:
        positions.append(pos)

if positions:
    end = min(positions)
else:
    # Fallback por líneas: cortar como máximo 100 líneas desde inicio.
    line_starts = [0]
    for m in re.finditer("\n", text):
        line_starts.append(m.end())

    start_line = 0
    for i, pos in enumerate(line_starts):
        if pos <= start:
            start_line = i

    end_line = min(start_line + 100, len(line_starts) - 1)
    end = line_starts[end_line]

text = text[:start] + safe_func + text[end:].lstrip("\n")
path.write_text(text, encoding="utf-8")
print("REPLACED _cl_fast_answer")
PY

echo
echo "== 4) Compilando app.py =="
if python3 -m py_compile "$ENGINE_FILE"; then
  echo "OK: app.py compila."
else
  echo "ERROR: app.py sigue roto. Zona 3035-3125:"
  nl -ba "$ENGINE_FILE" | sed -n '3035,3125p'
  exit 1
fi

echo
echo "== 5) Rebuild Data Engine =="
DATA_SERVICE="$(docker compose config --services | grep -E '^data-engine$|data_engine|engine' | head -1 || true)"
if [ -z "$DATA_SERVICE" ]; then
  DATA_SERVICE="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.service" }}' jomelai_data_engine 2>/dev/null || true)"
fi
if [ -z "$DATA_SERVICE" ]; then
  DATA_SERVICE="data-engine"
fi

echo "DATA_SERVICE=$DATA_SERVICE"

docker compose up -d --build "$DATA_SERVICE"

sleep 8

echo
echo "== 6) Logs Data Engine después del rebuild =="
docker logs --tail=120 jomelai_data_engine || true

echo
echo "== 7) Test interno Data Engine 8090 =="
docker exec jomelai_data_engine python3 -c 'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:8090/health", timeout=8).read().decode()[:800])'

echo
echo "== 8) Test directo ask-stream dentro de Data Engine =="
docker exec jomelai_data_engine python3 -c 'import json, urllib.request; payload=json.dumps({"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"limit":20,"allow_ollama":False}).encode(); req=urllib.request.Request("http://127.0.0.1:8090/chat-lateral/ask-stream",data=payload,headers={"Content-Type":"application/json"},method="POST"); print(urllib.request.urlopen(req,timeout=30).read(2500).decode())'

echo
echo "== 9) Detectando contenedor frontend/Nginx =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '38764|3000|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no detecté frontend container."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

echo
echo "== 10) Buscando conf Nginx =="
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
  echo "ERROR: no encontré Nginx conf."
  docker exec "$FRONT_CONTAINER" sh -lc 'cat /proc/1/cmdline | tr "\000" " "; echo' || true
  exit 1
fi

echo "NGINX_CONF=$NGINX_CONF"

TMP_CONF="/tmp/nginx_chat_lateral_fix_502.conf"
docker cp "$FRONT_CONTAINER:$NGINX_CONF" "$TMP_CONF"
cp "$TMP_CONF" "$BACKUP_DIR/nginx.before_fix_502.conf"

echo
echo "== 11) Reparando location Nginx /api/chat-lateral/ =="
python3 - "$TMP_CONF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

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

if "CHAT LATERAL V2 PROXY START" in text and "CHAT LATERAL V2 PROXY END" in text:
    text = re.sub(
        r"\s*# CHAT LATERAL V2 PROXY START.*?# CHAT LATERAL V2 PROXY END",
        "\n" + block,
        text,
        flags=re.S,
    )
else:
    m = re.search(r"server\s*\{", text)
    if not m:
        raise SystemExit("No encontré server { en nginx conf.")
    text = text[:m.end()] + "\n" + block + "\n" + text[m.end():]

path.write_text(text, encoding="utf-8")
PY

docker cp "$TMP_CONF" "$FRONT_CONTAINER:$NGINX_CONF"

echo
echo "== 12) Validando Nginx =="
docker exec "$FRONT_CONTAINER" nginx -t
docker exec "$FRONT_CONTAINER" nginx -s reload

echo
echo "== 13) Test conectividad desde frontend hacia data-engine =="
docker exec "$FRONT_CONTAINER" sh -lc '
if command -v curl >/dev/null 2>&1; then
  echo "--- curl data-engine health ---"
  curl -sS -m 8 http://data-engine:8090/health | head -c 500
  echo
else
  echo "No hay curl dentro del frontend container."
fi
' || true

echo
echo "== 14) Test público por Nginx 38764 =="
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 3500 || true

echo
echo
echo "== 15) Si 38764 no existe, test 3000 =="
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 3500 || true

echo
echo
echo "== 16) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Si el test público ya devuelve event: ready/config/final,"
echo "haz hard refresh en navegador: Ctrl+Shift+R"
