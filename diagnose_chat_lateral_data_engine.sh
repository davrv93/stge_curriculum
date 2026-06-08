#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER="${CONTAINER:-jomelai_data_engine}"

echo "=================================================="
echo " Diagnóstico Data Engine / Chat Lateral"
echo "=================================================="

echo
echo "== 1) Estado Docker =="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$CONTAINER|NAMES" || true

echo
echo "== 2) Logs recientes del Data Engine =="
docker logs --tail=120 "$CONTAINER" || true

echo
echo "== 3) Procesos internos =="
docker exec "$CONTAINER" sh -lc '
echo "PWD=$(pwd)"
echo "--- python/uvicorn ---"
ps aux | grep -Ei "uvicorn|fastapi|python|8000" | grep -v grep || true
echo "--- puertos ---"
(ss -lntp || netstat -lntp || true) 2>/dev/null
' || true

echo
echo "== 4) Health interno con timeout =="
docker exec "$CONTAINER" python3 - <<'PY' || true
import urllib.request, time
t = time.time()
try:
    with urllib.request.urlopen("http://127.0.0.1:8000/health", timeout=5) as r:
        print("OK_HEALTH", round(time.time() - t, 3))
        print(r.read().decode("utf-8", errors="replace")[:1200])
except Exception as e:
    print("ERROR_HEALTH", repr(e))
PY

echo
echo "== 5) Verificando si las APIs nuevas existen en OpenAPI =="
docker exec "$CONTAINER" python3 - <<'PY' || true
import json, urllib.request, time
try:
    with urllib.request.urlopen("http://127.0.0.1:8000/openapi.json", timeout=8) as r:
        data = json.loads(r.read().decode("utf-8"))
    paths = sorted(data.get("paths", {}).keys())
    matches = [p for p in paths if "chat-lateral" in p]
    print("CHAT_LATERAL_PATHS:", matches)
    print("TOTAL_PATHS:", len(paths))
except Exception as e:
    print("ERROR_OPENAPI", repr(e))
PY

echo
echo "== 6) Test ruta no-stream =="
docker exec "$CONTAINER" python3 - <<'PY' || true
import json, urllib.request, time

payload = json.dumps({
    "question": "qué carreras tienes cargadas",
    "table": "silabos",
    "collection": "silabos",
    "n_results": 2,
    "limit": 20,
    "allow_ollama": False
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/chat-lateral/route",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

t = time.time()
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        print("OK_ROUTE", round(time.time() - t, 3))
        print(r.read().decode("utf-8", errors="replace")[:2500])
except Exception as e:
    print("ERROR_ROUTE", repr(e))
PY

echo
echo "== 7) Test ask no-stream sin Ollama =="
docker exec "$CONTAINER" python3 - <<'PY' || true
import json, urllib.request, time

payload = json.dumps({
    "question": "qué carreras tienes cargadas",
    "table": "silabos",
    "collection": "silabos",
    "n_results": 2,
    "limit": 20,
    "allow_ollama": False
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/chat-lateral/ask",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

t = time.time()
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        print("OK_ASK", round(time.time() - t, 3))
        print(r.read().decode("utf-8", errors="replace")[:3500])
except Exception as e:
    print("ERROR_ASK", repr(e))
PY

echo
echo "== 8) Test stream con lectura corta =="
docker exec "$CONTAINER" python3 - <<'PY' || true
import json, urllib.request, time

payload = json.dumps({
    "question": "qué carreras tienes cargadas",
    "table": "silabos",
    "collection": "silabos",
    "n_results": 2,
    "limit": 20,
    "allow_ollama": False
}).encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/chat-lateral/ask-stream",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)

t = time.time()
try:
    with urllib.request.urlopen(req, timeout=25) as r:
        print("OK_STREAM_FIRST_READ", round(time.time() - t, 3))
        print(r.read(5000).decode("utf-8", errors="replace"))
except Exception as e:
    print("ERROR_STREAM", repr(e))
PY

echo
echo "== 9) Servicio compose real del contenedor =="
docker inspect -f '{{ index .Config.Labels "com.docker.compose.service" }}' "$CONTAINER" 2>/dev/null || true

echo
echo "=================================================="
echo " FIN DIAGNÓSTICO"
echo "=================================================="
