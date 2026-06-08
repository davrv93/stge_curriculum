#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f docker-compose.yml ]; then
  echo "ERROR: No se encontro docker-compose.yml. Ejecuta este script desde la carpeta raiz del proyecto."
  exit 1
fi

if [ ! -f frontend/index.html ]; then
  echo "ERROR: No se encontro frontend/index.html."
  echo "Causa probable: descomprimiste el ZIP dentro de otra carpeta del mismo proyecto o estas ejecutando docker compose desde una carpeta incorrecta."
  echo "Solucion: entra a la carpeta que contiene docker-compose.yml y frontend/index.html, luego ejecuta ./scripts/start_ui.sh"
  exit 1
fi

if [ ! -f nginx/default.conf ]; then
  echo "ERROR: No se encontro nginx/default.conf."
  exit 1
fi

if [ ! -f .env ]; then
  cp .env.example .env
fi

mkdir -p data/syllabi data/duckdb data/chroma data/jobs backend/storage/db backend/storage/sessions backend/storage/uploads backend/storage/reports
chmod -R 777 data backend/storage || true

docker compose up -d --build
PORT="$(grep -E '^APP_PORT=' .env | tail -1 | cut -d= -f2 || true)"
PORT="${PORT:-38768}"
echo "UPeU Silabo AI listo: http://localhost:${PORT}"
echo "Admin demo: admin@upeu.edu.pe / Admin12345!"
echo "Desde la UI entra a: Configurar desde UI"
