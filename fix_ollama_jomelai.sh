#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
PRIMARY_MODEL="${PRIMARY_MODEL:-qwen2.5-coder:3b}"
FALLBACK_MODEL="${FALLBACK_MODEL:-qwen2.5-coder:1.5b}"

echo "== JoMelAi / Ollama fix =="
echo "Proyecto: $PROJECT_DIR"
echo "Modelo principal: $PRIMARY_MODEL"
echo "Modelo fallback: $FALLBACK_MODEL"

cd "$PROJECT_DIR"

if [ ! -f docker-compose.yml ] && [ ! -f compose.yml ]; then
  echo "ERROR: No encuentro docker-compose.yml en $PROJECT_DIR"
  exit 1
fi

echo
echo "== Verificando Docker =="
docker --version
docker compose version

echo
echo "== Detectando servicio Ollama =="
OLLAMA_SERVICE="$(docker compose config --services | grep -i '^ollama$' || true)"

if [ -z "$OLLAMA_SERVICE" ]; then
  OLLAMA_SERVICE="$(docker compose config --services | grep -i 'ollama' | head -1 || true)"
fi

if [ -z "$OLLAMA_SERVICE" ]; then
  echo "ERROR: No se encontró servicio Ollama en docker compose."
  echo "Servicios disponibles:"
  docker compose config --services
  exit 1
fi

echo "Servicio Ollama detectado: $OLLAMA_SERVICE"

echo
echo "== Creando swap si no existe =="
if swapon --show | grep -q '/swapfile'; then
  echo "Swap ya existe:"
  swapon --show
else
  sudo fallocate -l 16G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  if ! grep -q '^/swapfile ' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi

  echo "Swap creado."
fi

free -h

echo
echo "== Backup de docker-compose.override.yml si existe =="
if [ -f docker-compose.override.yml ]; then
  cp docker-compose.override.yml "docker-compose.override.yml.bak.$(date +%Y%m%d_%H%M%S)"
fi

echo
echo "== Aplicando override seguro para Ollama =="
cat > docker-compose.override.yml <<YAML
services:
  $OLLAMA_SERVICE:
    image: ollama/ollama:latest
    environment:
      OLLAMA_HOST: "0.0.0.0:11434"
      OLLAMA_FLASH_ATTENTION: "0"
      OLLAMA_NUM_PARALLEL: "1"
      OLLAMA_MAX_LOADED_MODELS: "1"
      OLLAMA_CONTEXT_LENGTH: "2048"
      OLLAMA_KEEP_ALIVE: "0"
YAML

echo "Override creado:"
cat docker-compose.override.yml

echo
echo "== Actualizando solo Ollama =="
docker compose pull "$OLLAMA_SERVICE"
docker compose up -d "$OLLAMA_SERVICE"

echo
echo "== Esperando Ollama =="
sleep 8

OLLAMA_CONTAINER="$(docker compose ps -q "$OLLAMA_SERVICE")"

if [ -z "$OLLAMA_CONTAINER" ]; then
  echo "ERROR: No se pudo obtener el contenedor de Ollama."
  docker compose ps
  exit 1
fi

echo "Contenedor Ollama: $OLLAMA_CONTAINER"

echo
echo "== Logs recientes de Ollama =="
docker logs --tail=80 "$OLLAMA_CONTAINER" || true

echo
echo "== Modelos instalados =="
docker exec "$OLLAMA_CONTAINER" ollama list || true

echo
echo "== Asegurando modelo principal =="
if docker exec "$OLLAMA_CONTAINER" ollama list | awk '{print $1}' | grep -qx "$PRIMARY_MODEL"; then
  echo "Modelo $PRIMARY_MODEL ya existe."
else
  docker exec "$OLLAMA_CONTAINER" ollama pull "$PRIMARY_MODEL"
fi

echo
echo "== Probando modelo principal =="
set +e
docker exec "$OLLAMA_CONTAINER" ollama run "$PRIMARY_MODEL" "Responde solo: OK"
PRIMARY_STATUS=$?
set -e

if [ "$PRIMARY_STATUS" -eq 0 ]; then
  echo
  echo "OK: $PRIMARY_MODEL funciona."
  echo "Reiniciando stack completo..."
  docker compose restart
  echo
  echo "Estado final:"
  docker compose ps
  exit 0
fi

echo
echo "ADVERTENCIA: $PRIMARY_MODEL falló. Mostrando logs:"
docker logs --tail=120 "$OLLAMA_CONTAINER" || true

echo
echo "== Intentando fallback liviano: $FALLBACK_MODEL =="
docker exec "$OLLAMA_CONTAINER" ollama pull "$FALLBACK_MODEL"

set +e
docker exec "$OLLAMA_CONTAINER" ollama run "$FALLBACK_MODEL" "Responde solo: OK"
FALLBACK_STATUS=$?
set -e

if [ "$FALLBACK_STATUS" -eq 0 ]; then
  echo
  echo "OK: $FALLBACK_MODEL funciona."
  echo
  echo "Ahora cambia el modelo de la app de:"
  echo "  $PRIMARY_MODEL"
  echo "a:"
  echo "  $FALLBACK_MODEL"
  echo
  echo "Buscando dónde está configurado..."
  grep -R "$PRIMARY_MODEL\|OLLAMA_MODEL\|AI_MODEL" -n .env docker-compose.yml docker-compose.override.yml backend frontend public app 2>/dev/null | head -80 || true
  echo
  echo "Si está en .env, puedes ejecutar:"
  echo "  sed -i 's/$PRIMARY_MODEL/$FALLBACK_MODEL/g' .env"
  echo "  docker compose restart"
  exit 0
fi

echo
echo "ERROR: También falló $FALLBACK_MODEL."
echo "Últimos logs de Ollama:"
docker logs --tail=200 "$OLLAMA_CONTAINER" || true

echo
echo "Recursos del servidor:"
free -h
df -h

exit 1
