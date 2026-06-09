#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Fix pie render INSIDE chat card"
echo "=================================================="

BACKUP_DIR="backups/fix_pie_render_inside_chat_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Detectando contenedor frontend =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no pude detectar el contenedor frontend."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

echo
echo "== 2) Detectando root publico del contenedor =="
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

echo
echo "== 3) Detectando index activo dentro del contenedor =="
INDEX_FILE="$(docker exec "$FRONT_CONTAINER" sh -lc "
for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
  if [ -f \"\$f\" ]; then
    echo \"\$f\"
    exit 0
  fi
done
exit 1
" || true)"

if [ -z "$INDEX_FILE" ]; then
  echo "ERROR: no pude localizar index.html activo."
  exit 1
fi

echo "INDEX_FILE=$INDEX_FILE"

echo
echo "== 4) Creando JS fix que inserta el pie dentro de la card del chat =="
mkdir -p public

cat > public/chat-pie-in-chat-fix.js <<'JS'
(function () {
  if (window.__JOMELAI_PIE_IN_CHAT_FIX__) return;
  window.__JOMELAI_PIE_IN_CHAT_FIX__ = true;

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function chartType(payload) {
    return String(
      payload && (
        payload.chart_type ||
        (payload.route && payload.route.chart_type) ||
        (payload.route && payload.route.intent && payload.route.intent.chart_type) ||
        (payload.chart && payload.chart.chart_type) ||
        ''
      )
    ).toLowerCase();
  }

  function imageBase64(payload) {
    return (
      payload &&
      (
        payload.image_base64 ||
        (payload.chart && payload.chart.image_base64) ||
        (payload.data && payload.data.image_base64) ||
        ''
      )
    ) || '';
  }

  function mimeType(payload) {
    return (
      payload &&
      (
        payload.mime_type ||
        (payload.chart && payload.chart.mime_type) ||
        'image/png'
      )
    ) || 'image/png';
  }

  function rows(payload) {
    if (!payload) return [];
    if (Array.isArray(payload.rows)) return payload.rows;
    if (payload.data && Array.isArray(payload.data.rows)) return payload.data.rows;
    if (payload.chart && Array.isArray(payload.chart.rows)) return payload.chart.rows;
    if (payload.chart && Array.isArray(payload.chart.data)) return payload.chart.data;
    return [];
  }

  function isPiePayload(payload) {
    return chartType(payload) === 'pie' && !!imageBase64(payload);
  }

  function isVisible(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function injectStyles() {
    if (document.getElementById('jomelai-pie-in-chat-fix-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-pie-in-chat-fix-style';
    style.textContent = `
      .jomelai-pie-inline-wrap {
        margin-top: 10px;
        padding: 10px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #f8fafc;
        text-align: center;
        overflow: auto;
      }
      .jomelai-pie-inline-img {
        max-width: 100%;
        height: auto;
        display: inline-block;
        border-radius: 10px;
        background: #fff;
      }
    `;
    document.head.appendChild(style);
  }

  function getChatRoot() {
    const selectors = [
      '.assistant-panel .chat-body',
      '.assistant-panel .chat-messages',
      '.assistant-panel .messages',
      '.assistant-panel .conversation',
      '#chatMessages',
      '#chat-messages',
      '#messages',
      '.chat-body',
      '.chat-messages',
      '.messages',
      '.conversation'
    ];

    for (const selector of selectors) {
      const found = Array.from(document.querySelectorAll(selector)).filter(isVisible);
      if (found.length) return found[found.length - 1];
    }

    const panels = Array.from(document.querySelectorAll('.assistant-panel')).filter(isVisible);
    if (panels.length) return panels[panels.length - 1];

    return null;
  }

  function getPayloadTitle(payload) {
    return String(
      (payload &&
        (
          (payload.route && payload.route.intent && payload.route.intent.title) ||
          payload.title ||
          ''
        )
      ) || ''
    ).trim().toLowerCase();
  }

  function getCandidateCards(root, payload) {
    if (!root) return [];

    let cards = Array.from(
      root.querySelectorAll(
        '.jomelai-result-card, [data-chat-lateral-rendered="1"], .jomelai-force-pie-card'
      )
    ).filter(isVisible);

    if (!cards.length) {
      cards = Array.from(root.querySelectorAll('div')).filter(function (el) {
        if (!isVisible(el)) return false;
        const txt = (el.innerText || '').toLowerCase();
        return txt.includes('duckdb_chart') || txt.includes('grafico') || txt.includes('total por categoria');
      });
    }

    const title = getPayloadTitle(payload);
    if (title) {
      const filtered = cards.filter(function (card) {
        return (card.innerText || '').toLowerCase().includes(title);
      });
      if (filtered.length) return filtered;
    }

    return cards;
  }

  function buildImageWrap(payload) {
    const wrap = document.createElement('div');
    wrap.className = 'jomelai-pie-inline-wrap';
    wrap.innerHTML =
      '<img class="jomelai-pie-inline-img" ' +
      'src="data:' + esc(mimeType(payload)) + ';base64,' + imageBase64(payload) + '" ' +
      'alt="Grafico de pie" />';
    return wrap;
  }

  function removeStrayOldPieCards(chatRoot) {
    document.querySelectorAll('.jomelai-force-pie-card').forEach(function (el) {
      if (!chatRoot || !chatRoot.contains(el)) {
        el.remove();
      }
    });
  }

  function patchCard(card, payload) {
    if (!card) return false;

    injectStyles();

    const newWrap = buildImageWrap(payload);
    const existingWrap = card.querySelector('.jomelai-pie-inline-wrap');
    const oldChartBlock = card.querySelector('.jomelai-chart');
    const tableWrap =
      (card.querySelector('.jomelai-result-scroll') && card.querySelector('.jomelai-result-scroll')) ||
      (card.querySelector('.jomelai-force-pie-table-wrap') && card.querySelector('.jomelai-force-pie-table-wrap')) ||
      (card.querySelector('table') && card.querySelector('table').closest('div'));

    if (existingWrap) {
      existingWrap.replaceWith(newWrap);
    } else if (oldChartBlock) {
      oldChartBlock.replaceWith(newWrap);
    } else if (tableWrap && tableWrap.parentNode) {
      tableWrap.parentNode.insertBefore(newWrap, tableWrap);
    } else {
      card.appendChild(newWrap);
    }

    card.querySelectorAll('.jomelai-chart-row').forEach(function (el) { el.remove(); });
    card.querySelectorAll('.jomelai-chart-track').forEach(function (el) { el.remove(); });
    card.querySelectorAll('.jomelai-chart-bar').forEach(function (el) {
      const parent = el.closest('.jomelai-chart');
      if (parent && parent !== newWrap) {
        parent.remove();
      } else {
        el.remove();
      }
    });

    card.dataset.chartType = 'pie';
    card.dataset.pieInlinePatched = '1';

    return true;
  }

  function tryPatch(payload) {
    const chatRoot = getChatRoot();
    if (!chatRoot) return false;

    removeStrayOldPieCards(chatRoot);

    const candidates = getCandidateCards(chatRoot, payload);
    if (!candidates.length) return false;

    const card = candidates[candidates.length - 1];
    return patchCard(card, payload);
  }

  function watchAndPatch(payload) {
    let tries = 0;

    const observer = new MutationObserver(function () {
      tryPatch(payload);
    });

    observer.observe(document.body, { childList: true, subtree: true });

    const timer = setInterval(function () {
      tries += 1;
      const ok = tryPatch(payload);
      if (ok || tries > 40) {
        clearInterval(timer);
        setTimeout(function () { observer.disconnect(); }, 500);
      }
    }, 150);
  }

  function parseFinalChunk(chunk) {
    if (!chunk || !chunk.includes('event: final')) return null;
    const dataLine = chunk.split('\n').find(function (line) {
      return line.startsWith('data:');
    });
    if (!dataLine) return null;
    try {
      return JSON.parse(dataLine.slice(5).trim());
    } catch (e) {
      return null;
    }
  }

  const oldFetch = window.fetch.bind(window);

  window.fetch = function pieInChatFetch(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    const promise = oldFetch(input, init);

    if (url && url.includes('/api/chat-lateral/ask-stream')) {
      promise.then(function (res) {
        try {
          const clone = res.clone();
          const reader = clone.body && clone.body.getReader ? clone.body.getReader() : null;
          if (!reader) return;

          const decoder = new TextDecoder('utf-8');
          let buffer = '';

          function pump() {
            reader.read().then(function (result) {
              if (result.done) return;

              buffer += decoder.decode(result.value, { stream: true });
              const chunks = buffer.split('\n\n');
              buffer = chunks.pop() || '';

              for (const chunk of chunks) {
                const payload = parseFinalChunk(chunk);
                if (payload && isPiePayload(payload)) {
                  watchAndPatch(payload);
                }
              }

              pump();
            }).catch(function () {});
          }

          pump();
        } catch (e) {}
      }).catch(function () {});
    }

    return promise;
  };

  console.info('[JoMelAi] Pie in-chat fix activo');
})();
JS

echo
echo "== 5) Copiando JS fix a directorios locales conocidos =="
for d in public frontend/public app/public web public_html; do
  if [ -d "$d" ]; then
    cp public/chat-pie-in-chat-fix.js "$d/chat-pie-in-chat-fix.js" || true
  fi
done

echo
echo "== 6) Copiando JS fix al contenedor activo =="
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"
docker cp public/chat-pie-in-chat-fix.js "$FRONT_CONTAINER:$CONTAINER_ROOT/chat-pie-in-chat-fix.js"

echo
echo "== 7) Extrayendo index activo para parchearlo localmente =="
docker cp "$FRONT_CONTAINER:$INDEX_FILE" "$BACKUP_DIR/index.active.original.html"
cp "$BACKUP_DIR/index.active.original.html" "$BACKUP_DIR/index.active.patched.html"

python3 - "$BACKUP_DIR/index.active.patched.html" <<'PY'
from pathlib import Path
import sys
import time

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# Limpiar referencias viejas
lines = []
for ln in text.splitlines():
    if "chat-pie-image-override.js" in ln:
        continue
    if "chat-pie-in-chat-fix.js" in ln:
        continue
    lines.append(ln)
text = "\n".join(lines)

tag = f'  <script src="/chat-pie-in-chat-fix.js?v={int(time.time())}"></script>'

if "chat-panel-renderer-final.js" in text:
    out = []
    inserted = False
    for ln in text.splitlines():
        out.append(ln)
        if ("chat-panel-renderer-final.js" in ln) and (not inserted):
            out.append(tag)
            inserted = True
    text = "\n".join(out)
elif "</body>" in text:
    text = text.replace("</body>", tag + "\n</body>")
else:
    text += "\n" + tag + "\n"

p.write_text(text, encoding="utf-8")
print("Patcheado:", p)
PY

echo
echo "== 8) Subiendo index parchado al contenedor =="
docker cp "$BACKUP_DIR/index.active.patched.html" "$FRONT_CONTAINER:$INDEX_FILE"

echo
echo "== 9) Verificando que el script quedo referenciado =="
docker exec "$FRONT_CONTAINER" sh -lc "grep -n 'chat-panel-renderer-final\\|chat-pie-in-chat-fix' '$INDEX_FILE' || true"

echo
echo "== 10) Recargando Nginx si aplica =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 11) Probando asset =="
curl -sS -I "http://localhost:3000/chat-pie-in-chat-fix.js?v=test" || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Ahora haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "En consola debes ver:"
echo "  [JoMelAi] Pie in-chat fix activo"
echo
echo "Luego prueba de nuevo tu consulta de grafico pie."
