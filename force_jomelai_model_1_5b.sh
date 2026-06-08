#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
OLD_MODEL="${OLD_MODEL:-qwen2.5-coder:3b}"
NEW_MODEL="${NEW_MODEL:-qwen2.5-coder:1.5b}"

cd "$PROJECT_DIR"

echo "== Forzando cambio de modelo =="
echo "Antes: $OLD_MODEL"
echo "Ahora: $NEW_MODEL"

echo
echo "== Detectando servicio Ollama =="
OLLAMA_SERVICE="$(docker compose config --services | grep -i '^ollama$' || true)"
if [ -z "$OLLAMA_SERVICE" ]; then
  OLLAMA_SERVICE="$(docker compose config --services | grep -i 'ollama' | head -1 || true)"
fi

if [ -z "$OLLAMA_SERVICE" ]; then
  echo "ERROR: No encontré servicio Ollama."
  docker compose config --services
  exit 1
fi

OLLAMA_CONTAINER="$(docker compose ps -q "$OLLAMA_SERVICE" || true)"

if [ -z "$OLLAMA_CONTAINER" ]; then
  echo "Levantando Ollama..."
  docker compose up -d "$OLLAMA_SERVICE"
  sleep 5
  OLLAMA_CONTAINER="$(docker compose ps -q "$OLLAMA_SERVICE")"
fi

echo "Servicio Ollama: $OLLAMA_SERVICE"
echo "Contenedor Ollama: $OLLAMA_CONTAINER"

echo
echo "== Instalando modelo liviano =="
docker exec "$OLLAMA_CONTAINER" ollama pull "$NEW_MODEL"

echo
echo "== Probando modelo liviano directo en Ollama =="
docker exec "$OLLAMA_CONTAINER" ollama run "$NEW_MODEL" "Responde solo: OK"

echo
echo "== Buscando referencias al modelo anterior =="
grep -R "$OLD_MODEL" -n \
  .env \
  docker-compose.yml \
  docker-compose.override.yml \
  backend \
  frontend \
  public \
  src \
  app \
  config \
  2>/dev/null || true

echo
echo "== Reemplazando modelo en archivos de configuración/código =="
for path in .env docker-compose.yml docker-compose.override.yml backend frontend public src app config; do
  if [ -e "$path" ]; then
    grep -RIl "$OLD_MODEL" "$path" 2>/dev/null | while read file; do
      echo "Actualizando $file"
      sed -i.bak "s/$OLD_MODEL/$NEW_MODEL/g" "$file"
    done
  fi
done

echo
echo "== Verificando referencias restantes =="
grep -R "$OLD_MODEL" -n \
  .env \
  docker-compose.yml \
  docker-compose.override.yml \
  backend \
  frontend \
  public \
  src \
  app \
  config \
  2>/dev/null || echo "OK: ya no hay referencias visibles a $OLD_MODEL"

echo
echo "== Reiniciando stack completo =="
docker compose down
docker compose up -d --build

echo
echo "== Estado final =="
docker compose ps

echo
echo "== Modelos Ollama =="
docker exec "$(docker compose ps -q "$OLLAMA_SERVICE")" ollama list

echo
echo "Listo. Prueba JoMelAi de nuevo."
echo "Debe mostrar model: $NEW_MODEL"
