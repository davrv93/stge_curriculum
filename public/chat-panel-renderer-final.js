(function () {
  if (window.__JOMELAI_CHAT_PANEL_RENDERER_ROBUST__) return;
  window.__JOMELAI_CHAT_PANEL_RENDERER_ROBUST__ = true;

  const rendered = new Set();
  let wide = localStorage.getItem('jomelai_chat_wide') === '1';
  const originalStyles = new WeakMap();

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function visible(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function addStyles() {
    if (document.getElementById('jomelai-chat-panel-renderer-style-robust')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-chat-panel-renderer-style-robust';
    style.textContent = `
      .jomelai-chat-panel-detected {
        transition: width .22s ease, max-width .22s ease, right .22s ease;
      }

      .jomelai-chat-wide-btn {
        border: 1px solid rgba(148, 163, 184, .32);
        background: rgba(255,255,255,.10);
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
        background: rgba(255,255,255,.16);
      }

      .jomelai-chat-data-card {
        margin: 12px 0;
        padding: 12px;
        border-radius: 16px;
        border: 1px solid rgba(148,163,184,.28);
        background: rgba(255,255,255,.97);
        color: #172033;
        box-shadow: 0 14px 34px rgba(15,23,42,.20);
        overflow: hidden;
        font-family: Inter, Roboto, Arial, sans-serif;
      }

      .jomelai-chat-data-title {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        align-items: center;
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
        background: #fff;
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

      .jomelai-chat-chart {
        margin-top: 10px;
        padding: 12px;
        border-radius: 14px;
        background: #f8fafc;
        border: 1px solid #e5e7eb;
      }

      .jomelai-chat-chart-row {
        display: grid;
        grid-template-columns: minmax(120px,220px) 1fr minmax(46px,auto);
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
        background: linear-gradient(90deg,#0f2f57,#2f80ed);
        min-width: 3px;
      }

      .jomelai-chat-chart-value {
        text-align: right;
        font-weight: 900;
        color: #0f2f57;
      }

      @media (max-width:760px) {
        .jomelai-chat-chart-row {
          grid-template-columns: 1fr;
          gap: 5px;
        }

        .jomelai-chat-chart-value {
          text-align: left;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function closestPanelFromInput() {
    const inputs = Array.from(document.querySelectorAll('textarea,input,[contenteditable="true"]'))
      .filter(el => {
        const txt = ((el.getAttribute('placeholder') || '') + ' ' + (el.innerText || '')).toLowerCase();
        const r = el.getBoundingClientRect();
        return visible(el) && r.left > window.innerWidth * 0.35 && (
          txt.includes('consulta') ||
          txt.includes('pregunta') ||
          txt.includes('escribe') ||
          txt.includes('mensaje') ||
          el.tagName === 'TEXTAREA'
        );
      });

    if (!inputs.length) return null;

    const input = inputs.sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left)[0];

    let node = input;
    let best = null;

    for (let i = 0; i < 12 && node; i++) {
      const r = node.getBoundingClientRect ? node.getBoundingClientRect() : null;
      if (r && r.width >= 280 && r.height >= 300 && r.left > window.innerWidth * 0.35) {
        best = node;
      }
      node = node.parentElement;
    }

    return best;
  }

  function closestPanelFromText() {
    const all = Array.from(document.querySelectorAll('aside,section,div'));
    const candidates = [];

    all.forEach(el => {
      if (!visible(el)) return;
      const r = el.getBoundingClientRect();
      if (r.width < 280 || r.height < 300) return;
      if (r.left < window.innerWidth * 0.35) return;

      const txt = (el.innerText || '').toLowerCase();

      let score = 0;
      if (txt.includes('asistente jomelai')) score += 100;
      if (txt.includes('escribe tu consulta')) score += 80;
      if (txt.includes('conectando')) score += 30;
      if (txt.includes('ampliar respuesta')) score += 20;
      if (r.right > window.innerWidth - 80) score += 30;
      if (getComputedStyle(el).position === 'fixed') score += 20;

      if (score > 0) candidates.push({ el, score, area: r.width * r.height });
    });

    candidates.sort((a, b) => b.score - a.score || b.area - a.area);
    return candidates.length ? candidates[0].el : null;
  }

  function rightFixedPanelFallback() {
    const all = Array.from(document.querySelectorAll('aside,section,div'));
    const candidates = [];

    all.forEach(el => {
      if (!visible(el)) return;
      const r = el.getBoundingClientRect();
      const style = getComputedStyle(el);

      if (r.width < 300 || r.width > 760) return;
      if (r.height < window.innerHeight * 0.45) return;
      if (r.left < window.innerWidth * 0.45) return;

      let score = 0;
      if (style.position === 'fixed') score += 60;
      if (style.position === 'absolute') score += 30;
      if (r.right > window.innerWidth - 40) score += 40;
      if ((el.innerText || '').toLowerCase().includes('jomelai')) score += 40;

      if (score > 0) candidates.push({ el, score, area: r.width * r.height });
    });

    candidates.sort((a, b) => b.score - a.score || b.area - a.area);
    return candidates.length ? candidates[0].el : null;
  }

  function rememberStyle(panel) {
    if (!panel || originalStyles.has(panel)) return;
    originalStyles.set(panel, {
      width: panel.style.width || '',
      minWidth: panel.style.minWidth || '',
      maxWidth: panel.style.maxWidth || '',
      right: panel.style.right || '',
      zIndex: panel.style.zIndex || ''
    });
  }

  function findChatPanel() {
    const cached = document.querySelector('.jomelai-chat-panel-detected');
    if (cached && visible(cached)) return cached;

    const panel = closestPanelFromInput() || closestPanelFromText() || rightFixedPanelFallback();

    if (panel) {
      panel.classList.add('jomelai-chat-panel-detected');
      rememberStyle(panel);
      applyWide(panel);
    }

    return panel;
  }

  function applyWide(panel) {
    if (!panel) return;
    rememberStyle(panel);

    if (wide) {
      const target = Math.min(920, Math.max(560, Math.floor(window.innerWidth * 0.52)));
      panel.style.width = target + 'px';
      panel.style.maxWidth = 'calc(100vw - 24px)';
      panel.style.minWidth = Math.min(420, target) + 'px';
      panel.style.right = '12px';
      panel.style.zIndex = '9999';
    } else {
      const old = originalStyles.get(panel);
      if (old) {
        panel.style.width = old.width;
        panel.style.minWidth = old.minWidth;
        panel.style.maxWidth = old.maxWidth;
        panel.style.right = old.right;
        panel.style.zIndex = old.zIndex;
      }
    }

    updateWideButton();
  }

  function findHeader(panel) {
    if (!panel) return null;

    const nodes = Array.from(panel.querySelectorAll('header,div,section'))
      .filter(el => {
        if (!visible(el)) return false;
        const r = el.getBoundingClientRect();
        const txt = (el.innerText || '').toLowerCase();
        return r.height >= 32 && r.height <= 100 && (txt.includes('asistente') || txt.includes('jomelai'));
      })
      .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

    return nodes[0] || panel.firstElementChild || panel;
  }

  function ensureWideButton() {
    addStyles();

    const panel = findChatPanel();
    if (!panel) return null;

    let btn = panel.querySelector('.jomelai-chat-wide-btn');
    if (btn) {
      updateWideButton();
      return btn;
    }

    btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'jomelai-chat-wide-btn';
    btn.addEventListener('click', function () {
      wide = !wide;
      localStorage.setItem('jomelai_chat_wide', wide ? '1' : '0');
      applyWide(panel);
    });

    const header = findHeader(panel);
    header.appendChild(btn);

    updateWideButton();
    return btn;
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

    const candidates = Array.from(panel.querySelectorAll('div,section'))
      .filter(el => {
        if (!visible(el)) return false;
        const r = el.getBoundingClientRect();
        const txt = (el.innerText || '').toLowerCase();
        if (r.height < 120 || r.width < 240) return false;
        if (txt.includes('escribe tu consulta')) return false;

        const style = getComputedStyle(el);
        let score = 0;
        if (/(auto|scroll)/.test(style.overflowY + style.overflow)) score += 50;
        if (txt.includes('conectando')) score += 40;
        if (txt.includes('ampliar respuesta')) score += 20;
        if (txt.includes('carreras cargadas')) score += 20;
        if (r.bottom < panel.getBoundingClientRect().bottom - 70) score += 15;

        el.dataset.jomelaiScore = String(score);
        return score > 0;
      })
      .sort((a, b) => Number(b.dataset.jomelaiScore || 0) - Number(a.dataset.jomelaiScore || 0));

    return candidates[0] || panel;
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

    let html = '<div class="jomelai-chat-table-wrap"><table class="jomelai-chat-table">';
    html += '<thead><tr>' + headers.map(h => `<th>${esc(h)}</th>`).join('') + '</tr></thead><tbody>';

    rows.slice(0, 50).forEach(row => {
      html += '<tr>' + headers.map(h => `<td>${esc(row[h])}</td>`).join('') + '</tr>';
    });

    html += '</tbody></table></div>';
    return html;
  }

  function chartHtml(rows, payload) {
    const isChart =
      payload.mode === 'duckdb_chart' ||
      payload.chart ||
      payload.chart_type ||
      (payload.route && payload.route.route === 'duckdb_chart');

    if (!isChart || !rows || !rows.length) return '';

    const route = payload.route || {};
    const intent = route.intent || {};

    let x = payload.x || intent.x;
    let y = payload.y || intent.y;

    if (!x || !y) {
      const headers = Object.keys(rows[0] || {});
      const numeric = headers.filter(h => rows.some(r => !isNaN(Number(r[h])) && r[h] !== null && r[h] !== ''));
      const text = headers.filter(h => !numeric.includes(h));
      x = x || text[0] || headers[0];
      y = y || numeric[0];
    }

    if (!x || !y) return '';

    const data = rows
      .map(row => ({
        label: String(row[x] == null ? '' : row[x]),
        value: Number(row[y])
      }))
      .filter(item => item.label && !isNaN(item.value))
      .slice(0, 20);

    if (!data.length) return '';

    const max = Math.max(...data.map(x => x.value), 1);

    let html = '<div class="jomelai-chat-chart">';
    html += `<div class="jomelai-chat-data-title">Grafico <span class="jomelai-chat-data-badge">${esc(y)} por ${esc(x)}</span></div>`;

    data.forEach(item => {
      const pct = Math.max(2, Math.round((item.value / max) * 100));
      html += `
        <div class="jomelai-chat-chart-row">
          <div class="jomelai-chat-chart-label" title="${esc(item.label)}">${esc(item.label)}</div>
          <div class="jomelai-chat-chart-track"><div class="jomelai-chat-chart-bar" style="width:${pct}%"></div></div>
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
      rows
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
    if (mount) mount.appendChild(card);

    try { card.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); } catch (e) {}
  }

  function parseMarkdownTable(text) {
    if (!text) return null;

    const normalized = text
      .replace(/\\n/g, '\n')
      .replace(/FIN_RESPUESTA/g, '')
      .trim();

    if (!normalized.includes('|') || !normalized.includes('---')) return null;

    const lines = normalized.split('\n').map(x => x.trim()).filter(Boolean);
    const headerIndex = lines.findIndex(line => line.startsWith('|') && line.endsWith('|'));

    if (headerIndex < 0 || headerIndex + 1 >= lines.length) return null;

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

    if (!rows.length) return null;

    return {
      title: lines.slice(0, headerIndex).join(' '),
      rows
    };
  }

  function cleanupMarkdownInChat() {
    const panel = findChatPanel();
    if (!panel) return;

    const nodes = Array.from(panel.querySelectorAll('div,p,span'))
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
      });

    nodes.forEach(el => {
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

    document.querySelectorAll('.jomelai-pretty-card,.jomelai-result-card')
      .forEach(card => {
        if (!panel.contains(card)) card.remove();
      });
  }

  function installFetchTap() {
    if (window.__JOMELAI_PANEL_FETCH_TAP_ROBUST__) return;
    window.__JOMELAI_PANEL_FETCH_TAP_ROBUST__ = true;

    const originalFetch = window.fetch.bind(window);

    window.fetch = function patchedFetch(input, init) {
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

      return promise;
    };
  }

  function boot() {
    addStyles();
    installFetchTap();

    const run = () => {
      ensureWideButton();
      cleanupMarkdownInChat();
      removeExternalCards();
    };

    run();

    const obs = new MutationObserver(() => {
      clearTimeout(window.__jomelaiPanelTimer);
      window.__jomelaiPanelTimer = setTimeout(run, 150);
    });

    if (document.body) {
      obs.observe(document.body, { childList: true, subtree: true, characterData: true });
    }

    setTimeout(run, 500);
    setTimeout(run, 1500);
    setTimeout(run, 3000);
  }

  window.JoMelAiChatPanelRenderer = {
    findChatPanel,
    renderPayload,
    cleanupMarkdownInChat,
    ensureWideButton,
    toggleWide: function () {
      wide = !wide;
      localStorage.setItem('jomelai_chat_wide', wide ? '1' : '0');
      applyWide(findChatPanel());
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  window.addEventListener('resize', function () {
    applyWide(findChatPanel());
  });

  console.info('[JoMelAi] Chat panel renderer ROBUST activo');
})();
