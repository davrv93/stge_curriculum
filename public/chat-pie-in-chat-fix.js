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
