#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${PROJECT_DIR:-$HOME/jomelai}"
cd "$PROJECT_DIR"

echo "=================================================="
echo " Fix frontend: doble /api/chat-lateral"
echo "=================================================="

BACKUP_DIR="backups/fix_double_chat_lateral_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_file() {
  local f="$1"
  if [ -f "$f" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
}

echo
echo "== 1) Corrigiendo .env =="
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

# Interno Docker: Data Engine real está en 8090.
set_env "DATA_ENGINE_URL" "http://data-engine:8090"
set_env "SILABO_ENGINE_URL" "http://data-engine:8090"

# Frontend: rutas públicas correctas, SIN duplicar.
set_env "VITE_CHAT_LATERAL_BASE_URL" "/api/chat-lateral"
set_env "VITE_CHAT_LATERAL_STREAM_URL" "/api/chat-lateral/ask-stream"
set_env "VITE_CHAT_LATERAL_ASK_URL" "/api/chat-lateral/ask"
set_env "VITE_CHAT_LATERAL_ROUTE_URL" "/api/chat-lateral/route"

# Reemplazos directos en configs.
for f in .env docker-compose.yml docker-compose.override.yml routes/api.php backend/routes/api.php; do
  if [ -f "$f" ]; then
    backup_file "$f"
    sed -i \
      -e 's#/api/chat-lateral/api/chat-lateral#/api/chat-lateral#g' \
      -e 's#http://data-engine:8000#http://data-engine:8090#g' \
      -e 's#localhost:8000#localhost:8090#g' \
      "$f" || true
  fi
done

echo
echo "== 2) Parcheando archivos frontend/backend con rutas duplicadas =="
python3 - <<'PY'
from pathlib import Path
import shutil
import time
import re

timestamp = time.strftime("%Y%m%d_%H%M%S")

roots = [
    Path(".env"),
    Path("frontend"),
    Path("public"),
    Path("src"),
    Path("app"),
    Path("resources"),
    Path("routes"),
    Path("backend"),
]

suffixes = {
    ".js", ".ts", ".jsx", ".tsx", ".vue", ".html",
    ".php", ".blade.php", ".json", ".env", ".yml", ".yaml"
}

replacements = {
    "/api/chat-lateral/api/chat-lateral/ask-stream": "/api/chat-lateral/ask-stream",
    "/api/chat-lateral/api/chat-lateral/ask": "/api/chat-lateral/ask",
    "/api/chat-lateral/api/chat-lateral/route": "/api/chat-lateral/route",
    "/api/chat-lateral/api/chat-lateral": "/api/chat-lateral",

    "api/chat-lateral/api/chat-lateral/ask-stream": "api/chat-lateral/ask-stream",
    "api/chat-lateral/api/chat-lateral/ask": "api/chat-lateral/ask",
    "api/chat-lateral/api/chat-lateral/route": "api/chat-lateral/route",
    "api/chat-lateral/api/chat-lateral": "api/chat-lateral",

    "http://data-engine:8000": "http://data-engine:8090",
    "localhost:8000": "localhost:8090",
}

def should_skip(path: Path) -> bool:
    s = str(path)
    return any(x in s for x in [
        "/.git/",
        "/data/",
        "/node_modules/",
        "/vendor/",
        ".bak",
        "/backups/",
    ])

def patch_file(file: Path):
    if not file.is_file():
        return

    if should_skip(file):
        return

    if file.name == ".env":
        pass
    elif file.suffix not in suffixes and not file.name.endswith(".blade.php"):
        return

    try:
        text = file.read_text(encoding="utf-8")
    except Exception:
        return

    new = text

    for old, val in replacements.items():
        new = new.replace(old, val)

    # Casos comunes de concatenación defectuosa:
    # base = "/api/chat-lateral"; path = "/api/chat-lateral/ask-stream"
    # intentamos que path sea relativo cuando está cerca de variables de chat lateral.
    new = re.sub(
        r"(CHAT_LATERAL_[A-Z_]*STREAM[A-Z_]*\s*[:=]\s*['\"])/api/chat-lateral/ask-stream(['\"])",
        r"\1/ask-stream\2",
        new
    )
    new = re.sub(
        r"(CHAT_LATERAL_[A-Z_]*ASK[A-Z_]*\s*[:=]\s*['\"])/api/chat-lateral/ask(['\"])",
        r"\1/ask\2",
        new
    )
    new = re.sub(
        r"(CHAT_LATERAL_[A-Z_]*ROUTE[A-Z_]*\s*[:=]\s*['\"])/api/chat-lateral/route(['\"])",
        r"\1/route\2",
        new
    )

    # Pero en VITE env dejamos URLs absolutas correctas.
    if file.name == ".env":
        new = re.sub(r"^VITE_CHAT_LATERAL_STREAM_URL=.*$", "VITE_CHAT_LATERAL_STREAM_URL=/api/chat-lateral/ask-stream", new, flags=re.M)
        new = re.sub(r"^VITE_CHAT_LATERAL_ASK_URL=.*$", "VITE_CHAT_LATERAL_ASK_URL=/api/chat-lateral/ask", new, flags=re.M)
        new = re.sub(r"^VITE_CHAT_LATERAL_ROUTE_URL=.*$", "VITE_CHAT_LATERAL_ROUTE_URL=/api/chat-lateral/route", new, flags=re.M)
        new = re.sub(r"^VITE_CHAT_LATERAL_BASE_URL=.*$", "VITE_CHAT_LATERAL_BASE_URL=/api/chat-lateral", new, flags=re.M)

    if new != text:
        backup = file.with_name(file.name + f".bak.doublepath.{timestamp}")
        shutil.copy2(file, backup)
        file.write_text(new, encoding="utf-8")
        print("Parcheado:", file)

for root in roots:
    if root.is_file():
        patch_file(root)
    elif root.exists():
        for file in root.rglob("*"):
            patch_file(file)
PY

echo
echo "== 3) Reescribiendo cliente JS con normalizador anti-duplicación =="
PUBLIC_DIR=""

for d in public frontend/public app/public; do
  if [ -d "$d" ]; then
    PUBLIC_DIR="$d"
    break
  fi
done

if [ -z "$PUBLIC_DIR" ]; then
  PUBLIC_DIR="public"
  mkdir -p "$PUBLIC_DIR"
fi

echo "PUBLIC_DIR=$PUBLIC_DIR"

if [ -f "$PUBLIC_DIR/chat-lateral-v2-client.js" ]; then
  backup_file "$PUBLIC_DIR/chat-lateral-v2-client.js"
fi

cat > "$PUBLIC_DIR/chat-lateral-v2-client.js" <<'JS'
(function () {
  function normalizeChatUrl(url) {
    if (!url) return url;

    let out = String(url);

    // Corrige el bug actual:
    // /api/chat-lateral/api/chat-lateral/ask-stream
    while (out.includes('/api/chat-lateral/api/chat-lateral')) {
      out = out.replace('/api/chat-lateral/api/chat-lateral', '/api/chat-lateral');
    }

    return out;
  }

  function joinChatUrl(base, path) {
    base = normalizeChatUrl(base || '/api/chat-lateral');
    path = normalizeChatUrl(path || '');

    if (path.startsWith('/api/chat-lateral/')) {
      return path;
    }

    if (!path.startsWith('/')) {
      path = '/' + path;
    }

    return normalizeChatUrl(base.replace(/\/+$/, '') + path);
  }

  const BASE_URL = normalizeChatUrl(
    window.VITE_CHAT_LATERAL_BASE_URL ||
    window.CHAT_LATERAL_BASE_URL ||
    '/api/chat-lateral'
  );

  const STREAM_URL = normalizeChatUrl(
    window.VITE_CHAT_LATERAL_STREAM_URL ||
    window.CHAT_LATERAL_STREAM_URL ||
    joinChatUrl(BASE_URL, '/ask-stream')
  );

  const ASK_URL = normalizeChatUrl(
    window.VITE_CHAT_LATERAL_ASK_URL ||
    window.CHAT_LATERAL_ASK_URL ||
    joinChatUrl(BASE_URL, '/ask')
  );

  const ROUTE_URL = normalizeChatUrl(
    window.VITE_CHAT_LATERAL_ROUTE_URL ||
    window.CHAT_LATERAL_ROUTE_URL ||
    joinChatUrl(BASE_URL, '/route')
  );

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
    const value = normalizeChatUrl(url);

    try {
      const u = new URL(value, window.location.origin);
      const p = u.pathname;

      return [
        '/api/ask_stream',
        '/ask_stream',
        '/api/ask-stream',
        '/ask-stream',
        '/api/rag/answer',
        '/rag/answer',
        '/api/ask',
        '/ask',
        '/api/chat-lateral/api/chat-lateral/ask-stream',
        '/api/chat-lateral/api/chat-lateral/ask',
        '/api/chat-lateral/api/chat-lateral/route'
      ].includes(p);
    } catch (e) {
      return false;
    }
  }

  function shouldUseStream(url) {
    try {
      const u = new URL(normalizeChatUrl(url), window.location.origin);
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

  const originalFetch = window.fetch.bind(window);

  window.fetch = function patchedFetch(input, init) {
    let url = typeof input === 'string' ? input : (input && input.url ? input.url : '');

    if (url) {
      const fixedUrl = normalizeChatUrl(url);

      // Si solo está duplicado, lo corregimos.
      if (fixedUrl !== url && !isOldChatUrl(url)) {
        if (typeof input === 'string') {
          input = fixedUrl;
        } else if (input instanceof Request) {
          input = new Request(fixedUrl, input);
        }
      }

      url = fixedUrl;
    }

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
    routeUrl: ROUTE_URL,
    streamUrl: STREAM_URL,
    askUrl: ASK_URL,
    normalizeChatUrl
  };

  window.jomelaiChatLateralAskStream = askStream;
  window.jomelaiChatLateralAsk = ask;

  console.info('[JoMelAi] Chat Lateral V2 activo', {
    baseUrl: BASE_URL,
    streamUrl: STREAM_URL,
    askUrl: ASK_URL,
    routeUrl: ROUTE_URL
  });
})();
JS

echo
echo "== 4) Asegurando inyección del cliente JS =="
HTML_FILES="$(find . \
  -type f \
  \( -name "index.html" -o -name "*.blade.php" \) \
  ! -path "./.git/*" \
  ! -path "./data/*" \
  ! -path "./node_modules/*" \
  ! -path "./vendor/*" \
  ! -path "./backups/*" \
  ! -name "*.bak*" \
  2>/dev/null || true)"

if [ -n "$HTML_FILES" ]; then
  echo "$HTML_FILES" | while read html; do
    [ -z "$html" ] && continue

    if grep -q "</body>" "$html" && ! grep -q "chat-lateral-v2-client.js" "$html"; then
      echo "Inyectando cliente en $html"
      backup_file "$html"
      sed -i 's#</body>#  <script src="/chat-lateral-v2-client.js"></script>\n</body>#' "$html"
    fi
  done
fi

echo
echo "== 5) Verificando que no quede ruta duplicada =="
grep -R "/api/chat-lateral/api/chat-lateral" -n . \
  --exclude-dir=.git \
  --exclude-dir=data \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude-dir=backups \
  --exclude='*.bak*' \
  2>/dev/null | head -80 || true

echo
echo "== 6) Rebuild/restart frontend/backend =="
docker compose down
docker compose up -d --build

echo
echo "== 7) Test Data Engine directo =="
docker exec jomelai_data_engine python3 -c 'import json, urllib.request; payload=json.dumps({"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"limit":20,"allow_ollama":False}).encode(); req=urllib.request.Request("http://127.0.0.1:8090/chat-lateral/ask-stream",data=payload,headers={"Content-Type":"application/json"},method="POST"); print(urllib.request.urlopen(req,timeout=30).read(1500).decode())' || true

echo
echo "== 8) Test proxy público en 38764 =="
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2500 || true

echo
echo
echo "== 9) Test proxy público en 3000 =="
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2500 || true

echo
echo
echo "== 10) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Ruta correcta:"
echo "  /api/chat-lateral/ask-stream"
echo
echo "Ruta incorrecta eliminada:"
echo "  /api/chat-lateral/api/chat-lateral/ask-stream"
