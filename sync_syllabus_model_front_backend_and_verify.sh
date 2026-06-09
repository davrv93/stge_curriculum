#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Sync syllabus model front + backend + verify"
echo "=================================================="

TARGET_MODEL="${1:-llama3.2:1b}"
PUBLIC_IP="${2:-3.143.242.233}"
PUBLIC_BASE_URL="http://${PUBLIC_IP}:3000"

BACKUP_DIR="backups/sync_syllabus_model_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "TARGET_MODEL=$TARGET_MODEL"
echo "PUBLIC_BASE_URL=$PUBLIC_BASE_URL"
echo "BACKUP_DIR=$BACKUP_DIR"

echo
echo "== 1) Actualizando .env =="
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

set_env "PUBLIC_IP" "$PUBLIC_IP"
set_env "PUBLIC_BASE_URL" "$PUBLIC_BASE_URL"
set_env "APP_URL" "$PUBLIC_BASE_URL"
set_env "VITE_PUBLIC_BASE_URL" "$PUBLIC_BASE_URL"
set_env "VITE_API_BASE_URL" "/api"

# Modelo unico oficial para generacion de silabo
set_env "SYLLABUS_OLLAMA_MODEL" "$TARGET_MODEL"
set_env "VITE_SYLLABUS_OLLAMA_MODEL" "$TARGET_MODEL"
set_env "VITE_DEFAULT_SYLLABUS_MODEL" "$TARGET_MODEL"

# No permitir que el request del frontend cambie el modelo salvo que se active manualmente
set_env "SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE" "0"

# Ollama local
set_env "LLM_REMOTE_ENABLED" "0"
set_env "SYLLABUS_NUM_THREAD" "2"
set_env "SYLLABUS_KEEP_ALIVE" "30m"

echo
echo "== 2) Buscando PHP real del stream =="
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
  echo "ERROR: no encontre jm_handle_syllabus_stream."
  grep -R "function jm_handle_syllabus_stream" -n . --include='*.php' || true
  exit 1
fi

echo "PHP_FILE=$PHP_FILE"
cp "$PHP_FILE" "$BACKUP_DIR/$(basename "$PHP_FILE").bak"

echo
echo "== 3) Parchando backend para modelo oficial + eventos de verificacion =="
python3 - "$PHP_FILE" "$TARGET_MODEL" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
target_model = sys.argv[2]
text = p.read_text(encoding="utf-8")

# Quitar helper anterior de este script si existe.
text = re.sub(
    r"\n/\* JOMELAI_SYNC_SYLLABUS_MODEL_START \*/.*?/\* JOMELAI_SYNC_SYLLABUS_MODEL_END \*/\n",
    "\n",
    text,
    flags=re.S,
)

helpers = r'''
/* JOMELAI_SYNC_SYLLABUS_MODEL_START */

function jm_sync_read_dotenv_value($key)
{
    $key = trim((string)$key);

    if ($key === '') {
        return null;
    }

    $dirs = [];
    $dir = __DIR__;

    for ($i = 0; $i < 10; $i++) {
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

            return trim($v, "\"'");
        }
    }

    return null;
}

function jm_sync_env($key, $default = '')
{
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

    $dotenv = jm_sync_read_dotenv_value($key);

    if ($dotenv !== null && $dotenv !== '') {
        return $dotenv;
    }

    return $default;
}

function jm_sync_env_bool($key, $default = false)
{
    $raw = strtolower(trim((string)jm_sync_env($key, $default ? '1' : '0')));

    return in_array($raw, ['1', 'true', 'yes', 'si', 'sí', 'on'], true);
}

function jm_sync_syllabus_model($requestModel = '')
{
    $requestModel = trim((string)$requestModel);
    $envModel = trim((string)jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'));
    $allowOverride = jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false);

    if ($allowOverride && $requestModel !== '') {
        return $requestModel;
    }

    if ($envModel !== '') {
        return $envModel;
    }

    return 'llama3.2:1b';
}

/* JOMELAI_SYNC_SYLLABUS_MODEL_END */
'''

idx = text.find("function jm_handle_syllabus_stream()")
if idx == -1:
    raise SystemExit("No encontre function jm_handle_syllabus_stream().")

text = text[:idx] + helpers + "\n\n" + text[idx:]

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
    raise SystemExit("No pude detectar el final de jm_handle_syllabus_stream().")

end = min(positions)
before = text[:start]
func = text[start:end]
after = text[end:]

# Remover selecciones previas de modelo dentro de la funcion.
patterns = [
    r"\$model\s*=\s*trim\(\(string\)\(\$data\['model'\]\s*\?\?.*?\)\);\s*if\s*\(\$model\s*===\s*''\)\s*\{\s*\$model\s*=\s*['\"][^'\"]+['\"];\s*\}",
    r"\$requestModel\s*=\s*trim\(\(string\)\(\$data\['model'\]\s*\?\?\s*''\)\);\s*\$model\s*=\s*jm_syllabus_selected_model\(\$requestModel\);",
    r"\$requestModel\s*=\s*trim\(\(string\)\(\$data\['model'\]\s*\?\?\s*''\)\);\s*\$model\s*=\s*jm_force_syllabus_model\(\$requestModel\);",
    r"\$requestModel\s*=\s*trim\(\(string\)\(\$data\['model'\]\s*\?\?\s*''\)\);\s*\$model\s*=\s*jm_sync_syllabus_model\(\$requestModel\);",
]

for pat in patterns:
    func = re.sub(pat, "", func, count=1, flags=re.S)

# Insertar seleccion oficial despues de validar course.
if "$model = jm_sync_syllabus_model($requestModel);" not in func:
    m = re.search(
        r"(if\s*\(\$course\s*===\s*''\)\s*\{\s*jm_stream_json_response\(\['ok'\s*=>\s*false,\s*'message'\s*=>\s*'El nombre del curso es obligatorio\.'\],\s*422\);\s*\})",
        func,
        flags=re.S,
    )
    if not m:
        raise SystemExit("No pude ubicar validacion de course.")

    insert = m.group(1) + r'''

    $requestModel = trim((string)($data['model'] ?? ''));
    $model = jm_sync_syllabus_model($requestModel);'''

    func = func[:m.start()] + insert + func[m.end():]

# Agregar metadata dentro de tokens_config, solo una vez.
if "'model_env' => jm_sync_env('SYLLABUS_OLLAMA_MODEL'" not in func:
    func = func.replace(
        "'model' => $model,",
        "'model' => $model,\n        'model_env' => jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),\n        'request_model' => $requestModel,\n        'request_model_ignored' => !jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),\n        'request_model_override' => jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),",
        1,
    )

# Emitir evento model_resolved despues de jm_sse_start(); si existe.
if "event' => 'model_resolved'" not in func and "jm_sse_send('model_resolved'" not in func:
    func = func.replace(
        "jm_sse_start();",
        """jm_sse_start();

    jm_sse_send('model_resolved', [
        'ok' => true,
        'event' => 'model_resolved',
        'provider' => 'ollama_local',
        'model' => $model,
        'model_env' => jm_sync_env('SYLLABUS_OLLAMA_MODEL', 'llama3.2:1b'),
        'request_model' => $requestModel,
        'request_model_ignored' => !jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'request_model_override' => jm_sync_env_bool('SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE', false),
        'verification' => 'Confirmar con Ollama /api/ps mientras genera.',
    ]);""",
        1,
    )

text = before + func + after
p.write_text(text, encoding="utf-8")
PY

echo
echo "== 4) Validando PHP =="
if command -v php >/dev/null 2>&1; then
  php -l "$PHP_FILE"
else
  echo "PHP no esta instalado en host."
fi

echo
echo "== 5) Copiando .env junto al PHP si aplica =="
PHP_DIR="$(dirname "$PHP_FILE")"
if [ "$PHP_DIR" != "." ]; then
  cp .env "$PHP_DIR/.env" || true
fi

echo
echo "== 6) Creando shim frontend para sincronizar model en requests =="
mkdir -p public

cat > public/jomelai-syllabus-model-sync.js <<JS
(function () {
  var MODEL = "${TARGET_MODEL}";
  window.JOMELAI_SYLLABUS_MODEL = MODEL;

  console.log("[JoMelAi] Syllabus model sync activo:", MODEL);

  var originalFetch = window.fetch;

  if (!originalFetch || originalFetch.__jomelaiSyllabusModelSync) {
    return;
  }

  function isSyllabusUrl(input) {
    var url = "";

    if (typeof input === "string") {
      url = input;
    } else if (input && input.url) {
      url = input.url;
    }

    return url.indexOf("/api/assistant/generate-syllabus-stream") !== -1;
  }

  function cloneOptions(init) {
    var out = {};
    init = init || {};

    Object.keys(init).forEach(function (k) {
      out[k] = init[k];
    });

    return out;
  }

  window.fetch = function (input, init) {
    if (!isSyllabusUrl(input)) {
      return originalFetch.apply(this, arguments);
    }

    var opts = cloneOptions(init);

    try {
      var body = opts.body;

      if (typeof body === "string" && body.trim().charAt(0) === "{") {
        var payload = JSON.parse(body);

        var previous = payload.model;
        payload.model = MODEL;

        opts.body = JSON.stringify(payload);

        console.log("[JoMelAi] Syllabus request model sincronizado", {
          previous_model: previous,
          model: MODEL,
          url: typeof input === "string" ? input : input.url
        });

        return originalFetch.call(this, input, opts);
      }
    } catch (e) {
      console.warn("[JoMelAi] No se pudo sincronizar model del request:", e);
    }

    return originalFetch.apply(this, arguments);
  };

  window.fetch.__jomelaiSyllabusModelSync = true;
})();
JS

echo
echo "== 7) Parchando fuentes frontend donde aparezca qwen hardcodeado =="
FRONT_FILES="$(find . \
  -type f \
  \( -name '*.js' -o -name '*.ts' -o -name '*.html' -o -name '*.json' \) \
  ! -path './.git/*' \
  ! -path './node_modules/*' \
  ! -path './vendor/*' \
  ! -path './data/*' \
  ! -path './backups/*' \
  2>/dev/null || true)"

if [ -n "$FRONT_FILES" ]; then
  echo "$FRONT_FILES" | while read f; do
    [ -f "$f" ] || continue

    if grep -q "qwen2.5:0.5b\|qwen2.5:1.5b\|qwen2.5-coder:3b" "$f" 2>/dev/null; then
      safe_name="$(echo "$f" | sed 's#^\./##' | tr '/' '_')"
      cp "$f" "$BACKUP_DIR/${safe_name}.bak" || true

      sed -i "s#qwen2.5:0.5b#${TARGET_MODEL}#g" "$f"
      sed -i "s#qwen2.5:1.5b#${TARGET_MODEL}#g" "$f"
      sed -i "s#qwen2.5-coder:3b#${TARGET_MODEL}#g" "$f"

      echo "frontend actualizado: $f"
    fi
  done
fi

echo
echo "== 8) Detectando frontend activo e inyectando shim =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "WARN: no detecte contenedor frontend."
else
  echo "FRONT_CONTAINER=$FRONT_CONTAINER"

  CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
    if command -v nginx >/dev/null 2>&1; then
      nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
    fi
  ' || true)"

  if [ -z "$CONTAINER_ROOT" ]; then
    CONTAINER_ROOT="/usr/share/nginx/html"
  fi

  echo "CONTAINER_ROOT=$CONTAINER_ROOT"

  docker cp public/jomelai-syllabus-model-sync.js "$FRONT_CONTAINER:$CONTAINER_ROOT/jomelai-syllabus-model-sync.js"

  INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
    for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
      [ -f \"\$f\" ] && echo \"\$f\" && exit 0
    done
    exit 0
  " || true)"

  if [ -n "$INDEX_FILE" ]; then
    echo "INDEX_FILE=$INDEX_FILE"
    docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.active.original.html"

    cp "$BACKUP_DIR/index.active.original.html" "$BACKUP_DIR/index.active.patched.html"

    python3 - "$BACKUP_DIR/index.active.patched.html" <<'PY'
from pathlib import Path
import re

p = Path(__import__("sys").argv[1])
text = p.read_text(encoding="utf-8")

# Quitar duplicados previos.
text = re.sub(
    r'\s*<script[^>]+src=["\']/jomelai-syllabus-model-sync\.js[^"\']*["\'][^>]*></script>',
    '',
    text,
    flags=re.I,
)

tag = '<script src="/jomelai-syllabus-model-sync.js?v=sync-model"></script>'

if '</head>' in text:
    text = text.replace('</head>', '  ' + tag + '\n</head>', 1)
elif '</body>' in text:
    text = text.replace('</body>', '  ' + tag + '\n</body>', 1)
else:
    text += '\n' + tag + '\n'

p.write_text(text, encoding="utf-8")
PY

    docker cp "$BACKUP_DIR/index.active.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

    docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true
  fi
fi

echo
echo "== 9) Precalentando modelo en Ollama =="
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

    echo \"Warm-up...\"
    curl -sS http://127.0.0.1:11434/api/generate \
      -H 'Content-Type: application/json' \
      -d '{\"model\":\"${TARGET_MODEL}\",\"prompt\":\"Responde OK\",\"stream\":false,\"keep_alive\":\"30m\",\"options\":{\"num_predict\":4,\"num_ctx\":1024,\"num_thread\":2}}' \
      | head -c 300 || true
    echo
  " || true
fi

echo
echo "== 10) Reiniciando/reconstruyendo sin borrar volumenes =="
docker compose up -d --build

sleep 8

echo
echo "== 11) Test de endpoint y modelo resuelto =="
echo "Si sale 401, prueba desde navegador autenticado."

time curl -sS -N -m 180 -X POST http://localhost:3000/api/assistant/generate-syllabus-stream \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"qwen2.5:0.5b\",
    \"course\": \"calculo diferencial\",
    \"program\": \"ingenieria de sistemas\",
    \"credits\": \"4\",
    \"cycle\": \"3\",
    \"weeks\": \"16\",
    \"modality\": \"Presencial\",
    \"graduate_profile\": \"capacidad de decision\",
    \"competency\": \"calculo de integrales\",
    \"start_date\": \"\",
    \"sessions_per_week\": \"1\",
    \"use_ai_seed\": true,
    \"context_limit\": 1,
    \"ai_timeout\": 120
  }" | grep -E "event: model_resolved|event: config|model|model_env|request_model|request_model_ignored|provider" | head -60 || true

echo
echo
echo "== 12) Verificacion directa de Ollama /api/ps =="
if [ -n "${OLLAMA_CONTAINER:-}" ]; then
  docker exec "$OLLAMA_CONTAINER" sh -lc 'curl -s http://127.0.0.1:11434/api/ps || true'
fi

echo
echo
echo "== 13) Stats =="
docker stats --no-stream | grep -E 'ollama|frontend|backend|data' || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Modelo sincronizado:"
echo "  $TARGET_MODEL"
echo
echo "Frontend:"
echo "  window.JOMELAI_SYLLABUS_MODEL=$TARGET_MODEL"
echo "  shim: /jomelai-syllabus-model-sync.js"
echo
echo "Backend:"
echo "  SYLLABUS_OLLAMA_MODEL=$TARGET_MODEL"
echo "  SYLLABUS_ALLOW_REQUEST_MODEL_OVERRIDE=0"
echo
echo "Para verificar el modelo REAL mientras genera:"
echo "  docker exec $OLLAMA_CONTAINER sh -lc 'curl -s http://127.0.0.1:11434/api/ps'"
echo
echo "En navegador, consola debe mostrar:"
echo "  [JoMelAi] Syllabus model sync activo: $TARGET_MODEL"
echo
echo "En Network del stream debe aparecer:"
echo "  event: model_resolved"
echo "  model: $TARGET_MODEL"
echo
echo "Abre:"
echo "  $PUBLIC_BASE_URL/#silabos"
echo "y haz Ctrl+Shift+R."
