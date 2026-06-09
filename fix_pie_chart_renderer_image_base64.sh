#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Fix Pie Charts Renderer: image_base64 support"
echo "=================================================="

BACKUP_DIR="backups/fix_pie_renderer_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "== 1) Detectando contenedor frontend =="
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
echo "== 4) Escribiendo renderer con soporte image_base64/pie =="
for d in "${PUBLIC_DIRS[@]}"; do
  mkdir -p "$d"

  if [ -f "$d/chat-lateral-v2-renderer.js" ]; then
    cp "$d/chat-lateral-v2-renderer.js" "$BACKUP_DIR/$(echo "$d" | tr '/' '_')__chat-lateral-v2-renderer.js.bak"
  fi

  cat > "$d/chat-lateral-v2-renderer.js" <<'JS'
(function () {
  window.__JOMELAI_CHAT_LATERAL_RENDERER_VERSION__ = 'pie-image-base64-v2';

  const seen = new Set();

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function getChartType(payload) {
    return (
      payload.chart_type ||
      (payload.route && payload.route.chart_type) ||
      (payload.route && payload.route.intent && payload.route.intent.chart_type) ||
      (payload.chart && payload.chart.chart_type) ||
      ''
    );
  }

  function getImageBase64(payload) {
    return (
      payload.image_base64 ||
      (payload.chart && payload.chart.image_base64) ||
      (payload.data && payload.data.image_base64) ||
      ''
    );
  }

  function getMimeType(payload) {
    return (
      payload.mime_type ||
      (payload.chart && payload.chart.mime_type) ||
      'image/png'
    );
  }

  function getRows(payload) {
    if (!payload) return [];
    if (Array.isArray(payload.rows)) return payload.rows;
    if (payload.data && Array.isArray(payload.data.rows)) return payload.data.rows;
    if (payload.result && Array.isArray(payload.result.rows)) return payload.result.rows;
    if (payload.chart && Array.isArray(payload.chart.rows)) return payload.chart.rows;
    if (payload.chart && Array.isArray(payload.chart.data)) return payload.chart.data;
    if (Array.isArray(payload.data)) return payload.data;
    return [];
  }

  function hashPayload(payload) {
    const chartType = getChartType(payload);
    const img = getImageBase64(payload);

    try {
      return JSON.stringify({
        mode: payload.mode,
        chart_type: chartType,
        sql: payload.sql,
        row_count: payload.row_count,
        rows: getRows(payload),
        image_hash: img ? img.slice(0, 120) + ':' + img.length : ''
      });
    } catch (e) {
      return String(Date.now());
    }
  }

  function injectStyles() {
    if (document.getElementById('jomelai-chat-lateral-renderer-style-v2')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-chat-lateral-renderer-style-v2';
    style.textContent = `
      .jomelai-result-card {
        margin: 14px 0;
        padding: 14px;
        border: 1px solid rgba(15, 23, 42, .12);
        border-radius: 16px;
        background: #ffffff;
        box-shadow: 0 10px 30px rgba(15, 23, 42, .08);
        color: #1f2937;
        font-family: Inter, Roboto, Arial, sans-serif;
        max-width: 100%;
        overflow: hidden;
      }
      .jomelai-result-title {
        font-weight: 800;
        font-size: 14px;
        margin-bottom: 10px;
        color: #0f2f57;
        display: flex;
        justify-content: space-between;
        gap: 10px;
        align-items: center;
      }
      .jomelai-result-badge {
        font-size: 11px;
        font-weight: 700;
        padding: 4px 8px;
        border-radius: 999px;
        background: #eaf2ff;
        color: #174a7c;
        white-space: nowrap;
      }
      .jomelai-chart-img-wrap {
        margin-top: 10px;
        padding: 10px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #f8fafc;
        overflow: auto;
        text-align: center;
      }
      .jomelai-chart-img {
        max-width: 100%;
        height: auto;
        display: inline-block;
        border-radius: 10px;
        background: #ffffff;
      }
      .jomelai-result-scroll {
        width: 100%;
        overflow: auto;
        border-radius: 12px;
        border: 1px solid #e5e7eb;
        margin-top: 10px;
      }
      .jomelai-result-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: #fff;
      }
      .jomelai-result-table th {
        background: #f8fafc;
        color: #334155;
        font-weight: 800;
        text-align: left;
        padding: 9px 10px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
      }
      .jomelai-result-table td {
        padding: 8px 10px;
        border-bottom: 1px solid #eef2f7;
        vertical-align: top;
        color: #334155;
      }
      .jomelai-chart {
        margin-top: 10px;
        padding: 12px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #f8fafc;
      }
      .jomelai-chart-row {
        display: grid;
        grid-template-columns: minmax(120px, 220px) 1fr minmax(48px, auto);
        gap: 10px;
        align-items: center;
        margin: 8px 0;
        font-size: 12px;
      }
      .jomelai-chart-label {
        color: #334155;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .jomelai-chart-track {
        background: #e5e7eb;
        height: 12px;
        border-radius: 999px;
        overflow: hidden;
      }
      .jomelai-chart-bar {
        height: 12px;
        border-radius: 999px;
        background: linear-gradient(90deg, #0f2f57, #2f80ed);
        min-width: 3px;
      }
      .jomelai-chart-value {
        font-weight: 800;
        color: #0f2f57;
        text-align: right;
      }
      .jomelai-result-note {
        margin-top: 8px;
        font-size: 11px;
        color: #64748b;
      }
      @media (max-width: 700px) {
        .jomelai-chart-row {
          grid-template-columns: 1fr;
          gap: 5px;
        }
        .jomelai-chart-value {
          text-align: left;
        }
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
      const nodes = Array.from(document.querySelectorAll(selector)).filter(el => {
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      });

      if (nodes.length) return nodes[nodes.length - 1];
    }

    return document.body;
  }

  function renderImageChart(payload) {
    const img = getImageBase64(payload);
    if (!img) return '';

    const mime = getMimeType(payload);
    const chartType = getChartType(payload) || 'chart';

    return `
      <div class="jomelai-chart-img-wrap">
        <img
          class="jomelai-chart-img"
          alt="Gráfico ${esc(chartType)}"
          src="data:${esc(mime)};base64,${img}"
        />
      </div>
    `;
  }

  function renderTable(rows) {
    if (!rows || !rows.length) return '';

    const headers = Object.keys(rows[0] || {});
    if (!headers.length) return '';

    const maxRows = Math.min(rows.length, 50);

    let html = '<div class="jomelai-result-scroll">';
    html += '<table class="jomelai-result-table">';
    html += '<thead><tr>' + headers.map(h => `<th>${esc(h)}</th>`).join('') + '</tr></thead>';
    html += '<tbody>';

    for (let i = 0; i < maxRows; i++) {
      const row = rows[i] || {};
      html += '<tr>' + headers.map(h => `<td>${esc(row[h])}</td>`).join('') + '</tr>';
    }

    html += '</tbody></table></div>';

    if (rows.length > maxRows) {
      html += `<div class="jomelai-result-note">Mostrando ${maxRows} de ${rows.length} registros.</div>`;
    }

    return html;
  }

  function detectChartFields(rows, payload) {
    const route = payload && payload.route ? payload.route : {};
    const intent = route.intent || {};

    let x = payload.x || intent.x || null;
    let y = payload.y || intent.y || null;

    if (x && y) return { x, y };

    if (!rows || !rows.length) return null;

    const headers = Object.keys(rows[0] || {});
    const numeric = headers.filter(h =>
      rows.some(r => typeof r[h] === 'number' || (!isNaN(Number(r[h])) && r[h] !== null && r[h] !== ''))
    );
    const text = headers.filter(h => !numeric.includes(h));

    x = x || text[0] || headers[0];
    y = y || numeric[0];

    if (!x || !y) return null;
    return { x, y };
  }

  function renderFallbackBars(rows, payload) {
    const chartType = getChartType(payload);

    // Si es pie y hay image_base64, no renderizar barras.
    if (chartType === 'pie' && getImageBase64(payload)) return '';

    const shouldChart =
      payload.mode === 'duckdb_chart' ||
      payload.chart ||
      chartType ||
      (payload.route && payload.route.route === 'duckdb_chart');

    if (!shouldChart || !rows || !rows.length) return '';

    const fields = detectChartFields(rows, payload);
    if (!fields) return '';

    const data = rows
      .map(r => ({
        label: String(r[fields.x] == null ? '' : r[fields.x]),
        value: Number(r[fields.y])
      }))
      .filter(x => x.label && !isNaN(x.value))
      .slice(0, 20);

    if (!data.length) return '';

    const max = Math.max(...data.map(x => x.value), 1);

    let html = '<div class="jomelai-chart">';
    html += `<div class="jomelai-result-title">Gráfico <span class="jomelai-result-badge">${esc(fields.y)} por ${esc(fields.x)}</span></div>`;

    for (const item of data) {
      const pct = Math.max(2, Math.round((item.value / max) * 100));
      html += `
        <div class="jomelai-chart-row">
          <div class="jomelai-chart-label" title="${esc(item.label)}">${esc(item.label)}</div>
          <div class="jomelai-chart-track"><div class="jomelai-chart-bar" style="width:${pct}%"></div></div>
          <div class="jomelai-chart-value">${esc(item.value)}</div>
        </div>
      `;
    }

    html += '</div>';
    return html;
  }

  function render(payload, options) {
    if (!payload || typeof payload !== 'object') return;

    const rows = getRows(payload);
    const image = getImageBase64(payload);
    const chartType = getChartType(payload);

    const hasRows = rows && rows.length;
    const hasChart = payload.mode === 'duckdb_chart' || payload.chart || chartType || image;

    if (!hasRows && !hasChart) return;

    const key = hashPayload(payload);
    if (seen.has(key)) return;
    seen.add(key);

    injectStyles();

    const mount = options && options.mount ? options.mount : findMount();

    const card = document.createElement('div');
    card.className = 'jomelai-result-card';
    card.dataset.chatLateralRendered = '1';
    card.dataset.chartType = chartType || '';

    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      (hasChart ? 'Reporte gráfico' : 'Datos encontrados');

    const badge =
      chartType ||
      payload.mode ||
      (payload.route && payload.route.route) ||
      'resultado';

    let html = `
      <div class="jomelai-result-title">
        <span>${esc(title)}</span>
        <span class="jomelai-result-badge">${esc(badge)}</span>
      </div>
    `;

    // Prioridad: imagen real generada por backend. Esto arregla pie/pastel.
    html += renderImageChart(payload);

    // Fallback visual para barras si no hay imagen.
    html += renderFallbackBars(rows, payload);

    // Siempre mostrar tabla de datos.
    html += renderTable(rows);

    card.innerHTML = html;
    mount.appendChild(card);

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {}
  }

  function installFetchTap() {
    const originalFetch = window.fetch.bind(window);

    window.fetch = function jomelaiRendererFetch(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      const promise = originalFetch(input, init);

      try {
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
                    if (!chunk.includes('event: final')) continue;

                    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));
                    if (!dataLine) continue;

                    try {
                      const payload = JSON.parse(dataLine.slice(5).trim());
                      render(payload);
                    } catch (e) {}
                  }

                  pump();
                }).catch(() => {});
              }

              pump();
            } catch (e) {}
          }).catch(() => {});
        }
      } catch (e) {}

      return promise;
    };
  }

  window.JoMelAiChatLateralV2Renderer = {
    render,
    renderTable,
    renderImageChart,
    renderFallbackBars,
    version: 'pie-image-base64-v2'
  };

  installFetchTap();

  console.info('[JoMelAi] Renderer Chat Lateral V2 activo con soporte pie/image_base64');
})();
JS
done

echo
echo "== 5) Copiando renderer al contenedor activo =="
FIRST_PUBLIC="${PUBLIC_DIRS[0]}"
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"
docker cp "$FIRST_PUBLIC/chat-lateral-v2-renderer.js" "$FRONT_CONTAINER:$CONTAINER_ROOT/chat-lateral-v2-renderer.js"

echo
echo "== 6) Recargando Nginx si aplica =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 7) Test asset renderer =="
curl -sS -I "http://localhost:3000/chat-lateral-v2-renderer.js?v=piefix" || true

echo
echo
echo "== 8) Test API pie: verificando chart_type e image_base64 =="
curl -sS -N -m 40 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"grafica la distribucion de horas practicas de las carreras de sede juliaca a traves de los ciclos en un grafico de pie","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | grep -E '"chart_type"|"image_base64"|"mode"|"row_count"' \
  | head -20 || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Haz hard refresh en navegador:"
echo "  Ctrl + Shift + R"
echo
echo "Luego prueba:"
echo "  grafica la distribucion de horas practicas de las carreras de sede juliaca a traves de los ciclos en un grafico de pie"
