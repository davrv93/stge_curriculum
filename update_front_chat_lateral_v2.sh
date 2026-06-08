#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
DATA_ENGINE_URL="${DATA_ENGINE_URL:-http://data-engine:8090}"
PUBLIC_DATA_ENGINE_URL="${PUBLIC_DATA_ENGINE_URL:-/api/chat-lateral}"

cd "$PROJECT_DIR"

echo "=================================================="
echo " JoMelAi - Actualización Front Chat Lateral V2"
echo "=================================================="
echo "Proyecto: $PROJECT_DIR"
echo "Data Engine interno: $DATA_ENGINE_URL"

BACKUP_DIR="backups/chat_lateral_front_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_file() {
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
}

echo
echo "== 1) Corrigiendo .env a Data Engine 8090 =="
touch .env
backup_file ".env"

set_env() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|g" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

set_env "DATA_ENGINE_URL" "$DATA_ENGINE_URL"
set_env "SILABO_ENGINE_URL" "$DATA_ENGINE_URL"
set_env "VITE_CHAT_LATERAL_STREAM_URL" "/api/chat-lateral/ask-stream"
set_env "VITE_CHAT_LATERAL_ASK_URL" "/api/chat-lateral/ask"
set_env "VITE_CHAT_LATERAL_ROUTE_URL" "/api/chat-lateral/route"
set_env "VITE_OLLAMA_LATERAL_MODEL" "qwen2.5:0.5b"

# Corrige referencias viejas a 8000 en archivos de configuración.
for f in docker-compose.yml docker-compose.override.yml routes/api.php backend/routes/api.php .env; do
  if [ -f "$f" ]; then
    backup_file "$f"
    sed -i \
      -e 's#http://data-engine:8000#http://data-engine:8090#g' \
      -e 's#localhost:8000#localhost:8090#g' \
      "$f" || true
  fi
done

echo
echo "== 2) Asegurando proxy backend Laravel si existe =="
ROUTES_FILE=""
for f in routes/api.php backend/routes/api.php app/routes/api.php; do
  if [ -f "$f" ]; then
    ROUTES_FILE="$f"
    break
  fi
done

if [ -n "$ROUTES_FILE" ]; then
  echo "Rutas detectadas: $ROUTES_FILE"
  backup_file "$ROUTES_FILE"

  if ! grep -q "CHAT LATERAL V2 FRONT PROXY START" "$ROUTES_FILE"; then
    cat >> "$ROUTES_FILE" <<'PHP'

// === CHAT LATERAL V2 FRONT PROXY START ===
Route::post('/chat-lateral/route', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8090')), '/');

    $response = \Illuminate\Support\Facades\Http::timeout(90)
        ->post($base . '/chat-lateral/route', $request->all());

    return response($response->body(), $response->status())
        ->header('Content-Type', $response->header('Content-Type') ?: 'application/json');
});

Route::post('/chat-lateral/ask', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8090')), '/');

    $response = \Illuminate\Support\Facades\Http::timeout(180)
        ->post($base . '/chat-lateral/ask', $request->all());

    return response($response->body(), $response->status())
        ->header('Content-Type', $response->header('Content-Type') ?: 'application/json');
});

Route::post('/chat-lateral/ask-stream', function (\Illuminate\Http\Request $request) {
    $base = rtrim(env('DATA_ENGINE_URL', env('SILABO_ENGINE_URL', 'http://data-engine:8090')), '/');
    $payload = json_encode($request->all(), JSON_UNESCAPED_UNICODE);

    return response()->stream(function () use ($base, $payload) {
        $ch = curl_init($base . '/chat-lateral/ask-stream');

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_RETURNTRANSFER => false,
            CURLOPT_WRITEFUNCTION => function ($ch, $data) {
                echo $data;
                if (ob_get_level() > 0) {
                    @ob_flush();
                }
                flush();
                return strlen($data);
            },
            CURLOPT_TIMEOUT => 180,
        ]);

        curl_exec($ch);
        curl_close($ch);
    }, 200, [
        'Content-Type' => 'text/event-stream',
        'Cache-Control' => 'no-cache',
        'X-Accel-Buffering' => 'no',
        'Connection' => 'keep-alive',
    ]);
});
// === CHAT LATERAL V2 FRONT PROXY END ===
PHP
  else
    echo "Proxy ya existía, no se duplicó."
  fi
else
  echo "No encontré routes/api.php. Saltando proxy Laravel."
fi

echo
echo "== 3) Detectando carpeta pública/frontend =="
FRONT_PUBLIC_DIR=""

for d in public frontend/public app/public web public_html; do
  if [ -d "$d" ]; then
    FRONT_PUBLIC_DIR="$d"
    break
  fi
done

if [ -z "$FRONT_PUBLIC_DIR" ]; then
  FRONT_PUBLIC_DIR="public"
  mkdir -p "$FRONT_PUBLIC_DIR"
fi

echo "Directorio público elegido: $FRONT_PUBLIC_DIR"

echo
echo "== 4) Creando cliente JS Chat Lateral V2 =="
cat > "$FRONT_PUBLIC_DIR/chat-lateral-v2-client.js" <<'JS'
(function () {
  const STREAM_URL = '/api/chat-lateral/ask-stream';
  const ASK_URL = '/api/chat-lateral/ask';

  function safeJsonParse(value) {
    try {
      return JSON.parse(value);
    } catch (e) {
      return null;
    }
  }

  function getBodyObject(init) {
    if (!init || !init.body) return {};
    if (typeof init.body === 'string') {
      return safeJsonParse(init.body) || {};
    }
    return {};
  }

  function normalizePayload(original) {
    original = original || {};

    let question =
      original.question ||
      original.ask ||
      original.userAsk ||
      original.user_ask ||
      original.message ||
      original.prompt ||
      original.text ||
      '';

    if (!question && Array.isArray(original.messages) && original.messages.length) {
      const last = original.messages[original.messages.length - 1];
      question = last && (last.content || last.text || last.message || '');
    }

    return {
      question: String(question || '').trim(),
      table: original.table || original.duckdb_table || 'silabos',
      collection: original.collection || original.rag_collection || 'silabos',
      n_results: Number(original.n_results || original.nResults || 2),
      stream: true,
      prefer_duckdb: true,
      prefer_rag: true,
      allow_ollama: original.allow_ollama !== false,
      chart: true,
      limit: Number(original.limit || 100)
    };
  }

  function isOldChatUrl(url) {
    try {
      const u = new URL(url, window.location.origin);
      const p = u.pathname;

      return [
        '/api/ask_stream',
        '/ask_stream',
        '/api/ask-stream',
        '/ask-stream',
        '/api/rag/answer',
        '/rag/answer',
        '/api/ask',
        '/ask'
      ].includes(p);
    } catch (e) {
      return false;
    }
  }

  function shouldUseStream(url) {
    try {
      const u = new URL(url, window.location.origin);
      const p = u.pathname;
      return p.includes('stream') || p.includes('ask_stream') || p.includes('ask-stream');
    } catch (e) {
      return true;
    }
  }

  async function askStream(question, handlers, options) {
    handlers = handlers || {};
    options = options || {};

    const payload = normalizePayload({
      question: question,
      table: options.table,
      collection: options.collection,
      n_results: options.n_results,
      limit: options.limit,
      allow_ollama: options.allow_ollama
    });

    const res = await fetch(STREAM_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) {
      throw new Error('HTTP ' + res.status + ' en ' + STREAM_URL);
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';
    let finalData = null;

    while (true) {
      const read = await reader.read();
      if (read.done) break;

      buffer += decoder.decode(read.value, { stream: true });
      const chunks = buffer.split('\n\n');
      buffer = chunks.pop() || '';

      for (const chunk of chunks) {
        const lines = chunk.split('\n');
        let event = 'message';
        let dataLine = '';

        for (const line of lines) {
          if (line.startsWith('event:')) event = line.slice(6).trim();
          if (line.startsWith('data:')) dataLine += line.slice(5).trim();
        }

        if (!dataLine) continue;

        let data = {};
        try {
          data = JSON.parse(dataLine);
        } catch (e) {
          data = { raw: dataLine };
        }

        if (event === 'ready' && handlers.onReady) handlers.onReady(data);
        if (event === 'config' && handlers.onConfig) handlers.onConfig(data);
        if (event === 'token' && handlers.onToken) handlers.onToken(data.text || '', data);
        if (event === 'final') {
          finalData = data;
          if (handlers.onFinal) handlers.onFinal(data);
        }
      }
    }

    return finalData || { ok: true };
  }

  async function ask(question, options) {
    options = options || {};
    const payload = normalizePayload({
      question: question,
      table: options.table,
      collection: options.collection,
      n_results: options.n_results,
      limit: options.limit,
      allow_ollama: options.allow_ollama
    });

    const res = await fetch(ASK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) {
      throw new Error('HTTP ' + res.status + ' en ' + ASK_URL);
    }

    return await res.json();
  }

  // Monkey patch conservador:
  // Si el frontend viejo llama a /api/ask_stream, /api/rag/answer o /api/ask,
  // lo redirigimos al Chat Lateral V2 sin tocar el resto de la app.
  const originalFetch = window.fetch.bind(window);

  window.fetch = function patchedFetch(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');

    if (url && isOldChatUrl(url)) {
      const oldPayload = getBodyObject(init);
      const newPayload = normalizePayload(oldPayload);

      if (newPayload.question) {
        const targetUrl = shouldUseStream(url) ? STREAM_URL : ASK_URL;

        return originalFetch(targetUrl, {
          method: 'POST',
          headers: Object.assign(
            {},
            (init && init.headers) || {},
            { 'Content-Type': 'application/json' }
          ),
          body: JSON.stringify(newPayload)
        });
      }
    }

    return originalFetch(input, init);
  };

  window.JoMelAiChatLateralV2 = {
    askStream,
    ask,
    streamUrl: STREAM_URL,
    askUrl: ASK_URL
  };

  window.jomelaiChatLateralAskStream = askStream;
  window.jomelaiChatLateralAsk = ask;

  console.info('[JoMelAi] Chat Lateral V2 activo:', {
    streamUrl: STREAM_URL,
    askUrl: ASK_URL
  });
})();
JS

echo
echo "== 5) Inyectando cliente JS en HTML principal =="
HTML_FILES="$(find . \
  -type f \
  \( -name "index.html" -o -name "*.blade.php" \) \
  ! -path "./.git/*" \
  ! -path "./data/*" \
  ! -path "./node_modules/*" \
  ! -path "./vendor/*" \
  ! -name "*.bak*" \
  2>/dev/null || true)"

if [ -n "$HTML_FILES" ]; then
  echo "$HTML_FILES" | while read html; do
    [ -z "$html" ] && continue

    if grep -q "</body>" "$html" && ! grep -q "chat-lateral-v2-client.js" "$html"; then
      echo "Inyectando en $html"
      backup_file "$html"
      sed -i 's#</body>#  <script src="/chat-lateral-v2-client.js"></script>\n</body>#' "$html"
    fi
  done
fi

echo
echo "== 6) Parcheando JS/TS del frontend viejo =="
python3 - <<'PY'
from pathlib import Path
import re
import shutil
import time

roots = [
    Path("frontend"),
    Path("public"),
    Path("src"),
    Path("app"),
    Path("resources"),
]

suffixes = {".js", ".ts", ".jsx", ".tsx", ".vue", ".html", ".blade.php"}

replacements = {
    "qwen2.5-coder:3b": "qwen2.5:0.5b",
    "qwen2.5-coder:1.5b": "qwen2.5:0.5b",
    "/api/ask_stream": "/api/chat-lateral/ask-stream",
    "/ask_stream": "/api/chat-lateral/ask-stream",
    "/api/ask-stream": "/api/chat-lateral/ask-stream",
    "/ask-stream": "/api/chat-lateral/ask-stream",
    "/api/rag/answer": "/api/chat-lateral/ask",
    "/rag/answer": "/api/chat-lateral/ask",
}

timestamp = time.strftime("%Y%m%d_%H%M%S")

for root in roots:
    if not root.exists():
        continue

    for file in root.rglob("*"):
        if not file.is_file():
            continue

        p = str(file)

        if any(x in p for x in ["/.git/", "/node_modules/", "/vendor/", "/data/", ".bak"]):
            continue

        if file.suffix not in suffixes:
            continue

        try:
            text = file.read_text(encoding="utf-8")
        except Exception:
            continue

        new = text

        for old, repl in replacements.items():
            new = new.replace(old, repl)

        new = re.sub(r"num_ctx\s*:\s*4096", "num_ctx: 1024", new)
        new = re.sub(r"num_ctx\s*:\s*2048", "num_ctx: 1024", new)
        new = re.sub(r"num_predict\s*:\s*700", "num_predict: 220", new)
        new = re.sub(r"num_predict\s*:\s*500", "num_predict: 220", new)

        # Si hay constantes de endpoints, intenta llevarlas a los nuevos endpoints.
        new = re.sub(
            r"(['\"])(/api/ask|/ask)\1",
            r"'/api/chat-lateral/ask'",
            new
        )

        if new != text:
            backup = file.with_name(file.name + f".bak.frontchatv2.{timestamp}")
            shutil.copy2(file, backup)
            file.write_text(new, encoding="utf-8")
            print("Parcheado:", file)
PY

echo
echo "== 7) Verificando referencias activas viejas =="
grep -R "qwen2.5-coder:3b\|/api/ask_stream\|/ask_stream\|/api/rag/answer\|/rag/answer" -n . \
  --exclude-dir=.git \
  --exclude-dir=data \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude='*.bak*' \
  2>/dev/null | head -80 || true

echo
echo "== 8) Rebuild/restart de servicios =="
docker compose down
docker compose up -d --build

echo
echo "== 9) Prueba Data Engine interna =="
docker exec jomelai_data_engine python3 -c 'import json, urllib.request; payload=json.dumps({"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"limit":20,"allow_ollama":False}).encode(); req=urllib.request.Request("http://127.0.0.1:8090/chat-lateral/ask-stream",data=payload,headers={"Content-Type":"application/json"},method="POST"); print(urllib.request.urlopen(req,timeout=30).read(2000).decode())' || true

echo
echo "== 10) Prueba proxy frontend/backend =="
echo "Probando puerto 3000 si existe..."
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2000 || true

echo
echo
echo "Probando puerto 38764 si existe..."
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2000 || true

echo
echo
echo "== 11) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup en: $BACKUP_DIR"
echo
echo "El frontend ahora debe usar:"
echo "  /api/chat-lateral/ask-stream"
echo "  /api/chat-lateral/ask"
echo
echo "El Data Engine interno está en:"
echo "  http://data-engine:8090"
echo
echo "Prueba en el navegador:"
echo "  qué carreras tienes cargadas"
echo
echo "Esperado:"
echo "  mode=duckdb_sql"
echo "  ollama_used=false"
echo "  respuesta rápida"
