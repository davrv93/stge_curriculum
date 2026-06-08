#!/usr/bin/env bash
set -euo pipefail

APP_NAME="UPeU Silabo AI"
CSV_CONTAINER="/data/syllabi/silabos.csv"

usage() {
  cat <<'EOF'
UPeU Silabo AI - comando unico

Uso:
  ./scripts/upeu_silabo_ai.sh ui
  ./scripts/upeu_silabo_ai.sh setup /ruta/local/silabos.csv
  ./scripts/upeu_silabo_ai.sh start
  ./scripts/upeu_silabo_ai.sh stop
  ./scripts/upeu_silabo_ai.sh restart
  ./scripts/upeu_silabo_ai.sh pull-models
  ./scripts/upeu_silabo_ai.sh duckdb [/data/syllabi/silabos.csv]
  ./scripts/upeu_silabo_ai.sh rag-sample [limite_filas]
  ./scripts/upeu_silabo_ai.sh rag-full
  ./scripts/upeu_silabo_ai.sh status
  ./scripts/upeu_silabo_ai.sh logs [servicio]

Ejemplo recomendado para CSV de 700 MB:
  ./scripts/upeu_silabo_ai.sh setup /home/ubuntu/silabos.csv
  ./scripts/upeu_silabo_ai.sh rag-sample 2000
EOF
}

compose() {
  docker compose "$@"
}

ensure_env() {
  if [ ! -f .env ]; then
    cp .env.example .env
  fi
  mkdir -p data/syllabi data/duckdb data/chroma data/jobs backend/storage/db backend/storage/sessions backend/storage/uploads backend/storage/reports
  chmod -R 777 data backend/storage 2>/dev/null || true
}

copy_csv() {
  local src="${1:-}"
  if [ -z "$src" ]; then
    echo "No se indicó ruta local de CSV. Se usará data/syllabi/silabos.csv si existe."
    return 0
  fi
  if [ ! -f "$src" ]; then
    echo "No existe el archivo CSV: $src" >&2
    exit 1
  fi
  mkdir -p data/syllabi
  cp "$src" data/syllabi/silabos.csv
  echo "CSV copiado a data/syllabi/silabos.csv"
}

wait_for_service() {
  local service="$1"
  local tries=60
  echo "Esperando servicio $service..."
  for _ in $(seq 1 "$tries"); do
    if compose ps "$service" >/dev/null 2>&1; then
      if compose exec -T "$service" sh -lc 'true' >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done
  echo "El servicio $service no quedó listo a tiempo." >&2
  exit 1
}

ensure_model() {
  local model="$1"
  if compose exec -T ollama ollama list | awk 'NR>1{print $1}' | grep -Fxq "$model"; then
    echo "OK: $model ya existe en ./data/ollama; no se descarga otra vez."
  else
    echo "Descargando modelo faltante: $model"
    compose exec -T ollama ollama pull "$model"
  fi
}

pull_models() {
  wait_for_service ollama
  ensure_model qwen2.5-coder:3b
  ensure_model deepseek-coder:1.5b
  ensure_model nomic-embed-text
  echo "Modelos base verificados sin borrar volúmenes. Opcional: docker compose exec ollama ollama pull qwen2.5-coder:7b"
}

duckdb_import() {
  local csv_path="${1:-$CSV_CONTAINER}"
  wait_for_service data-engine
  compose exec -T data-engine python /app/cli.py duckdb "$csv_path" --table silabos --sample-size 20000
}

rag_index() {
  local limit="$1"
  wait_for_service data-engine
  compose exec -T data-engine python /app/cli.py rag "$CSV_CONTAINER" --collection silabos --limit "$limit" --chunk 1000 --batch 16
}

cmd="${1:-}"
case "$cmd" in
  ui)
    ensure_env
    compose up -d --build
    port="$(grep -E '^APP_PORT=' .env | cut -d= -f2 | tail -1 || echo 38768)"
    echo "Abre: http://localhost:${port:-38768}"
    echo "Admin demo: admin@upeu.edu.pe / Admin12345!"
    echo "Luego entra a Configurar desde UI para subir CSV, instalar modelos, convertir DuckDB y construir RAG."
    ;;
  setup)
    ensure_env
    copy_csv "${2:-}"
    compose up -d --build
    pull_models
    duckdb_import "$CSV_CONTAINER"
    echo ""
    echo "$APP_NAME listo. Abre: http://localhost:$(grep -E '^APP_PORT=' .env | cut -d= -f2 | tail -1 || echo 38768)"
    echo "Admin demo: admin@upeu.edu.pe / Admin12345!"
    ;;
  start)
    ensure_env
    compose up -d --build
    ;;
  stop)
    compose down
    ;;
  restart)
    compose down
    compose up -d --build
    ;;
  pull-models)
    pull_models
    ;;
  duckdb)
    duckdb_import "${2:-$CSV_CONTAINER}"
    ;;
  rag-sample)
    pull_models
    rag_index "${2:-2000}"
    ;;
  rag-full)
    pull_models
    rag_index 0
    ;;
  status)
    compose ps
    ;;
  logs)
    compose logs -f "${2:-nginx}"
    ;;
  *)
    usage
    ;;
esac
