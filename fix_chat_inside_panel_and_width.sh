#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " FIX chat render inside panel + width button"
echo "=================================================="

BACKUP_DIR="backups/fix_chat_inside_panel_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

RENDERER="/tmp/jomelai-chat-panel-renderer.js"

cat > "$RENDERER" <<'JS'
(function () {
  if (window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__) return;
  window.__JOMELAI_CHAT_PANEL_RENDERER_FINAL__ = true;

  const rendered = new Set();
  let wide = localStorage.getItem('jomelai_chat_wide') === '1';
  const originalPanelStyles = new WeakMap();

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function addStyles() {
    if (document.getElementById('jomelai-chat-panel-renderer-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-chat-panel-renderer-style';
    style.textContent = `
      .jomelai-chat-panel-detected {
        transition: width .22s ease, max-width .22s ease, transform .22s ease;
      }

      .jomelai-chat-wide-btn {
        border: 1px solid rgba(148, 163, 184, .28);
        background: rgba(255,255,255,.08);
        color: #eef2ff;
        border-radius: 10px;
        padding: 7px 10px;
        font-size: 12px;
        font-weight: 800;
        cursor: pointer;
        margin-left: auto;
        margin-right: 8px;
      }

      .jomelai-chat-wide-btn:hover {
        background: rgba(255,255,255,.14);
      }

      .jomelai-chat-data-card {
        margin: 12px 0;
        padding: 12px;
        border-radius: 16px;
        border: 1px solid rgba(148, 163, 184, .28);
        background: rgba(255,255,255,.96);
        color: #172033;
        box-shadow: 0 14px 34px rgba(15,23,42,.20);
        overflow: hidden;
        font-family: Inter, Roboto, Arial, sans-serif;
      }

      .jomelai-chat-data-title {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 10px;
        font-size: 14px;
        font-weight: 900;
        color: #0f2f57;
      }

      .jomelai-chat-data-badge {
        padding: 4px 9px;
        border-radius: 999px;
        font-size: 11px;
        font-weight: 900;
        background: #eaf2ff;
        color: #174a7c;
        white-space: nowrap;
      }

      .jomelai-chat-table-wrap {
        width: 100%;
        overflow-x: auto;
        border-radius: 12px;
        border: 1px solid #e5e7eb;
        background: #ffffff;
      }

      .jomelai-chat-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        color: #243244;
      }

      .jomelai-chat-table th {
        background: #f8fafc;
        color: #0f2f57;
        text-align: left;
        padding: 9px 10px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
        font-weight: 900;
      }

      .jomelai-chat-table td {
        padding: 8px 10px;
        border-bottom: 1px solid #eef2f7;
        vertical-align: top;
      }

      .jomelai-chat-table tr:last-child td {
        border-bottom: 0;
      }

      .jomelai-chat-chart {
        margin-top: 10px;
        padding: 12px;
        border-radius: 14px;
        background: #f8fafc;
        border: 1px solid #e5e7eb;
      }

      .jomelai-chat-chart-row {
        display: grid;
        grid-template-columns: minmax(120px, 220px) 1fr minmax(46px, auto);
        gap: 10px;
        align-items: center;
        margin: 8px 0;
        font-size: 12px;
      }

      .jomelai-chat-chart-label {
        color: #334155;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .jomelai-chat-chart-track {
        height: 13px;
        background: #e5e7eb;
        border-radius: 999px;
        overflow: hidden;
      }

      .jomelai-chat-chart-bar {
        height: 13px;
        border-radius: 999px;
        background: linear-gradient(90deg, #0f2f57, #2f80ed);
        min-width: 3px;
      }

      .jomelai-chat-chart-value {
        text-align: right;
        font-weight: 900;
        color: #0f2f57;
      }

      .jomelai-chat-data-note {
        margin-top: 8px;
        font-size: 11px;
        color: #64748b;
      }

      @media (max-width: 760px) {
        .jomelai-chat-chart-row {
          grid-template-columns: 1fr;
          gap: 5px;
        }

        .jomelai-chat-chart-value {
          text-align: left;
        }

        .jomelai-chat-table {
          font-size: 11px;
        }

        .jomelai-chat-table th,
        .jomelai-chat-table td {
          padding: 8px;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function visible(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function findChatPanel() {
    const cached = document.querySelector('.jomelai-chat-panel-detected');
    if (cached && visible(cached)) return cached;

    const all = Array.from(document.querySelectorAll('aside, section, div'));
    const candidates = [];

    for (const el of all) {
      const txt = (el.innerText || '').trim();
      if (!txt.includes('Asistente JoMelAI')) continue;

      const r = el.getBoundingClientRect();
      if (r.width < 260 || r.height < 300) continue;

      candidates.push({ el, area: r.width * r.height, right: window.innerWidth - r.right });
    }

    candidates.sort((a, b) => {
      const ar = a.el.getBoundingClientRect();
      const br = b.el.getBoundingClientRect();

      const aRightScore = ar.left > window.innerWidth * 0.45 ? 1 : 0;
      const bRightScore = br.left > window.innerWidth * 0.45 ? 1 : 0;

      if (aRightScore !== bRightScore) return bRightScore - aRightScore;
      return b.area - a.area;
    });

    const panel = candidates.length ? candidates[0].el : null;

    if (panel) {
      panel.classList.add('jomelai-chat-panel-detected');
      rememberPanelStyle(panel);
      applyWideState(panel);
    }

    return panel;
  }

  function rememberPanelStyle(panel) {
    if (!panel || originalPanelStyles.has(panel)) return;

    originalPanelStyles.set(panel, {
      width: panel.style.width || '',
      minWidth: panel.style.minWidth || '',
      maxWidth: panel.style.maxWidth || '',
      right: panel.style.right || '',
      zIndex: panel.style.zIndex || ''
    });
  }

  function applyWideState(panel) {
    if (!panel) return;
    rememberPanelStyle(panel);

    if (wide) {
      const target = Math.min(920, Math.max(560, Math.floor(window.innerWidth * 0.52)));
      panel.style.width = target + 'px';
      panel.style.maxWidth = 'calc(100vw - 24px)';
      panel.style.minWidth = Math.min(420, target) + 'px';
      panel.style.right = '12px';
      panel.style.zIndex = '9999';
      document.body.classList.add('jomelai-chat-wide-active');
    } else {
      const old = originalPanelStyles.get(panel);
      if (old) {
        panel.style.width = old.width;
        panel.style.minWidth = old.minWidth;
        panel.style.maxWidth = old.maxWidth;
        panel.style.right = old.right;
        panel.style.zIndex = old.zIndex;
      }
      document.body.classList.remove('jomelai-chat-wide-active');
    }

    updateWideButton();
  }

  function findHeader(panel) {
    if (!panel) return null;

    const nodes = Array.from(panel.querySelectorAll('div, header, section'));
    const header = nodes.find(el => {
      const txt = (el.innerText || '').trim();
      const r = el.getBoundingClientRect();
      return txt.includes('Asistente JoMelAI') && r.height > 30 && r.height < 90;
    });

    return header || panel.firstElementChild || panel;
  }

  function ensureWideButton() {
    addStyles();

    const panel = findChatPanel();
    if (!panel) return;

    let btn = panel.querySelector('.jomelai-chat-wide-btn');
    if (btn) return;

    const header = findHeader(panel);

    btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'jomelai-chat-wide-btn';
    btn.addEventListener('click', function () {
      wide = !wide;
      localStorage.setItem('jomelai_chat_wide', wide ? '1' : '0');
      applyWideState(panel);
    });

    if (header) {
      header.appendChild(btn);
    } else {
      panel.insertBefore(btn, panel.firstChild);
    }

    updateWideButton();
  }

  function updateWideButton() {
    const btn = document.querySelector('.jomelai-chat-wide-btn');
    if (!btn) return;
    btn.textContent = wide ? 'Reducir chat' : 'Ampliar chat';
    btn.title = wide ? 'Volver al ancho normal' : 'Ampliar ancho del chat';
  }

  function getChatMount() {
    const panel = findChatPanel();
    if (!panel) return null;

    const selectors = [
      '.chat-messages',
      '.messages',
      '.conversation',
      '.chat-body',
      '.ai-chat-body',
      '#chatMessages',
      '#chat-messages',
      '#messages',
      '#conversation'
    ];

    for (const selector of selectors) {
      const node = panel.querySelector(selector);
      if (node && visible(node)) return node;
    }

    const scrollables = Array.from(panel.querySelectorAll('div, section'))
      .filter(el => {
        const r = el.getBoundingClientRect();
        const style = getComputedStyle(el);
        const isScroll = /(auto|scroll)/.test(style.overflowY + style.overflow);
        return r.height > 180 && r.width > 250 && isScroll;
      })
      .sort((a, b) => b.getBoundingClientRect().height - a.getBoundingClientRect().height);

    return scrollables[0] || panel;
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

    let html = '<div class="jomelai-chat-table-wrap">';
    html += '<table class="jomelai-chat-table">';
    html += '<thead><tr>' + headers.map(h => `<th>${esc(h)}</th>`).join('') + '</tr></thead>';
    html += '<tbody>';

    rows.slice(0, 50).forEach(row => {
      html += '<tr>' + headers.map(h => `<td>${esc(row[h])}</td>`).join('') + '</tr>';
    });

    html += '</tbody></table></div>';

    if (rows.length > 50) {
      html += `<div class="jomelai-chat-data-note">Mostrando 50 de ${rows.length} registros.</div>`;
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

    let html = '<div class="jomelai-chat-chart">';
    html += `<div class="jomelai-chat-data-title">Grafico <span class="jomelai-chat-data-badge">${esc(fields.y)} por ${esc(fields.x)}</span></div>`;

    data.forEach(item => {
      const pct = Math.max(2, Math.round((item.value / max) * 100));
      html += `
        <div class="jomelai-chat-chart-row">
          <div class="jomelai-chat-chart-label" title="${esc(item.label)}">${esc(item.label)}</div>
          <div class="jomelai-chat-chart-track">
            <div class="jomelai-chat-chart-bar" style="width:${pct}%"></div>
          </div>
          <div class="jomelai-chat-chart-value">${esc(item.value)}</div>
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
    ensureWideButton();
    removeExternalCards();

    const title =
      (payload.route && payload.route.intent && payload.route.intent.title) ||
      payload.title ||
      (hasChart ? 'Reporte grafico' : 'Datos encontrados');

    const badge = payload.mode || (payload.route && payload.route.route) || 'resultado';

    const card = document.createElement('div');
    card.className = 'jomelai-chat-data-card';
    card.innerHTML = `
      <div class="jomelai-chat-data-title">
        <span>${esc(title)}</span>
        <span class="jomelai-chat-data-badge">${esc(badge)}</span>
      </div>
      ${chartHtml(rows, payload)}
      ${tableHtml(rows)}
    `;

    const mount = getChatMount();
    if (mount) {
      mount.appendChild(card);
    }

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

  function cleanupMarkdownInChat() {
    const panel = findChatPanel();
    if (!panel) return;

    addStyles();

    const candidates = Array.from(panel.querySelectorAll('div,p,span'))
      .filter(el => {
        if (el.dataset.jomelaiMarkdownCleaned === '1') return false;
        if (el.closest('.jomelai-chat-data-card')) return false;

        const txt = el.innerText || el.textContent || '';
        if (!txt.includes('|') || !txt.includes('---')) return false;

        const childHas = Array.from(el.children || []).some(ch => {
          const t = ch.innerText || ch.textContent || '';
          return t.includes('|') && t.includes('---');
        });

        return !childHas;
      })
      .sort((a, b) => (a.innerText || '').length - (b.innerText || '').length);

    candidates.forEach(el => {
      const parsed = parseMarkdownTable(el.innerText || el.textContent || '');
      if (!parsed) return;

      el.dataset.jomelaiMarkdownCleaned = '1';
      el.innerHTML = `
        <div style="font-weight:900;margin-bottom:10px;color:#fff">${esc(parsed.title)}</div>
        ${tableHtml(parsed.rows)}
      `;
    });

    Array.from(panel.querySelectorAll('div,p,span')).forEach(el => {
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

  function removeExternalCards() {
    const panel = findChatPanel();
    if (!panel) return;

    document.querySelectorAll('.jomelai-pretty-card, .jomelai-result-card')
      .forEach(card => {
        if (!panel.contains(card)) {
          card.remove();
        }
      });
  }

  function installFetchTap() {
    if (window.__JOMELAI_PANEL_FETCH_TAP__) return;
    window.__JOMELAI_PANEL_FETCH_TAP__ = true;

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
    const run = () => {
      ensureWideButton();
      cleanupMarkdownInChat();
      removeExternalCards();
    };

    const obs = new MutationObserver(() => {
      clearTimeout(window.__jomelaiPanelTimer);
      window.__jomelaiPanelTimer = setTimeout(run, 150);
    });

    if (document.body) {
      obs.observe(document.body, { childList: true, subtree: true, characterData: true });
      run();
    }
  }

  window.JoMelAiChatPanelRenderer = {
    renderPayload,
    cleanupMarkdownInChat,
    findChatPanel,
    toggleWide: function () {
      wide = !wide;
      localStorage.setItem('jomelai_chat_wide', wide ? '1' : '0');
      applyWideState(findChatPanel());
    }
  };

  addStyles();
  installFetchTap();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', installObserver);
  } else {
    installObserver();
  }

  window.addEventListener('resize', function () {
    applyWideState(findChatPanel());
  });

  console.info('[JoMelAi] Chat panel renderer activo');
})();
JS

echo
echo "== 1) Installing renderer on host files =="

for dir in frontend frontend/public public sync_docker_to_host_20260608_125609/docker_frontend; do
  if [ -d "$dir" ]; then
    cp "$RENDERER" "$dir/chat-panel-renderer-final.js"
    cp "$RENDERER" "$dir/chat-lateral-pretty-renderer.js"
    echo "Installed renderer in $dir"
  fi
done

echo
echo "== 2) Injecting renderer into index.html =="

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
      sed -i '/chat-panel-renderer-final.js/d' "$html" || true

      sed -i 's#</body>#  <script src="/chat-panel-renderer-final.js?v=20260608panel"></script>\n</body>#' "$html"
      echo "Injected in $html"
    fi
  done
fi

echo
echo "== 3) Copying renderer into running frontend container =="

if docker ps --format '{{.Names}}' | grep -q '^jomelai_frontend$'; then
  for target in /usr/share/nginx/html /var/www/html /app /usr/src/app; do
    if docker exec jomelai_frontend sh -lc "[ -d '$target' ]" >/dev/null 2>&1; then
      docker cp "$RENDERER" "jomelai_frontend:$target/chat-panel-renderer-final.js"
      docker cp "$RENDERER" "jomelai_frontend:$target/chat-lateral-pretty-renderer.js"

      if docker exec jomelai_frontend sh -lc "[ -f '$target/index.html' ]" >/dev/null 2>&1; then
        docker exec jomelai_frontend sh -lc "cp '$target/index.html' '$target/index.html.bak.panelrenderer' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-v2-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-lateral-pretty-renderer.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i '/chat-panel-renderer-final.js/d' '$target/index.html' || true"
        docker exec jomelai_frontend sh -lc "sed -i 's#</body>#  <script src=\"/chat-panel-renderer-final.js?v=20260608panel\"></script>\\n</body>#' '$target/index.html'"
      fi

      echo "Installed inside container at $target"
    fi
  done

  docker exec jomelai_frontend nginx -s reload 2>/dev/null || true
fi

echo
echo "== 4) Verifying renderer served by frontend =="

curl -sS -m 10 http://localhost:3000/chat-panel-renderer-final.js | head -c 300 || true
echo

echo
echo "== 5) Verifying public ask-stream still works =="

curl -sS -N -m 30 -X POST http://localhost:3000/api/chat-lateral/ask-stream \
  -H "Content-Type: application/json" \
  -d '{"question":"que carreras tienes?","table":"silabos","collection":"silabos","n_results":2,"allow_ollama":false}' \
  | head -c 2500 || true

echo
echo
echo "== 6) Final status =="
docker compose ps

echo
echo "=================================================="
echo " DONE"
echo "=================================================="
echo "Backup: $BACKUP_DIR"
echo
echo "Open:"
echo "  http://18.191.127.254:3000"
echo
echo "Hard refresh:"
echo "  Ctrl + Shift + R"
echo
echo "Now you should see:"
echo "  - table inside the right chat panel"
echo "  - no table in dashboard main area"
echo "  - button Ampliar chat / Reducir chat"
