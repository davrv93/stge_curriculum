#!/usr/bin/env bash
set -Eeuo pipefail

cd /home/ubuntu/jomelai

echo "=================================================="
echo " Fix missing frontend assets + clean index"
echo "=================================================="

BACKUP_DIR="backups/fix_missing_assets_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Detectando frontend activo =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no pude detectar contenedor frontend."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
if command -v nginx >/dev/null 2>&1; then
  nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
fi
' || true)"

if [ -z "$CONTAINER_ROOT" ]; then
  CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
for d in /usr/share/nginx/html /app/dist /app/build /app/public /app/frontend/dist /app/frontend/public; do
  [ -d "$d" ] && echo "$d" && exit 0
done
echo /usr/share/nginx/html
' || true)"
fi

echo "CONTAINER_ROOT=$CONTAINER_ROOT"

INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
  [ -f \"\$f\" ] && echo \"\$f\" && exit 0
done
exit 0
" || true)"

if [ -z "$INDEX_FILE" ]; then
  echo "ERROR: no encontré index.html activo."
  docker exec "$FRONT_CONTAINER" sh -lc "find '$CONTAINER_ROOT' -maxdepth 2 -type f | head -80" || true
  exit 1
fi

echo "INDEX_FILE=$INDEX_FILE"

echo
echo "== 2) Preparando directorios públicos locales =="
mkdir -p public

PUBLIC_DIRS=("public")
for d in frontend/public app/public web public_html; do
  [ -d "$d" ] && PUBLIC_DIRS+=("$d")
done

printf ' - %s\n' "${PUBLIC_DIRS[@]}"

echo
echo "== 3) Creando assets faltantes compatibles =="

cat > public/chat-lateral-v2-client.js <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__) return;
  window.__JOMELAI_CHAT_LATERAL_V2_CLIENT__ = true;

  const STREAM_URL = '/api/chat-lateral/ask-stream';
  const ASK_URL = '/api/chat-lateral/ask';

  function parseSseChunk(chunk) {
    const eventLine = chunk.split('\n').find(x => x.startsWith('event:'));
    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));
    if (!dataLine) return null;
    try {
      return {
        event: eventLine ? eventLine.slice(6).trim() : 'message',
        data: JSON.parse(dataLine.slice(5).trim())
      };
    } catch (e) {
      return null;
    }
  }

  async function ask(payload) {
    const body = Object.assign({
      table: 'silabos',
      collection: 'silabos',
      n_results: 2,
      chart: true
    }, payload || {});

    const res = await fetch(ASK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    return await res.json();
  }

  async function askStream(payload, onEvent) {
    const body = Object.assign({
      table: 'silabos',
      collection: 'silabos',
      n_results: 2,
      chart: true
    }, payload || {});

    const res = await fetch(STREAM_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    if (!res.body || !res.body.getReader) return res;

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';

    while (true) {
      const item = await reader.read();
      if (item.done) break;

      buffer += decoder.decode(item.value, { stream: true });
      const chunks = buffer.split('\n\n');
      buffer = chunks.pop() || '';

      for (const chunk of chunks) {
        const parsed = parseSseChunk(chunk);
        if (parsed && typeof onEvent === 'function') {
          onEvent(parsed.event, parsed.data);
        }
      }
    }

    return res;
  }

  window.JoMelAiChatLateralV2 = {
    ask,
    askStream,
    STREAM_URL,
    ASK_URL,
    version: 'asset-fix-v1'
  };

  console.info('[JoMelAi] chat-lateral-v2-client cargado');
})();
JS

cat > public/chat-panel-renderer-final.js <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__) return;
  window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__ = true;

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function rows(payload) {
    if (Array.isArray(payload && payload.rows)) return payload.rows;
    if (payload && payload.data && Array.isArray(payload.data.rows)) return payload.data.rows;
    return [];
  }

  function image(payload) {
    return payload && (payload.image_base64 || (payload.chart && payload.chart.image_base64) || '');
  }

  function mime(payload) {
    return payload && (payload.mime_type || (payload.chart && payload.chart.mime_type) || 'image/png');
  }

  function mount() {
    const selectors = ['#chatMessages', '#chat-messages', '.chat-messages', '.chat-body', '.messages', '.conversation', 'main'];
    for (const s of selectors) {
      const nodes = Array.from(document.querySelectorAll(s)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      if (nodes.length) return nodes[nodes.length - 1];
    }
    return document.body;
  }

  function render(payload) {
    if (!payload || typeof payload !== 'object') return false;

    const dataRows = rows(payload);
    const img = image(payload);

    if (!dataRows.length && !img) return false;

    const card = document.createElement('div');
    card.className = 'jomelai-result-card';
    card.dataset.chatLateralRendered = '1';
    card.style.cssText = 'margin:14px 0;padding:14px;border:1px solid #e5e7eb;border-radius:14px;background:#fff;box-shadow:0 10px 28px rgba(15,23,42,.08);overflow:auto;';

    let html = '<div style="font-weight:800;color:#0f2f57;margin-bottom:10px;">' + esc(payload.mode || 'Resultado') + '</div>';

    if (img) {
      html += '<div style="text-align:center;background:#f8fafc;border:1px solid #e5e7eb;border-radius:12px;padding:10px;margin-bottom:10px;">';
      html += '<img style="max-width:100%;height:auto;border-radius:10px;background:#fff;" src="data:' + esc(mime(payload)) + ';base64,' + img + '">';
      html += '</div>';
    }

    if (dataRows.length) {
      const headers = Object.keys(dataRows[0] || {});
      html += '<div style="overflow:auto;border:1px solid #e5e7eb;border-radius:12px;"><table style="width:100%;border-collapse:collapse;font-size:12px;">';
      html += '<thead><tr>' + headers.map(h => '<th style="text-align:left;background:#f8fafc;padding:8px;border-bottom:1px solid #e5e7eb;">' + esc(h) + '</th>').join('') + '</tr></thead>';
      html += '<tbody>' + dataRows.slice(0, 50).map(row => '<tr>' + headers.map(h => '<td style="padding:8px;border-bottom:1px solid #eef2f7;">' + esc(row[h]) + '</td>').join('') + '</tr>').join('') + '</tbody>';
      html += '</table></div>';
    }

    card.innerHTML = html;
    mount().appendChild(card);
    return true;
  }

  window.JoMelAiChatPanelRenderer = {
    render,
    version: 'asset-fix-v1'
  };

  console.info('[JoMelAi] Chat panel renderer ROBUST activo');
})();
JS

cat > public/chat-pie-image-override.js <<'JS'
(function () {
  if (window.__JOMELAI_PIE_IMAGE_OVERRIDE_SHIM__) return;
  window.__JOMELAI_PIE_IMAGE_OVERRIDE_SHIM__ = true;
  console.info('[JoMelAi] chat-pie-image-override shim activo');
})();
JS

cat > public/jomelai-syllabus-pretty-v7-live.js <<'JS'
(function () {
  if (window.__JOMELAI_SYLLABUS_PRETTY_V7_SHIM__) return;
  window.__JOMELAI_SYLLABUS_PRETTY_V7_SHIM__ = true;
  console.info('[JoMelAi] jomelai-syllabus-pretty-v7-live shim activo');
})();
JS

# Si el formatter ya existe, conservarlo. Si no, crear fallback mínimo.
if [ ! -f public/jomelai-syllabus-format-renderer.js ]; then
cat > public/jomelai-syllabus-format-renderer.js <<'JS'
(function () {
  if (window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__) return;
  window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__ = true;

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function tryJson(v) {
    if (!v || typeof v !== 'string') return null;
    try { return JSON.parse(v); } catch(e) {}
    const a = v.indexOf('{'), b = v.lastIndexOf('}');
    if (a >= 0 && b > a) {
      try { return JSON.parse(v.slice(a, b + 1)); } catch(e) {}
    }
    return null;
  }

  function getSyllabus(p) {
    return p && (p.syllabus || tryJson(p.response) || tryJson(p.answer) || tryJson(p.raw_response));
  }

  function mount() {
    const selectors = ['#syllabusResult','#silaboResult','#syllabus-output','#silabo-output','.syllabus-result','.silabo-result','.content','main'];
    for (const s of selectors) {
      const nodes = Array.from(document.querySelectorAll(s)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      if (nodes.length) return nodes[nodes.length - 1];
    }
    return document.body;
  }

  function render(p) {
    const s = getSyllabus(p);
    if (!s) return false;
    const dg = s.datos_generales || {};
    const card = document.createElement('div');
    card.className = 'jomelai-syllabus-card';
    card.style.cssText = 'margin:18px 0;background:#fff;border:1px solid #e5e7eb;border-radius:18px;box-shadow:0 14px 38px rgba(15,23,42,.10);overflow:hidden;font-family:Inter,Roboto,Arial,sans-serif;color:#1f2937;';
    card.innerHTML =
      '<div style="padding:18px 20px;background:#0f2f57;color:#fff;"><h2 style="margin:0;font-size:20px;">' + esc(dg.curso || 'Sílabo generado') + '</h2><p style="margin:6px 0 0;">' + esc(dg.programa || '') + '</p></div>' +
      '<div style="padding:18px 20px;"><pre style="white-space:pre-wrap;font-family:inherit;line-height:1.55;">' + esc(p.markdown || JSON.stringify(s, null, 2)) + '</pre></div>';
    mount().appendChild(card);
    return true;
  }

  function parseChunk(chunk) {
    const ev = (chunk.split('\n').find(x => x.startsWith('event:')) || 'event: message').slice(6).trim();
    const dl = chunk.split('\n').find(x => x.startsWith('data:'));
    if (!dl) return null;
    try { return {event: ev, data: JSON.parse(dl.slice(5).trim())}; } catch(e) { return null; }
  }

  const oldFetch = window.fetch.bind(window);
  window.fetch = function(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    const promise = oldFetch(input, init);

    if (url.includes('/api/assistant/generate-syllabus-stream')) {
      promise.then(res => {
        try {
          const clone = res.clone();
          const reader = clone.body && clone.body.getReader ? clone.body.getReader() : null;
          if (!reader) return;
          const dec = new TextDecoder('utf-8');
          let buf = '';
          function pump() {
            reader.read().then(({done, value}) => {
              if (done) return;
              buf += dec.decode(value, {stream:true});
              const chunks = buf.split('\n\n');
              buf = chunks.pop() || '';
              for (const ch of chunks) {
                const p = parseChunk(ch);
                if (p && (p.event === 'syllabus' || p.event === 'final')) render(p.data);
              }
              pump();
            }).catch(()=>{});
          }
          pump();
        } catch(e) {}
      }).catch(()=>{});
    }

    return promise;
  };

  window.JoMelAiSyllabusFormatRenderer = { render, getSyllabus, version: 'fallback-v1' };
  console.info('[JoMelAi] Syllabus format renderer activo');
})();
JS
fi

echo
echo "== 4) Copiando assets a públicos locales =="
for d in "${PUBLIC_DIRS[@]}"; do
  mkdir -p "$d"
  cp public/chat-lateral-v2-client.js "$d/chat-lateral-v2-client.js"
  cp public/chat-panel-renderer-final.js "$d/chat-panel-renderer-final.js"
  cp public/chat-pie-image-override.js "$d/chat-pie-image-override.js"
  cp public/jomelai-syllabus-pretty-v7-live.js "$d/jomelai-syllabus-pretty-v7-live.js"
  cp public/jomelai-syllabus-format-renderer.js "$d/jomelai-syllabus-format-renderer.js"
done

echo
echo "== 5) Copiando assets al contenedor activo =="
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"

for f in \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js \
  jomelai-syllabus-pretty-v7-live.js \
  jomelai-syllabus-format-renderer.js
do
  docker cp "public/$f" "$FRONT_CONTAINER:$CONTAINER_ROOT/$f"
done

echo
echo "== 6) Limpiando index activo y reinyectando una sola vez =="
docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.original.html"
cp "$BACKUP_DIR/index.original.html" "$BACKUP_DIR/index.patched.html"

python3 - "$BACKUP_DIR/index.patched.html" <<'PY'
from pathlib import Path
import sys, time

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

targets = [
    "chat-lateral-v2-client.js",
    "chat-panel-renderer-final.js",
    "chat-pie-image-override.js",
    "chat-pie-in-chat-fix.js",
    "jomelai-syllabus-pretty-v7-live.js",
    "jomelai-syllabus-format-renderer.js",
]

lines = []
for ln in text.splitlines():
    if any(t in ln for t in targets):
        continue
    lines.append(ln)

text = "\n".join(lines)
v = int(time.time())

scripts = "\n".join([
    f'  <script src="/jomelai-syllabus-pretty-v7-live.js?v={v}"></script>',
    f'  <script src="/chat-lateral-v2-client.js?v={v}"></script>',
    f'  <script src="/chat-panel-renderer-final.js?v={v}"></script>',
    f'  <script src="/chat-pie-image-override.js?v={v}"></script>',
    f'  <script src="/jomelai-syllabus-format-renderer.js?v={v}"></script>',
])

if "</body>" in text:
    text = text.replace("</body>", scripts + "\n</body>")
else:
    text += "\n" + scripts + "\n"

p.write_text(text, encoding="utf-8")
PY

docker cp "$BACKUP_DIR/index.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

echo
echo "== 7) Verificando index =="
docker exec "$FRONT_CONTAINER" sh -lc "grep -n 'chat-lateral-v2-client\\|chat-panel-renderer-final\\|chat-pie-image-override\\|jomelai-syllabus-pretty-v7-live\\|jomelai-syllabus-format-renderer' '$INDEX_FILE' || true"

echo
echo "== 8) Recargando Nginx si aplica =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 9) Test HTTP de assets =="
for f in \
  chat-lateral-v2-client.js \
  chat-panel-renderer-final.js \
  chat-pie-image-override.js \
  jomelai-syllabus-pretty-v7-live.js \
  jomelai-syllabus-format-renderer.js
do
  echo
  echo "---- $f ----"
  curl -sS -I "http://localhost:3000/$f?v=test" | head -5 || true
done

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "En consola ya no deberían aparecer 404 de esos JS."
