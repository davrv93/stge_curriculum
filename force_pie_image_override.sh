#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Force Pie Chart Image Override"
echo "=================================================="

BACKUP_DIR="backups/force_pie_image_override_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Detectando contenedor frontend =="
FRONT_CONTAINER="$(docker ps --format '{{.Names}} {{.Ports}} {{.Image}}' \
  | grep -Ei '3000|38764|frontend|nginx|web' \
  | grep -vi 'data_engine' \
  | head -1 \
  | awk '{print $1}' || true)"

if [ -z "$FRONT_CONTAINER" ]; then
  echo "ERROR: no pude detectar frontend."
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
  exit 1
fi

echo "FRONT_CONTAINER=$FRONT_CONTAINER"

echo
echo "== 2) Detectando root público del contenedor =="
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
echo "== 3) Detectando directorios públicos locales =="
PUBLIC_DIRS=()

for d in public frontend/public app/public web public_html; do
  if [ -d "$d" ]; then
    PUBLIC_DIRS+=("$d")
  fi
done

if [ "${#PUBLIC_DIRS[@]}" -eq 0 ]; then
  mkdir -p public
  PUBLIC_DIRS+=("public")
fi

printf ' - %s\n' "${PUBLIC_DIRS[@]}"

echo
echo "== 4) Creando override para pie/image_base64 =="
for d in "${PUBLIC_DIRS[@]}"; do
  mkdir -p "$d"

  if [ -f "$d/chat-pie-image-override.js" ]; then
    cp "$d/chat-pie-image-override.js" "$BACKUP_DIR/$(echo "$d" | tr '/' '_')__chat-pie-image-override.js.bak"
  fi

  cat > "$d/chat-pie-image-override.js" <<'JS'
(function () {
  if (window.__JOMELAI_FORCE_PIE_IMAGE_OVERRIDE__) return;
  window.__JOMELAI_FORCE_PIE_IMAGE_OVERRIDE__ = true;

  const seen = new Set();

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function chartType(payload) {
    return String(
      payload.chart_type ||
      (payload.route && payload.route.chart_type) ||
      (payload.route && payload.route.intent && payload.route.intent.chart_type) ||
      ''
    ).toLowerCase();
  }

  function imageBase64(payload) {
    return (
      payload.image_base64 ||
      (payload.chart && payload.chart.image_base64) ||
      (payload.data && payload.data.image_base64) ||
      ''
    );
  }

  function mimeType(payload) {
    return payload.mime_type || (payload.chart && payload.chart.mime_type) || 'image/png';
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

  function payloadKey(payload) {
    const img = imageBase64(payload);
    return [
      chartType(payload),
      payload.sql || '',
      img.length,
      img.slice(0, 60)
    ].join('|');
  }

  function injectStyle() {
    if (document.getElementById('jomelai-force-pie-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-force-pie-style';
    style.textContent = `
      .jomelai-force-pie-card {
        margin: 14px 0;
        padding: 14px;
        border: 1px solid rgba(15,23,42,.12);
        border-radius: 16px;
        background: #fff;
        box-shadow: 0 10px 30px rgba(15,23,42,.08);
        color: #1f2937;
        font-family: Inter, Roboto, Arial, sans-serif;
        max-width: 100%;
        overflow: hidden;
      }
      .jomelai-force-pie-title {
        font-weight: 800;
        font-size: 14px;
        margin-bottom: 10px;
        color: #0f2f57;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
      }
      .jomelai-force-pie-badge {
        font-size: 11px;
        font-weight: 800;
        padding: 4px 8px;
        border-radius: 999px;
        background: #eaf2ff;
        color: #174a7c;
        white-space: nowrap;
      }
      .jomelai-force-pie-img-wrap {
        padding: 10px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #f8fafc;
        overflow: auto;
        text-align: center;
      }
      .jomelai-force-pie-img {
        max-width: 100%;
        height: auto;
        border-radius: 10px;
        background: #fff;
        display: inline-block;
      }
      .jomelai-force-pie-table-wrap {
        margin-top: 10px;
        overflow: auto;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
      }
      .jomelai-force-pie-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: #fff;
      }
      .jomelai-force-pie-table th {
        background: #f8fafc;
        color: #334155;
        text-align: left;
        padding: 8px 10px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
      }
      .jomelai-force-pie-table td {
        color: #334155;
        padding: 8px 10px;
        border-bottom: 1px solid #eef2f7;
      }
    `;
    document.head.appendChild(style);
  }

  function findMount() {
    const selectors = [
      '#chatMessages',
      '#chat-messages',
      '#messages',
      '#conversation',
      '#aiMessages',
      '.chat-messages',
      '.chat-body',
      '.messages',
      '.conversation',
      '.ai-chat-body',
      '.jomelai-chat',
      '.assistant-panel',
      'main'
    ];

    for (const selector of selectors) {
      const found = Array.from(document.querySelectorAll(selector)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });

      if (found.length) return found[found.length - 1];
    }

    return document.body;
  }

  function renderTable(dataRows) {
    if (!dataRows || !dataRows.length) return '';

    const headers = Object.keys(dataRows[0] || {});
    if (!headers.length) return '';

    return `
      <div class="jomelai-force-pie-table-wrap">
        <table class="jomelai-force-pie-table">
          <thead>
            <tr>${headers.map(h => `<th>${esc(h)}</th>`).join('')}</tr>
          </thead>
          <tbody>
            ${dataRows.slice(0, 50).map(row => `
              <tr>${headers.map(h => `<td>${esc(row[h])}</td>`).join('')}</tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function removeOldBarCard(payload) {
    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      '';

    const bars = Array.from(document.querySelectorAll('.jomelai-chart-bar'));

    for (const bar of bars) {
      const card =
        bar.closest('.jomelai-result-card') ||
        bar.closest('.assistant-message') ||
        bar.closest('.chat-message') ||
        bar.closest('.message') ||
        bar.closest('div');

      if (!card) continue;
      if (card.classList.contains('jomelai-force-pie-card')) continue;

      const text = card.innerText || '';

      // Quita solo la tarjeta de barras que corresponde al último pie.
      if (!title || text.includes(title) || text.includes('duckdb_chart') || text.includes('total por categoria')) {
        card.remove();
      }
    }
  }

  function renderPie(payload) {
    if (!isPiePayload(payload)) return;

    const key = payloadKey(payload);
    if (seen.has(key)) {
      removeOldBarCard(payload);
      return;
    }

    seen.add(key);
    injectStyle();

    const dataRows = rows(payload);
    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      'Gráfico de pie';

    const img = imageBase64(payload);
    const mime = mimeType(payload);

    const card = document.createElement('div');
    card.className = 'jomelai-force-pie-card';
    card.dataset.chartType = 'pie';
    card.dataset.key = key;

    card.innerHTML = `
      <div class="jomelai-force-pie-title">
        <span>${esc(title)}</span>
        <span class="jomelai-force-pie-badge">pie</span>
      </div>
      <div class="jomelai-force-pie-img-wrap">
        <img class="jomelai-force-pie-img" src="data:${esc(mime)};base64,${img}" alt="${esc(title)}" />
      </div>
      ${renderTable(dataRows)}
    `;

    const mount = findMount();
    mount.appendChild(card);

    // El renderer viejo puede pintar barras después; las borramos con pequeños delays.
    setTimeout(() => removeOldBarCard(payload), 50);
    setTimeout(() => removeOldBarCard(payload), 300);
    setTimeout(() => removeOldBarCard(payload), 900);

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {}
  }

  function parseSseChunk(chunk) {
    if (!chunk || !chunk.includes('event: final')) return null;

    const dataLine = chunk.split('\n').find(line => line.startsWith('data:'));
    if (!dataLine) return null;

    try {
      return JSON.parse(dataLine.slice(5).trim());
    } catch (e) {
      return null;
    }
  }

  function installFetchTap() {
    const previousFetch = window.fetch.bind(window);

    window.fetch = function pieOverrideFetch(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      const promise = previousFetch(input, init);

      if (url && url.includes('/api/chat-lateral/ask-stream')) {
        promise.then(res => {
          try {
            const clone = res.clone();
            const reader = clone.body && clone.body.getReader ? clone.body.getReader() : null;
            if (!reader) return;

            const decoder = new TextDecoder('utf-8');
            let buffer = '';

            function pump() {
              reader.read().then(({ done, value }) => {
                if (done) return;

                buffer += decoder.decode(value, { stream: true });

                const chunks = buffer.split('\n\n');
                buffer = chunks.pop() || '';

                for (const chunk of chunks) {
                  const payload = parseSseChunk(chunk);
                  if (payload && isPiePayload(payload)) {
                    renderPie(payload);
                  }
                }

                pump();
              }).catch(() => {});
            }

            pump();
          } catch (e) {}
        }).catch(() => {});
      }

      return promise;
    };
  }

  // También expone una función manual para pruebas desde consola.
  window.JoMelAiForcePieImage = {
    renderPie,
    removeOldBarCard,
    version: 'force-pie-image-v1'
  };

  installFetchTap();

  console.info('[JoMelAi] Force Pie Image Override activo');
})();
JS
done

echo
echo "== 5) Inyectando override DESPUÉS del renderer activo =="
HTML_FILES="$(find . \
  -type f \
  \( -name 'index.html' -o -name '*.blade.php' \) \
  ! -path './.git/*' \
  ! -path './data/*' \
  ! -path './node_modules/*' \
  ! -path './vendor/*' \
  ! -path './backups/*' \
  ! -name '*.bak*' \
  2>/dev/null || true)"

if [ -n "$HTML_FILES" ]; then
  echo "$HTML_FILES" | while read html; do
    [ -z "$html" ] && continue
    [ -f "$html" ] || continue

    cp "$html" "$BACKUP_DIR/$(echo "$html" | tr '/' '_').bak"

    python3 - "$html" <<'PY'
from pathlib import Path
import sys
import time

p = Path(sys.argv[1])
text = p.read_text(encoding="utf-8")

# Quita inyecciones previas.
lines = [ln for ln in text.splitlines() if "chat-pie-image-override.js" not in ln]
text = "\n".join(lines)

script = f'  <script src="/chat-pie-image-override.js?v={int(time.time())}"></script>'

# Prioridad: después de chat-panel-renderer-final.js.
if "chat-panel-renderer-final.js" in text:
    out = []
    inserted = False
    for ln in text.splitlines():
        out.append(ln)
        if "chat-panel-renderer-final.js" in ln and not inserted:
            out.append(script)
            inserted = True
    text = "\n".join(out)
elif "</body>" in text:
    text = text.replace("</body>", script + "\n</body>")
else:
    text += "\n" + script + "\n"

p.write_text(text, encoding="utf-8")
print("Inyectado override en", p)
PY
  done
fi

echo
echo "== 6) Copiando override al contenedor activo =="
FIRST_PUBLIC="${PUBLIC_DIRS[0]}"
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"
docker cp "$FIRST_PUBLIC/chat-pie-image-override.js" "$FRONT_CONTAINER:$CONTAINER_ROOT/chat-pie-image-override.js"

echo
echo "== 7) Recargando Nginx si aplica =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 8) Test asset override =="
curl -sS -I "http://localhost:3000/chat-pie-image-override.js?v=test" || true

echo
echo
echo "== 9) Test API pie: debe traer image_base64 =="
curl -sS -N -m 40 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"grafica la distribucion de horas practicas de las carreras de sede juliaca a traves de los ciclos en un grafico de pie","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | grep -E '"chart_type"|"image_base64"|"mode"|"row_count"' \
  | head -20 || true

echo
echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "Luego en consola del navegador debes ver:"
echo "  [JoMelAi] Force Pie Image Override activo"
echo
echo "Prueba:"
echo "  grafica la distribucion de horas practicas de las carreras de sede juliaca a traves de los ciclos en un grafico de pie"
