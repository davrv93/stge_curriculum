#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " FINAL FIX tablas / graficos / FIN_RESPUESTA"
echo "=================================================="

BACKUP_DIR="backups/final_fix_tables_charts_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

ENGINE_FILE="data-engine/app.py"

if [ ! -f "$ENGINE_FILE" ]; then
  echo "ERROR: no existe $ENGINE_FILE"
  exit 1
fi

cp "$ENGINE_FILE" "$BACKUP_DIR/app.py.before_final_fix.bak"

echo
echo "== 1) Reparando _cl_fast_answer con saltos reales y FIN_RESPUESTA =="

python3 - "$ENGINE_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

safe_func = r'''def _cl_fast_answer(rows: List[Dict[str, Any]], title: str = "Resultado") -> str:
    if not rows:
        return "No encontré registros para esa consulta.\nFIN_RESPUESTA"

    total = len(rows)
    sample = rows[:20]

    if not sample or not isinstance(sample[0], dict):
        return f"{title}: encontré {total} registros.\nFIN_RESPUESTA"

    headers = list(sample[0].keys())

    def _fmt(v):
        s = "" if v is None else str(v)
        s = s.replace("\n", " ").replace("\r", " ").replace("|", "/").strip()
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

    lines.append("")
    lines.append("FIN_RESPUESTA")

    return "\n".join(lines)


'''

start = text.find("def _cl_fast_answer(")

if start == -1:
    insert_markers = [
        "def _cl_route(",
        "def _cl_rag_context(",
        '@api.post("/chat-lateral/route")',
    ]
    insert_at = -1
    for marker in insert_markers:
        insert_at = text.find(marker)
        if insert_at != -1:
            break
    if insert_at == -1:
        raise SystemExit("No encontré dónde insertar _cl_fast_answer.")
    text = text[:insert_at] + safe_func + text[insert_at:]
else:
    end_markers = [
        "\ndef _cl_route(",
        "\ndef _cl_rag_context(",
        "\ndef _cl_generate(",
        '\n@api.post("/chat-lateral/route")',
        '\n@api.post("/chat-lateral/ask")',
        '\n@api.post("/chat-lateral/ask-stream")',
        "\n# === CHAT LATERAL",
    ]

    positions = []
    for marker in end_markers:
        pos = text.find(marker, start + 1)
        if pos != -1:
            positions.append(pos)

    if not positions:
        raise SystemExit("No encontré final de _cl_fast_answer.")

    end = min(positions)
    text = text[:start] + safe_func + text[end:].lstrip("\n")

# Asegura FIN_RESPUESTA en respuestas de gráfico DuckDB.
text = text.replace(
    'answer = "Generé el gráfico solicitado desde DuckDB."',
    'answer = "Generé el gráfico solicitado desde DuckDB.\\nFIN_RESPUESTA"'
)

text = text.replace(
    '"answer": "Generé el gráfico solicitado desde DuckDB.",',
    '"answer": "Generé el gráfico solicitado desde DuckDB.\\nFIN_RESPUESTA",'
)

path.write_text(text, encoding="utf-8")
PY

echo
echo "== 2) Compilando app.py =="
python3 -m py_compile "$ENGINE_FILE"
echo "OK: app.py compila."

echo
echo "== 3) Instalando renderer visual en TODAS las carpetas frontend =="

RENDERER_CODE_FILE="/tmp/chat-lateral-pretty-renderer-final.js"

cat > "$RENDERER_CODE_FILE" <<'JS'
(function () {
  if (window.__JOMELAI_PRETTY_RENDERER_FINAL__) return;
  window.__JOMELAI_PRETTY_RENDERER_FINAL__ = true;

  const rendered = new Set();

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function addStyles() {
    if (document.getElementById('jomelai-pretty-renderer-style-final')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-pretty-renderer-style-final';
    style.textContent = `
      .jomelai-pretty-card {
        margin: 14px 0;
        padding: 14px;
        border-radius: 18px;
        border: 1px solid rgba(148, 163, 184, .22);
        background: rgba(255,255,255,.97);
        color: #172033;
        box-shadow: 0 18px 40px rgba(15,23,42,.18);
        overflow: hidden;
        font-family: Inter, Roboto, Arial, sans-serif;
      }
      .jomelai-pretty-title {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        margin-bottom: 10px;
        font-weight: 900;
        font-size: 14px;
        color: #0f2f57;
      }
      .jomelai-pretty-badge {
        flex: 0 0 auto;
        padding: 4px 9px;
        border-radius: 999px;
        font-size: 11px;
        font-weight: 900;
        background: #eaf2ff;
        color: #174a7c;
      }
      .jomelai-pretty-scroll {
        overflow: auto;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #ffffff;
      }
      .jomelai-pretty-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        color: #243244;
      }
      .jomelai-pretty-table th {
        background: #f8fafc;
        color: #0f2f57;
        text-align: left;
        padding: 10px 11px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
        font-weight: 900;
      }
      .jomelai-pretty-table td {
        padding: 9px 11px;
        border-bottom: 1px solid #eef2f7;
        vertical-align: top;
      }
      .jomelai-chart {
        margin-top: 10px;
        padding: 12px;
        border-radius: 14px;
        background: #f8fafc;
        border: 1px solid #e5e7eb;
      }
      .jomelai-chart-row {
        display: grid;
        grid-template-columns: minmax(120px, 240px) 1fr minmax(50px, auto);
        gap: 10px;
        align-items: center;
        margin: 8px 0;
        font-size: 12px;
      }
      .jomelai-chart-label {
        color: #334155;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .jomelai-chart-track {
        height: 13px;
        background: #e5e7eb;
        border-radius: 999px;
        overflow: hidden;
      }
      .jomelai-chart-bar {
        height: 13px;
        border-radius: 999px;
        background: linear-gradient(90deg, #0f2f57, #2f80ed);
        min-width: 3px;
      }
      .jomelai-chart-value {
        text-align: right;
        font-weight: 900;
        color: #0f2f57;
      }
      @media (max-width: 700px) {
        .jomelai-chart-row {
          grid-template-columns: 1fr;
          gap: 5px;
        }
        .jomelai-chart-value {
          text-align: left;
        }
        .jomelai-pretty-table {
          font-size: 11px;
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

  function tableHtml(rows) {
    if (!rows || !rows.length) return '';

    const headers = Object.keys(rows[0] || {});
    if (!headers.length) return '';

    let html = '<div class="jomelai-pretty-scroll">';
    html += '<table class="jomelai-pretty-table">';
    html += '<thead><tr>' + headers.map(h => `<th>${esc(h)}</th>`).join('') + '</tr></thead>';
    html += '<tbody>';

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

  function chartHtml(rows, payload) {
    const isChart =
      payload.mode === 'duckdb_chart' ||
      payload.chart ||
      payload.chart_type ||
      (payload.route && payload.route.route === 'duckdb_chart');

    if (!isChart || !rows || !rows.length) return '';

    const fields = detectChartFields(rows, payload);
    if (!fields) return '';

    const data = rows
      .map(row => ({
        label: String(row[fields.x] == null ? '' : row[fields.x]),
        value: Number(row[fields.y])
      }))
      .filter(item => item.label && !isNaN(item.value))
      .slice(0, 20);

    if (!data.length) return '';

    const max = Math.max(...data.map(x => x.value), 1);

    let html = '<div class="jomelai-chart">';
    html += `<div class="jomelai-pretty-title">Gráfico <span class="jomelai-pretty-badge">${esc(fields.y)} por ${esc(fields.x)}</span></div>`;

    data.forEach(item => {
      const pct = Math.max(2, Math.round((item.value / max) * 100));
      html += `
        <div class="jomelai-chart-row">
          <div class="jomelai-chart-label" title="${esc(item.label)}">${esc(item.label)}</div>
          <div class="jomelai-chart-track">
            <div class="jomelai-chart-bar" style="width:${pct}%"></div>
          </div>
          <div class="jomelai-chart-value">${esc(item.value)}</div>
        </div>
      `;
    });

    html += '</div>';
    return html;
  }

  function renderPayload(payload) {
    if (!payload || typeof payload !== 'object') return;

    const rows = getRows(payload);
    const hasRows = rows && rows.length;
    const hasChart =
      payload.mode === 'duckdb_chart' ||
      payload.chart ||
      payload.chart_type ||
      (payload.route && payload.route.route === 'duckdb_chart');

    if (!hasRows && !hasChart) return;

    const key = JSON.stringify({
      mode: payload.mode,
      sql: payload.sql,
      row_count: payload.row_count,
      rows: rows
    });

    if (rendered.has(key)) return;
    rendered.add(key);

    addStyles();

    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      (hasChart ? 'Reporte gráfico' : 'Datos encontrados');

    const badge = payload.mode || (payload.route && payload.route.route) || 'resultado';

    const card = document.createElement('div');
    card.className = 'jomelai-pretty-card';
    card.innerHTML = `
      <div class="jomelai-pretty-title">
        <span>${esc(title)}</span>
        <span class="jomelai-pretty-badge">${esc(badge)}</span>
      </div>
      ${chartHtml(rows, payload)}
      ${tableHtml(rows)}
    `;

    findMount().appendChild(card);

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {}
  }

  function parseMarkdownTable(text) {
    if (!text) return null;

    const normalized = text
      .replace(/\\n/g, '\n')
      .replace(/FIN_RESPUESTA/g, '')
      .trim();

    if (!normalized.includes('|')) return null;

    const lines = normalized.split('\n').map(x => x.trim()).filter(Boolean);
    const headerIndex = lines.findIndex(line => line.startsWith('|') && line.endsWith('|'));

    if (headerIndex < 0 || headerIndex + 1 >= lines.length) return null;
    if (!lines[headerIndex + 1].includes('---')) return null;

    const headers = lines[headerIndex].split('|').slice(1, -1).map(x => x.trim());
    const rows = [];

    for (let i = headerIndex + 2; i < lines.length; i++) {
      const line = lines[i];
      if (!line.startsWith('|') || !line.endsWith('|')) continue;

      const cells = line.split('|').slice(1, -1).map(x => x.trim());
      const row = {};
      headers.forEach((h, idx) => row[h] = cells[idx] || '');
      rows.push(row);
    }

    if (!headers.length || !rows.length) return null;

    return {
      title: lines.slice(0, headerIndex).join(' '),
      rows
    };
  }

  function cleanupMarkdown() {
    addStyles();

    const candidates = Array.from(document.querySelectorAll('div,p,span'))
      .filter(el => {
        if (el.dataset.prettyCleaned === '1') return false;
        if (el.closest('.jomelai-pretty-card')) return false;

        const txt = el.innerText || el.textContent || '';
        if (!txt.includes('|')) return false;
        if (!txt.includes('---')) return false;

        const childHas = Array.from(el.children || []).some(ch => {
          const t = ch.innerText || ch.textContent || '';
          return t.includes('|') && t.includes('---');
        });

        return !childHas;
      });

    candidates.forEach(el => {
      const parsed = parseMarkdownTable(el.innerText || el.textContent || '');
      if (!parsed) return;

      el.dataset.prettyCleaned = '1';
      el.innerHTML = `
        <div style="font-weight:900;margin-bottom:10px;color:#fff">${esc(parsed.title)}</div>
        ${tableHtml(parsed.rows)}
      `;
    });

    Array.from(document.querySelectorAll('div,p,span')).forEach(el => {
      if (el.children && el.children.length) return;
      if (!el.textContent) return;

      if (el.textContent.includes('FIN_RESPUESTA')) {
        el.textContent = el.textContent.replace(/FIN_RESPUESTA/g, '').trim();
      }

      if (el.textContent.includes('\\n')) {
        el.textContent = el.textContent.replace(/\\n/g, '\n');
      }
    });
  }

  function installFetchTap() {
    if (window.__JOMELAI_FETCH_TAP_FINAL__) return;
    window.__JOMELAI_FETCH_TAP_FINAL__ = true;

    const originalFetch = window.fetch.bind(window);

    window.fetch = function patchedFetch(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      const promise = originalFetch(input, init);

      try {
        if (url && url.includes('/api/chat-lateral/ask-stream')) {
          promise.then(res => {
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

                chunks.forEach(chunk => {
                  if (!chunk.includes('event: final')) return;

                  const line = chunk.split('\n').find(x => x.startsWith('data:'));
                  if (!line) return;

                  try {
                    renderPayload(JSON.parse(line.slice(5).trim()));
                  } catch (e) {}
                });

                pump();
              }).catch(() => {});
            }

            pump();
          }).catch(() => {});
        }
      } catch (e) {}

      return promise;
    };
  }

  function installObserver() {
    const run = () => cleanupMarkdown();

    const obs = new MutationObserver(() => {
      clearTimeout(window.__jomelaiPrettyTimer);
      window.__jomelaiPrettyTimer = setTimeout(run, 120);
    });

    if (document.body) {
      obs.observe(document.body, { childList: true, subtree: true, characterData: true });
      run();
    }
  }

  window.JoMelAiPrettyRenderer = {
    renderPayload,
    cleanupMarkdown
  };

  installFetchTap();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', installObserver);
  } else {
    installObserver();
  }

  console.info('[JoMelAi] Pretty renderer FINAL activo');
})();
JS

# Instalar en todas las rutas probables del frontend host.
for dir in frontend frontend/public public sync_docker_to_host_20260608_125609/docker_frontend; do
  if [ -d "$dir" ]; then
    cp "$RENDERER_CODE_FILE" "$dir/chat-lateral-pretty-renderer.js"
    echo "Renderer instalado en $dir/chat-lateral-pretty-renderer.js"
  fi
done

echo
echo "== 4) Inyectando renderer en index.html disponibles =="

HTML_FILES="$(find frontend public sync_docker_to_host_20260608_125609/docker_frontend . \
  -maxdepth 3 \
  -type f \
  -name "index.html" \
  ! -path "./.git/*" \
  ! -path "./data/*" \
  ! -path "./node_modules/*" \
  ! -path "./vendor/*" \
  ! -path "./backups/*" \
  ! -name "*.bak*" \
  2>/dev/null | sort -u || true)"

if [ -n "$HTML_FILES" ]; then
  echo "$HTML_FILES" | while read html; do
    [ -z "$html" ] && continue

    if grep -q "</body>" "$html"; then
      cp "$html" "$BACKUP_DIR/$(echo "$html" | tr '/' '_').bak" || true

      sed -i '/chat-lateral-v2-renderer.js/d' "$html" || true
      sed -i '/chat-lateral-pretty-renderer.js/d' "$html" || true

      echo "Inyectando en $html"
      sed -i 's#</body>#  <script src="/chat-lateral-pretty-renderer.js?v=20260608final"></script>\n</body>#' "$html"
    fi
  done
fi

echo
echo "== 5) Copiando renderer directo al contenedor frontend si existe =="

if docker ps --format '{{.Names}}' | grep -q '^jomelai_frontend$'; then
  for target in /usr/share/nginx/html /var/www/html /app /usr/src/app; do
    if docker exec jomelai_frontend sh -lc "[ -d '$target' ]" >/dev/null 2>&1; then
      docker cp "$RENDERER_CODE_FILE" "jomelai_frontend:$target/chat-lateral-pretty-renderer.js" || true

      if docker exec jomelai_frontend sh -lc "[ -f '$target/index.html' ]" >/dev/null 2>&1; then
        docker exec jomelai_frontend sh -lc "cp '$target/index.html' '$target/index.html.bak.prettyfinal' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-v2-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-pretty-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i 's#</body>#  <script src=\"/chat-lateral-pretty-renderer.js?v=20260608final\"></script>\\n</body>#' '$target/index.html' || true"
      fi

      echo "Renderer copiado dentro del contenedor en $target"
    fi
  done
fi

echo
echo "== 6) Corrigiendo rutas y puerto 8090 =="
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
echo "== 7) Rebuild/restart =="
docker compose up -d --build

sleep 10

echo
echo "== 8) Reinstalando renderer dentro del contenedor luego del rebuild =="
if docker ps --format '{{.Names}}' | grep -q '^jomelai_frontend$'; then
  for target in /usr/share/nginx/html /var/www/html /app /usr/src/app; do
    if docker exec jomelai_frontend sh -lc "[ -d '$target' ]" >/dev/null 2>&1; then
      docker cp "$RENDERER_CODE_FILE" "jomelai_frontend:$target/chat-lateral-pretty-renderer.js" || true

      if docker exec jomelai_frontend sh -lc "[ -f '$target/index.html' ]" >/dev/null 2>&1; then
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-v2-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-pretty-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i 's#</body>#  <script src=\"/chat-lateral-pretty-renderer.js?v=20260608final\"></script>\\n</body>#' '$target/index.html' || true"
      fi
    fi
  done

  docker exec jomelai_frontend nginx -s reload 2>/dev/null || true
fi

echo
echo "== 9) Test Data Engine directo =="
curl -sS -N -m 30 -X POST http://localhost:8090/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"que carreras tienes?","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 4000 || true

echo
echo
echo "== 10) Test Frontend 3000 =="
curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"que carreras tienes?","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 4000 || true

echo
echo
echo "== 11) Test archivo renderer servido =="
curl -sS -m 10 http://localhost:3000/chat-lateral-pretty-renderer.js | head -c 300 || true

echo
echo
echo "== 12) Estado final =="
docker compose ps

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Abre:"
echo "  http://18.191.127.254:3000"
echo
echo "Haz hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "Prueba:"
echo "  que carreras tienes?"
echo "  grafica carreras por facultad"
