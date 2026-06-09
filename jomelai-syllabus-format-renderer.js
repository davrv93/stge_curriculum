(function () {
  if (window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__) return;
  window.__JOMELAI_SYLLABUS_FORMAT_RENDERER__ = true;

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function arr(v) {
    if (Array.isArray(v)) return v;
    if (v == null || v === '') return [];
    return [v];
  }

  function tryJson(text) {
    if (!text || typeof text !== 'string') return null;

    try {
      const direct = JSON.parse(text);
      if (direct && typeof direct === 'object') return direct;
    } catch (e) {}

    const a = text.indexOf('{');
    const b = text.lastIndexOf('}');
    if (a >= 0 && b > a) {
      try {
        const obj = JSON.parse(text.slice(a, b + 1));
        if (obj && typeof obj === 'object') return obj;
      } catch (e) {}
    }

    return null;
  }

  function getSyllabus(payload) {
    if (!payload || typeof payload !== 'object') return null;

    if (payload.syllabus && typeof payload.syllabus === 'object') {
      return payload.syllabus;
    }

    return (
      tryJson(payload.raw_response) ||
      tryJson(payload.response) ||
      tryJson(payload.answer) ||
      null
    );
  }

  function injectStyles() {
    if (document.getElementById('jomelai-syllabus-format-style')) return;

    const style = document.createElement('style');
    style.id = 'jomelai-syllabus-format-style';
    style.textContent = `
      .jomelai-syllabus-card {
        margin: 18px 0;
        padding: 0;
        background: #ffffff;
        border: 1px solid rgba(15, 23, 42, .12);
        border-radius: 18px;
        box-shadow: 0 16px 45px rgba(15, 23, 42, .10);
        overflow: hidden;
        font-family: Inter, Roboto, Arial, sans-serif;
        color: #1f2937;
      }

      .jomelai-syllabus-header {
        padding: 18px 20px;
        background: linear-gradient(135deg, #0f2f57, #174a7c);
        color: #ffffff;
      }

      .jomelai-syllabus-header h2 {
        margin: 0;
        font-size: 20px;
        line-height: 1.2;
        font-weight: 850;
      }

      .jomelai-syllabus-header p {
        margin: 6px 0 0;
        font-size: 13px;
        opacity: .88;
      }

      .jomelai-syllabus-body {
        padding: 18px 20px 22px;
      }

      .jomelai-syllabus-section {
        margin-top: 18px;
        padding-top: 14px;
        border-top: 1px solid #e5e7eb;
      }

      .jomelai-syllabus-section:first-child {
        margin-top: 0;
        padding-top: 0;
        border-top: 0;
      }

      .jomelai-syllabus-section h3 {
        margin: 0 0 10px;
        font-size: 15px;
        color: #0f2f57;
        font-weight: 850;
      }

      .jomelai-syllabus-section h4 {
        margin: 14px 0 8px;
        font-size: 13px;
        color: #174a7c;
        font-weight: 850;
      }

      .jomelai-syllabus-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 10px;
      }

      .jomelai-syllabus-field {
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        padding: 10px 12px;
        background: #f8fafc;
      }

      .jomelai-syllabus-label {
        font-size: 11px;
        color: #64748b;
        font-weight: 750;
        text-transform: uppercase;
        letter-spacing: .04em;
      }

      .jomelai-syllabus-value {
        margin-top: 4px;
        color: #1f2937;
        font-size: 13px;
        font-weight: 650;
      }

      .jomelai-syllabus-p {
        margin: 0;
        font-size: 13px;
        line-height: 1.65;
        color: #334155;
      }

      .jomelai-syllabus-list {
        margin: 0;
        padding-left: 18px;
        color: #334155;
        font-size: 13px;
        line-height: 1.55;
      }

      .jomelai-unit-card {
        margin-top: 12px;
        padding: 14px;
        border: 1px solid #e5e7eb;
        border-radius: 14px;
        background: #fbfdff;
      }

      .jomelai-unit-title {
        font-size: 14px;
        font-weight: 850;
        color: #0f2f57;
        margin-bottom: 8px;
      }

      .jomelai-table-wrap {
        width: 100%;
        overflow: auto;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        margin-top: 10px;
      }

      .jomelai-syllabus-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        background: #ffffff;
      }

      .jomelai-syllabus-table th {
        background: #f8fafc;
        color: #334155;
        font-weight: 850;
        text-align: left;
        padding: 9px 10px;
        border-bottom: 1px solid #e5e7eb;
        white-space: nowrap;
      }

      .jomelai-syllabus-table td {
        padding: 8px 10px;
        border-bottom: 1px solid #eef2f7;
        vertical-align: top;
        color: #334155;
      }

      .jomelai-syllabus-actions {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: 16px;
      }

      .jomelai-syllabus-btn {
        border: 1px solid #dbe3ef;
        background: #ffffff;
        color: #0f2f57;
        border-radius: 999px;
        padding: 8px 12px;
        font-size: 12px;
        font-weight: 800;
        cursor: pointer;
      }

      .jomelai-syllabus-btn:hover {
        background: #f1f5f9;
      }

      @media (max-width: 720px) {
        .jomelai-syllabus-grid {
          grid-template-columns: 1fr;
        }

        .jomelai-syllabus-header,
        .jomelai-syllabus-body {
          padding-left: 14px;
          padding-right: 14px;
        }
      }
    `;
    document.head.appendChild(style);
  }

  function renderList(items) {
    const values = arr(items).filter(x => x != null && String(x).trim() !== '');
    if (!values.length) return '<p class="jomelai-syllabus-p">No especificado.</p>';

    return '<ol class="jomelai-syllabus-list">' +
      values.map(x => '<li>' + esc(typeof x === 'string' ? x : JSON.stringify(x)) + '</li>').join('') +
      '</ol>';
  }

  function table(headers, rows) {
    return `
      <div class="jomelai-table-wrap">
        <table class="jomelai-syllabus-table">
          <thead>
            <tr>${headers.map(h => `<th>${esc(h.label)}</th>`).join('')}</tr>
          </thead>
          <tbody>
            ${rows.map(row => `
              <tr>
                ${headers.map(h => `<td>${esc(row[h.key] == null ? '' : row[h.key])}</td>`).join('')}
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderDatos(dg) {
    dg = dg || {};

    const fields = [
      ['curso', 'Curso'],
      ['programa', 'Programa'],
      ['creditos', 'Créditos'],
      ['ciclo', 'Ciclo'],
      ['semanas', 'Semanas'],
      ['sesiones_por_semana', 'Sesiones por semana'],
      ['modalidad', 'Modalidad'],
      ['fecha_inicio', 'Fecha inicio'],
      ['fecha_fin', 'Fecha fin'],
      ['sistema_evaluacion', 'Sistema evaluación']
    ];

    return `
      <div class="jomelai-syllabus-grid">
        ${fields.map(([key, label]) => `
          <div class="jomelai-syllabus-field">
            <div class="jomelai-syllabus-label">${esc(label)}</div>
            <div class="jomelai-syllabus-value">${esc(dg[key] == null || dg[key] === '' ? 'No especificado' : dg[key])}</div>
          </div>
        `).join('')}
      </div>
    `;
  }

  function renderUnidades(unidades) {
    const list = arr(unidades);
    if (!list.length) return '<p class="jomelai-syllabus-p">No se generaron unidades.</p>';

    return list.map((u, idx) => {
      if (!u || typeof u !== 'object') return '';

      const sesiones = arr(u.sesiones);
      const sesionesTable = sesiones.length ? table(
        [
          { key: 'semana', label: 'Semana' },
          { key: 'sesion', label: 'Sesión' },
          { key: 'titulo', label: 'Título' },
          { key: 'actividad_aprendizaje', label: 'Actividad' },
          { key: 'producto', label: 'Producto' },
          { key: 'fecha_sugerida', label: 'Fecha' }
        ],
        sesiones.filter(x => x && typeof x === 'object')
      ) : '';

      return `
        <div class="jomelai-unit-card">
          <div class="jomelai-unit-title">
            Unidad ${esc(u.unidad || idx + 1)}: ${esc(u.titulo || 'Sin título')}
          </div>

          <p class="jomelai-syllabus-p"><strong>Semanas:</strong> ${esc(Array.isArray(u.semanas) ? u.semanas.join(', ') : (u.semanas || 'No especificado'))}</p>
          <p class="jomelai-syllabus-p"><strong>Resultado:</strong> ${esc(u.resultado_unidad || 'No especificado')}</p>

          <h4>Contenidos</h4>
          ${renderList(u.contenidos)}

          <h4>Sesiones</h4>
          ${sesionesTable || '<p class="jomelai-syllabus-p">No se generaron sesiones.</p>'}

          <h4>Producto de unidad</h4>
          <p class="jomelai-syllabus-p">${esc(u.producto_unidad || 'No especificado')}</p>
        </div>
      `;
    }).join('');
  }

  function renderEvaluaciones(evaluaciones) {
    const rows = arr(evaluaciones).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron evaluaciones.</p>';

    return table(
      [
        { key: 'tipo', label: 'Tipo' },
        { key: 'descripcion', label: 'Descripción' },
        { key: 'evidencia', label: 'Evidencia' },
        { key: 'semana', label: 'Semana' },
        { key: 'puntaje_vigesimal', label: 'Puntaje' },
        { key: 'fecha_sugerida', label: 'Fecha' }
      ],
      rows
    );
  }

  function renderReferencias(refs) {
    const rows = arr(refs).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron referencias.</p>';

    return table(
      [
        { key: 'autor', label: 'Autor' },
        { key: 'anio', label: 'Año' },
        { key: 'titulo', label: 'Título' },
        { key: 'fuente', label: 'Fuente' },
        { key: 'url', label: 'URL/DOI' },
        { key: 'utilidad', label: 'Utilidad' }
      ],
      rows
    );
  }

  function renderEnlaces(enlaces) {
    const rows = arr(enlaces).filter(x => x && typeof x === 'object');

    if (!rows.length) return '<p class="jomelai-syllabus-p">No se generaron enlaces.</p>';

    return table(
      [
        { key: 'titulo', label: 'Título' },
        { key: 'url', label: 'URL' },
        { key: 'uso', label: 'Uso' }
      ],
      rows
    );
  }

  function findMount() {
    const selectors = [
      '#syllabusResult',
      '#silaboResult',
      '#syllabus-output',
      '#silabo-output',
      '#generatedSyllabus',
      '#generated-syllabus',
      '.syllabus-result',
      '.silabo-result',
      '.syllabus-preview',
      '.silabo-preview',
      '.generated-syllabus',
      '[data-syllabus-output]',
      '[data-silabo-output]',
      '.page.active',
      '.tab-pane.active',
      '.content',
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

  function render(payload) {
    const syl = getSyllabus(payload);
    if (!syl) return false;

    injectStyles();

    const dg = syl.datos_generales || {};
    const course = dg.curso || syl.curso || 'Sílabo generado';
    const program = dg.programa || syl.programa || '';

    const card = document.createElement('div');
    card.className = 'jomelai-syllabus-card';
    card.dataset.jomelaiSyllabusRendered = '1';

    card.innerHTML = `
      <div class="jomelai-syllabus-header">
        <h2>${esc(course)}</h2>
        <p>${esc(program || 'Sílabo académico generado por JoMelAI')}</p>
      </div>

      <div class="jomelai-syllabus-body">
        <section class="jomelai-syllabus-section">
          <h3>I. Datos generales</h3>
          ${renderDatos(dg)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>II. Sumilla</h3>
          <p class="jomelai-syllabus-p">${esc(syl.sumilla || 'No especificado.')}</p>
        </section>

        <section class="jomelai-syllabus-section">
          <h3>III. Competencia del curso</h3>
          <p class="jomelai-syllabus-p">${esc(syl.competencia_curso || 'No especificado.')}</p>
        </section>

        <section class="jomelai-syllabus-section">
          <h3>IV. Resultados de aprendizaje</h3>
          ${renderList(syl.resultados_curso)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>V. Unidades de aprendizaje</h3>
          ${renderUnidades(syl.unidades)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VI. Evaluaciones</h3>
          ${renderEvaluaciones(syl.evaluaciones)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VII. Metodologías</h3>
          ${renderList(syl.metodologias)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>VIII. Referencias</h3>
          ${renderReferencias(syl.referencias)}
        </section>

        <section class="jomelai-syllabus-section">
          <h3>IX. Enlaces</h3>
          ${renderEnlaces(syl.enlaces)}
        </section>

        <div class="jomelai-syllabus-actions">
          <button class="jomelai-syllabus-btn" type="button" data-copy-syllabus>Copiar JSON</button>
          <button class="jomelai-syllabus-btn" type="button" data-copy-markdown>Copiar Markdown</button>
        </div>
      </div>
    `;

    const mount = findMount();

    Array.from(mount.querySelectorAll('.jomelai-syllabus-card[data-jomelai-syllabus-rendered="1"]')).forEach(x => x.remove());

    mount.appendChild(card);

    const copyJson = card.querySelector('[data-copy-syllabus]');
    if (copyJson) {
      copyJson.addEventListener('click', function () {
        navigator.clipboard && navigator.clipboard.writeText(JSON.stringify(syl, null, 2));
      });
    }

    const copyMd = card.querySelector('[data-copy-markdown]');
    if (copyMd) {
      copyMd.addEventListener('click', function () {
        const md = payload.markdown || payload.answer || '';
        navigator.clipboard && navigator.clipboard.writeText(md);
      });
    }

    try {
      card.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (e) {}

    return true;
  }

  function parseSseChunk(chunk) {
    const eventLine = chunk.split('\n').find(x => x.startsWith('event:'));
    const dataLine = chunk.split('\n').find(x => x.startsWith('data:'));

    if (!dataLine) return null;

    const event = eventLine ? eventLine.slice(6).trim() : 'message';

    try {
      return {
        event,
        data: JSON.parse(dataLine.slice(5).trim())
      };
    } catch (e) {
      return null;
    }
  }

  const oldFetch = window.fetch.bind(window);

  window.fetch = function syllabusFormatFetch(input, init) {
    const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
    const promise = oldFetch(input, init);

    if (url && url.includes('/api/assistant/generate-syllabus-stream')) {
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
                const parsed = parseSseChunk(chunk);
                if (!parsed) continue;

                if (parsed.event === 'syllabus' || parsed.event === 'final') {
                  if (parsed.data && parsed.data.render_mode === 'syllabus_formatted') {
                    render(parsed.data);
                  } else if (getSyllabus(parsed.data)) {
                    render(parsed.data);
                  }
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

  window.JoMelAiSyllabusFormatRenderer = {
    render,
    getSyllabus,
    version: 'v1'
  };

  console.info('[JoMelAi] Syllabus format renderer activo');
})();
