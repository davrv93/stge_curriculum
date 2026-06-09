#!/usr/bin/env bash
set -Eeuo pipefail

cd ~/jomelai

echo "=================================================="
echo " Install Pie Override in ACTIVE frontend container"
echo "=================================================="

BACKUP_DIR="backups/pie_override_active_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

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

CONTAINER_ROOT="$(docker exec "$FRONT_CONTAINER" sh -lc '
if command -v nginx >/dev/null 2>&1; then
  nginx -T 2>/dev/null | awk "/root / {gsub(\";\", \"\", \$2); print \$2; exit}"
fi
' || true)"

if [ -z "$CONTAINER_ROOT" ]; then
  CONTAINER_ROOT="/usr/share/nginx/html"
fi

echo "CONTAINER_ROOT=$CONTAINER_ROOT"

mkdir -p public

cat > public/chat-pie-image-override.js <<'JS'
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

  function chartType(p) {
    return String(
      p.chart_type ||
      (p.route && p.route.chart_type) ||
      (p.route && p.route.intent && p.route.intent.chart_type) ||
      ''
    ).toLowerCase();
  }

  function img64(p) {
    return p.image_base64 || (p.chart && p.chart.image_base64) || '';
  }

  function mime(p) {
    return p.mime_type || (p.chart && p.chart.mime_type) || 'image/png';
  }

  function rows(p) {
    if (Array.isArray(p.rows)) return p.rows;
    if (p.chart && Array.isArray(p.chart.rows)) return p.chart.rows;
    if (p.data && Array.isArray(p.data.rows)) return p.data.rows;
    return [];
  }

  function isPie(p) {
    return p && chartType(p) === 'pie' && !!img64(p);
  }

  function mount() {
    const selectors = [
      '#chatMessages',
      '#chat-messages',
      '#messages',
      '.chat-messages',
      '.chat-body',
      '.messages',
      '.conversation',
      '.ai-chat-body',
      '.assistant-panel',
      'main'
    ];

    for (const s of selectors) {
      const nodes = Array.from(document.querySelectorAll(s)).filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      if (nodes.length) return nodes[nodes.length - 1];
    }

    return document.body;
  }

  function style() {
    if (document.getElementById('jomelai-force-pie-style')) return;

    const st = document.createElement('style');
    st.id = 'jomelai-force-pie-style';
    st.textContent = `
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
        justify-content: space-between;
        gap: 10px;
        align-items: center;
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
        text-align: center;
        overflow: auto;
      }
      .jomelai-force-pie-img {
        max-width: 100%;
        height: auto;
        border-radius: 10px;
        background: #fff;
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
    document.head.appendChild(st);
  }

  function table(data) {
    if (!data || !data.length) return '';
    const headers = Object.keys(data[0] || {});
    if (!headers.length) return '';

    return `
      <div class="jomelai-force-pie-table-wrap">
        <table class="jomelai-force-pie-table">
          <thead>
            <tr>${headers.map(h => `<th>${esc(h)}</th>`).join('')}</tr>
          </thead>
          <tbody>
            ${data.slice(0, 50).map(row => `
              <tr>${headers.map(h => `<td>${esc(row[h])}</td>`).join('')}</tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function removeBars() {
    const bars = Array.from(document.querySelectorAll('.jomelai-chart-bar'));
    for (const bar of bars) {
      const card =
        bar.closest('.jomelai-result-card') ||
        bar.closest('.assistant-message') ||
        bar.closest('.chat-message') ||
        bar.closest('.message');

      if (card && !card.classList.contains('jomelai-force-pie-card')) {
        card.remove();
      }
    }
  }

  function renderPie(p) {
    if (!isPie(p)) return;

    const key = [p.sql || '', img64(p).length, img64(p).slice(0, 40)].join('|');

    if (seen.has(key)) {
      setTimeout(removeBars, 100);
      setTimeout(removeBars, 500);
      return;
    }

    seen.add(key);
    style();

    const title =
      (p.route && p.route.intent && p.route.intent.title) ||
      p.title ||
      'Gráfico de pie';

    const card = document.createElement('div');
    card.className = 'jomelai-force-pie-card';

    card.innerHTML = `
      <div class="jomelai-force-pie-title">
        <span>${esc(title)}</span>
        <span class="jomelai-force-pie-badge">pie</span>
      </div>
      <div class="jomelai-force-pie-img-wrap">
        <img class="jomelai-force-pie-img" src="data:${esc(mime(p))};base64,${img64(p)}" alt="${esc(title)}" />
      </div>
      ${table(rows(p))}
    `;

    mount().appendChild(card);

    setTimeout(removeBars, 80);
    setTimeout(removeBars, 300);
    setTimeout(removeBars, 900);

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    } catch (e) {}
  }

  function parseFinal(chunk) {
    if (!chunk.includes('event: final')) return null;
    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));
    if (!dataLine) return null;
    try {
      return JSON.parse(dataLine.slice(5).trim());
    } catch (e) {
      return null;
    }
  }

  const oldFetch = window.fetch.bind(window);

  window.fetch = function patchedPieFetch(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    const resPromise = oldFetch(input, init);

    if (url && url.includes('/api/chat-lateral/ask-stream')) {
      resPromise.then(res => {
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
                const payload = parseFinal(chunk);
                if (payload && isPie(payload)) {
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

    return resPromise;
  };

  window.JoMelAiForcePieImage = {
    renderPie,
    removeBars,
    version: 'active-container-v2'
  };

  console.info('[JoMelAi] Force Pie Image Override activo');
})();
JS

echo
echo "== 1) Copiando override al contenedor activo =="
docker exec "$FRONT_CONTAINER" sh -lc "mkdir -p '$CONTAINER_ROOT'"
docker cp public/chat-pie-image-override.js "$FRONT_CONTAINER:$CONTAINER_ROOT/chat-pie-image-override.js"

echo
echo "== 2) Parcheando index.html activo dentro del contenedor =="
docker exec "$FRONT_CONTAINER" sh -lc "
set -e
INDEX_FILE=''
for f in '$CONTAINER_ROOT/index.html' /usr/share/nginx/html/index.html /app/dist/index.html /app/build/index.html; do
  if [ -f \"\$f\" ]; then INDEX_FILE=\"\$f\"; break; fi
done

if [ -z \"\$INDEX_FILE\" ]; then
  echo 'ERROR: no encontré index.html activo'
  find '$CONTAINER_ROOT' -maxdepth 2 -type f | head -50
  exit 1
fi

echo INDEX_FILE=\$INDEX_FILE
cp \"\$INDEX_FILE\" \"\$INDEX_FILE.bak.pieoverride.$(date +%s)\"

# Quitar override anterior
sed -i '/chat-pie-image-override.js/d' \"\$INDEX_FILE\"

# Insertar después de chat-panel-renderer-final si existe; si no, antes de body
if grep -q 'chat-panel-renderer-final' \"\$INDEX_FILE\"; then
  awk '
    {
      print \$0;
      if (\$0 ~ /chat-panel-renderer-final/ && inserted != 1) {
        print \"  <script src=\\\"/chat-pie-image-override.js?v='$(date +%s)'\\\"></script>\";
        inserted = 1;
      }
    }
  ' \"\$INDEX_FILE\" > \"\$INDEX_FILE.tmp\" && mv \"\$INDEX_FILE.tmp\" \"\$INDEX_FILE\"
else
  sed -i 's#</body>#  <script src=\"/chat-pie-image-override.js?v='$(date +%s)'\"></script>\\n</body>#' \"\$INDEX_FILE\"
fi

grep -n 'chat-panel-renderer-final\\|chat-pie-image-override' \"\$INDEX_FILE\" || true
"

echo
echo "== 3) Copiando también a públicos locales =="
for d in public frontend/public app/public web public_html; do
  if [ -d "$d" ]; then
    cp public/chat-pie-image-override.js "$d/chat-pie-image-override.js"
  fi
done

echo
echo "== 4) Recargando Nginx =="
docker exec "$FRONT_CONTAINER" sh -lc 'if command -v nginx >/dev/null 2>&1; then nginx -t && nginx -s reload; fi' || true

echo
echo "== 5) Test asset =="
curl -sS -I "http://localhost:3000/chat-pie-image-override.js?v=test" || true

echo
echo "=================================================="
echo " LISTO"
echo "=================================================="
echo "Ahora haz Ctrl+Shift+R."
echo "En consola debe aparecer:"
echo "  [JoMelAi] Force Pie Image Override activo"
