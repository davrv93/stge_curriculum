#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Repair app.py SyntaxError + Render Data/Charts"
echo "=================================================="

BACKUP_DIR="backups/repair_app_py_render_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

ENGINE_FILE="data-engine/app.py"

if [ ! -f "$ENGINE_FILE" ]; then
  ENGINE_FILE="$(find . -type f -name "*.py" \
    ! -path "./data/*" \
    ! -path "./.git/*" \
    ! -path "./node_modules/*" \
    ! -path "./vendor/*" \
    -print0 | xargs -0 grep -sl '@api.post("/chat-lateral/ask-stream")' | head -1 || true)"
fi

if [ -z "$ENGINE_FILE" ] || [ ! -f "$ENGINE_FILE" ]; then
  echo "ERROR: no encontré el app.py del Data Engine."
  exit 1
fi

echo "ENGINE_FILE=$ENGINE_FILE"
cp "$ENGINE_FILE" "$BACKUP_DIR/app.py.broken.bak"

echo
echo "== 1) Reescribiendo _cl_fast_answer de forma segura =="

python3 - "$ENGINE_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

safe_func = '''
def _cl_fast_answer(rows: List[Dict[str, Any]], title: str = "Resultado") -> str:
    if not rows:
        return "No encontré registros para esa consulta."

    total = len(rows)
    sample = rows[:20]

    if not sample or not isinstance(sample[0], dict):
        return f"{title}: encontré {total} registros."

    headers = list(sample[0].keys())

    def _fmt(v):
        s = "" if v is None else str(v)
        s = s.replace("\\\\n", " ").replace("\\\\r", " ").replace("|", "/").strip()
        return s[:120]

    lines = []
    lines.append(f"{title}: encontré {total} registros.")
    lines.append("")
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for row in sample:
        lines.append("| " + " | ".join(_fmt(row.get(h)) for h in headers) + " |")

    if total > len(sample):
        lines.append("")
        lines.append(f"Mostrando {len(sample)} de {total} registros.")

    return "\\\\n".join(lines)
'''.strip()

start = text.find("def _cl_fast_answer(")

if start == -1:
    marker = "def _cl_route("
    pos = text.find(marker)
    if pos == -1:
        marker = "@api.post(\"/chat-lateral/route\")"
        pos = text.find(marker)
    if pos == -1:
        raise SystemExit("No encontré dónde insertar _cl_fast_answer.")
    text = text[:pos] + safe_func + "\\n\\n\\n" + text[pos:]
else:
    # Buscar el inicio del siguiente def/decorador de nivel superior después de _cl_fast_answer.
    candidates = []
    for pat in ["\\ndef _cl_route(", "\\ndef _cl_rag_context(", "\\ndef _cl_generate(", "\\n@api.post"]:
        idx = text.find(pat, start + 1)
        if idx != -1:
            candidates.append(idx)

    if not candidates:
        raise SystemExit("No pude encontrar el final de _cl_fast_answer.")

    end = min(candidates)
    text = text[:start] + safe_func + "\\n\\n" + text[end:].lstrip("\\n")

path.write_text(text, encoding="utf-8")
PY

echo
echo "== 2) Compilando app.py =="
python3 -m py_compile "$ENGINE_FILE"

echo "OK: app.py compila."

echo
echo "== 3) Asegurando renderer frontend =="

PUBLIC_DIR="public"
if [ -d "frontend/public" ]; then
  PUBLIC_DIR="frontend/public"
fi
if [ ! -d "$PUBLIC_DIR" ]; then
  mkdir -p "$PUBLIC_DIR"
fi

echo "PUBLIC_DIR=$PUBLIC_DIR"

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

  function hashPayload(payload) {
    try {
      return JSON.stringify({
        mode: payload.mode,
        sql: payload.sql,
        row_count: payload.row_count,
        rows: payload.rows,
        chart: payload.chart,
        answer: payload.answer
      });
    } catch (e) {
      return String(Date.now());
    }
  }

  function injectStyles() {
    if (document.getElementById('jomelai-chat-lateral-renderer-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-chat-lateral-renderer-style';
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
      .jomelai-result-scroll {
        width: 100%;
        overflow: auto;
        border-radius: 12px;
        border: 1px solid #e5e7eb;
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

  function renderChart(rows, payload) {
    if (!rows || !rows.length) return '';

    const shouldChart =
      payload.mode === 'duckdb_chart' ||
      payload.chart ||
      payload.chart_type ||
      (payload.route && payload.route.route === 'duckdb_chart');

    if (!shouldChart) return '';

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
    const hasRows = rows && rows.length;
    const hasChart = payload.mode === 'duckdb_chart' || payload.chart || payload.chart_type || (payload.route && payload.route.route === 'duckdb_chart');

    if (!hasRows && !hasChart) return;

    const key = hashPayload(payload);
    if (seen.has(key)) return;
    seen.add(key);

    injectStyles();

    const mount = options && options.mount ? options.mount : findMount();

    const card = document.createElement('div');
    card.className = 'jomelai-result-card';
    card.dataset.chatLateralRendered = '1';

    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      (hasChart ? 'Reporte gráfico' : 'Datos encontrados');

    const badge = payload.mode || (payload.route && payload.route.route) || 'resultado';

    let html = `
      <div class="jomelai-result-title">
        <span>${esc(title)}</span>
        <span class="jomelai-result-badge">${esc(badge)}</span>
      </div>
    `;

    html += renderChart(rows, payload);
    html += renderTable(rows);

    card.innerHTML = html;
    mount.appendChild(card);

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {}
  }

  function installFetchTap() {
    if (window.__JOMELAI_CHAT_LATERAL_FETCH_TAP__) return;
    window.__JOMELAI_CHAT_LATERAL_FETCH_TAP__ = true;

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
    renderChart
  };

  installFetchTap();

  console.info('[JoMelAi] Renderer Chat Lateral V2 activo');
})();
JS

echo
echo "== 3) Inyectando renderer en HTML =="

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

    if grep -q "</body>" "$html"; then
      cp "$html" "$BACKUP_DIR/$(basename "$html").bak" || true

      if ! grep -q "chat-lateral-v2-renderer.js" "$html"; then
        echo "Inyectando renderer en $html"
        sed -i 's#</body>#  <script src="/chat-lateral-v2-renderer.js?v=20260608c"></script>\n</body>#' "$html"
      fi
    fi
  done
fi

echo
echo "== 4) Corrigiendo URLs 8090 y rutas públicas =="
touch .env

sed -i \
  -e 's#/api/chat-lateral/api/chat-lateral#/api/chat-lateral#g' \
  -e 's#http://data-engine:8000#http://data-engine:8090#g' \
  -e 's#localhost:8000#localhost:8090#g' \
  .env docker-compose.yml docker-compose.override.yml routes/api.php backend/routes/api.php 2>/dev/null || true

if grep -q '^DATA_ENGINE_URL=' .env; then
  sed -i 's#^DATA_ENGINE_URL=.*#DATA_ENGINE_URL=http://data-engine:8090#g' .env
else
  echo 'DATA_ENGINE_URL=http://data-engine:8090' >> .env
fi

if grep -q '^SILABO_ENGINE_URL=' .env; then
  sed -i 's#^SILABO_ENGINE_URL=.*#SILABO_ENGINE_URL=http://data-engine:8090#g' .env
else
  echo 'SILABO_ENGINE_URL=http://data-engine:8090' >> .env
fi

echo
echo "== 5) Rebuild/restart =="
docker compose down
docker compose up -d --build

echo
echo "== 6) Test Data Engine tabla =="
docker exec jomelai_data_engine python3 -c 'import json, urllib.request; payload=json.dumps({"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"limit":20,"allow_ollama":False}).encode(); req=urllib.request.Request("http://127.0.0.1:8090/chat-lateral/ask-stream",data=payload,headers={"Content-Type":"application/json"},method="POST"); print(urllib.request.urlopen(req,timeout=30).read(4000).decode())'

echo
echo "== 7) Test proxy público tabla =="
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"qué carreras tienes cargadas","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 4000 || true

echo
echo
echo "== 8) Test proxy público gráfico =="
curl -sS -N -m 30 -X POST http://localhost:38764/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"grafica carreras por facultad","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 4000 || true

echo
echo
echo "== 9) Verificando renderer inyectado =="
grep -R "chat-lateral-v2-renderer.js" -n . \
  --exclude-dir=.git \
  --exclude-dir=data \
  --exclude-dir=node_modules \
  --exclude-dir=vendor \
  --exclude-dir=backups \
  --exclude='*.bak*' \
  2>/dev/null | head -80 || true

echo
echo "== 10) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "Prueba:"
echo "  qué carreras tienes cargadas"
echo "  grafica carreras por facultad"
