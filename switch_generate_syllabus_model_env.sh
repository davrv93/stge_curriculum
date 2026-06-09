#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Switch generate-syllabus-stream model by ENV"
echo " Default now: llama3.2:1b"
echo "=================================================="

BACKUP_DIR="backups/switch_syllabus_model_env_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

TARGET_MODEL="${1:-llama3.2:1b}"

echo "TARGET_MODEL=$TARGET_MODEL"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Buscando archivo PHP del stream =="
PHP_FILE="$(grep -Rsl "function jm_handle_syllabus_stream" . \
  --include='*.php' \
  --exclude-dir=.git \
  --exclude-dir=vendor \
  --exclude-dir=node_modules \
  --exclude-dir=data \
  --exclude-dir=backups \
  --exclude='*.bak*' \
  | head -1 || true)"

if [ -z "$PHP_FILE" ] || [ ! -f "$PHP_FILE" ]; then
  echo "ERROR: no encontre el PHP con jm_handle_syllabus_stream."
  grep -R "function jm_handle_syllabus_stream" -n . --include='*.php' || true
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"
cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 2) Parchando seleccion de modelo por variable de entorno =="
python3 - "$PHP_FILE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# ------------------------------------------------------------
# Helper robusto para leer env:
# - getenv()
# - Support::config()
# - .env cercano al archivo PHP, subiendo directorios
# ------------------------------------------------------------
text = re.sub(
    r"\n/\* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_START \*/.*?/\* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_END \*/\n",
    "\n",
    text,
    flags=re.S,
)

helpers = r'''
/* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_START */

function jm_syllabus_read_dotenv_value($key)
{
    $key = trim((string)$key);

    if ($key === '') {
        return null;
    }

    $dirs = [];
    $dir = __DIR__;

    for ($i = 0; $i < 8; $i++) {
        if (!$dir || $dir === '/' || in_array($dir, $dirs, true)) {
            break;
        }

        $dirs[] = $dir;
        $parent = dirname($dir);

        if ($parent === $dir) {
            break;
        }

        $dir = $parent;
    }

    foreach ($dirs as $d) {
        $file = rtrim($d, '/') . '/.env';

        if (!is_file($file) || !is_readable($file)) {
            continue;
        }

        $lines = @file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

        if (!is_array($lines)) {
            continue;
        }

        foreach ($lines as $line) {
            $line = trim($line);

            if ($line === '' || strpos($line, '#') === 0) {
                continue;
            }

            if (strpos($line, '=') === false) {
                continue;
            }

            [$k, $v] = explode('=', $line, 2);

            $k = trim($k);
            $v = trim($v);

            if ($k !== $key) {
                continue;
            }

            $v = trim($v, "\"'");

            return $v;
        }
    }

    return null;
}

function jm_syllabus_env_value($key, $default = '')
{
    $key = trim((string)$key);

    if ($key === '') {
        return $default;
    }

    $value = getenv($key);

    if ($value !== false && $value !== '') {
        return $value;
    }

    if (isset($_ENV[$key]) && $_ENV[$key] !== '') {
        return $_ENV[$key];
    }

    if (isset($_SERVER[$key]) && $_SERVER[$key] !== '') {
        return $_SERVER[$key];
    }

    if (function_exists('jm_stream_config')) {
        try {
            $configKey = strtolower($key);
            $value = jm_stream_config($configKey, '');

            if ($value !== null && $value !== '') {
                return $value;
            }
        } catch (Throwable $e) {
            // fallback
        }
    }

    $value = jm_syllabus_read_dotenv_value($key);

    if ($value !== null && $value !== '') {
        return $value;
    }

    return $default;
}

function jm_syllabus_env_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_syllabus_env_value($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_syllabus_selected_model($requestModel = '')
{
    /*
     * Regla:
     * - Por defecto manda .env: SYLLABUS_OLLAMA_MODEL
     * - Si quieres que el frontend pueda sobrescribir modelo:
     *   SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE=1
     */
    $envModel = trim((string)jm_syllabus_env_value('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $requestModel = trim((string)$requestModel);
    $allowOverride = jm_syllabus_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    if ($envModel !== '') {
        return $envModel;
    }

    if ($requestModel !== '') {
        return $requestModel;
    }

    return 'llama3.2:1b';
}

/* JOMELAI_SYLLABUS_MODEL_ENV_HELPERS_END */
'''

idx = text.find("function jm_handle_syllabus_stream()")

if idx == -1:
    raise SystemExit("No encontre function jm_handle_syllabus_stream().")

text = text[:idx] + helpers + "\n\n" + text[idx:]

# ------------------------------------------------------------
# Encontrar funcion jm_handle_syllabus_stream completa
# ------------------------------------------------------------
start = text.find("function jm_handle_syllabus_stream()")

markers = [
    "\n$__jm_path = jm_stream_path();",
    "\nif ($__jm_path === '/api/ask-stream')",
]

positions = []
for marker in markers:
    pos = text.find(marker, start)
    if pos != -1:
        positions.append(pos)

if not positions:
    raise SystemExit("No pude detectar fin de jm_handle_syllabus_stream().")

end = min(positions)

before = text[:start]
func = text[start:end]
after = text[end:]

# ------------------------------------------------------------
# Reemplazar bloque de seleccion de modelo dentro de jm_handle_syllabus_stream
# Soporta variantes anteriores: qwen, coder, llama, multi-phase, etc.
# ------------------------------------------------------------
pattern = re.compile(
    r"""
    \$model\s*=\s*trim\(\(string\)\((?:.|\n)*?\)\);\s*
    if\s*\(\$model\s*===\s*''\)\s*\{\s*
        \$model\s*=\s*['"][^'"]+['"];\s*
    \}
    """,
    re.X,
)

replacement = """$requestModel = trim((string)($data['model'] ?? ''));
    $model = jm_syllabus_selected_model($requestModel);"""

new_func, count = pattern.subn(replacement, func, count=1)

if count == 0:
    # Fallback: insertar despues de validar course.
    course_block = re.search(
        r"(if\s*\(\$course\s*===\s*''\)\s*\{\s*jm_stream_json_response\(\['ok'\s*=>\s*false,\s*'message'\s*=>\s*'El nombre del curso es obligatorio\.'\],\s*422\);\s*\})",
        func,
        flags=re.S,
    )

    if not course_block:
        raise SystemExit("No pude reemplazar ni insertar seleccion de modelo.")

    insert = course_block.group(1) + """

    $requestModel = trim((string)($data['model'] ?? ''));
    $model = jm_syllabus_selected_model($requestModel);"""

    new_func = func[:course_block.start()] + insert + func[course_block.end():]

func = new_func

# ------------------------------------------------------------
# Asegurar que tokens_config reporte modelo/env/override
# ------------------------------------------------------------
if "'model_env' => jm_syllabus_env_value('SYLLABUS_OLLAMA_MODEL'" not in func:
    func = func.replace(
        "'model' => $model,",
        "'model' => $model,\n        'model_env' => jm_syllabus_env_value('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),\n        'request_model_override' => jm_syllabus_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),",
        1,
    )

text = before + func + after

p.write_text(text, encoding="utf-8")
PY

echo
echo "== 3) Validando sintaxis PHP =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host; se validara al levantar contenedor si aplica."
fi

echo
echo "== 4) Actualizando .env para usar llama3.2:1b ahora =="
touch .env
cp .env "$BACKUP_DIR/.env.bak"

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s#^${key}=.*#${key}=${value}#g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "SYLLABUS_OLLAMA_MODEL" "$TARGET_MODEL"
set_env "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE" "0"
set_env "SYLLABUS_NUM_THREAD" "2"
set_env "SYLLABUS_KEEP_ALIVE" "30m"

# Desactivar remoto para que se pruebe Ollama local, si antes activaste remoto.
set_env "LLM_REMOTE_ENABLED" "0"

echo
echo "== 5) Sincronizando .env cerca del PHP si el archivo esta montado en otra ruta =="
PHP_DIR="$(dirname "$PHP_FILE")"

if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
fi

echo
echo "== 6) Precalentando modelo en Ollama =="
OLLAMA_CONTAINER="$(docker ps --format '{{.Names}} {{.Image}}' | grep -Ei 'ollama' | head -1 | awk '{print $1}' || true)"

if [ -z "$OLLAMA_CONTAINER" ]; then
  echo "WARN: no detecte contenedor Ollama."
else
  echo "OLLAMA_CONTAINER=$OLLAMA_CONTAINER"

  docker exec "$OLLAMA_CONTAINER" sh -lc "
    if ollama list | grep -q \"${TARGET_MODEL}\"; then
      echo \"${TARGET_MODEL} ya existe.\"
    else
      echo \"Descargando ${TARGET_MODEL}...\"
      ollama pull \"${TARGET_MODEL}\"
    fi

    echo \"Warm-up ${TARGET_MODEL}...\"
    curl -sS http://127.0.0.1:11434/api/generate \
      -H 'Content-Type: application/json' \
      -d '{\"model\":\"${TARGET_MODEL}\",\"prompt\":\"Responde OK\",\"stream\":false,\"keep_alive\":\"30m\",\"options\":{\"num_predict\":4,\"num_ctx\":1024,\"num_thread\":2}}' \
      | head -c 300 || true
    echo
  " || true
fi

echo
echo "== 7) Reiniciando/reconstruyendo sin borrar volumenes =="
docker compose up -d --build

sleep 5

echo
echo "== 8) Verificando parche =="
grep -R "jm_syllabus_selected_model\|SYLLABUS_OLLAMA_MODEL\|model_env\|request_model_override" -n "$PHP_FILE" | head -80 || true

echo
echo "== 9) Test publico del endpoint real =="
echo "Si responde 401, es normal si requiere sesion. En navegador autenticado debe funcionar."

time curl -sS -N -m 160 -X POST http://localhost:3000/api/assistant/generate-syllabus-stream \
  -H "Content-Type: application/json" \
  -d "{
    \"course\": \"Investigación\",
    \"program\": \"Ingeniería de Sistemas\",
    \"credits\": \"3\",
    \"cycle\": \"VIII\",
    \"weeks\": 16,
    \"sessions_per_week\": 1,
    \"modality\": \"Presencial\"
  }" | head -c 4000 || true

echo
echo
echo "== 10) Stats Ollama =="
docker stats --no-stream | grep -E 'ollama|frontend|backend|data' || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Modelo activo por .env:"
echo "  SYLLABUS_OLLAMA_MODEL=$TARGET_MODEL"
echo
echo "Override desde frontend:"
echo "  SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE=0"
echo
echo "Para cambiar a Qwen luego:"
echo "  sed -i 's#^SYLLABUS_OLLAMA_MODEL=.*#SYLLABUS_OLLAMA_MODEL=qwen2.5:1.5b#g' .env"
echo "  docker exec $OLLAMA_CONTAINER ollama pull qwen2.5:1.5b"
echo "  docker compose up -d --build"
echo
echo "Para volver a llama:"
echo "  sed -i 's#^SYLLABUS_OLLAMA_MODEL=.*#SYLLABUS_OLLAMA_MODEL=llama3.2:1b#g' .env"
echo "  docker compose up -d --build"
echo
echo "En Network/config debes ver:"
echo "  model: $TARGET_MODEL"
echo "  model_env: $TARGET_MODEL"
