#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# JoMelAI - Fix Ollama timeout / backend / data-engine
# Ejecutar desde la raíz del proyecto donde está docker-compose.yml
# NO borra volúmenes, NO ejecuta down -v.
# ============================================================

ROOT_DIR="${1:-$(pwd)}"
cd "$ROOT_DIR"

TS="$(date +%Y%m%d_%H%M%S)"

log() {
  echo ""
  echo "==> $1"
}

fail() {
  echo "ERROR: $1"
  exit 1
}

require_file() {
  [ -f "$1" ] || fail "No existe $1. Ejecuta este script desde la raíz del proyecto."
}

backup_file() {
  if [ -f "$1" ]; then
    cp "$1" "$1.bak.$TS"
    echo "Backup: $1.bak.$TS"
  fi
}

command -v docker >/dev/null 2>&1 || fail "Docker no está instalado o no está en PATH."
command -v python3 >/dev/null 2>&1 || fail "python3 no está instalado o no está en PATH."

require_file "docker-compose.yml"
require_file "backend/config/app.php"
require_file "backend/src/OllamaClient.php"

log "Creando backups"
touch .env
backup_file ".env"
backup_file "docker-compose.yml"
backup_file "backend/config/app.php"
backup_file "backend/src/OllamaClient.php"

if [ -f "data-engine/app.py" ]; then
  backup_file "data-engine/app.py"
fi

log "Actualizando .env"
python3 - <<'PY'
from pathlib import Path

env_path = Path(".env")
raw = env_path.read_text(encoding="utf-8") if env_path.exists() else ""

updates = {
    "OLLAMA_BASE_URL": "http://ollama:11434",
    "OLLAMA_MODEL": "qwen2.5-coder:3b",
    "OLLAMA_HTTP_TIMEOUT": "180",
    "OLLAMA_PLAN_TIMEOUT": "180",
    "OLLAMA_PLAN_CTX": "2048",
    "OLLAMA_PLAN_PREDICT": "120",
    "OLLAMA_KEEP_ALIVE": "10m",
    "EMBED_MODEL": "nomic-embed-text",
    "INTENT_ENGINE_MODE": "auto",
    "OLLAMA_INTENT_MODEL": "qwen2.5-coder:3b",
    "FAST_INTENT_MIN_CONFIDENCE": "0.90",
    "OLLAMA_INTENT_TIMEOUT": "180",
}

lines = raw.splitlines()
seen = set()
out = []

for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue

    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)

if out and out[-1].strip():
    out.append("")

out.append("# JoMelAI Ollama/Data Engine tuning")
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")

env_path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
print("OK .env actualizado")
PY

log "Actualizando docker-compose.yml"
python3 - <<'PY'
from pathlib import Path
import re

path = Path("docker-compose.yml")
text = path.read_text(encoding="utf-8")

# Elimina warning de Compose moderno si existe.
text = re.sub(r'^\s*version:\s*["\'][^"\']+["\']\s*\n+', '', text, count=1, flags=re.M)

def get_service_block(text: str, service: str):
    pattern = rf"(?ms)^  {re.escape(service)}:\n.*?(?=^  [A-Za-z0-9_-]+:\n|^networks:|^volumes:|\Z)"
    m = re.search(pattern, text)
    return m

def ensure_env_lines(text: str, service: str, env_lines: list[str]) -> str:
    m = get_service_block(text, service)
    if not m:
        print(f"AVISO: no encontré servicio {service}")
        return text

    block = m.group(0)

    if "    environment:" not in block:
        # Insertar environment antes de networks/depends_on/restart/expose/volumes si no existe.
        insert = "    environment:\n" + "\n".join(env_lines) + "\n"
        anchor = re.search(r"(?m)^    (networks|restart|depends_on|expose|volumes):", block)
        if anchor:
            block = block[:anchor.start()] + insert + block[anchor.start():]
        else:
            block = block.rstrip() + "\n" + insert
    else:
        for line in env_lines:
            key = line.strip().split(":", 1)[0]
            if re.search(rf"(?m)^\s*{re.escape(key)}\s*:", block):
                continue

            env_pos = block.find("    environment:")
            after_env = block.find("\n", env_pos) + 1

            # Preferimos insertar después de OLLAMA_DEFAULT_MODEL / OLLAMA_MODEL si existe.
            candidates = [
                "OLLAMA_DEFAULT_MODEL:",
                "OLLAMA_MODEL:",
                "OLLAMA_BASE_URL:",
                "DATA_ENGINE_BASE_URL:",
            ]

            insert_pos = None
            for candidate in candidates:
                mm = re.search(rf"(?m)^      {re.escape(candidate)}.*\n", block)
                if mm:
                    insert_pos = mm.end()

            if insert_pos is None:
                insert_pos = after_env

            block = block[:insert_pos] + line + "\n" + block[insert_pos:]

    return text[:m.start()] + block + text[m.end():]

backend_env = [
    "      OLLAMA_BASE_URL: http://ollama:11434",
    "      OLLAMA_DEFAULT_MODEL: ${OLLAMA_MODEL:-qwen2.5-coder:3b}",
    "      OLLAMA_HTTP_TIMEOUT: ${OLLAMA_HTTP_TIMEOUT:-180}",
    "      OLLAMA_PLAN_TIMEOUT: ${OLLAMA_PLAN_TIMEOUT:-180}",
    "      OLLAMA_PLAN_CTX: ${OLLAMA_PLAN_CTX:-2048}",
    "      OLLAMA_PLAN_PREDICT: ${OLLAMA_PLAN_PREDICT:-120}",
    "      OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-10m}",
]

data_engine_env = [
    "      OLLAMA_BASE_URL: http://ollama:11434",
    "      OLLAMA_MODEL: ${OLLAMA_MODEL:-qwen2.5-coder:3b}",
    "      OLLAMA_INTENT_MODEL: ${OLLAMA_INTENT_MODEL:-qwen2.5-coder:3b}",
    "      INTENT_ENGINE_MODE: ${INTENT_ENGINE_MODE:-auto}",
    "      FAST_INTENT_MIN_CONFIDENCE: ${FAST_INTENT_MIN_CONFIDENCE:-0.90}",
    "      OLLAMA_INTENT_TIMEOUT: ${OLLAMA_INTENT_TIMEOUT:-180}",
    "      EMBED_MODEL: ${EMBED_MODEL:-nomic-embed-text}",
    "      PYTHONPATH: /app",
]

text = ensure_env_lines(text, "backend", backend_env)
text = ensure_env_lines(text, "data-engine", data_engine_env)

# Asegurar depends_on de backend hacia ollama.
m = get_service_block(text, "backend")
if m:
    block = m.group(0)
    if "    depends_on:" in block:
        dep_match = re.search(r"(?m)^    depends_on:\n(?P<body>(?:      - .+\n)+)", block)
        if dep_match and "- ollama" not in dep_match.group("body"):
            body_end = dep_match.end("body")
            block = block[:body_end] + "      - ollama\n" + block[body_end:]
    else:
        anchor = re.search(r"(?m)^    networks:", block)
        insert = "    depends_on:\n      - data-engine\n      - ollama\n"
        if anchor:
            block = block[:anchor.start()] + insert + block[anchor.start():]
        else:
            block = block.rstrip() + "\n" + insert
    text = text[:m.start()] + block + text[m.end():]

# Asegurar depends_on de data-engine hacia ollama.
m = get_service_block(text, "data-engine")
if m:
    block = m.group(0)
    if "    depends_on:" in block:
        dep_match = re.search(r"(?m)^    depends_on:\n(?P<body>(?:      - .+\n)+)", block)
        if dep_match and "- ollama" not in dep_match.group("body"):
            body_end = dep_match.end("body")
            block = block[:body_end] + "      - ollama\n" + block[body_end:]
    else:
        anchor = re.search(r"(?m)^    networks:", block)
        insert = "    depends_on:\n      - ollama\n"
        if anchor:
            block = block[:anchor.start()] + insert + block[anchor.start():]
        else:
            block = block.rstrip() + "\n" + insert
    text = text[:m.start()] + block + text[m.end():]

path.write_text(text, encoding="utf-8")
print("OK docker-compose.yml actualizado")
PY

log "Actualizando backend/config/app.php"
python3 - <<'PY'
from pathlib import Path
import re

path = Path("backend/config/app.php")
text = path.read_text(encoding="utf-8")

replacements = {
    "ollama_base_url": "'ollama_base_url' => getenv('OLLAMA_BASE_URL') ?: 'http://ollama:11434',",
    "ollama_default_model": "'ollama_default_model' => getenv('OLLAMA_DEFAULT_MODEL') ?: (getenv('OLLAMA_MODEL') ?: 'qwen2.5-coder:3b'),",
    "ollama_http_timeout": "'ollama_http_timeout' => (int)(getenv('OLLAMA_HTTP_TIMEOUT') ?: 180),",
    "ollama_plan_timeout": "'ollama_plan_timeout' => (int)(getenv('OLLAMA_PLAN_TIMEOUT') ?: 180),",
    "ollama_plan_ctx": "'ollama_plan_ctx' => (int)(getenv('OLLAMA_PLAN_CTX') ?: 2048),",
    "ollama_plan_predict": "'ollama_plan_predict' => (int)(getenv('OLLAMA_PLAN_PREDICT') ?: 120),",
    "ollama_keep_alive": "'ollama_keep_alive' => getenv('OLLAMA_KEEP_ALIVE') ?: '10m',",
}

for key, new_line in replacements.items():
    pattern = rf"(?m)^\s*'{re.escape(key)}'\s*=>.*?,\s*$"
    if re.search(pattern, text):
        text = re.sub(pattern, "    " + new_line, text)
    else:
        # Insertar después de ollama_default_model si existe; si no, antes del cierre del array.
        anchor = re.search(r"(?m)^\s*'ollama_default_model'\s*=>.*?,\s*$", text)
        if anchor:
            pos = anchor.end()
            text = text[:pos] + "\n    " + new_line + text[pos:]
        else:
            close = text.rfind("];")
            if close != -1:
                text = text[:close] + "    " + new_line + "\n" + text[close:]

path.write_text(text, encoding="utf-8")
print("OK backend/config/app.php actualizado")
PY

log "Reemplazando backend/src/OllamaClient.php con versión robusta"
cat > backend/src/OllamaClient.php <<'PHP'
<?php

final class OllamaClient
{
    private string $baseUrl;

    public function __construct()
    {
        $this->baseUrl = rtrim((string)Support::config('ollama_base_url'), '/');
    }

    public function health(): array
    {
        try {
            $result = $this->request('GET', '/api/tags', null, 10);
            return [
                'ok' => true,
                'base_url' => $this->baseUrl,
                'models' => $result['models'] ?? [],
            ];
        } catch (Throwable $e) {
            return [
                'ok' => false,
                'base_url' => $this->baseUrl,
                'message' => $e->getMessage(),
                'models' => [],
            ];
        }
    }

    public function models(): array
    {
        return $this->health();
    }

    public function generate(string $prompt, ?string $model = null, array $options = [], ?int $timeoutSeconds = null): array
    {
        $model = $model ?: Support::config('ollama_default_model');

        $payload = [
            'model' => $model,
            'prompt' => $prompt,
            'stream' => false,
            'keep_alive' => Support::config('ollama_keep_alive') ?: '10m',
            'options' => array_merge([
                'temperature' => 0.20,
                'top_p' => 0.85,
                'num_ctx' => (int)Support::config('ollama_plan_ctx'),
                'num_predict' => (int)Support::config('ollama_plan_predict'),
                'repeat_penalty' => 1.08,
            ], $options),
        ];

        return $this->request('POST', '/api/generate', $payload, $timeoutSeconds);
    }

    public function generateFast(string $prompt, ?string $model = null, array $options = [], ?int $timeoutSeconds = null): array
    {
        $options = array_merge([
            'temperature' => 0.15,
            'top_p' => 0.82,
            'num_ctx' => (int)Support::config('ollama_plan_ctx'),
            'num_predict' => (int)Support::config('ollama_plan_predict'),
            'repeat_penalty' => 1.08,
        ], $options);

        return $this->generate(
            $prompt,
            $model,
            $options,
            $timeoutSeconds ?: (int)Support::config('ollama_plan_timeout')
        );
    }

    private function request(string $method, string $path, ?array $payload = null, ?int $timeoutSeconds = null): array
    {
        $url = $this->baseUrl . $path;

        $timeout = max(1, $timeoutSeconds ?: (int)Support::config('ollama_http_timeout'));

        $headers = [
            'Content-Type: application/json',
            'Connection: close',
        ];

        $opts = [
            'http' => [
                'method' => $method,
                'header' => implode("\r\n", $headers),
                'timeout' => $timeout,
                'ignore_errors' => true,
            ],
        ];

        if ($payload !== null) {
            $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            if ($encoded === false) {
                throw new RuntimeException('No se pudo serializar el payload para Ollama.');
            }
            $opts['http']['content'] = $encoded;
        }

        $context = stream_context_create($opts);
        $started = microtime(true);
        $raw = @file_get_contents($url, false, $context);
        $elapsed = round(microtime(true) - $started, 3);

        if ($raw === false) {
            $last = error_get_last();
            $detail = is_array($last) && isset($last['message']) ? $last['message'] : 'sin detalle';

            throw new RuntimeException(
                'No se pudo completar la llamada a Ollama en ' . $this->baseUrl .
                '. Posible timeout o corte de conexión. Timeout=' . $timeout .
                's, elapsed=' . $elapsed . 's. Detalle: ' . $detail
            );
        }

        $statusLine = $http_response_header[0] ?? 'HTTP/1.1 200 OK';
        if (!preg_match('/\s(\d{3})\s/', $statusLine, $m)) {
            $status = 200;
        } else {
            $status = (int)$m[1];
        }

        $json = json_decode($raw, true);

        if ($status >= 400) {
            throw new RuntimeException(
                'Ollama respondió HTTP ' . $status .
                ' en ' . $elapsed . 's. Respuesta: ' . Support::strLimit($raw, 800)
            );
        }

        if (!is_array($json)) {
            throw new RuntimeException(
                'Respuesta inválida de Ollama en ' . $elapsed .
                's: ' . Support::strLimit($raw, 800)
            );
        }

        return $json;
    }
}
PHP

log "Corrigiendo data-engine/app.py si existe"
if [ -f "data-engine/app.py" ]; then
python3 - <<'PY'
from pathlib import Path
import re

path = Path("data-engine/app.py")
text = path.read_text(encoding="utf-8")

replacement = '''def embed_one(text: str) -> List[float]:
    payload = {
        "model": EMBED_MODEL,
        "input": text
    }

    r = requests.post(f"{OLLAMA_BASE_URL}/api/embed", json=payload, timeout=180)
    r.raise_for_status()

    data = r.json()
    embeddings = data.get("embeddings")

    if not isinstance(embeddings, list) or not embeddings:
        raise RuntimeError("Ollama no devolvio embeddings.")

    emb = embeddings[0]

    if not isinstance(emb, list):
        raise RuntimeError("Ollama devolvio un embedding invalido.")

    return [float(x) for x in emb]
'''

pattern = r"def embed_one\(text: str\) -> List\[float\]:\n.*?(?=\ndef embed_many\()"
new_text, count = re.subn(pattern, replacement + "\n", text, flags=re.S)

if count == 0:
    print("AVISO: no se encontró def embed_one(...) para reemplazar.")
else:
    path.write_text(new_text, encoding="utf-8")
    print("OK data-engine/app.py: embed_one usa /api/embed")
PY
else
  echo "AVISO: no existe data-engine/app.py, saltando."
fi

log "Levantando Ollama"
docker compose up -d ollama

log "Verificando/descargando modelos Ollama"
if ! docker compose exec -T ollama ollama list | grep -q "qwen2.5-coder:3b"; then
  docker compose exec -T ollama ollama pull qwen2.5-coder:3b
fi

if ! docker compose exec -T ollama ollama list | grep -q "nomic-embed-text"; then
  docker compose exec -T ollama ollama pull nomic-embed-text
fi

log "Reconstruyendo backend y data-engine sin borrar volúmenes"
if [ -f "data-engine/Dockerfile" ]; then
  docker compose build --no-cache backend data-engine
  docker compose up -d --force-recreate backend data-engine
else
  docker compose build --no-cache backend
  docker compose up -d --force-recreate backend
fi

log "Validando variables dentro del backend"
docker compose exec -T backend sh -lc 'printenv | grep -E "OLLAMA_HTTP_TIMEOUT|OLLAMA_PLAN_TIMEOUT|OLLAMA_PLAN_CTX|OLLAMA_PLAN_PREDICT|OLLAMA_KEEP_ALIVE|OLLAMA_BASE_URL" || true'

log "Probando conexión backend -> Ollama /api/tags"
docker compose exec -T backend php -r '$r=@file_get_contents("http://ollama:11434/api/tags"); if($r===false){echo "ERROR\n"; var_dump(error_get_last()); exit(1);} echo substr($r,0,500)."\n";'

log "Probando generación backend -> Ollama /api/generate con timeout 180"
docker compose exec -T backend php -r '$payload=json_encode(["model"=>"qwen2.5-coder:3b","prompt"=>"Responde solo OK","stream"=>false,"keep_alive"=>"10m","options"=>["num_ctx"=>1024,"num_predict"=>20]]); $ctx=stream_context_create(["http"=>["method"=>"POST","header"=>"Content-Type: application/json\r\nConnection: close\r\n","content"=>$payload,"timeout"=>180,"ignore_errors"=>true]]); $r=@file_get_contents("http://ollama:11434/api/generate",false,$ctx); if($r===false){echo "ERROR\n"; var_dump(error_get_last()); exit(1);} echo substr($r,0,1000)."\n";'

if [ -f "data-engine/app.py" ]; then
  log "Verificando que data-engine no use /api/embeddings"
  docker compose exec -T data-engine sh -lc 'grep -R "api/embeddings" -n /app || true'
fi

log "Estado final"
docker compose ps

echo ""
echo "============================================================"
echo "Fix aplicado."
echo "Prueba ahora desde la web."
echo "Si vuelve a fallar, mira logs con:"
echo "docker compose logs -f backend ollama data-engine"
echo "============================================================"
