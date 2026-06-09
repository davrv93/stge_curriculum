(function () {
  var MODEL = window.JOMELAI_SYLLABUS_MODEL || "qwen2.5:1.5b";
  var lastRequestPayload = null;
  var lastRawResponse = "";

  function esc(v) {
    return String(v == null ? "" : v)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function list(v) {
    return Array.isArray(v) ? v : [];
  }

  function css() {
    if (document.getElementById("jm-qwen-syl-v4-css")) return;

    var s = document.createElement("style");
    s.id = "jm-qwen-syl-v4-css";
    s.textContent = `
      .jm-qwen-progress{
        margin:16px 0;
        padding:16px;
        border:1px solid #e4ebf3;
        border-radius:18px;
        background:#fff;
        box-shadow:0 12px 32px rgba(15,42,75,.08);
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-qwen-progress-top{
        display:flex;
        align-items:center;
        justify-content:space-between;
        gap:12px;
        margin-bottom:10px;
      }
      .jm-qwen-stage{
        font-weight:900;
        color:#0f2a4b;
      }
      .jm-qwen-percent{
        font-weight:900;
        color:#0f2a4b;
        background:#eef5ff;
        border-radius:999px;
        padding:6px 10px;
      }
      .jm-qwen-bar{
        height:12px;
        border-radius:999px;
        overflow:hidden;
        background:#edf2f7;
      }
      .jm-qwen-fill{
        height:100%;
        width:0%;
        background:linear-gradient(90deg,#0f2a4b,#2c6aa0);
        transition:width .25s ease;
      }
      .jm-qwen-msg{
        margin-top:8px;
        color:#536174;
        font-size:13px;
      }
      .jm-qwen-doc{
        margin:18px 0;
        background:#f3f6fa;
        border-radius:24px;
        padding:18px;
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-qwen-paper{
        max-width:1180px;
        margin:0 auto;
        background:white;
        border-radius:22px;
        box-shadow:0 18px 50px rgba(15,42,75,.13);
        overflow:hidden;
        border:1px solid rgba(15,42,75,.08);
      }
      .jm-qwen-head{
        background:linear-gradient(135deg,#0f2a4b,#173e6f);
        color:#fff;
        padding:26px 30px;
      }
      .jm-qwen-tag{
        display:inline-block;
        padding:5px 10px;
        border-radius:999px;
        background:rgba(214,174,92,.18);
        border:1px solid rgba(214,174,92,.4);
        color:#ffe1a1;
        font-size:12px;
        margin-bottom:10px;
      }
      .jm-qwen-head h2{
        margin:0;
        font-size:26px;
      }
      .jm-qwen-head p{
        margin:8px 0 0;
        color:#dce9f8;
      }
      .jm-qwen-section{
        padding:22px 30px;
        border-bottom:1px solid #edf1f5;
      }
      .jm-qwen-section h3{
        margin:0 0 14px;
        color:#0f2a4b;
        font-size:18px;
      }
      .jm-qwen-section p,
      .jm-qwen-section li{
        color:#2d3f53;
        line-height:1.6;
      }
      .jm-qwen-data{
        display:grid;
        grid-template-columns:repeat(4,minmax(0,1fr));
        gap:10px;
      }
      .jm-qwen-item{
        background:#f7f9fc;
        border:1px solid #edf1f5;
        border-radius:14px;
        padding:12px;
      }
      .jm-qwen-label{
        display:block;
        color:#66758a;
        font-size:11px;
        text-transform:uppercase;
        letter-spacing:.04em;
        margin-bottom:4px;
      }
      .jm-qwen-value{
        color:#152b46;
        font-weight:800;
        font-size:13px;
      }
      .jm-qwen-table-wrap{
        overflow-x:auto;
        margin-top:12px;
      }
      .jm-qwen-table{
        width:100%;
        border-collapse:collapse;
        font-size:13px;
      }
      .jm-qwen-table th{
        text-align:left;
        background:#0f2a4b;
        color:white;
        padding:10px;
        font-weight:800;
        white-space:nowrap;
      }
      .jm-qwen-table td{
        border-bottom:1px solid #edf1f5;
        padding:10px;
        vertical-align:top;
        color:#2d3f53;
      }
      .jm-qwen-unit{
        border:1px solid #e4ebf3;
        border-radius:18px;
        overflow:hidden;
        margin:16px 0;
        background:#fff;
      }
      .jm-qwen-unit-title{
        padding:16px 18px;
        background:#f8fafc;
        border-bottom:1px solid #e4ebf3;
      }
      .jm-qwen-unit-title strong{
        color:#0f2a4b;
        font-size:16px;
      }
      .jm-qwen-unit-body{
        padding:16px 18px;
      }
      .jm-qwen-chip{
        display:inline-flex;
        margin:3px 5px 3px 0;
        padding:5px 9px;
        border-radius:999px;
        background:#eef5ff;
        color:#24517e;
        font-size:12px;
        font-weight:700;
      }
      .jm-qwen-actions{
        display:flex;
        flex-wrap:wrap;
        gap:8px;
        justify-content:flex-end;
        padding:14px 30px;
        background:#f8fafc;
      }
      .jm-qwen-actions button{
        border:0;
        border-radius:12px;
        padding:10px 14px;
        font-weight:900;
        cursor:pointer;
        background:#0f2a4b;
        color:white;
      }
      .jm-qwen-actions button.secondary{
        background:#6b7280;
      }
      .jm-qwen-warning{
        margin:14px 0;
        padding:12px;
        border-radius:14px;
        background:#fff7ed;
        border:1px solid #fed7aa;
        color:#9a3412;
        font-size:13px;
      }
      @media(max-width:760px){
        .jm-qwen-data{grid-template-columns:1fr;}
        .jm-qwen-head,.jm-qwen-section{padding:18px;}
      }
    `;
    document.head.appendChild(s);
  }

  function root() {
    return document.querySelector("#silabos") ||
      document.querySelector("[data-page='silabos']") ||
      document.querySelector(".page-silabos") ||
      document.querySelector("main") ||
      document.body;
  }

  function ensureUi() {
    css();

    var r = root();

    if (!document.getElementById("jm-qwen-progress")) {
      var p = document.createElement("div");
      p.id = "jm-qwen-progress";
      p.className = "jm-qwen-progress";
      p.innerHTML = `
        <div class="jm-qwen-progress-top">
          <div>
            <div class="jm-qwen-stage" id="jm-qwen-stage">Esperando generación</div>
            <div class="jm-qwen-msg" id="jm-qwen-msg">Completa el formulario y genera el sílabo.</div>
          </div>
          <div class="jm-qwen-percent" id="jm-qwen-percent">0%</div>
        </div>
        <div class="jm-qwen-bar"><div class="jm-qwen-fill" id="jm-qwen-fill"></div></div>
      `;
      r.insertBefore(p, r.firstChild || null);
    }

    if (!document.getElementById("jomelai-syllabus-pretty-output")) {
      var out = document.createElement("div");
      out.id = "jomelai-syllabus-pretty-output";
      r.appendChild(out);
    }
  }

  function setProgress(percent, stage, message) {
    ensureUi();

    percent = Math.max(0, Math.min(100, Number(percent || 0)));

    var pct = document.getElementById("jm-qwen-percent");
    var fill = document.getElementById("jm-qwen-fill");
    var st = document.getElementById("jm-qwen-stage");
    var msg = document.getElementById("jm-qwen-msg");

    if (pct) pct.textContent = Math.round(percent) + "%";
    if (fill) fill.style.width = percent + "%";
    if (st && stage) st.textContent = stage;
    if (msg && message) msg.textContent = message;
  }

  function extractJson(text) {
    if (!text) return null;
    if (typeof text === "object") return text;

    try {
      return JSON.parse(text);
    } catch (e) {}

    var s = String(text);
    var a = s.indexOf("{");
    var b = s.lastIndexOf("}");

    if (a >= 0 && b > a) {
      try {
        return JSON.parse(s.slice(a, b + 1));
      } catch (e) {}
    }

    return null;
  }

  function renderRaw(markdown, payload) {
    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

    var issues = payload && Array.isArray(payload.quality_issues) ? payload.quality_issues : [];

    out.innerHTML = `
      <div class="jm-qwen-doc">
        <div class="jm-qwen-paper">
          <div class="jm-qwen-head">
            <span class="jm-qwen-tag">Sílabo incompleto</span>
            <h2>La generación necesita completarse</h2>
            <p>El modelo devolvió JSON incompleto o baja calidad curricular. Puedes continuar la generación con Qwen.</p>
          </div>
          <div class="jm-qwen-section">
            <h3>Observaciones</h3>
            <div class="jm-qwen-warning">
              ${issues.length ? "<ul>" + issues.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul>" : "La respuesta quedó incompleta o no pudo convertirse a JSON válido."}
            </div>
            <pre style="white-space:pre-wrap;max-height:340px;overflow:auto;background:#0f172a;color:#e5e7eb;padding:14px;border-radius:14px;">${esc(markdown || "")}</pre>
          </div>
          <div class="jm-qwen-actions">
            <button type="button" id="jm-qwen-continue">Continuar generación</button>
            <button type="button" class="secondary" id="jm-qwen-copy-raw">Copiar borrador</button>
          </div>
        </div>
      </div>
    `;

    var btn = document.getElementById("jm-qwen-continue");
    var copy = document.getElementById("jm-qwen-copy-raw");

    if (copy) {
      copy.onclick = function () {
        navigator.clipboard.writeText(markdown || "");
      };
    }

    if (btn) {
      btn.onclick = function () {
        if (!lastRequestPayload) {
          alert("No encontré el payload anterior para continuar.");
          return;
        }

        var next = {};
        Object.keys(lastRequestPayload).forEach(function (k) {
          next[k] = lastRequestPayload[k];
        });

        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRawResponse || markdown || "";
        next.max_tokens = 7200;
        next.num_ctx = 8192;
        next.render_mode = "syllabus_qwen_curricular_v4";

        setProgress(3, "Continuando generación", "Reconstruyendo el sílabo completo con Qwen.");

        fetch("/api/assistant/generate-syllabus-stream", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(next)
        });
      };
    }
  }

  function renderSyllabus(syl, markdown, payload) {
    ensureUi();

    if (!syl) {
      renderRaw(markdown, payload);
      return;
    }

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

    var dg = syl.datos_generales || {};

    var dataHtml = [
      ["Curso", dg.curso],
      ["Programa", dg.programa],
      ["Créditos", dg.creditos],
      ["Ciclo", dg.ciclo],
      ["Semanas", dg.semanas],
      ["Modalidad", dg.modalidad],
      ["Inicio", dg.fecha_inicio],
      ["Fin", dg.fecha_fin]
    ].map(function (it) {
      return `
        <div class="jm-qwen-item">
          <span class="jm-qwen-label">${esc(it[0])}</span>
          <span class="jm-qwen-value">${esc(it[1] || "")}</span>
        </div>
      `;
    }).join("");

    var raHtml = list(syl.resultados_curso).map(function (r) {
      return `
        <tr>
          <td>${esc(r.codigo || "")}</td>
          <td>${esc(r.descripcion || "")}</td>
          <td>${esc(r.nivel_taxonomico || "")}</td>
          <td>${esc(r.verbo_observable || "")}</td>
          <td>${esc(r.evidencia_integradora || "")}</td>
        </tr>
      `;
    }).join("");

    var unidadesHtml = list(syl.unidades).map(function (u) {
      var contents = list(u.contenidos).map(function (c) {
        return '<span class="jm-qwen-chip">' + esc(c) + '</span>';
      }).join("");

      var sessions = list(u.sesiones).map(function (s) {
        return `
          <tr>
            <td>${esc(s.semana || "")}</td>
            <td>${esc(s.sesion || "")}</td>
            <td>${esc(s.titulo || "")}</td>
            <td>${esc(s.resultado_curso_vinculado || "")}</td>
            <td>${esc(s.nivel_taxonomico || "")}</td>
            <td>${esc(s.actividad_aprendizaje || "")}</td>
            <td>${esc(s.producto || "")}</td>
            <td>${esc(s.aporte_a_resultado_unidad || "")}</td>
          </tr>
        `;
      }).join("");

      return `
        <div class="jm-qwen-unit">
          <div class="jm-qwen-unit-title">
            <strong>Unidad ${esc(u.unidad || "")}: ${esc(u.titulo || "")}</strong>
            <div style="margin-top:6px;color:#66758a;font-size:12px;">
              Semanas: ${esc(Array.isArray(u.semanas) ? u.semanas.join(", ") : (u.semanas || ""))}
              | RA: ${esc(Array.isArray(u.resultados_curso_vinculados) ? u.resultados_curso_vinculados.join(", ") : (u.resultados_curso_vinculados || ""))}
              | Nivel: ${esc(u.nivel_taxonomico_dominante || "")}
            </div>
          </div>
          <div class="jm-qwen-unit-body">
            <p><strong>Resultado de unidad:</strong> ${esc(u.resultado_unidad || "")}</p>
            <p><strong>Metodología:</strong> ${esc(u.metodologia_unidad || "")}</p>
            <p><strong>Justificación:</strong> ${esc(u.justificacion_metodologica || "")}</p>
            <div>${contents}</div>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Semana</th><th>Sesión</th><th>Tema</th><th>RA</th><th>Nivel</th><th>Actividad</th><th>Producto</th><th>Aporte</th></tr></thead>
                <tbody>${sessions}</tbody>
              </table>
            </div>
            <p><strong>Producto integrador:</strong> ${esc(u.producto_unidad || "")}</p>
          </div>
        </div>
      `;
    }).join("");

    var traceHtml = list(syl.matriz_trazabilidad).map(function (t) {
      return `
        <tr>
          <td>${esc(t.resultado_curso || "")}</td>
          <td>${esc(t.unidad || "")}</td>
          <td>${esc(Array.isArray(t.sesiones) ? t.sesiones.join(", ") : (t.sesiones || ""))}</td>
          <td>${esc(t.producto || "")}</td>
          <td>${esc(t.evaluacion || "")}</td>
          <td>${esc(t.criterio_logro || "")}</td>
        </tr>
      `;
    }).join("");

    var evalHtml = list(syl.evaluaciones).map(function (e) {
      return `
        <tr>
          <td>${esc(e.tipo || "")}</td>
          <td>${esc(e.descripcion || "")}</td>
          <td>${esc(e.evidencia || "")}</td>
          <td>${esc(e.instrumento || "")}</td>
          <td>${esc(Array.isArray(e.resultados_vinculados) ? e.resultados_vinculados.join(", ") : (e.resultados_vinculados || ""))}</td>
          <td>${esc(e.semana || "")}</td>
          <td>${esc(e.puntaje_vigesimal || "")}</td>
        </tr>
      `;
    }).join("");

    var metHtml = list(syl.metodologias).map(function (m) {
      return "<li><strong>" + esc(m.nombre || "") + ":</strong> " + esc(m.aplicacion || "") + " " + esc(m.justificacion || "") + "</li>";
    }).join("");

    var refHtml = list(syl.referencias).map(function (r) {
      return "<li>" + esc((r.autor || "") + " (" + (r.anio || "") + "). " + (r.titulo || "") + ". " + (r.fuente || "") + (r.url ? ". " + r.url : "")) + "</li>";
    }).join("");

    var needs = payload && payload.needs_continue;

    out.innerHTML = `
      <div class="jm-qwen-doc">
        <div class="jm-qwen-paper">
          <div class="jm-qwen-head">
            <span class="jm-qwen-tag">Sílabo curricular Qwen</span>
            <h2>${esc(dg.curso || "Sílabo")}</h2>
            <p>${esc(dg.programa || "")}</p>
          </div>

          ${needs ? '<div class="jm-qwen-section"><div class="jm-qwen-warning">El sistema detectó que aún puede mejorar. Puedes usar “Continuar generación”.</div></div>' : ''}

          <div class="jm-qwen-section">
            <h3>I. Datos generales</h3>
            <div class="jm-qwen-data">${dataHtml}</div>
          </div>

          <div class="jm-qwen-section">
            <h3>II. Sumilla</h3>
            <p>${esc(syl.sumilla || "")}</p>
          </div>

          <div class="jm-qwen-section">
            <h3>III. Competencia del curso</h3>
            <p>${esc(syl.competencia_curso || "")}</p>
          </div>

          <div class="jm-qwen-section">
            <h3>IV. Resultados de aprendizaje y taxonomía</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Código</th><th>Resultado</th><th>Nivel</th><th>Verbo</th><th>Evidencia</th></tr></thead>
                <tbody>${raHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>V. Unidades y sesiones</h3>
            ${unidadesHtml}
          </div>

          <div class="jm-qwen-section">
            <h3>VI. Matriz de trazabilidad curricular</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>RA</th><th>Unidad</th><th>Sesiones</th><th>Producto</th><th>Evaluación</th><th>Criterio</th></tr></thead>
                <tbody>${traceHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>VII. Evaluación</h3>
            <div class="jm-qwen-table-wrap">
              <table class="jm-qwen-table">
                <thead><tr><th>Tipo</th><th>Descripción</th><th>Evidencia</th><th>Instrumento</th><th>RA</th><th>Semana</th><th>Puntaje</th></tr></thead>
                <tbody>${evalHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-qwen-section">
            <h3>VIII. Metodologías</h3>
            <ul>${metHtml}</ul>
          </div>

          <div class="jm-qwen-section">
            <h3>IX. Referencias</h3>
            <ul>${refHtml}</ul>
          </div>

          <div class="jm-qwen-actions">
            ${needs ? '<button type="button" id="jm-qwen-continue">Continuar generación</button>' : ''}
            <button type="button" id="jm-qwen-copy-md">Copiar Markdown</button>
            <button type="button" class="secondary" id="jm-qwen-copy-json">Copiar JSON</button>
          </div>
        </div>
      </div>
    `;

    var mdBtn = document.getElementById("jm-qwen-copy-md");
    var jsonBtn = document.getElementById("jm-qwen-copy-json");
    var continueBtn = document.getElementById("jm-qwen-continue");

    if (mdBtn) {
      mdBtn.onclick = function () {
        navigator.clipboard.writeText(markdown || "");
      };
    }

    if (jsonBtn) {
      jsonBtn.onclick = function () {
        navigator.clipboard.writeText(JSON.stringify(syl, null, 2));
      };
    }

    if (continueBtn) {
      continueBtn.onclick = function () {
        var next = {};
        Object.keys(lastRequestPayload || {}).forEach(function (k) {
          next[k] = lastRequestPayload[k];
        });

        next.model = MODEL;
        next.continue_generation = true;
        next.previous_raw = lastRawResponse || JSON.stringify(syl, null, 2);
        next.max_tokens = 7200;
        next.num_ctx = 8192;
        next.render_mode = "syllabus_qwen_curricular_v4";

        setProgress(3, "Continuando generación", "Reconstruyendo el sílabo completo con Qwen.");

        fetch("/api/assistant/generate-syllabus-stream", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(next)
        });
      };
    }
  }

  function isSyllabusUrl(input) {
    var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
    return url.indexOf("/api/assistant/generate-syllabus-stream") !== -1;
  }

  function handleEvent(eventName, dataText) {
    var data = null;

    try {
      data = JSON.parse(dataText);
    } catch (e) {}

    if (eventName === "progress" && data) {
      setProgress(data.percent, data.stage, data.message);
      return;
    }

    if (eventName === "config" && data) {
      setProgress(10, "Configuración", data.message || "Configurando generación curricular.");
      return;
    }

    if ((eventName === "syllabus" || eventName === "final") && data) {
      lastRawResponse = data.raw_response || data.response || data.answer || lastRawResponse;
      var syl = data.syllabus || extractJson(data.raw_response) || extractJson(data.response) || extractJson(data.answer);
      var md = data.markdown || data.answer || data.response || "";
      renderSyllabus(syl, md, data);

      if (eventName === "final" && !data.needs_continue) {
        setProgress(100, "Completado", "Sílabo curricular generado y listo para revisión.");
      }
    }
  }

  function parseSseBuffer(buffer, onEvent) {
    var parts = buffer.split(/\r?\n\r?\n/);
    var rest = parts.pop();

    parts.forEach(function (block) {
      var ev = "message";
      var data = [];

      block.split(/\r?\n/).forEach(function (line) {
        if (line.indexOf("event:") === 0) {
          ev = line.slice(6).trim();
        } else if (line.indexOf("data:") === 0) {
          data.push(line.slice(5).trim());
        }
      });

      if (data.length) {
        onEvent(ev, data.join("\n"));
      }
    });

    return rest;
  }

  function patchFetch() {
    if (!window.fetch || window.fetch.__jmQwenSylV4) return;

    var originalFetch = window.fetch;

    window.fetch = function (input, init) {
      if (!isSyllabusUrl(input)) {
        return originalFetch.apply(this, arguments);
      }

      ensureUi();
      setProgress(2, "Inicio", "Enviando solicitud al generador curricular Qwen.");

      var opts = {};
      init = init || {};
      Object.keys(init).forEach(function (k) { opts[k] = init[k]; });

      try {
        if (typeof opts.body === "string" && opts.body.trim().charAt(0) === "{") {
          var payload = JSON.parse(opts.body);
          payload.model = MODEL;
          payload.max_tokens = payload.max_tokens || 7200;
          payload.num_ctx = payload.num_ctx || 8192;
          payload.temperature = payload.temperature || 0.28;
          payload.top_p = payload.top_p || 0.86;
          payload.render_mode = "syllabus_qwen_curricular_v4";
          lastRequestPayload = payload;
          opts.body = JSON.stringify(payload);
        }
      } catch (e) {}

      return originalFetch.call(this, input, opts).then(function (resp) {
        if (!resp.body || !resp.body.tee) {
          resp.clone().text().then(function (text) {
            parseSseBuffer(text + "\n\n", handleEvent);
          }).catch(function () {});
          return resp;
        }

        var streams = resp.body.tee();
        var uiStream = streams[0];
        var appStream = streams[1];

        var reader = uiStream.getReader();
        var decoder = new TextDecoder();
        var buffer = "";

        function pump() {
          reader.read().then(function (res) {
            if (res.done) {
              parseSseBuffer(buffer + "\n\n", handleEvent);
              return;
            }

            buffer += decoder.decode(res.value, { stream: true });
            buffer = parseSseBuffer(buffer, handleEvent);
            pump();
          }).catch(function () {});
        }

        pump();

        return new Response(appStream, {
          status: resp.status,
          statusText: resp.statusText,
          headers: resp.headers
        });
      });
    };

    window.fetch.__jmQwenSylV4 = true;
  }

  function init() {
    ensureUi();
    patchFetch();
    console.log("[JoMelAi] Qwen syllabus curricular v4 activo. Modelo:", MODEL);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
