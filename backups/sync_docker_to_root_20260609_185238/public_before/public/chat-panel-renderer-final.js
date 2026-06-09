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
