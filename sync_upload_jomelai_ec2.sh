#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# JoMelAi local Docker -> Mac host -> EC2
# ============================================================

EC2_IP="3.140.243.183"
EC2_USER="ubuntu"
PEM_KEY="$HOME/Downloads/cur.pem"
REMOTE_DIR="/home/ubuntu/jomelai_ec2"

PROJECT_NAME="jomelai"
STAMP="$(date +%Y%m%d_%H%M%S)"
BUNDLE_DIR="$PWD/${PROJECT_NAME}_ec2_bundle_${STAMP}"

BACKEND_CONTAINER="jomelai_backend"
FRONTEND_CONTAINER="jomelai_frontend"
DATA_ENGINE_CONTAINER="jomelai_data_engine"
OLLAMA_CONTAINER="jomelai_ollama"

BACKEND_IMAGE="jomelai_backend_ec2:${STAMP}"
FRONTEND_IMAGE="jomelai_frontend_ec2:${STAMP}"
DATA_ENGINE_IMAGE="jomelai_data_engine_ec2:${STAMP}"

echo "============================================================"
echo "JoMelAi Docker -> EC2"
echo "Bundle: $BUNDLE_DIR"
echo "EC2: $EC2_USER@$EC2_IP"
echo "============================================================"

if [ ! -f "$PEM_KEY" ]; then
  echo "ERROR: no encuentro tu llave PEM en: $PEM_KEY"
  echo "Verifica si el archivo se llama cur.pem y esta en Downloads."
  exit 1
fi

chmod 600 "$PEM_KEY"

mkdir -p "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/images"
mkdir -p "$BUNDLE_DIR/snapshots"
mkdir -p "$BUNDLE_DIR/data"
mkdir -p "$BUNDLE_DIR/meta"

echo ""
echo "=== 1. Verificando contenedores locales ==="

for c in "$BACKEND_CONTAINER" "$FRONTEND_CONTAINER" "$DATA_ENGINE_CONTAINER" "$OLLAMA_CONTAINER"; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    echo "OK: $c"
  else
    echo "ERROR: no existe el contenedor $c"
    echo "Contenedores disponibles:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    exit 1
  fi
done

echo ""
echo "=== 2. Guardando metadata Docker ==="

docker ps -a > "$BUNDLE_DIR/meta/docker_ps.txt"
docker images > "$BUNDLE_DIR/meta/docker_images.txt"
docker inspect "$BACKEND_CONTAINER" "$FRONTEND_CONTAINER" "$DATA_ENGINE_CONTAINER" "$OLLAMA_CONTAINER" > "$BUNDLE_DIR/meta/docker_inspect.json"

if [ -f docker-compose.yml ]; then
  cp docker-compose.yml "$BUNDLE_DIR/docker-compose.local.yml"
fi

if [ -f compose.yml ]; then
  cp compose.yml "$BUNDLE_DIR/compose.local.yml"
fi

if [ -f .env ]; then
  cp .env "$BUNDLE_DIR/.env.local"
fi

docker compose config > "$BUNDLE_DIR/meta/docker-compose.resolved.yml" 2>/dev/null || true

echo ""
echo "=== 3. Sincronizando archivos desde contenedores hacia el host ==="

copy_from_container() {
  container="$1"
  src="$2"
  dest="$3"

  if docker exec "$container" sh -c "[ -e '$src' ]" >/dev/null 2>&1; then
    echo "Copiando $container:$src -> $dest"
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest"
    docker cp "$container:$src" "$dest"
  else
    echo "Aviso: $container:$src no existe, se omite."
  fi
}

copy_from_container "$BACKEND_CONTAINER" "/var/www/app" "$BUNDLE_DIR/snapshots/backend_app"
copy_from_container "$BACKEND_CONTAINER" "/var/www/html" "$BUNDLE_DIR/snapshots/backend_html"

copy_from_container "$FRONTEND_CONTAINER" "/usr/share/nginx/html" "$BUNDLE_DIR/snapshots/frontend_html"
copy_from_container "$FRONTEND_CONTAINER" "/app" "$BUNDLE_DIR/snapshots/frontend_app"

copy_from_container "$DATA_ENGINE_CONTAINER" "/app" "$BUNDLE_DIR/snapshots/data_engine_app"
copy_from_container "$DATA_ENGINE_CONTAINER" "/engine_storage" "$BUNDLE_DIR/data/engine_storage"
copy_from_container "$DATA_ENGINE_CONTAINER" "/data" "$BUNDLE_DIR/data/data"

copy_from_container "$OLLAMA_CONTAINER" "/root/.ollama" "$BUNDLE_DIR/data/ollama"

echo ""
echo "=== 4. Creando imagenes snapshot con cambios actuales ==="

docker commit "$BACKEND_CONTAINER" "$BACKEND_IMAGE" >/dev/null
docker commit "$FRONTEND_CONTAINER" "$FRONTEND_IMAGE" >/dev/null
docker commit "$DATA_ENGINE_CONTAINER" "$DATA_ENGINE_IMAGE" >/dev/null

echo "Imagen backend: $BACKEND_IMAGE"
echo "Imagen frontend: $FRONTEND_IMAGE"
echo "Imagen data-engine: $DATA_ENGINE_IMAGE"

echo ""
echo "=== 5. Exportando imagenes a tar.gz ==="

docker save "$BACKEND_IMAGE" | gzip -c > "$BUNDLE_DIR/images/backend_image.tar.gz"
docker save "$FRONTEND_IMAGE" | gzip -c > "$BUNDLE_DIR/images/frontend_image.tar.gz"
docker save "$DATA_ENGINE_IMAGE" | gzip -c > "$BUNDLE_DIR/images/data_engine_image.tar.gz"

cat > "$BUNDLE_DIR/.ec2_images.env" <<EOF
BACKEND_IMAGE=$BACKEND_IMAGE
FRONTEND_IMAGE=$FRONTEND_IMAGE
DATA_ENGINE_IMAGE=$DATA_ENGINE_IMAGE
EOF

echo ""
echo "=== 6. Generando docker-compose para EC2 ==="

cat > "$BUNDLE_DIR/docker-compose.ec2.yml" <<EOF
services:
  ollama:
    image: ollama/ollama:latest
    container_name: jomelai_ollama
    restart: unless-stopped
    environment:
      - OLLAMA_NUM_PARALLEL=2
      - OLLAMA_MAX_LOADED_MODELS=1
      - OLLAMA_KEEP_ALIVE=10m
    volumes:
      - ./data/ollama:/root/.ollama
    ports:
      - "11434:11434"

  data_engine:
    image: ${DATA_ENGINE_IMAGE}
    container_name: jomelai_data_engine
    restart: unless-stopped
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - DUCKDB_PATH=/engine_storage/duckdb/silabos.duckdb
      - CHROMA_PATH=/engine_storage/chroma
      - JOBS_PATH=/engine_storage/jobs
      - SYLLABI_PATH=/data/syllabi
    volumes:
      - ./data/engine_storage:/engine_storage
      - ./data/data:/data
    depends_on:
      - ollama
    ports:
      - "8851:8000"

  backend:
    image: ${BACKEND_IMAGE}
    container_name: jomelai_backend
    restart: unless-stopped
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - DATA_ENGINE_URL=http://data_engine:8000
    depends_on:
      - ollama
      - data_engine
    ports:
      - "8847:80"

  frontend:
    image: ${FRONTEND_IMAGE}
    container_name: jomelai_frontend
    restart: unless-stopped
    depends_on:
      - backend
    ports:
      - "3000:80"
EOF

echo ""
echo "=== 7. Generando script de restauracion para EC2 ==="

cat > "$BUNDLE_DIR/restore_on_ec2.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "============================================================"
echo "Restaurando JoMelAi en EC2"
echo "Directorio: $(pwd)"
echo "============================================================"

echo ""
echo "=== 1. Instalando Docker si falta ==="

if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

sudo usermod -aG docker "$USER" || true

echo ""
echo "=== 2. Cargando imagenes snapshot ==="

gzip -dc images/backend_image.tar.gz | sudo docker load
gzip -dc images/frontend_image.tar.gz | sudo docker load
gzip -dc images/data_engine_image.tar.gz | sudo docker load

echo ""
echo "=== 3. Preparando permisos de datos ==="

mkdir -p data/engine_storage data/data data/ollama
sudo chown -R 0:0 data/ollama || true
sudo chmod -R a+rwX data/engine_storage data/data || true

echo ""
echo "=== 4. Deteniendo stack anterior si existe ==="

sudo docker compose -f docker-compose.ec2.yml down || true

echo ""
echo "=== 5. Levantando JoMelAi ==="

sudo docker compose -f docker-compose.ec2.yml up -d

echo ""
echo "=== 6. Estado ==="

sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "============================================================"
echo "JoMelAi deberia estar disponible en:"
echo "http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo TU_IP_PUBLICA):3000"
echo "Backend interno/publico: puerto 8847"
echo "Data engine: puerto 8851"
echo "Ollama: puerto 11434"
echo "============================================================"
EOF

chmod +x "$BUNDLE_DIR/restore_on_ec2.sh"

echo ""
echo "=== 8. Empaquetando bundle ==="

tar -C "$PWD" -czf "${BUNDLE_DIR}.tar.gz" "$(basename "$BUNDLE_DIR")"

echo "Bundle generado:"
du -sh "$BUNDLE_DIR" "${BUNDLE_DIR}.tar.gz"

echo ""
echo "=== 9. Subiendo bundle a EC2 ==="

ssh -i "$PEM_KEY" -o StrictHostKeyChecking=accept-new "$EC2_USER@$EC2_IP" "mkdir -p '$REMOTE_DIR'"

rsync -avz --progress \
  -e "ssh -i '$PEM_KEY' -o StrictHostKeyChecking=accept-new" \
  "${BUNDLE_DIR}.tar.gz" \
  "$EC2_USER@$EC2_IP:$REMOTE_DIR/"

echo ""
echo "=== 10. Descomprimiendo en EC2 ==="

ssh -i "$PEM_KEY" "$EC2_USER@$EC2_IP" "
  set -e
  cd '$REMOTE_DIR'
  tar xzf '$(basename "${BUNDLE_DIR}.tar.gz")'
  ln -sfn '$(basename "$BUNDLE_DIR")' current
  echo 'Bundle listo en $REMOTE_DIR/current'
"

echo ""
echo "============================================================"
echo "Subida completa."
echo ""
echo "Para restaurar y levantar en EC2 ejecuta:"
echo "ssh -i \"$PEM_KEY\" $EC2_USER@$EC2_IP"
echo "cd $REMOTE_DIR/current"
echo "bash restore_on_ec2.sh"
echo ""
echo "Luego abre:"
echo "http://$EC2_IP:3000"
echo "============================================================"
