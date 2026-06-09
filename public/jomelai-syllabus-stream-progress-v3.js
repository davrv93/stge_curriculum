(function () {
  var MODEL = window.JOMELAI_SYLLABUS_MODEL || "llama3.2:1b";

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
    if (document.getElementById("jm-syl-progress-v3-css")) return;

    var s = document.createElement("style");
    s.id = "jm-syl-progress-v3-css";
    s.textContent = `
      .jm-syl-progress-card{
        margin:16px 0;
        padding:16px;
        background:#fff;
        border:1px solid #e4ebf3;
        border-radius:18px;
        box-shadow:0 12px 32px rgba(15,42,75,.08);
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-syl-progress-top{
        display:flex;
        justify-content:space-between;
        gap:12px;
        align-items:center;
        margin-bottom:10px;
      }
      .jm-syl-progress-title{
        font-weight:900;
        color:#0f2a4b;
      }
      .jm-syl-progress-percent{
        font-weight:900;
        color:#0f2a4b;
        background:#eef5ff;
        border-radius:999px;
        padding:6px 10px;
      }
      .jm-syl-progress-bar{
        height:12px;
        background:#edf2f7;
        border-radius:999px;
        overflow:hidden;
      }
      .jm-syl-progress-fill{
        height:100%;
        width:0%;
        background:linear-gradient(90deg,#0f2a4b,#2c6aa0);
        transition:width .25s ease;
      }
      .jm-syl-progress-msg{
        margin-top:9px;
        color:#536174;
        font-size:13px;
      }
      .jm-syl-doc{
        margin:18px 0;
        background:#f3f6fa;
        border-radius:24px;
        padding:18px;
        font-family:Inter,Roboto,Arial,sans-serif;
      }
      .jm-syl-paper{
        max-width:1180px;
        margin:0 auto;
        background:white;
        border-radius:22px;
        box-shadow:0 18px 50px rgba(15,42,75,.13);
        overflow:hidden;
        border:1px solid rgba(15,42,75,.08);
      }
      .jm-syl-head{
        background:linear-gradient(135deg,#0f2a4b,#173e6f);
        color:#fff;
        padding:26px 30px;
      }
      .jm-syl-head .tag{
        display:inline-block;
        padding:5px 10px;
        border-radius:999px;
        background:rgba(214,174,92,.18);
        border:1px solid rgba(214,174,92,.4);
        color:#ffe1a1;
        font-size:12px;
        margin-bottom:10px;
      }
      .jm-syl-head h2{
        margin:0;
        font-size:26px;
      }
      .jm-syl-head p{
        margin:8px 0 0;
        color:#dce9f8;
      }
      .jm-syl-section{
        padding:22px 30px;
        border-bottom:1px solid #edf1f5;
      }
      .jm-syl-section h3{
        margin:0 0 14px;
        color:#0f2a4b;
        font-size:18px;
      }
      .jm-syl-section p,
      .jm-syl-section li{
        color:#2d3f53;
        line-height:1.6;
      }
      .jm-syl-data{
        display:grid;
        grid-template-columns:repeat(4,minmax(0,1fr));
        gap:10px;
      }
      .jm-syl-data .item{
        background:#f7f9fc;
        border:1px solid #edf1f5;
        border-radius:14px;
        padding:12px;
      }
      .jm-syl-data .label{
        display:block;
        color:#66758a;
        font-size:11px;
        text-transform:uppercase;
        letter-spacing:.04em;
        margin-bottom:4px;
      }
      .jm-syl-data .value{
        color:#152b46;
        font-weight:800;
        font-size:13px;
      }
      .jm-syl-table-wrap{
        overflow-x:auto;
        margin-top:12px;
      }
      .jm-syl-table{
        width:100%;
        border-collapse:collapse;
        font-size:13px;
      }
      .jm-syl-table th{
        text-align:left;
        background:#0f2a4b;
        color:white;
        padding:10px;
        font-weight:800;
        white-space:nowrap;
      }
      .jm-syl-table td{
        border-bottom:1px solid #edf1f5;
        padding:10px;
        vertical-align:top;
        color:#2d3f53;
      }
      .jm-unit{
        border:1px solid #e4ebf3;
        border-radius:18px;
        overflow:hidden;
        margin:16px 0;
        background:#fff;
      }
      .jm-unit-title{
        padding:16px 18px;
        background:#f8fafc;
        border-bottom:1px solid #e4ebf3;
      }
      .jm-unit-title strong{
        color:#0f2a4b;
        font-size:16px;
      }
      .jm-unit-body{
        padding:16px 18px;
      }
      .jm-chip{
        display:inline-flex;
        margin:3px 5px 3px 0;
        padding:5px 9px;
        border-radius:999px;
        background:#eef5ff;
        color:#24517e;
        font-size:12px;
        font-weight:700;
      }
      .jm-actions{
        display:flex;
        gap:8px;
        justify-content:flex-end;
        padding:14px 30px;
        background:#f8fafc;
      }
      .jm-actions button{
        border:0;
        border-radius:12px;
        padding:10px 14px;
        font-weight:900;
        cursor:pointer;
        background:#0f2a4b;
        color:white;
      }
      @media(max-width:760px){
        .jm-syl-data{grid-template-columns:1fr;}
        .jm-syl-head,.jm-syl-section{padding:18px;}
      }
    `;
    document.head.appendChild(s);
  }

  function getRoot() {
    return document.querySelector("#silabos") ||
      document.querySelector("[data-page='silabos']") ||
      document.querySelector(".page-silabos") ||
      document.querySelector("main") ||
      document.body;
  }

  function ensureProgress() {
    css();

    var root = getRoot();
    var el = document.getElementById("jm-syl-progress-card");

    if (!el) {
      el = document.createElement("div");
      el.id = "jm-syl-progress-card";
      el.className = "jm-syl-progress-card";
      el.innerHTML = `
        <div class="jm-syl-progress-top">
          <div>
            <div class="jm-syl-progress-title" id="jm-syl-progress-stage">Esperando generación</div>
            <div class="jm-syl-progress-msg" id="jm-syl-progress-message">Completa el formulario y genera el sílabo.</div>
          </div>
          <div class="jm-syl-progress-percent" id="jm-syl-progress-percent">0%</div>
        </div>
        <div class="jm-syl-progress-bar"><div class="jm-syl-progress-fill" id="jm-syl-progress-fill"></div></div>
      `;
      root.insertBefore(el, root.firstChild || null);
    }

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) {
      out = document.createElement("div");
      out.id = "jomelai-syllabus-pretty-output";
      root.appendChild(out);
    }
  }

  function setProgress(percent, stage, message) {
    ensureProgress();

    percent = Math.max(0, Math.min(100, Number(percent || 0)));

    var pct = document.getElementById("jm-syl-progress-percent");
    var fill = document.getElementById("jm-syl-progress-fill");
    var st = document.getElementById("jm-syl-progress-stage");
    var msg = document.getElementById("jm-syl-progress-message");

    if (pct) pct.textContent = Math.round(percent) + "%";
    if (fill) fill.style.width = percent + "%";
    if (st && stage) st.textContent = stage;
    if (msg && message) msg.textContent = message;
  }

  function extractJson(text) {
    if (!text) return null;
    if (typeof text === "object") return text;

    try { return JSON.parse(text); } catch (e) {}

    var s = String(text);
    var a = s.indexOf("{");
    var b = s.lastIndexOf("}");

    if (a >= 0 && b > a) {
      try { return JSON.parse(s.slice(a, b + 1)); } catch (e) {}
    }

    return null;
  }

  function renderSyllabus(syl, markdown) {
    css();
    ensureProgress();

    var out = document.getElementById("jomelai-syllabus-pretty-output");
    if (!out) return;

    if (!syl) {
      out.innerHTML = `
        <div class="jm-syl-doc">
          <div class="jm-syl-paper">
            <div class="jm-syl-head">
              <span class="tag">Sílabo generado</span>
              <h2>Resultado</h2>
              <p>No se pudo convertir a JSON visual. Se muestra el texto recibido.</p>
            </div>
            <div class="jm-syl-section"><pre>${esc(markdown || "")}</pre></div>
          </div>
        </div>
      `;
      return;
    }

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
        <div class="item">
          <span class="label">${esc(it[0])}</span>
          <span class="value">${esc(it[1] || "")}</span>
        </div>
      `;
    }).join("");

    var resultadosHtml = list(syl.resultados_curso).map(function (r) {
      if (typeof r === "string") {
        return `<tr><td></td><td>${esc(r)}</td><td></td><td></td><td></td></tr>`;
      }

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
      var contenidos = list(u.contenidos).map(function (c) {
        return '<span class="jm-chip">' + esc(c) + '</span>';
      }).join("");

      var sesiones = list(u.sesiones).map(function (s) {
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
        <div class="jm-unit">
          <div class="jm-unit-title">
            <strong>Unidad ${esc(u.unidad || "")}: ${esc(u.titulo || "")}</strong>
            <div style="margin-top:6px;color:#66758a;font-size:12px;">
              Semanas: ${esc(Array.isArray(u.semanas) ? u.semanas.join(", ") : (u.semanas || ""))}
              &nbsp; | &nbsp; RA: ${esc(Array.isArray(u.resultados_curso_vinculados) ? u.resultados_curso_vinculados.join(", ") : (u.resultados_curso_vinculados || ""))}
              &nbsp; | &nbsp; Nivel: ${esc(u.nivel_taxonomico_dominante || "")}
            </div>
          </div>
          <div class="jm-unit-body">
            <p><strong>Resultado de unidad:</strong> ${esc(u.resultado_unidad || "")}</p>
            <p><strong>Metodología:</strong> ${esc(u.metodologia_unidad || "")}</p>
            <p><strong>Justificación:</strong> ${esc(u.justificacion_metodologica || "")}</p>
            <div>${contenidos}</div>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead>
                  <tr>
                    <th>Semana</th><th>Sesión</th><th>Tema</th><th>RA</th><th>Nivel</th><th>Actividad</th><th>Producto</th><th>Aporte</th>
                  </tr>
                </thead>
                <tbody>${sesiones}</tbody>
              </table>
            </div>
            <p><strong>Producto integrador:</strong> ${esc(u.producto_unidad || "")}</p>
          </div>
        </div>
      `;
    }).join("");

    var trazabilidadHtml = list(syl.matriz_trazabilidad).map(function (t) {
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

    var metodHtml = list(syl.metodologias).map(function (m) {
      if (typeof m === "string") return "<li>" + esc(m) + "</li>";
      return "<li><strong>" + esc(m.nombre || "") + ":</strong> " + esc(m.aplicacion || "") + " " + esc(m.justificacion || "") + "</li>";
    }).join("");

    var refsHtml = list(syl.referencias).map(function (r) {
      if (typeof r === "string") return "<li>" + esc(r) + "</li>";
      return "<li>" + esc((r.autor || "") + " (" + (r.anio || "") + "). " + (r.titulo || "") + ". " + (r.fuente || "") + (r.url ? ". " + r.url : "")) + "</li>";
    }).join("");

    out.innerHTML = `
      <div class="jm-syl-doc">
        <div class="jm-syl-paper">
          <div class="jm-syl-head">
            <span class="tag">Sílabo curricular con trazabilidad</span>
            <h2>${esc(dg.curso || "Sílabo")}</h2>
            <p>${esc(dg.programa || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>I. Datos generales</h3>
            <div class="jm-syl-data">${dataHtml}</div>
          </div>

          <div class="jm-syl-section">
            <h3>II. Sumilla</h3>
            <p>${esc(syl.sumilla || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>III. Competencia del curso</h3>
            <p>${esc(syl.competencia_curso || "")}</p>
          </div>

          <div class="jm-syl-section">
            <h3>IV. Resultados de aprendizaje y taxonomía</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>Código</th><th>Resultado</th><th>Nivel</th><th>Verbo</th><th>Evidencia</th></tr></thead>
                <tbody>${resultadosHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>V. Unidades y sesiones</h3>
            ${unidadesHtml}
          </div>

          <div class="jm-syl-section">
            <h3>VI. Matriz de trazabilidad curricular</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>RA</th><th>Unidad</th><th>Sesiones</th><th>Producto</th><th>Evaluación</th><th>Criterio de logro</th></tr></thead>
                <tbody>${trazabilidadHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>VII. Evaluación</h3>
            <div class="jm-syl-table-wrap">
              <table class="jm-syl-table">
                <thead><tr><th>Tipo</th><th>Descripción</th><th>Evidencia</th><th>Instrumento</th><th>RA</th><th>Semana</th><th>Puntaje</th></tr></thead>
                <tbody>${evalHtml}</tbody>
              </table>
            </div>
          </div>

          <div class="jm-syl-section">
            <h3>VIII. Metodologías</h3>
            <ul>${metodHtml}</ul>
          </div>

          <div class="jm-syl-section">
            <h3>IX. Referencias</h3>
            <ul>${refsHtml}</ul>
          </div>

          <div class="jm-actions">
            <button type="button" id="jm-copy-syllabus-md">Copiar Markdown</button>
            <button type="button" id="jm-copy-syllabus-json">Copiar JSON</button>
          </div>
        </div>
      </div>
    `;

    var mdBtn = document.getElementById("jm-copy-syllabus-md");
    var jsonBtn = document.getElementById("jm-copy-syllabus-json");

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
  }

  function isSyllabusUrl(input) {
    var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
    return url.indexOf("/api/assistant/generate-syllabus-stream") !== -1;
  }

  function handleEvent(eventName, dataText) {
    var data = null;

    try {
      data = JSON.parse(dataText);
    } catch (e) {
      data = null;
    }

    if (eventName === "progress" && data) {
      setProgress(data.percent, data.stage, data.message);
      return;
    }

    if (eventName === "config" && data) {
      setProgress(10, "Configuración", data.message || "Configurando generación curricular.");
      return;
    }

    if (eventName === "quality_repair" && data) {
      setProgress(88, "Reparación curricular", data.message || "Profundizando salida.");
      return;
    }

    if ((eventName === "syllabus" || eventName === "final") && data) {
      var syl = data.syllabus || extractJson(data.raw_response) || extractJson(data.response) || extractJson(data.answer);
      var md = data.markdown || data.answer || "";
      renderSyllabus(syl, md);

      if (eventName === "final") {
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
    if (!window.fetch || window.fetch.__jmSyllabusProgressV3) return;

    var originalFetch = window.fetch;

    window.fetch = function (input, init) {
      if (!isSyllabusUrl(input)) {
        return originalFetch.apply(this, arguments);
      }

      ensureProgress();
      setProgress(2, "Inicio", "Enviando solicitud al generador curricular.");

      var opts = {};
      init = init || {};
      Object.keys(init).forEach(function (k) { opts[k] = init[k]; });

      try {
        if (typeof opts.body === "string" && opts.body.trim().charAt(0) === "{") {
          var payload = JSON.parse(opts.body);
          payload.model = MODEL;
          payload.render_mode = "syllabus_curricular_traceability";
          payload.max_tokens = payload.max_tokens || 6200;
          payload.num_ctx = payload.num_ctx || 8192;
          opts.body = JSON.stringify(payload);
        }
      } catch (e) {}

      return originalFetch.call(this, input, opts).then(function (resp) {
        if (!resp.body || !resp.body.tee) {
          resp.clone().text().then(function (text) {
            var rest = "";
            rest += text;
            parseSseBuffer(rest + "\n\n", handleEvent);
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
              buffer = parseSseBuffer(buffer + "\n\n", handleEvent);
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

    window.fetch.__jmSyllabusProgressV3 = true;
  }

  function init() {
    css();
    ensureProgress();
    patchFetch();
    console.log("[JoMelAi] Syllabus curricular progress v3 activo");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
