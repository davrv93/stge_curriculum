#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Install only Chat Lateral Renderer"
echo "=================================================="

BACKUP_DIR="backups/install_renderer_only_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

PUBLIC_DIR="public"
if [ -d "frontend/public" ]; then
  PUBLIC_DIR="frontend/public"
fi
mkdir -p "$PUBLIC_DIR"

cat > "$PUBLIC_DIR/chat-lateral-v2-renderer.js" <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_LATERAL_RENDERER_LOADED__) return;
  window.__JOMELAI_CHAT_LATERAL_RENDERER_LOADED__ = true;

  const seen = new Set();

  function esc(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function injectStyles() {
    if (document.getElementById('jomelai-chat-lateral-renderer-style')) return;
    const style = document.createElement('style');
    style.id = 'jomelai-chat-lateral-renderer-style';
    style.textContent = `
      .jomelai-result-card{margin:14px 0;padding:14px;border:1px solid rgba(15,23,42,.12);border-radius:16px;background:#fff;box-shadow:0 10px 30px rgba(15,23,42,.08);color:#1f2937;font-family:Inter,Roboto,Arial,sans-serif;max-width:100%;overflow:hidden}
      .jomelai-result-title{font-weight:800;font-size:14px;margin-bottom:10px;color:#0f2f57;display:flex;justify-content:space-between;gap:10px}
      .jomelai-result-badge{font-size:11px;font-weight:700;padding:4px 8px;border-radius:999px;background:#eaf2ff;color:#174a7c;white-space:nowrap}
      .jomelai-result-scroll{width:100%;overflow:auto;border-radius:12px;border:1px solid #e5e7eb}
      .jomelai-result-table{width:100%;border-collapse:collapse;font-size:12px;background:#fff}
      .jomelai-result-table th{background:#f8fafc;color:#334155;font-weight:800;text-align:left;padding:9px 10px;border-bottom:1px solid #e5e7eb;white-space:nowrap}
      .jomelai-result-table td{padding:8px 10px;border-bottom:1px solid #eef2f7;vertical-align:top;color:#334155}
      .jomelai-chart{margin-top:10px;padding:12px;border:1px solid #e5e7eb;border-radius:14px;background:#f8fafc}
      .jomelai-chart-row{display:grid;grid-template-columns:minmax(120px,220px) 1fr minmax(48px,auto);gap:10px;align-items:center;margin:8px 0;font-size:12px}
      .jomelai-chart-label{color:#334155;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .jomelai-chart-track{background:#e5e7eb;height:12px;border-radius:999px;overflow:hidden}
      .jomelai-chart-bar{height:12px;border-radius:999px;background:linear-gradient(90deg,#0f2f57,#2f80ed);min-width:3px}
      .jomelai-chart-value{font-weight:800;color:#0f2f57;text-align:right}
    `;
    document.head.appendChild(style);
  }

  function findMount() {
    const selectors = ['#chatMessages','#chat-messages','#messages','#conversation','#aiMessages','.chat-messages','.chat-body','.messages','.conversation','.ai-chat-body','.jomelai-chat','.assistant-panel','main'];
    for (const selector of selectors) {
      const nodes = Array.from(document.querySelectorAll(selector)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      if (nodes.length) return nodes[nodes.length - 1];
    }
    return document.body;
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

  function renderTable(rows) {
    if (!rows || !rows.length) return '';
    const headers = Object.keys(rows[0] || {});
    if (!headers.length) return '';
    let html = '<div class="jomelai-result-scroll"><table class="jomelai-result-table">';
    html += '<thead><tr>' + headers.map(h => `<th>${esc(h)}</th>`).join('') + '</tr></thead><tbody>';
    rows.slice(0, 50).forEach(row => {
      html += '<tr>' + headers.map(h => `<td>${esc(row[h])}</td>`).join('') + '</tr>';
    });
    html += '</tbody></table></div>';
    return html;
  }

  function detectChartFields(rows, payload) {
    const route = payload && payload.route ? payload.route : {};
    const intent = route.intent || {};
    let x = payload.x || intent.x || null;
    let y = payload.y || intent.y || null;
    if (x && y) return {x, y};
    if (!rows || !rows.length) return null;
    const headers = Object.keys(rows[0] || {});
    const numeric = headers.filter(h => rows.some(r => typeof r[h] === 'number' || (!isNaN(Number(r[h])) && r[h] !== null && r[h] !== '')));
    const text = headers.filter(h => !numeric.includes(h));
    x = x || text[0] || headers[0];
    y = y || numeric[0];
    if (!x || !y) return null;
    return {x, y};
  }

  function renderChart(rows, payload) {
    const shouldChart = payload.mode === 'duckdb_chart' || payload.chart || payload.chart_type || (payload.route && payload.route.route === 'duckdb_chart');
    if (!shouldChart || !rows || !rows.length) return '';
    const fields = detectChartFields(rows, payload);
    if (!fields) return '';
    const data = rows.map(r => ({label:String(r[fields.x] ?? ''), value:Number(r[fields.y])})).filter(x => x.label && !isNaN(x.value)).slice(0,20);
    if (!data.length) return '';
    const max = Math.max(...data.map(x => x.value), 1);
    let html = '<div class="jomelai-chart">';
    html += `<div class="jomelai-result-title">Gráfico <span class="jomelai-result-badge">${esc(fields.y)} por ${esc(fields.x)}</span></div>`;
    data.forEach(item => {
      const pct = Math.max(2, Math.round((item.value / max) * 100));
      html += `<div class="jomelai-chart-row"><div class="jomelai-chart-label">${esc(item.label)}</div><div class="jomelai-chart-track"><div class="jomelai-chart-bar" style="width:${pct}%"></div></div><div class="jomelai-chart-value">${esc(item.value)}</div></div>`;
    });
    html += '</div>';
    return html;
  }

  function render(payload) {
    if (!payload || typeof payload !== 'object') return;
    const rows = getRows(payload);
    const hasRows = rows && rows.length;
    const hasChart = payload.mode === 'duckdb_chart' || payload.chart || payload.chart_type || (payload.route && payload.route.route === 'duckdb_chart');
    if (!hasRows && !hasChart) return;
    const key = JSON.stringify({mode:payload.mode, sql:payload.sql, row_count:payload.row_count, rows:rows});
    if (seen.has(key)) return;
    seen.add(key);
    injectStyles();
    const card = document.createElement('div');
    card.className = 'jomelai-result-card';
    const title = (payload.route && payload.route.intent && payload.route.intent.title) || payload.title || (hasChart ? 'Reporte gráfico' : 'Datos encontrados');
    const badge = payload.mode || (payload.route && payload.route.route) || 'resultado';
    card.innerHTML = `<div class="jomelai-result-title"><span>${esc(title)}</span><span class="jomelai-result-badge">${esc(badge)}</span></div>` + renderChart(rows, payload) + renderTable(rows);
    findMount().appendChild(card);
  }

  function installFetchTap() {
    const originalFetch = window.fetch.bind(window);
    window.fetch = function(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      const promise = originalFetch(input, init);
      if (url && url.includes('/api/chat-lateral/ask-stream')) {
        promise.then(res => {
          const clone = res.clone();
          const reader = clone.body && clone.body.getReader ? clone.body.getReader() : null;
          if (!reader) return;
          const decoder = new TextDecoder('utf-8');
          let buffer = '';
          function pump() {
            reader.read().then(({done, value}) => {
              if (done) return;
              buffer += decoder.decode(value, {stream:true});
              const chunks = buffer.split('\n\n');
              buffer = chunks.pop() || '';
              chunks.forEach(chunk => {
                if (!chunk.includes('event: final')) return;
                const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));
                if (!dataLine) return;
                try { render(JSON.parse(dataLine.slice(5).trim())); } catch(e) {}
              });
              pump();
            }).catch(() => {});
          }
          pump();
        }).catch(() => {});
      }
      return promise;
    };
  }

  window.JoMelAiChatLateralV2Renderer = {render, renderTable, renderChart};
  installFetchTap();
  console.info('[JoMelAi] Renderer Chat Lateral V2 activo');
})();
JS

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
    if grep -q "</body>" "$html" && ! grep -q "chat-lateral-v2-renderer.js" "$html"; then
      cp "$html" "$BACKUP_DIR/$(basename "$html").bak" || true
      sed -i 's#</body>#  <script src="/chat-lateral-v2-renderer.js?v=20260608d"></script>\n</body>#' "$html"
      echo "Inyectado renderer en $html"
    fi
  done
fi

docker compose up -d --build

echo "LISTO. Haz Ctrl+Shift+R y prueba: qué carreras tienes cargadas"
