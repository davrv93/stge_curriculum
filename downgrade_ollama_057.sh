#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
OLLAMA_VERSION="${OLLAMA_VERSION:-0.5.7}"
MODEL="${MODEL:-qwen2.5-coder:1.5b}"

cd "$PROJECT_DIR"

echo "== Downgrade Ollama =="
echo "Proyecto: $PROJECT_DIR"
echo "Versión Ollama: $OLLAMA_VERSION"
echo "Modelo prueba: $MODEL"

OLLAMA_SERVICE="$(docker compose config --services | grep -i '^ollama$' || true)"
if [ -z "$OLLAMA_SERVICE" ]; then
  OLLAMA_SERVICE="$(docker compose config --services | grep -i 'ollama' | head -1 || true)"
fi

if [ -z "$OLLAMA_SERVICE" ]; then
  echo "ERROR: No encontré servicio Ollama."
  docker compose config --services
  exit 1
fi

echo "Servicio Ollama: $OLLAMA_SERVICE"

echo
echo "== Backup override anterior =="
if [ -f docker-compose.override.yml ]; then
  cp docker-compose.override.yml "docker-compose.override.yml.bak.$(date +%Y%m%d_%H%M%S)"
fi

echo
echo "== Creando override con Ollama $OLLAMA_VERSION =="
cat > docker-compose.override.yml <<YAML
services:
  $OLLAMA_SERVICE:
    image: ollama/ollama:$OLLAMA_VERSION
    environment:
      OLLAMA_HOST: "0.0.0.0:11434"
      OLLAMA_NUM_PARALLEL: "1"
      OLLAMA_MAX_LOADED_MODELS: "1"
      OLLAMA_KEEP_ALIVE: "0"
YAML

cat docker-compose.override.yml

echo
echo "== Bajando imagen fija =="
docker compose pull "$OLLAMA_SERVICE"

echo
echo "== Recreando solo Ollama =="
docker compose up -d --force-recreate "$OLLAMA_SERVICE"

sleep 8

CONTAINER="$(docker compose ps -q "$OLLAMA_SERVICE")"

echo
echo "== Version y logs =="
docker exec "$CONTAINER" ollama --version || true
docker logs --tail=100 "$CONTAINER" || true

echo
echo "== Modelos existentes =="
docker exec "$CONTAINER" ollama list || true

echo
echo "== Asegurando modelo =="
docker exec "$CONTAINER" ollama pull "$MODEL"

echo
echo "== Probando modelo =="
docker exec "$CONTAINER" ollama run "$MODEL" "Responde solo: OK"

echo
echo "== Cambiando JoMelAi a $MODEL si estaba usando qwen2.5-coder:3b =="
for path in .env backend frontend public src app config; do
  if [ -e "$path" ]; then
    grep -RIl "qwen2.5-coder:3b" "$path" 2>/dev/null | while read file; do
      echo "Actualizando $file"
      sed -i.bak "s/qwen2.5-coder:3b/$MODEL/g" "$file"
    done
  fi
done

echo
echo "== Reiniciando stack =="
docker compose restart

echo
echo "== Estado final =="
docker compose ps

echo
echo "Listo. Prueba JoMelAi otra vez."
echo "Debe usar Ollama $OLLAMA_VERSION y modelo $MODEL."
