#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ensure_model() {
  local model="$1"
  if docker compose exec -T ollama ollama list | awk 'NR>1{print $1}' | grep -Fxq "$model"; then
    echo "OK: $model ya existe en ./data/ollama; no se descarga otra vez."
  else
    echo "Descargando modelo faltante: $model"
    docker compose exec -T ollama ollama pull "$model"
  fi
}

ensure_model "qwen2.5-coder:3b"
ensure_model "deepseek-coder:1.5b"
ensure_model "nomic-embed-text"
printf '\nModelos base verificados sin borrar volúmenes. Opcional si tienes RAM suficiente:\n'
printf '  docker compose exec ollama ollama pull qwen2.5-coder:7b\n'
printf '  docker compose exec ollama ollama pull llama3.2:3b\n'
