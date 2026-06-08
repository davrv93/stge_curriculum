#!/usr/bin/env bash
set -euo pipefail

DOCKERFILE="data-engine/Dockerfile"
TS="$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$DOCKERFILE" ]; then
  echo "ERROR: No existe $DOCKERFILE"
  exit 1
fi

cp "$DOCKERFILE" "$DOCKERFILE.bak.$TS"
echo "Backup: $DOCKERFILE.bak.$TS"

cat > "$DOCKERFILE" <<'DOCKERFILE'
FROM python:3.11-slim-bookworm

WORKDIR /app

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && apt-get clean \
    && apt-get update -o Acquire::Retries=5 \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY requirements.txt /app/requirements.txt

RUN python -m pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r /app/requirements.txt

COPY . /app

EXPOSE 8090

CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8090"]
DOCKERFILE

echo "OK Dockerfile reemplazado por versión bookworm estable."

docker builder prune -f

docker compose build --pull --no-cache data-engine
docker compose up -d --force-recreate data-engine

echo "Esperando data-engine..."
for i in $(seq 1 60); do
  if docker compose exec -T data-engine python - <<'PY' >/dev/null 2>&1
import requests
try:
    r = requests.get("http://localhost:8090/health", timeout=2)
    raise SystemExit(0 if r.status_code == 200 else 1)
except Exception:
    raise SystemExit(1)
PY
  then
    echo "data-engine listo."
    exit 0
  fi
  sleep 2
done

echo "ERROR: data-engine no respondió."
docker compose logs --tail=150 data-engine
exit 1
