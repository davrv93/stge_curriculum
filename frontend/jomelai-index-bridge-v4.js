/* JOMELAI_INDEX_BRIDGE_V4
   Compatible con el HTML actual:
   - Sílabo: generateSilabo() -> pinta en #silabo-html y guarda raw en #silabo-text
   - Recursos v2: generateResourceV2() -> pinta en #rc-result-content
   - Chat: sendAiMessage() -> streaming + continuar concatenando
*/
(function () {
  const MODEL = 'qwen2.5:0.5b';

  const ST = window.JM_BRIDGE_V4 = window.JM_BRIDGE_V4 || {
    chat: {},
    silabo: { raw: '', config: null, meta: {} },
    recurso: { raw: '', config: null, meta: {}, active: false }
  };

  function $(id) { return document.getElementById(id); }

  function apiBase() {
    return window.API_BASE || '';
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

  function norm(v) {
    return clean(v)
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9ñ\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function toastSafe(msg, type) {
    if (typeof window.toast === 'function') window.toast(msg, type || '');
    else console.log(msg);
  }

  function css() {
    if ($('jm-index-bridge-v4-css')) return;

    const style = document.createElement('style');
    style.id = 'jm-index-bridge-v4-css';
    style.textContent = `
      .jm-chip{display:inline-flex!important;align-items:center!important;gap:5px!important;padding:4px 8px!important;border-radius:999px!important;background:#eef2ff!important;border:1px solid #c7d2fe!important;color:#3730a3!important;font-size:11px!important;font-weight:900!important;margin:2px!important}
      .jm-stream-note{padding:10px 12px!important;border-radius:10px!important;background:#eff6ff!important;border:1px solid #bfdbfe!important;color:#1d4ed8!important;font-weight:800!important;margin:10px 0!important}
      .jm-stream-warn{padding:10px 12px!important;border-radius:10px!important;background:#fff7ed!important;border:1px solid #fed7aa!important;color:#9a3412!important;font-weight:800!important;margin:10px 0!important}
      .jm-continue-btn{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:7px!important;padding:8px 12px!important;border-radius:10px!important;border:1px solid #93c5fd!important;background:rgba(59,130,246,.20)!important;color:#dbeafe!important;font-weight:900!important;font-size:12px!important;cursor:pointer!important;margin-top:8px!important}
      .jm-continue-btn:disabled{opacity:.55!important;cursor:not-allowed!important}
      #silabo-html,#silabo-html *{color:#0f172a!important;text-shadow:none!important}
      #silabo-html h1,#silabo-html h2,#silabo-html h3,#silabo-html h4,#silabo-html strong{color:#020617!important;font-weight:900!important}
      #silabo-html table{width:100%!important;border-collapse:collapse!important;margin:12px 0!important;font-size:13px!important}
      #silabo-html th,#silabo-html td{border:1px solid #e5e7eb!important;padding:8px!important;vertical-align:top!important}
      #silabo-html th{background:#f8fafc!important}
      .jm-syl-unit{border:1px solid #dbeafe!important;background:#f8fbff!important;border-radius:12px!important;padding:14px!important;margin:12px 0!important}
      .jm-syl-session{border-left:4px solid #7c3aed!important;background:#faf5ff!important;border-radius:8px!important;padding:10px 12px!important;margin:8px 0!important}
      .jm-syl-eval{border-left:4px solid #f97316!important;background:#fff7ed!important;border-radius:8px!important;padding:10px 12px!important;margin:8px 0!important}
      #rc-result-content,#rc-result-content *{color:#0f172a!important;text-shadow:none!important}
      #rc-result-content h1,#rc-result-content h2,#rc-result-content h3,#rc-result-content h4,#rc-result-content strong{color:#020617!important;font-weight:900!important}
      .jm-chat-body,.jm-chat-body p,.jm-chat-body li{color:#eef2ff!important;line-height:1.58!important;font-size:13px!important}
      .jm-chat-body h2,.jm-chat-body h3,.jm-chat-body h4,.jm-chat-body strong{color:#fff!important;font-weight:900!important}
      .jm-chat-card{border:1px solid rgba(139,69,245,.24)!important;background:linear-gradient(180deg,rgba(107,33,212,.20),rgba(30,20,70,.82))!important;border-radius:16px!important;padding:14px!important}
    `;
    document.head.appendChild(style);
  }

  function md(text) {
    const safe = esc(clean(text));
    const lines = safe.split('\n');
    let html = '';
    let ul = false;
    let ol = false;

    function close() {
      if (ul) { html += '</ul>'; ul = false; }
      if (ol) { html += '</ol>'; ol = false; }
    }

    for (const line of lines) {
      const t = line.trim();

      if (!t) {
        close();
        html += '<div style="height:8px"></div>';
        continue;
      }

      if (/^#{1,4}\s+/.test(t)) {
        close();
        const level = Math.min((t.match(/^#+/) || ['##'])[0].length, 4);
        const tag = 'h' + Math.max(2, level);
        html += '<' + tag + '>' + t.replace(/^#{1,4}\s+/, '') + '</' + tag + '>';
        continue;
      }

      if (/^[-*]\s+/.test(t)) {
        if (!ul) { close(); html += '<ul>'; ul = true; }
        html += '<li>' + t.replace(/^[-*]\s+/, '') + '</li>';
        continue;
      }

      if (/^\d+\.\s+/.test(t)) {
        if (!ol) { close(); html += '<ol>'; ol = true; }
        html += '<li>' + t.replace(/^\d+\.\s+/, '') + '</li>';
        continue;
      }

      close();

      const colon = /^([A-ZÁÉÍÓÚÑ][^:]{2,80}):\s*(.*)$/.exec(t);
      if (colon && colon[2]) html += '<p><strong>' + colon[1] + ':</strong> ' + colon[2] + '</p>';
      else if (colon && !colon[2]) html += '<h3>' + colon[1] + '</h3>';
      else html += '<p>' + t + '</p>';
    }

    close();

    return html
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>');
  }

  function parseEvent(raw) {
    const lines = raw.split('\n');
    let event = 'message';
    let data = '';

    for (const line of lines) {
      if (line.startsWith('event:')) event = line.replace('event:', '').trim();
      if (line.startsWith('data:')) data += line.replace('data:', '').trim();
    }

    try { return { event, data: JSON.parse(data) }; }
    catch (e) { return null; }
  }

  async function streamPost(endpoint, payload, handlers) {
    const res = await fetch(apiBase() + endpoint, {
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
        const p = parseEvent(ev);
        if (!p) continue;
        if (handlers && typeof handlers[p.event] === 'function') handlers[p.event](p.data || {});
      }
    }
  }

  function chips(config, label) {
    config = config || {};
    let html = `
      <span class="jm-chip">🤖 ${esc(config.model || MODEL)}</span>
      <span class="jm-chip">ctx ${esc(config.num_ctx || 2048)}</span>
      <span class="jm-chip">salida ${esc(config.num_predict || config.max_tokens || '-')} tokens</span>
      <span class="jm-chip">RAG ${esc(config.n_results ?? '-')}</span>
      <span class="jm-chip">temp ${esc(config.temperature ?? '-')}</span>
    `;
    if (label) html += `<span class="jm-chip">${esc(label)}</span>`;
    return html;
  }

  function tryJson(raw) {
    const c = clean(raw);
    const fenced = c.match(/```json\s*([\s\S]*?)```/i);
    let txt = fenced ? fenced[1] : c;
    const first = txt.indexOf('{');
    const last = txt.lastIndexOf('}');
    if (first >= 0 && last > first) txt = txt.slice(first, last + 1);
    try { return JSON.parse(txt); } catch (e) { return null; }
  }

  function arr(v) { return Array.isArray(v) ? v : []; }

  function li(items) {
    return arr(items).length
      ? `<ul>${arr(items).map(x => `<li>${esc(x)}</li>`).join('')}</ul>`
      : '<p>Por completar.</p>';
  }

  function renderSilabo(raw, meta, config, label) {
    css();

    const result = $('silabo-result');
    const html = $('silabo-html');
    const text = $('silabo-text');
    const index = $('silabo-index');

    if (!result || !html) return;

    result.style.display = 'block';
    if (text) text.value = raw;

    const data = tryJson(raw);
    let body = '';

    if (!data) {
      body = `
        <div class="jm-stream-note">${chips(config || {}, label || 'generando...')}</div>
        <pre style="white-space:pre-wrap;font-family:Arial,Helvetica,sans-serif">${esc(clean(raw) || 'Generando estructura completa del sílabo...')}</pre>
      `;
    } else {
      const dg = data.datos_generales || {};
      const unidades = arr(data.unidades);
      const evaluaciones = arr(data.evaluaciones);

      body = `
        <div class="jm-stream-note">${chips(config || {}, label || 'generando...')}</div>

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
        ${li(data.resultados_curso)}

        <h3>5. Unidades, resultados de unidad y sesiones</h3>
        ${unidades.length ? unidades.map((u, idx) => `
          <div class="jm-syl-unit">
            <h4>Unidad ${esc(u.unidad || idx + 1)}: ${esc(u.titulo || 'Unidad')}</h4>
            <p><strong>Semanas:</strong> ${esc(arr(u.semanas).join(', ') || 'por definir')}</p>
            <p><strong>Resultado de aprendizaje de la unidad:</strong> ${esc(u.resultado_unidad || u.resultado || '')}</p>
            <p><strong>Contenidos:</strong></p>
            ${li(u.contenidos)}

            <h4>Sesiones</h4>
            ${arr(u.sesiones).length ? arr(u.sesiones).map(s => `
              <div class="jm-syl-session">
                <p><strong>Semana ${esc(s.semana || '-')} · Sesión ${esc(s.sesion || '-')}:</strong> ${esc(s.titulo || '')}</p>
                <p><strong>Resultado de sesión:</strong> ${esc(s.resultado_sesion || '')}</p>
                <p><strong>Contenidos:</strong> ${esc(arr(s.contenidos).join('; '))}</p>
                <p><strong>Actividad:</strong> ${esc(s.actividad_aprendizaje || '')}</p>
                <p><strong>Producto:</strong> ${esc(s.producto || '')}</p>
                <p><strong>Fecha sugerida:</strong> ${esc(s.fecha_sugerida || '')}</p>
              </div>
            `).join('') : '<p>Sesiones por completar.</p>'}

            <p><strong>Producto de unidad:</strong> ${esc(u.producto_unidad || u.producto || '')}</p>

            ${u.evaluacion_producto_unidad ? `
              <div class="jm-syl-eval">
                <p><strong>Evaluación del producto de unidad:</strong> ${esc(u.evaluacion_producto_unidad.descripcion || '')}</p>
                <p><strong>Criterios:</strong> ${esc(arr(u.evaluacion_producto_unidad.criterios).join('; '))}</p>
                <p><strong>Puntaje:</strong> ${esc(u.evaluacion_producto_unidad.puntaje_vigesimal || 20)} / 20</p>
                <p><strong>Fecha:</strong> ${esc(u.evaluacion_producto_unidad.fecha_sugerida || '')}</p>
              </div>
            ` : ''}
          </div>
        `).join('') : '<p>Unidades por completar.</p>'}

        <h3>6. Evaluaciones</h3>
        ${evaluaciones.length ? evaluaciones.map(ev => `
          <div class="jm-syl-eval">
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
        ${li(data.metodologias)}

        <h3>8. Referencias bibliográficas</h3>
        ${arr(data.referencias).length ? arr(data.referencias).map(r => `
          <p><strong>${esc(r.autor || 'Autor')}</strong> (${esc(r.anio || 's/f')}). ${esc(r.titulo || 'Referencia')}. ${esc(r.fuente || '')}. ${esc(r.url || '')}<br><em>${esc(r.utilidad || '')}</em></p>
        `).join('') : '<p>Referencias por completar.</p>'}

        <h3>9. Enlaces de apoyo</h3>
        ${arr(data.enlaces).length ? `<ul>${arr(data.enlaces).map(l => `<li><strong>${esc(l.titulo || 'Recurso')}</strong>: ${esc(l.url || '')}. ${esc(l.uso || '')}</li>`).join('')}</ul>` : '<p>Enlaces por completar.</p>'}
      `;
    }

    html.innerHTML = body;

    if (index) {
      index.innerHTML = `
        <a href="#silabo-html">Datos generales</a>
        <a href="#silabo-html">Sumilla</a>
        <a href="#silabo-html">Competencia</a>
        <a href="#silabo-html">Resultados</a>
        <a href="#silabo-html">Unidades y sesiones</a>
        <a href="#silabo-html">Evaluación</a>
        <a href="#silabo-html">Referencias</a>
      `;
    }

    ST.silabo.raw = raw;
    ST.silabo.meta = meta;
    if (config) ST.silabo.config = config;
  }

  async function generateSilaboStream() {
    css();

    const course = $('s-course') ? $('s-course').value.trim() : '';
    if (!course) {
      toastSafe('El nombre del curso es obligatorio', 'error');
      return;
    }

    const meta = {
      course,
      program: $('s-program') ? $('s-program').value : '',
      credits: $('s-credits') ? $('s-credits').value : '',
      cycle: $('s-cycle') ? $('s-cycle').value : '',
      weeks: $('s-weeks') ? $('s-weeks').value : '16',
      modality: $('s-modal') ? $('s-modal').value : 'Presencial',
      competency: $('s-competency') ? $('s-competency').value : '',
      graduate_profile: $('s-profile') ? $('s-profile').value : '',
      sessions_per_week: '1'
    };

    const btn = $('btn-gen-silabo');
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando sílabo completo...';
    }

    if ($('silabo-result')) {
      $('silabo-result').style.display = 'block';
      $('silabo-result').scrollIntoView({ behavior: 'smooth' });
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
        sessions_per_week: meta.sessions_per_week,
        max_tokens: 2400,
        num_ctx: 1024,
        temperature: 0.22
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderSilabo(raw, meta, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderSilabo(raw, meta, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && (data.response || data.answer)) raw = data.response || data.answer;
          renderSilabo(raw, meta, config, '✅ final');
          toastSafe('✅ Sílabo completo generado', 'success');
        }
      });
    } catch (e) {
      raw += '\n\nERROR: ' + e.message;
      renderSilabo(raw, meta, config, 'error');
      toastSafe('Error al generar sílabo: ' + e.message, 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar sílabo con JoMelAi';
      }
    }
  }

  function selectedResourceType() {
    const selected = document.querySelector('.rc-card.sel');
    if (selected && selected.id) return selected.id.replace('rc-card-', '');
    if (window.STATE && window.STATE.selectedResourceType) return window.STATE.selectedResourceType;
    return 'actividad';
  }

  function selectedCourseText() {
    const custom = $('rc-curso-custom');
    if (custom && custom.style.display !== 'none' && custom.value.trim()) return custom.value.trim();

    const sel = $('rc-curso');
    if (!sel) return '';

    if (sel.value && sel.value !== '__custom__') {
      const opt = sel.options[sel.selectedIndex];
      return opt ? opt.textContent.trim() : sel.value.trim();
    }

    return '';
  }

  function resourceLabel(type) {
    const map = {
      actividad: 'Actividad de Aprendizaje',
      rubrica: 'Rúbrica de Evaluación',
      sesion: 'Plan de Sesión',
      caso: 'Caso Práctico',
      secuencia: 'Secuencia Didáctica',
      lectura: 'Guía de Lectura Crítica',
      instrumento: 'Instrumento de Evaluación',
      mapa: 'Organizador Gráfico'
    };
    return map[type] || 'Recurso de Aprendizaje';
  }

  function renderResource(raw, meta, config, label) {
    css();

    const panel = $('rc-result-panel');
    const content = $('rc-result-content');
    const title = $('rc-result-title');
    const metaEl = $('rc-result-meta');

    if (!panel || !content) return;

    panel.style.display = 'block';

    if (title) title.textContent = '✅ ' + resourceLabel(meta.type);
    if (metaEl) metaEl.innerHTML = `${esc(meta.course || 'Curso')} · ${esc(meta.week || 'Semana por definir')}<br>${chips(config || ST.recurso.config || {}, label || null)}`;

    content.innerHTML = md(raw);

    ST.recurso.raw = raw;
    ST.recurso.meta = meta;
    if (config) ST.recurso.config = config;
  }

  async function generateResourceV2Stream() {
    css();

    const type = selectedResourceType();
    const course = selectedCourseText();
    const outcome = $('rc-outcome') ? $('rc-outcome').value.trim() : '';
    const week = $('rc-semana') ? $('rc-semana').value.trim() : '';
    const bloom = $('rc-bloom') ? $('rc-bloom').value.trim() : '';
    const context = $('rc-context') ? $('rc-context').value.trim() : '';

    if (!course) {
      toastSafe('Selecciona o escribe el curso/asignatura.', 'error');
      return;
    }

    if (!outcome) {
      toastSafe('Ingresa el resultado de aprendizaje esperado.', 'error');
      return;
    }

    const meta = { type, course, outcome, week, bloom, context };
    const btn = $('btn-gen-resource');

    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando recurso...';
    }

    let raw = '';
    let config = null;

    const question =
      'Genera un recurso académico completo de tipo "' + resourceLabel(type) + '".\n' +
      'Curso: ' + course + '\n' +
      'Semana o unidad: ' + (week || 'no especificada') + '\n' +
      'Resultado de aprendizaje: ' + outcome + '\n' +
      'Nivel Bloom: ' + (bloom || 'no especificado') + '\n' +
      'Contexto: ' + (context || 'universitario UPeU') + '\n\n' +
      'Debe incluir: título, propósito, resultado de aprendizaje, instrucciones para el docente, instrucciones para el estudiante, recursos necesarios, secuencia de trabajo, producto esperado, criterios de evaluación con escala vigesimal, recomendaciones de uso y referencias o recursos de apoyo. Cierra con FIN_DOCUMENTO.';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question,
        context: 'resource_v2',
        model: MODEL,
        max_tokens: 1300,
        num_ctx: 1024,
        n_results: 1,
        temperature: 0.22,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderResource(raw, meta, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderResource(raw, meta, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && data.answer) raw = data.answer;
          renderResource(raw, meta, config, '✅ final');
          toastSafe('✅ Recurso generado', 'success');
        }
      });
    } catch (e) {
      raw += '\n\nERROR: ' + e.message;
      renderResource(raw, meta, config, 'error');
      toastSafe('Error al generar recurso: ' + e.message, 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar recurso con JoMelAi';
      }
    }
  }

  function copySilaboBridge() {
    const text = ST.silabo.raw || ($('silabo-text') ? $('silabo-text').value : '') || ($('silabo-html') ? $('silabo-html').innerText : '');
    navigator.clipboard.writeText(clean(text)).then(() => toastSafe('✅ Sílabo copiado', 'success'));
  }

  function rcCopyResultBridge() {
    const text = ST.recurso.raw || ($('rc-result-content') ? $('rc-result-content').innerText : '');
    navigator.clipboard.writeText(clean(text)).then(() => toastSafe('✅ Recurso copiado', 'success'));
  }

  function rcDownloadResultBridge() {
    const content = $('rc-result-content') ? $('rc-result-content').innerHTML : md(ST.recurso.raw || '');
    const win = window.open('', '_blank');
    if (!win) return toastSafe('No se pudo abrir la ventana de descarga.', 'error');

    win.document.write(`
      <!doctype html><html><head><meta charset="utf-8"><title>Recurso JoMelAi</title>
      <style>body{font-family:Arial,Helvetica,sans-serif;background:#f1f5f9;margin:0;padding:24px;color:#0f172a}.paper{max-width:900px;margin:0 auto;background:white;padding:42px;border-radius:10px}h1,h2,h3,h4{color:#1e3a8a}p,li{line-height:1.6}@media print{body{background:#fff;padding:0}.paper{max-width:none;border-radius:0}}</style>
      </head><body><div class="paper"><h1>Recurso de aprendizaje JoMelAi</h1>${content}</div><script>window.onload=function(){window.print();}</script></body></html>
    `);
    win.document.close();
  }

  function renderChat(id, raw, config, label) {
    const body = $(id + '-body');
    const meta = $(id + '-meta');
    const actions = $(id + '-actions');
    if (!body) return;

    body.innerHTML = md(raw);
    if (meta) meta.innerHTML = chips(config || {}, label || null);

    if (actions) {
      actions.innerHTML = `<button type="button" class="jm-continue-btn" onclick="window.jmContinueChatV4('${id}')">➕ ${seemsIncomplete(raw) ? 'Seguir generando' : 'Ampliar respuesta'}</button>`;
    }

    ST.chat[id].raw = raw;
    if (config) ST.chat[id].config = config;

    const panel = $('ai-panel-body');
    if (panel) panel.scrollTop = panel.scrollHeight;
  }

  function seemsIncomplete(text) {
    const raw = String(text || '').trim();
    if (!raw) return false;
    const last = raw.split('\n').map(x => x.trim()).filter(Boolean).pop() || '';
    if (last.length < 18) return true;
    if (/[,:;]$/.test(last)) return true;
    if (/\b(los|las|el|la|de|del|para|con|por|en|y|o|que|se|un|una|criterios|resultado|resultados|actividades|competencias|evidencias|cr[eé]d)\.?$/i.test(last)) return true;
    if (!/[.!?)]$/.test(last)) return true;
    return false;
  }

  function dedupe(base, append) {
    const baseClean = clean(base);
    let a = clean(append);
    if (!a) return '';
    const baseNorm = norm(baseClean);
    const aNorm = norm(a);
    if (aNorm && baseNorm.includes(aNorm.slice(0, Math.min(160, aNorm.length)))) return '';
    return a;
  }

  async function sendAiMessageStream() {
    css();

    const input = $('ai-panel-input');
    const text = input ? input.value.trim() : '';
    if (!text) return;
    if (input) input.value = '';

    const panel = $('ai-panel-body');
    if (!panel) return;

    panel.insertAdjacentHTML('beforeend', `<div class="ai-msg"><div class="ai-msg-user">${esc(text)}</div></div>`);

    const id = 'jm-chat-' + Date.now() + '-' + Math.floor(Math.random() * 100000);
    panel.insertAdjacentHTML('beforeend', `
      <div class="ai-msg">
        <div class="ai-msg-bot jm-chat-card">
          <div id="${id}-meta" style="margin-bottom:10px"><span class="jm-chip">conectando...</span></div>
          <div id="${id}-body" class="jm-chat-body">Generando...</div>
          <div id="${id}-actions"></div>
        </div>
      </div>
    `);

    ST.chat[id] = { raw: '', question: text, config: null, active: true };

    let raw = '';
    let config = null;

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question: text + '\n\nResponde de forma organizada y cierra con FIN_RESPUESTA.',
        context: 'chat',
        model: MODEL,
        max_tokens: 700,
        num_ctx: 1024,
        n_results: 2,
        temperature: 0.22,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderChat(id, raw, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderChat(id, raw, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && data.answer) raw = data.answer;
          ST.chat[id].active = false;
          renderChat(id, raw, config, '✅ final');
        }
      });
    } catch (e) {
      ST.chat[id].active = false;
      renderChat(id, raw + '\n\nERROR: ' + e.message, config, 'error');
    }
  }

  async function continueChat(id) {
    const item = ST.chat[id];
    if (!item) return;

    const base = clean(item.raw || '');
    let append = '';
    let config = item.config || null;
    const tail = base.slice(Math.max(0, base.length - 1800));

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question:
          'Continúa la respuesta anterior exactamente desde donde quedó. Devuelve solo contenido nuevo, sin repetir encabezados. Cierra con FIN_RESPUESTA.\n\n' +
          'PREGUNTA ORIGINAL:\n' + item.question + '\n\n' +
          'RESPUESTA YA MOSTRADA:\n' + base + '\n\n' +
          'ULTIMO FRAGMENTO:\n' + tail + '\n\nCONTINUACIÓN NUEVA:',
        context: 'chat_continue',
        model: MODEL,
        max_tokens: 700,
        num_ctx: 1024,
        n_results: 0,
        temperature: 0.14,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          const da = dedupe(base, append);
          renderChat(id, base + (da ? '\n\n' + da : ''), config, 'continuando...');
        },
        token(data) {
          append += data.text || '';
          const da = dedupe(base, append);
          renderChat(id, base + (da ? '\n\n' + da : ''), config, 'continuando...');
        },
        final(data) {
          config = data.tokens_config || config;
          const da = dedupe(base, append || data.answer || '');
          renderChat(id, base + (da ? '\n\n' + da : ''), config, '✅ continuación final');
        }
      });
    } catch (e) {
      renderChat(id, base + '\n\nERROR: ' + e.message, config, 'error');
    }
  }

  function install() {
    css();

    window.generateSilabo = generateSilaboStream;
    window.generateSyllabus = generateSilaboStream;
    window.copySilabo = copySilaboBridge;

    window.generateResourceV2 = generateResourceV2Stream;
    window.rcCopyResult = rcCopyResultBridge;
    window.rcDownloadResult = rcDownloadResultBridge;

    window.sendAiMessage = sendAiMessageStream;
    window.sendAiMessageWith = sendAiMessageStream;
    window.jmContinueChatV4 = continueChat;
  }

  install();
  document.addEventListener('DOMContentLoaded', install);
  setTimeout(install, 500);
})();
