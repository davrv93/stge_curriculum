/* JOMELAI_SYLLABUS_PRETTY_V6_LAYOUT_FIX */
(function () {
  const MODEL = 'qwen2.5:0.5b';

  const STATE = window.JM_SYLLABUS_PRETTY_V6 = window.JM_SYLLABUS_PRETTY_V6 || {
    raw: '',
    meta: {},
    config: null,
    active: false,
    continuing: false
  };

  function el(id) {
    return document.getElementById(id);
  }

  function api(path) {
    return (window.API_BASE || '') + path;
  }

  function esc(v) {
    return String(v == null ? '' : v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function clean(v) {
    return String(v == null ? '' : v)
      .replace(/```json/gi, '')
      .replace(/```markdown/gi, '')
      .replace(/```/g, '')
      .replace(/FIN_DOCUMENTO/gi, '')
      .replace(/FIN_RESPUESTA/gi, '')
      .replace(/\bconectando\.\.\./gi, '')
      .replace(/\bcontinuando\.\.\./gi, '')
      .replace(/\bgenerando\.\.\./gi, '')
      .trim();
  }

  function arr(v) {
    return Array.isArray(v) ? v : [];
  }

  function toastSafe(msg, type) {
    if (typeof window.toast === 'function') window.toast(msg, type || '');
    else console.log(msg);
  }

  function injectCss() {
    if (el('jm-syllabus-pretty-v6-css')) return;

    const style = document.createElement('style');
    style.id = 'jm-syllabus-pretty-v6-css';
    style.textContent = `
      #silabo-result.jm-syl-v6-result {
        display:block !important;
        width:100% !important;
        max-width:none !important;
        margin:24px 0 0 !important;
        padding:0 !important;
        background:transparent !important;
        border:0 !important;
        box-shadow:none !important;
      }

      .jm-syl-v6-shell {
        width:100% !important;
        min-height:600px !important;
        background:#e5e7eb !important;
        border-radius:18px !important;
        padding:28px !important;
        color:#0f172a !important;
        box-sizing:border-box !important;
      }

      .jm-syl-v6-paper {
        width:100% !important;
        max-width:980px !important;
        margin:0 auto !important;
        background:#ffffff !important;
        border-radius:12px !important;
        box-shadow:0 18px 45px rgba(15,23,42,.18) !important;
        padding:42px !important;
        box-sizing:border-box !important;
        color:#0f172a !important;
        font-family:Arial,Helvetica,sans-serif !important;
        line-height:1.58 !important;
      }

      .jm-syl-v6-paper,
      .jm-syl-v6-paper * {
        color:#0f172a !important;
        text-shadow:none !important;
        opacity:1 !important;
        box-sizing:border-box !important;
      }

      .jm-syl-v6-paper h1,
      .jm-syl-v6-paper h2,
      .jm-syl-v6-paper h3,
      .jm-syl-v6-paper h4,
      .jm-syl-v6-paper strong,
      .jm-syl-v6-paper b {
        color:#020617 !important;
        font-weight:900 !important;
      }

      .jm-syl-v6-paper h2 {
        font-size:28px !important;
        margin:0 0 10px !important;
      }

      .jm-syl-v6-paper h3 {
        color:#1e3a8a !important;
        font-size:18px !important;
        margin:22px 0 10px !important;
      }

      .jm-syl-v6-paper h4 {
        color:#1d4ed8 !important;
        font-size:15px !important;
        margin:14px 0 8px !important;
      }

      .jm-syl-v6-toolbar {
        display:flex !important;
        justify-content:space-between !important;
        align-items:flex-start !important;
        gap:12px !important;
        flex-wrap:wrap !important;
        margin-bottom:18px !important;
      }

      .jm-syl-v6-toolbar-title h3 {
        margin:0 !important;
        color:#020617 !important;
        font-size:17px !important;
      }

      .jm-syl-v6-toolbar-title p {
        margin:4px 0 0 !important;
        color:#64748b !important;
        font-size:12px !important;
      }

      .jm-syl-v6-actions-top {
        display:flex !important;
        gap:8px !important;
        flex-wrap:wrap !important;
      }

      .jm-syl-v6-btn {
        display:inline-flex !important;
        align-items:center !important;
        justify-content:center !important;
        gap:8px !important;
        padding:8px 11px !important;
        border-radius:9px !important;
        background:#f8fafc !important;
        border:1px solid #cbd5e1 !important;
        color:#1e293b !important;
        font-weight:800 !important;
        font-size:12px !important;
        cursor:pointer !important;
      }

      .jm-syl-v6-btn-orange {
        background:#f97316 !important;
        color:#ffffff !important;
        border-color:#fb923c !important;
        box-shadow:0 8px 20px rgba(249,115,22,.20) !important;
      }

      .jm-syl-v6-btn:disabled {
        opacity:.55 !important;
        cursor:not-allowed !important;
      }

      .jm-syl-v6-title {
        border-bottom:3px solid #7c3aed !important;
        padding-bottom:14px !important;
        margin-bottom:18px !important;
      }

      .jm-syl-v6-title small {
        display:block !important;
        color:#64748b !important;
        text-transform:uppercase !important;
        letter-spacing:.14em !important;
        font-size:11px !important;
        margin-bottom:6px !important;
      }

      .jm-syl-v6-meta {
        color:#475569 !important;
        margin-top:8px !important;
        font-size:14px !important;
      }

      .jm-syl-v6-chip {
        display:inline-flex !important;
        align-items:center !important;
        gap:5px !important;
        padding:4px 8px !important;
        border-radius:999px !important;
        background:#eef2ff !important;
        border:1px solid #c7d2fe !important;
        color:#3730a3 !important;
        font-size:11px !important;
        font-weight:900 !important;
        margin:2px !important;
      }

      #silabo-html {
        min-height:520px !important;
        outline:none !important;
        background:#ffffff !important;
        color:#0f172a !important;
        width:100% !important;
      }

      #silabo-html[contenteditable="true"]:focus {
        box-shadow:0 0 0 3px rgba(124,58,237,.16) !important;
        border-radius:8px !important;
      }

      #silabo-html table {
        width:100% !important;
        border-collapse:collapse !important;
        margin:12px 0 !important;
        font-size:13px !important;
      }

      #silabo-html th,
      #silabo-html td {
        border:1px solid #e5e7eb !important;
        padding:8px !important;
        vertical-align:top !important;
      }

      #silabo-html th {
        width:34% !important;
        background:#f8fafc !important;
        color:#1e3a8a !important;
        font-weight:900 !important;
      }

      #silabo-html td {
        background:#ffffff !important;
        color:#111827 !important;
      }

      .jm-syl-v6-unit {
        border:1px solid #dbeafe !important;
        background:#f8fbff !important;
        border-radius:12px !important;
        padding:14px !important;
        margin:12px 0 !important;
      }

      .jm-syl-v6-session {
        border-left:4px solid #7c3aed !important;
        background:#faf5ff !important;
        border-radius:8px !important;
        padding:10px 12px !important;
        margin:8px 0 !important;
      }

      .jm-syl-v6-eval {
        border-left:4px solid #f97316 !important;
        background:#fff7ed !important;
        border-radius:8px !important;
        padding:10px 12px !important;
        margin:8px 0 !important;
      }

      .jm-syl-v6-notice {
        margin-top:18px !important;
        padding:12px 14px !important;
        border-radius:10px !important;
        font-size:13px !important;
        font-weight:700 !important;
        line-height:1.45 !important;
      }

      .jm-syl-v6-notice-ok {
        background:#ecfdf5 !important;
        border:1px solid #bbf7d0 !important;
        color:#166534 !important;
      }

      .jm-syl-v6-notice-warn {
        background:#fff7ed !important;
        border:1px solid #fed7aa !important;
        color:#9a3412 !important;
      }

      .jm-syl-v6-notice-busy {
        background:#eff6ff !important;
        border:1px solid #bfdbfe !important;
        color:#1d4ed8 !important;
      }

      .jm-syl-v6-bottom-actions {
        display:flex !important;
        align-items:center !important;
        gap:10px !important;
        flex-wrap:wrap !important;
        margin-top:12px !important;
      }

      .jm-syl-v6-loading {
        min-height:300px !important;
        display:flex !important;
        align-items:center !important;
        justify-content:center !important;
        flex-direction:column !important;
        gap:12px !important;
        color:#475569 !important;
        text-align:center !important;
      }

      .jm-syl-v6-spinner {
        width:36px !important;
        height:36px !important;
        border-radius:50% !important;
        border:4px solid #e5e7eb !important;
        border-top-color:#7c3aed !important;
        animation:jmSylSpin .85s linear infinite !important;
      }

      @keyframes jmSylSpin {
        to { transform:rotate(360deg); }
      }

      @media (max-width: 900px) {
        .jm-syl-v6-shell {
          padding:14px !important;
        }

        .jm-syl-v6-paper {
          padding:24px !important;
        }
      }

      @media print {
        body * { visibility:hidden !important; }
        .jm-syl-v6-shell, .jm-syl-v6-shell * { visibility:visible !important; }
        .jm-syl-v6-shell {
          position:absolute !important;
          left:0 !important;
          top:0 !important;
          width:100% !important;
          padding:0 !important;
          background:white !important;
        }
        .jm-syl-v6-paper {
          max-width:none !important;
          box-shadow:none !important;
          border-radius:0 !important;
        }
        .jm-syl-v6-toolbar,
        .jm-syl-v6-notice,
        .jm-syl-v6-bottom-actions {
          display:none !important;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function chips(config, label) {
    config = config || {};

    let html = `
      <span class="jm-syl-v6-chip">🤖 ${esc(config.model || MODEL)}</span>
      <span class="jm-syl-v6-chip">ctx ${esc(config.num_ctx || 2048)}</span>
      <span class="jm-syl-v6-chip">salida ${esc(config.num_predict || config.max_tokens || '-')} tokens</span>
      <span class="jm-syl-v6-chip">temp ${esc(config.temperature ?? '-')}</span>
    `;

    if (label) html += `<span class="jm-syl-v6-chip">${esc(label)}</span>`;

    return html;
  }

  function parseSseEvent(raw) {
    const lines = raw.split('\n');
    let event = 'message';
    let data = '';

    for (const line of lines) {
      if (line.startsWith('event:')) event = line.replace('event:', '').trim();
      if (line.startsWith('data:')) data += line.replace('data:', '').trim();
    }

    try {
      return { event, data: JSON.parse(data) };
    } catch (e) {
      return null;
    }
  }

  async function streamPost(endpoint, payload, handlers) {
    const res = await fetch(api(endpoint), {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
      body: JSON.stringify(payload || {})
    });

    if (!res.ok || !res.body) {
      throw new Error(endpoint + ' HTTP ' + res.status);
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';

    while (true) {
      const read = await reader.read();
      if (read.done) break;

      buffer += decoder.decode(read.value, { stream: true });

      const events = buffer.split('\n\n');
      buffer = events.pop() || '';

      for (const ev of events) {
        const parsed = parseSseEvent(ev);
        if (!parsed) continue;

        if (handlers && typeof handlers[parsed.event] === 'function') {
          handlers[parsed.event](parsed.data || {});
        }
      }
    }
  }

  function tryJson(raw) {
    const c = clean(raw);
    const fenced = c.match(/```json\s*([\s\S]*?)```/i);
    let txt = fenced ? fenced[1] : c;

    const first = txt.indexOf('{');
    const last = txt.lastIndexOf('}');

    if (first >= 0 && last > first) {
      txt = txt.slice(first, last + 1);
    }

    try {
      return JSON.parse(txt);
    } catch (e) {
      return null;
    }
  }

  function list(items) {
    return arr(items).length
      ? `<ul>${arr(items).map(x => `<li>${esc(typeof x === 'string' ? x : JSON.stringify(x))}</li>`).join('')}</ul>`
      : '<p>Por completar.</p>';
  }

  function syllabusLooksComplete(data) {
    return !!(
      data &&
      data.sumilla &&
      data.competencia_curso &&
      arr(data.resultados_curso).length >= 3 &&
      arr(data.unidades).length >= 3 &&
      arr(data.evaluaciones).length >= 2 &&
      arr(data.referencias).length >= 3
    );
  }

  function getMeta() {
    return {
      course: el('s-course') ? el('s-course').value.trim() : '',
      program: el('s-program') ? el('s-program').value.trim() : '',
      credits: el('s-credits') ? el('s-credits').value.trim() : '',
      cycle: el('s-cycle') ? el('s-cycle').value.trim() : '',
      weeks: el('s-weeks') ? el('s-weeks').value.trim() : '16',
      modality: el('s-modal') ? el('s-modal').value.trim() : 'Presencial',
      competency: el('s-competency') ? el('s-competency').value.trim() : '',
      graduate_profile: el('s-profile') ? el('s-profile').value.trim() : '',
      start_date: el('s-start-date') ? el('s-start-date').value.trim() : '',
      sessions_per_week: el('s-sessions-per-week') ? el('s-sessions-per-week').value.trim() : '1'
    };
  }

  function ensureLayout(meta) {
    injectCss();

    const host = el('silabo-result');
    if (!host) return;

    host.className = 'jm-syl-v6-result';
    host.style.display = 'block';

    host.innerHTML = `
      <div class="jm-syl-v6-shell">
        <div class="jm-syl-v6-paper">
          <div class="jm-syl-v6-toolbar">
            <div class="jm-syl-v6-toolbar-title">
              <h3>✅ Sílabo generado</h3>
              <p>Editable en vivo · propuesta preliminar</p>
            </div>
            <div class="jm-syl-v6-actions-top">
              <button class="jm-syl-v6-btn" onclick="window.copySilabo()">📋 Copiar texto</button>
              <button class="jm-syl-v6-btn" onclick="window.saveSilaboDraft && window.saveSilaboDraft()">💾 Guardar borrador</button>
              <button class="jm-syl-v6-btn jm-syl-v6-btn-orange" onclick="window.downloadSilaboPdf && window.downloadSilaboPdf()">📄 Descargar PDF</button>
            </div>
          </div>

          <div class="jm-syl-v6-title">
            <small>JoMelAi · Sílabo preliminar</small>
            <h2>Sílabo preliminar: ${esc(meta.course || 'Curso')}</h2>
            <div class="jm-syl-v6-meta">${esc(meta.program || 'Programa')} · ${esc(meta.credits || '-')} créditos · Ciclo ${esc(meta.cycle || '-')}</div>
          </div>

          <div id="jm-syllabus-config" style="margin-bottom:16px"></div>

          <div id="silabo-html" contenteditable="true" spellcheck="true">
            <div class="jm-syl-v6-loading">
              <div class="jm-syl-v6-spinner"></div>
              <strong>Generando estructura completa del sílabo...</strong>
              <span>JoMelAi está preparando sumilla, competencia, resultados, unidades, sesiones, evaluaciones y referencias.</span>
            </div>
          </div>

          <textarea id="silabo-text" style="display:none"></textarea>

          <div id="jm-syllabus-notice" class="jm-syl-v6-notice jm-syl-v6-notice-busy">
            Generación en proceso. El sílabo se irá estructurando automáticamente.
          </div>

          <div id="jm-syllabus-actions" class="jm-syl-v6-bottom-actions">
            <button class="jm-syl-v6-btn jm-syl-v6-btn-orange" disabled>Generando...</button>
          </div>
        </div>
      </div>
    `;
  }

  function renderLoading(raw, meta, config, label) {
    const cfg = el('jm-syllabus-config');
    const text = el('silabo-text');

    if (cfg) cfg.innerHTML = chips(config || STATE.config || {}, label || 'generando...');
    if (text) text.value = raw;

    STATE.raw = raw;
    STATE.meta = meta;
    if (config) STATE.config = config;
  }

  function renderStructured(data, meta, config, label) {
    const html = el('silabo-html');
    const text = el('silabo-text');
    const cfg = el('jm-syllabus-config');

    if (!html) return;

    const dg = data.datos_generales || {};
    const unidades = arr(data.unidades);
    const evaluaciones = arr(data.evaluaciones);

    if (cfg) cfg.innerHTML = chips(config || STATE.config || {}, label || null);
    if (text) text.value = STATE.raw || '';

    html.setAttribute('contenteditable', 'true');
    html.setAttribute('spellcheck', 'true');

    html.innerHTML = `
      <h2>Sílabo preliminar: ${esc(dg.curso || meta.course || 'Curso')}</h2>

      <h3>1. Datos generales</h3>
      <table>
        <tbody>
          <tr><th>Curso</th><td>${esc(dg.curso || meta.course || '')}</td></tr>
          <tr><th>Programa</th><td>${esc(dg.programa || meta.program || '')}</td></tr>
          <tr><th>Créditos</th><td>${esc(dg.creditos || meta.credits || '')}</td></tr>
          <tr><th>Ciclo</th><td>${esc(dg.ciclo || meta.cycle || '')}</td></tr>
          <tr><th>Semanas</th><td>${esc(dg.semanas || meta.weeks || '16')}</td></tr>
          <tr><th>Sesiones por semana</th><td>${esc(dg.sesiones_por_semana || meta.sessions_per_week || '1')}</td></tr>
          <tr><th>Modalidad</th><td>${esc(dg.modalidad || meta.modality || 'Presencial')}</td></tr>
          <tr><th>Fecha inicio</th><td>${esc(dg.fecha_inicio || meta.start_date || 'Sugerida')}</td></tr>
          <tr><th>Fecha fin</th><td>${esc(dg.fecha_fin || 'Sugerida')}</td></tr>
          <tr><th>Sistema de evaluación</th><td>${esc(dg.sistema_evaluacion || 'Sistema numérico vigesimal: 0 a 20')}</td></tr>
        </tbody>
      </table>

      <h3>2. Sumilla</h3>
      <p>${esc(data.sumilla || 'Por completar.')}</p>

      <h3>3. Competencia del curso</h3>
      <p>${esc(data.competencia_curso || meta.competency || 'Por completar.')}</p>

      <h3>4. Resultados de aprendizaje de la asignatura</h3>
      ${list(data.resultados_curso)}

      <h3>5. Unidades, resultados de unidad y sesiones</h3>
      ${unidades.length ? unidades.map((u, idx) => `
        <div class="jm-syl-v6-unit">
          <h4>Unidad ${esc(u.unidad || idx + 1)}: ${esc(u.titulo || 'Unidad')}</h4>
          <p><strong>Semanas:</strong> ${esc(arr(u.semanas).join(', ') || 'por definir')}</p>
          <p><strong>Resultado de aprendizaje de la unidad:</strong> ${esc(u.resultado_unidad || u.resultado || 'Por completar.')}</p>
          <p><strong>Contenidos:</strong></p>
          ${list(u.contenidos)}

          <h4>Sesiones</h4>
          ${arr(u.sesiones).length ? arr(u.sesiones).map(s => `
            <div class="jm-syl-v6-session">
              <p><strong>Semana ${esc(s.semana || '-')} · Sesión ${esc(s.sesion || '-')}:</strong> ${esc(s.titulo || '')}</p>
              <p><strong>Resultado de sesión:</strong> ${esc(s.resultado_sesion || '')}</p>
              <p><strong>Contenidos:</strong> ${esc(arr(s.contenidos).join('; '))}</p>
              <p><strong>Actividad:</strong> ${esc(s.actividad_aprendizaje || '')}</p>
              <p><strong>Producto:</strong> ${esc(s.producto || '')}</p>
              <p><strong>Fecha sugerida:</strong> ${esc(s.fecha_sugerida || '')}</p>
            </div>
          `).join('') : '<p>Sesiones por completar. Use “Continuar generación” si el modelo cortó la respuesta.</p>'}

          <p><strong>Producto de unidad:</strong> ${esc(u.producto_unidad || u.producto || 'Por completar.')}</p>

          ${u.evaluacion_producto_unidad ? `
            <div class="jm-syl-v6-eval">
              <p><strong>Evaluación del producto de unidad:</strong> ${esc(u.evaluacion_producto_unidad.descripcion || '')}</p>
              <p><strong>Criterios:</strong> ${esc(arr(u.evaluacion_producto_unidad.criterios).join('; '))}</p>
              <p><strong>Puntaje:</strong> ${esc(u.evaluacion_producto_unidad.puntaje_vigesimal || 20)} / 20</p>
              <p><strong>Fecha:</strong> ${esc(u.evaluacion_producto_unidad.fecha_sugerida || '')}</p>
            </div>
          ` : '<p><strong>Evaluación del producto de unidad:</strong> Por completar.</p>'}
        </div>
      `).join('') : '<p>Unidades por completar. Use “Continuar generación” si el modelo cortó la respuesta.</p>'}

      <h3>6. Evaluaciones</h3>
      ${evaluaciones.length ? evaluaciones.map(ev => `
        <div class="jm-syl-v6-eval">
          <p><strong>Tipo:</strong> ${esc(ev.tipo || '')}</p>
          <p><strong>Descripción:</strong> ${esc(ev.descripcion || '')}</p>
          <p><strong>Evidencia:</strong> ${esc(ev.evidencia || '')}</p>
          <p><strong>Criterios:</strong> ${esc(arr(ev.criterios).join('; '))}</p>
          <p><strong>Puntaje vigesimal:</strong> ${esc(ev.puntaje_vigesimal || 20)} / 20</p>
          <p><strong>Semana:</strong> ${esc(ev.semana || '')}</p>
          <p><strong>Fecha sugerida:</strong> ${esc(ev.fecha_sugerida || '')}</p>
        </div>
      `).join('') : '<p>Evaluaciones por completar.</p>'}

      <h3>7. Metodologías</h3>
      ${list(data.metodologias)}

      <h3>8. Referencias bibliográficas</h3>
      ${arr(data.referencias).length ? arr(data.referencias).map(r => `
        <p><strong>${esc(r.autor || 'Autor')}</strong> (${esc(r.anio || 's/f')}). ${esc(r.titulo || 'Referencia')}. ${esc(r.fuente || '')}. ${esc(r.url || '')}<br><em>${esc(r.utilidad || '')}</em></p>
      `).join('') : '<p>Referencias por completar.</p>'}

      <h3>9. Enlaces de apoyo</h3>
      ${arr(data.enlaces).length ? `<ul>${arr(data.enlaces).map(l => `<li><strong>${esc(l.titulo || 'Recurso')}</strong>: ${esc(l.url || '')}. ${esc(l.uso || '')}</li>`).join('')}</ul>` : '<p>Enlaces por completar.</p>'}
    `;

    updateNotice(data);
  }

  function updateNotice(data) {
    const notice = el('jm-syllabus-notice');
    const actions = el('jm-syllabus-actions');

    if (!notice || !actions) return;

    notice.className = 'jm-syl-v6-notice';

    if (STATE.active || STATE.continuing) {
      notice.classList.add('jm-syl-v6-notice-busy');
      notice.textContent = STATE.continuing
        ? 'Continuación en proceso. Se conservará el contenido actual y se agregará lo faltante.'
        : 'Generación en proceso. El sílabo se irá estructurando automáticamente.';
      actions.innerHTML = `<button class="jm-syl-v6-btn jm-syl-v6-btn-orange" disabled>Generando...</button>`;
      return;
    }

    if (syllabusLooksComplete(data)) {
      notice.classList.add('jm-syl-v6-notice-ok');
      notice.textContent = 'El sílabo contiene las secciones principales. Puede editarlo directamente en la hoja.';
    } else {
      notice.classList.add('jm-syl-v6-notice-warn');
      notice.textContent = 'El sílabo todavía parece incompleto o el modelo cortó la generación. Puede continuar sin perder lo ya generado.';
    }

    actions.innerHTML = `
      <button class="jm-syl-v6-btn jm-syl-v6-btn-orange" onclick="window.continueSilaboGeneration()">➕ Continuar generación</button>
      <button class="jm-syl-v6-btn" onclick="window.copySilabo()">📋 Copiar texto</button>
    `;
  }

  function render(raw, meta, config, label) {
    STATE.raw = raw;
    STATE.meta = meta;
    if (config) STATE.config = config;

    const data = tryJson(raw);

    if (!data) {
      renderLoading(raw, meta, config, label);
      return;
    }

    renderStructured(data, meta, config, label);
  }

  async function generateSilabo() {
    injectCss();

    const meta = getMeta();

    if (!meta.course) {
      toastSafe('El nombre del curso es obligatorio.', 'error');
      return;
    }

    const btn = el('btn-gen-silabo');

    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando sílabo completo...';
    }

    STATE.raw = '';
    STATE.meta = meta;
    STATE.active = true;
    STATE.continuing = false;
    STATE.config = null;

    ensureLayout(meta);

    if (el('silabo-result')) {
      el('silabo-result').scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    let raw = '';
    let config = null;

    try {
      await streamPost('/api/assistant/generate-syllabus-stream', {
        model: MODEL,
        course: meta.course,
        program: meta.program,
        credits: meta.credits,
        cycle: meta.cycle,
        weeks: meta.weeks,
        modality: meta.modality,
        graduate_profile: meta.graduate_profile,
        competency: meta.competency,
        start_date: meta.start_date,
        sessions_per_week: meta.sessions_per_week,
        max_tokens: 2400,
        num_ctx: 1024,
        temperature: 0.22
      }, {
        config(data) {
          config = data.tokens_config || config;
          render(raw, meta, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          render(raw, meta, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && (data.response || data.answer)) raw = data.response || data.answer;
          STATE.active = false;
          render(raw, meta, config, '✅ final');
          toastSafe('✅ Sílabo generado en formato editable.', 'success');
        }
      });
    } catch (e) {
      STATE.active = false;
      render(raw, meta, config, 'error');
      toastSafe('Error al generar sílabo: ' + e.message, 'error');
    } finally {
      STATE.active = false;
      const data = tryJson(STATE.raw);
      updateNotice(data);

      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar sílabo con JoMelAi';
      }
    }
  }

  async function continueSilabo() {
    injectCss();

    if (STATE.active || STATE.continuing) {
      toastSafe('Espere a que termine la generación actual.', 'error');
      return;
    }

    const base = clean(STATE.raw || (el('silabo-text') ? el('silabo-text').value : ''));

    if (!base) {
      toastSafe('No hay sílabo previo para continuar.', 'error');
      return;
    }

    const meta = STATE.meta && STATE.meta.course ? STATE.meta : getMeta();

    STATE.continuing = true;
    updateNotice(tryJson(base));

    let append = '';
    let config = STATE.config || null;
    const tail = base.slice(Math.max(0, base.length - 2200));

    const prompt =
      'Continúa y completa este JSON de sílabo. Devuelve únicamente el fragmento JSON faltante o las claves faltantes. ' +
      'No repitas datos_generales, sumilla ni secciones ya completas. Completa especialmente unidades, sesiones, resultado_unidad, evaluaciones y referencias si faltan. ' +
      'Mantén formato JSON coherente y cierra las llaves si quedaron abiertas.\n\n' +
      'CURSO: ' + (meta.course || '') + '\n\n' +
      'JSON YA GENERADO:\n' + base + '\n\n' +
      'ULTIMO FRAGMENTO:\n' + tail + '\n\n' +
      'CONTINUACION JSON:';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question: prompt,
        context: 'syllabus_continue',
        model: MODEL,
        max_tokens: 1200,
        num_ctx: 1024,
        n_results: 0,
        temperature: 0.12,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          render(base + append, meta, config, 'continuando...');
        },
        token(data) {
          append += data.text || '';
          render(base + append, meta, config, 'continuando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!append && data.answer) append = data.answer;
          STATE.continuing = false;
          render(base + append, meta, config, '✅ continuación final');
          toastSafe('✅ Continuación agregada.', 'success');
        }
      });
    } catch (e) {
      toastSafe('Error al continuar: ' + e.message, 'error');
    } finally {
      STATE.continuing = false;
      updateNotice(tryJson(STATE.raw));
    }
  }

  function copySilabo() {
    const pretty = el('silabo-html') ? el('silabo-html').innerText : '';
    const raw = STATE.raw || (el('silabo-text') ? el('silabo-text').value : '');
    navigator.clipboard.writeText(clean(pretty || raw)).then(() => toastSafe('✅ Sílabo copiado.', 'success'));
  }

  function install() {
    injectCss();

    window.generateSilabo = generateSilabo;
    window.generateSyllabus = generateSilabo;
    window.continueSilaboGeneration = continueSilabo;
    window.copySilabo = copySilabo;
  }

  install();
  document.addEventListener('DOMContentLoaded', install);
  setTimeout(install, 300);
  setTimeout(install, 1000);
})();
