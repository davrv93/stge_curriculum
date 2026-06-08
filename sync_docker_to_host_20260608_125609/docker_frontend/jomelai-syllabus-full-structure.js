/* JOMELAI_SYLLABUS_FULL_STRUCTURE_V1 */
(function () {
  const MODEL = 'qwen2.5-coder:3b';

  function id(x) { return document.getElementById(x); }

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
      .trim();
  }

  function css() {
    if (document.getElementById('jm-syllabus-full-css')) return;

    const style = document.createElement('style');
    style.id = 'jm-syllabus-full-css';
    style.textContent = `
      .jm-syl-shell{background:#e5e7eb!important;border-radius:18px!important;padding:24px!important;color:#0f172a!important}
      .jm-syl-paper{max-width:980px!important;margin:0 auto!important;background:#fff!important;border-radius:10px!important;box-shadow:0 18px 45px rgba(15,23,42,.18)!important;padding:42px!important;color:#0f172a!important;font-family:Arial,Helvetica,sans-serif!important;line-height:1.58!important}
      .jm-syl-paper,.jm-syl-paper *{color:#0f172a!important;text-shadow:none!important;opacity:1!important}
      .jm-syl-paper h1,.jm-syl-paper h2,.jm-syl-paper h3,.jm-syl-paper h4,.jm-syl-paper strong,.jm-syl-paper b{color:#020617!important;font-weight:900!important}
      .jm-syl-title{border-bottom:3px solid #7c3aed!important;padding-bottom:14px!important;margin-bottom:18px!important}
      .jm-syl-title small{display:block!important;color:#64748b!important;text-transform:uppercase!important;letter-spacing:.14em!important;font-size:11px!important;margin-bottom:6px!important}
      .jm-syl-title h2{margin:0!important;font-size:28px!important}
      .jm-syl-meta{color:#475569!important;margin-top:8px!important;font-size:14px!important}
      .jm-syl-toolbar{display:flex!important;justify-content:space-between!important;align-items:center!important;gap:10px!important;margin-bottom:18px!important}
      .jm-syl-btn{display:inline-flex!important;align-items:center!important;justify-content:center!important;gap:8px!important;padding:8px 11px!important;border-radius:9px!important;background:#f8fafc!important;border:1px solid #cbd5e1!important;color:#1e293b!important;font-weight:800!important;font-size:12px!important;cursor:pointer!important}
      .jm-syl-chip{display:inline-flex!important;align-items:center!important;gap:5px!important;padding:4px 8px!important;border-radius:999px!important;background:#eef2ff!important;border:1px solid #c7d2fe!important;color:#3730a3!important;font-size:11px!important;font-weight:900!important;margin:2px!important}
      .jm-syl-body{min-height:320px!important;outline:none!important}
      .jm-syl-body table{width:100%!important;border-collapse:collapse!important;margin:12px 0!important;font-size:13px!important}
      .jm-syl-body th,.jm-syl-body td{border:1px solid #e5e7eb!important;padding:8px!important;vertical-align:top!important}
      .jm-syl-body th{background:#f8fafc!important}
      .jm-syl-unit{border:1px solid #dbeafe!important;background:#f8fbff!important;border-radius:12px!important;padding:14px!important;margin:12px 0!important}
      .jm-syl-unit-label{font-size:12px!important;text-transform:uppercase!important;letter-spacing:.12em!important;color:#2563eb!important;font-weight:900!important}
      .jm-syl-session{border-left:4px solid #7c3aed!important;background:#faf5ff!important;border-radius:8px!important;padding:10px 12px!important;margin:8px 0!important}
      .jm-syl-eval{border-left:4px solid #f97316!important;background:#fff7ed!important;border-radius:8px!important;padding:10px 12px!important;margin:8px 0!important}
    `;
    document.head.appendChild(style);
  }

  function chips(config, label) {
    config = config || {};
    let html = `
      <span class="jm-syl-chip">🤖 ${esc(config.model || MODEL)}</span>
      <span class="jm-syl-chip">ctx ${esc(config.num_ctx || 2048)}</span>
      <span class="jm-syl-chip">salida ${esc(config.num_predict || '-')} tokens</span>
      <span class="jm-syl-chip">temp ${esc(config.temperature ?? '-')}</span>
    `;
    if (label) html += `<span class="jm-syl-chip">${esc(label)}</span>`;
    return html;
  }

  function parseJSON(raw) {
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

  function arr(v) {
    return Array.isArray(v) ? v : [];
  }

  function li(items) {
    return arr(items).length ? `<ul>${arr(items).map(x => `<li>${esc(x)}</li>`).join('')}</ul>` : '<p>Por completar.</p>';
  }

  function renderSyllabus(raw, meta, config, label) {
    css();

    const host = id('silabo-result');
    if (!host) return;

    host.style.display = 'block';

    const data = parseJSON(raw);

    let body = '';

    if (!data) {
      body = `<pre style="white-space:pre-wrap;font-family:Arial,Helvetica,sans-serif">${esc(clean(raw) || 'Generando estructura del sílabo...')}</pre>`;
    } else {
      const dg = data.datos_generales || {};
      const unidades = arr(data.unidades);
      const evaluaciones = arr(data.evaluaciones);

      body = `
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
            <div class="jm-syl-unit-label">Unidad ${esc(u.unidad || idx + 1)} · Semanas ${esc(arr(u.semanas).join(', ') || 'por definir')}</div>
            <h4>${esc(u.titulo || 'Unidad por completar')}</h4>
            <p><strong>Resultado de aprendizaje de la unidad:</strong> ${esc(u.resultado_unidad || u.resultado || 'Por completar.')}</p>
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

    host.innerHTML = `
      <div class="jm-syl-shell">
        <div class="jm-syl-paper">
          <div class="jm-syl-toolbar">
            <div>
              <strong>✅ Sílabo generado</strong>
              <div style="font-size:12px;color:#64748b">Editable en vivo · propuesta preliminar</div>
            </div>
            <div>
              <button class="jm-syl-btn" onclick="window.copySilabo()">📋 Copiar</button>
            </div>
          </div>

          <div class="jm-syl-title">
            <small>JoMelAi · Sílabo preliminar</small>
            <h2>Sílabo preliminar: ${esc(meta.course || 'Curso')}</h2>
            <div class="jm-syl-meta">${esc(meta.program || 'Programa por completar')} · ${esc(meta.credits || '-')} créditos · Ciclo ${esc(meta.cycle || '-')}</div>
          </div>

          <div id="jm-syllabus-config" style="margin-bottom:16px">${chips(config || {}, label || 'generando...')}</div>
          <div id="silabo-text" class="jm-syl-body" contenteditable="true" spellcheck="true">${body}</div>
        </div>
      </div>
    `;

    window.JM_STREAM_PRETTY = window.JM_STREAM_PRETTY || {};
    window.JM_STREAM_PRETTY.syllabus = window.JM_STREAM_PRETTY.syllabus || {};
    window.JM_STREAM_PRETTY.syllabus.raw = raw;
    window.JM_STREAM_PRETTY.syllabus.meta = meta;
    window.JM_STREAM_PRETTY.syllabus.config = config;
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
      headers: {'Content-Type': 'application/json', 'Accept': 'text/event-stream'},
      body: JSON.stringify(payload || {})
    });

    if (!res.ok || !res.body) throw new Error('No se pudo abrir el stream: ' + endpoint);

    const reader = res.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let buffer = '';

    while (true) {
      const read = await reader.read();
      if (read.done) break;

      buffer += decoder.decode(read.value, {stream: true});
      const events = buffer.split('\n\n');
      buffer = events.pop() || '';

      for (const ev of events) {
        const parsed = parseSseEvent(ev);
        if (!parsed) continue;
        if (handlers && typeof handlers[parsed.event] === 'function') handlers[parsed.event](parsed.data || {});
      }
    }
  }

  async function generateSyllabusFull() {
    css();

    const course = id('s-course') ? id('s-course').value.trim() : '';
    if (!course) {
      if (typeof toast === 'function') toast('El nombre del curso es obligatorio', 'error');
      else alert('El nombre del curso es obligatorio');
      return;
    }

    const meta = {
      course,
      program: id('s-program') ? id('s-program').value : '',
      credits: id('s-credits') ? id('s-credits').value : '',
      cycle: id('s-cycle') ? id('s-cycle').value : '',
      weeks: id('s-weeks') ? id('s-weeks').value : '16',
      modality: id('s-modal') ? id('s-modal').value : 'Presencial',
      graduate_profile: id('s-profile') ? id('s-profile').value : '',
      competency: id('s-competency') ? id('s-competency').value : '',
      start_date: id('s-start-date') ? id('s-start-date').value : '',
      sessions_per_week: id('s-sessions-per-week') ? id('s-sessions-per-week').value : '1'
    };

    const btn = id('btn-gen-silabo');
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando sílabo completo...';
    }

    const host = id('silabo-result');
    if (host) {
      host.style.display = 'block';
      host.innerHTML = `
        <div class="jm-syl-shell">
          <div class="jm-syl-paper">
            <div class="jm-syl-title">
              <small>JoMelAi · Sílabo preliminar</small>
              <h2>Sílabo preliminar: ${esc(course)}</h2>
              <div class="jm-syl-meta">Preparando generación completa...</div>
            </div>
            <div class="jm-syl-body">Generando estructura completa del sílabo...</div>
          </div>
        </div>
      `;
      host.scrollIntoView({behavior: 'smooth'});
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
        num_ctx: 2048,
        temperature: 0.22
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderSyllabus(raw, meta, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderSyllabus(raw, meta, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && (data.response || data.answer)) raw = data.response || data.answer;
          renderSyllabus(raw, meta, config, '✅ final');
          if (typeof toast === 'function') toast('✅ Sílabo completo generado', 'success');
        }
      });
    } catch (e) {
      raw += '\n\nERROR: ' + e.message;
      renderSyllabus(raw, meta, config, 'error');
      if (typeof toast === 'function') toast('Error al generar sílabo: ' + e.message, 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar sílabo con JoMelAi';
      }
    }
  }

  function copySilaboFull() {
    const text =
      (window.JM_STREAM_PRETTY && window.JM_STREAM_PRETTY.syllabus && window.JM_STREAM_PRETTY.syllabus.raw) ||
      (id('silabo-text') ? id('silabo-text').innerText : '') ||
      '';

    navigator.clipboard.writeText(clean(text));
  }

  window.generateSilabo = generateSyllabusFull;
  window.generateSyllabus = generateSyllabusFull;
  window.copySilabo = copySilaboFull;

  document.addEventListener('DOMContentLoaded', function () {
    css();
    setTimeout(function () {
      window.generateSilabo = generateSyllabusFull;
      window.generateSyllabus = generateSyllabusFull;
      window.copySilabo = copySilaboFull;
    }, 300);
  });
})();
