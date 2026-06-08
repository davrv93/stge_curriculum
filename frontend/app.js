/* ══════════════════════════════════════════════════════
   CONFIG
══════════════════════════════════════════════════════ */
const API = window.API_BASE || "";
const STATE = {
  user: null,
  page: "dashboard",
  projects: [],
  planStep: 0,
  planData: {},
  planSteps: [],
  selectedResourceType: "actividad",
  mallaResult: null,
  silaboResult: null,
  resourceResult: null,
};
window.STATE = STATE;

/* ══════════════════════════════════════════════════════
   PARTICLES & BUBBLES
══════════════════════════════════════════════════════ */
function initParticles() {
  const canvas = document.getElementById("particle-canvas");
  const ctx = canvas.getContext("2d");
  let W = (canvas.width = window.innerWidth);
  let H = (canvas.height = window.innerHeight);
  const particles = [];
  const count = 60;

  for (let i = 0; i < count; i++) {
    particles.push({
      x: Math.random() * W,
      y: Math.random() * H,
      vx: (Math.random() - 0.5) * 0.4,
      vy: (Math.random() - 0.5) * 0.4,
      r: Math.random() * 2 + 0.5,
      a: Math.random() * 0.5 + 0.1,
      col: ["#3B72F0", "#8B45F5", "#E5283D"][Math.floor(Math.random() * 3)],
    });
  }

  function draw() {
    ctx.clearRect(0, 0, W, H);
    particles.forEach((p) => {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0) p.x = W;
      if (p.x > W) p.x = 0;
      if (p.y < 0) p.y = H;
      if (p.y > H) p.y = 0;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = p.col;
      ctx.globalAlpha = p.a;
      ctx.fill();
    });
    // Draw connections
    ctx.globalAlpha = 1;
    particles.forEach((a, i) => {
      particles.slice(i + 1).forEach((b) => {
        const d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d < 120) {
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.strokeStyle = a.col;
          ctx.globalAlpha = (1 - d / 120) * 0.12;
          ctx.lineWidth = 0.6;
          ctx.stroke();
        }
      });
    });
    requestAnimationFrame(draw);
  }
  draw();
  window.addEventListener("resize", () => {
    W = canvas.width = window.innerWidth;
    H = canvas.height = window.innerHeight;
  });
}

function initBubbles() {
  const container = document.getElementById("bubbles");
  const colors = [
    "rgba(34,81,197,0.3)",
    "rgba(107,33,212,0.25)",
    "rgba(192,25,42,0.25)",
    "rgba(59,114,240,0.2)",
    "rgba(139,69,245,0.2)",
    "rgba(229,40,61,0.15)",
    "rgba(34,81,197,0.15)",
    "rgba(107,33,212,0.15)",
  ];
  for (let i = 0; i < 14; i++) {
    const b = document.createElement("div");
    b.className = "bubble";
    const size = Math.random() * 100 + 30;
    b.style.cssText = `
      width:${size}px;height:${size}px;
      left:${Math.random() * 100}%;
      background:${colors[Math.floor(Math.random() * colors.length)]};
      border:1px solid rgba(255,255,255,0.05);
      backdrop-filter:blur(2px);
      animation-duration:${Math.random() * 20 + 15}s;
      animation-delay:${Math.random() * 10}s;
    `;
    container.appendChild(b);
  }
}

/* ══════════════════════════════════════════════════════
   API HELPER
══════════════════════════════════════════════════════ */
async function api(method, endpoint, body) {
  const opts = {
    method,
    credentials: "include",
    headers: { "Content-Type": "application/json" },
  };
  if (body) opts.body = JSON.stringify(body);
  try {
    const r = await fetch(API + endpoint, opts);
    return await r.json();
  } catch (e) {
    return { ok: false, message: "Error de conexión: " + e.message };
  }
}

/* ══════════════════════════════════════════════════════
   TOAST
══════════════════════════════════════════════════════ */
function toast(msg, type = "") {
  const t = document.getElementById("toast");
  t.textContent = msg;
  t.className = "toast show" + (type ? " " + type : "");
  setTimeout(() => (t.className = "toast"), 3000);
}

/* ══════════════════════════════════════════════════════
   AUTH
══════════════════════════════════════════════════════ */
async function checkAuth() {
  const r = await api("GET", "/api/auth/me");
  if (r.ok && r.authenticated) {
    STATE.user = r.user;
    showApp();
  }
}

async function doLogin() {
  const email = document.getElementById("login-email").value.trim();
  const pass = document.getElementById("login-pass").value;
  const btn = document.getElementById("login-btn");
  const errEl = document.getElementById("login-error");
  errEl.style.display = "none";
  if (!email || !pass) {
    errEl.textContent = "Completa todos los campos.";
    errEl.style.display = "block";
    return;
  }
  btn.disabled = true;
  document.getElementById("login-btn-text").innerHTML =
    '<span class="spinner"></span> Verificando...';
  const r = await api("POST", "/api/auth/login", { email, password: pass });
  if (r.ok) {
    STATE.user = r.user;
    document.getElementById("login-page").classList.add("hide");
    setTimeout(showApp, 400);
  } else {
    errEl.textContent = r.message || "Credenciales inválidas.";
    errEl.style.display = "block";
    btn.disabled = false;
    document.getElementById("login-btn-text").textContent =
      "Ingresar a la plataforma";
  }
}

async function fillDemo() {
  document.getElementById("login-email").value = "rv@local.test";
  document.getElementById("login-pass").value = "123";
  toast("Credenciales rv precargadas ✓", "success");
}

async function doLogout() {
  await api("POST", "/api/auth/logout");
  location.reload();
}

function showApp() {
  const login = document.getElementById("login-page");
  if (login) login.style.display = "none";
  document.getElementById("app").style.display = "flex";
  document.getElementById("fab").style.display = "flex";
  if (STATE.user) {
    const n = STATE.user.name || "Curriculista";
    const role = STATE.user.role || "curriculista";
    document.getElementById("welcome-name").textContent = n.split(" ")[0];
    document.getElementById("sidebar-name").textContent = n;
    document.getElementById("sidebar-role").textContent =
      role === "superadmin"
        ? "Superadmin"
        : role === "admin"
          ? "Administrador"
          : "Curriculista";
    document.getElementById("sidebar-avatar").textContent = n
      .charAt(0)
      .toUpperCase();
  }
  const requestedPage = (location.hash || "").replace("#", "").trim();
  const firstPage =
    requestedPage && document.getElementById("page-" + requestedPage)
      ? requestedPage
      : "dashboard";
  navigate(firstPage);
  loadDashboard();
  loadFramework();
  initPlanWizard();
  initQuickPrompts();
  if (document.getElementById("rc-type-grid")) window.rcInit();
  if (firstPage === "tecnico") techRefresh();
}

/* ══════════════════════════════════════════════════════
   NAVIGATION
══════════════════════════════════════════════════════ */
const bgMap = {
  dashboard: "bg-mixed",
  malla: "bg-blue",
  plan: "bg-purple",
  silabos: "bg-red",
  recursos: "bg-purple",
  tecnico: "bg-blue",
};

function navigate(page) {
  page = page || "dashboard";
  if (!document.getElementById("page-" + page)) page = "dashboard";
  STATE.page = page;
  document
    .querySelectorAll(".page")
    .forEach((p) => p.classList.remove("active"));
  document
    .querySelectorAll(".nav-item")
    .forEach((n) => n.classList.remove("active"));
  const targetPage = document.getElementById("page-" + page);
  if (targetPage) targetPage.classList.add("active");
  const targetNav = document.querySelector('[data-page="' + page + '"]');
  if (targetNav) targetNav.classList.add("active");
  const bg = document.getElementById("bg-layer");
  if (bg) bg.className = "bg-layer " + (bgMap[page] || "bg-mixed");
  if (page !== "tecnico") {
    if (location.hash !== "#" + page)
      history.replaceState(null, "", "#" + page);
  }
}

/* ══════════════════════════════════════════════════════
   DASHBOARD
══════════════════════════════════════════════════════ */
async function loadDashboard() {
  // Projects
  const r = await api("GET", "/api/curriculum/projects");
  if (r.ok) {
    STATE.projects = r.projects || [];
    document.getElementById("stat-projects").textContent =
      STATE.projects.length;
    renderRecentProjects();
  }
  // Stats
  const rs = await api("GET", "/api/reports/summary");
  if (rs.ok) {
    document.getElementById("stat-syllabi").textContent =
      rs.syllabus_count ?? rs.total_syllabi ?? "—";
  }
  // JoMelAi stats
  const rj = await api("GET", "/api/jomelai/stats");
  if (rj.ok && rj.stats) {
    const stats = rj.stats;
    document.getElementById("stat-queries").textContent =
      stats.total_queries ?? stats.total ?? "—";
  }
  const pub = STATE.projects.filter((p) => p.status === "published").length;
  document.getElementById("stat-published").textContent = pub;
}

function renderRecentProjects() {
  const el = document.getElementById("recent-projects-list");
  if (!STATE.projects.length) {
    el.innerHTML =
      '<div class="empty-state"><div class="es-icon">📂</div><p>No hay proyectos aún. ¡Crea tu primera malla curricular!</p></div>';
    return;
  }
  const cols = [
    "linear-gradient(135deg,#2251C5,#7C3AED)",
    "linear-gradient(135deg,#C0192A,#7C3AED)",
    "linear-gradient(135deg,#C0192A,#E5283D)",
    "linear-gradient(135deg,#6B21D4,#2251C5)",
  ];
  el.innerHTML = STATE.projects
    .slice(0, 5)
    .map(
      (p, i) => `
    <div class="project-card">
      <div class="project-icon" style="background:${cols[i % cols.length]}">📁</div>
      <div class="project-info">
        <h4>${esc(p.program)}</h4>
        <p>${esc(p.faculty)} · ${p.cycles} ciclos · ${p.target_credits} créditos</p>
      </div>
      <div class="project-status ${p.status === "published" ? "status-published" : "status-draft"}">${p.status === "published" ? "Publicado" : "Borrador"}</div>
    </div>
  `,
    )
    .join("");
}

async function dashAsk() {
  const q = document.getElementById("dash-ask-input").value.trim();
  if (!q) return;
  openAiPanel();
  await sendAiMessageWith(q);
  document.getElementById("dash-ask-input").value = "";
}

/* ══════════════════════════════════════════════════════
   AI PANEL
══════════════════════════════════════════════════════ */
function toggleAiPanel() {
  const panel = document.getElementById("ai-panel");
  panel.classList.toggle("open");
}
function openAiPanel() {
  document.getElementById("ai-panel").classList.add("open");
}

async function sendAiMessage() {
  const input = document.getElementById("ai-panel-input");
  const q = input.value.trim();
  if (!q) return;
  input.value = "";
  await sendAiMessageWith(q);
}

async function sendAiMessageWith(question) {
  const body = document.getElementById("ai-panel-body");
  body.innerHTML += `<div class="ai-msg"><div class="ai-msg-user">${esc(question)}</div></div>`;
  const thinking = document.createElement("div");
  thinking.className = "ai-msg";
  thinking.innerHTML =
    '<div class="ai-thinking"><span></span><span></span><span></span></div>';
  body.appendChild(thinking);
  body.scrollTop = body.scrollHeight;
  const r = await api("POST", '/api/chat-lateral/ask', {
    question,
    context: "user",
    options: { table: "silabos" },
  });
  body.removeChild(thinking);
  if (r.ok || r.answer || r.message) {
    const intentHtml = r.visible_intent
      ? `<div class="ai-intent">🎯 ${r.visible_intent}</div>`
      : "";
    const text = r.answer || r.message || "No se pudo procesar la consulta.";
    const chartHtml = renderAiChart(r);
    const tableHtml = renderAiTable(r);
    body.innerHTML += `<div class="ai-msg"><div class="ai-msg-bot">${intentHtml}${nl2br(esc(text))}${chartHtml}${tableHtml}</div></div>`;
  } else {
    body.innerHTML += `<div class="ai-msg"><div class="ai-msg-bot" style="color:var(--red-300)">⚠️ ${esc(r.message || "Error al procesar.")}</div></div>`;
  }
  body.scrollTop = body.scrollHeight;
}

function renderAiChart(r) {
  const chart = r.chart || null;
  const b64 =
    chart?.image_base64 || chart?.chart?.image_base64 || r.image_base64;
  if (!b64) return "";
  const src = b64.startsWith("data:") ? b64 : `data:image/png;base64,${b64}`;
  return `<div class="ai-result-chart"><img src="${src}" alt="Gráfico generado por JoMelAi"></div>`;
}
function renderAiTable(r) {
  const table = r.table || r.query || r.chart?.table || r.chart?.query || null;
  const rows = table?.rows || [];
  if (!Array.isArray(rows) || !rows.length) return "";
  const columns =
    table.columns && table.columns.length
      ? table.columns
      : Object.keys(rows[0] || {});
  const head = columns.map((c) => `<th>${esc(String(c))}</th>`).join("");
  const bodyRows = rows
    .slice(0, 8)
    .map(
      (row) =>
        `<tr>${columns.map((c) => `<td>${esc(String(row[c] ?? ""))}</td>`).join("")}</tr>`,
    )
    .join("");
  return `<div class="ai-result-table"><table><thead><tr>${head}</tr></thead><tbody>${bodyRows}</tbody></table></div>`;
}

/* ══════════════════════════════════════════════════════
   FRAMEWORK / MALLA
══════════════════════════════════════════════════════ */
async function loadFramework() {
  const r = await api("GET", "/api/curriculum/framework");
  if (!r.ok) return;
  STATE.planSteps = r.wizard || [];
  const el = document.getElementById("framework-principles");
  el.innerHTML = (r.principles || [])
    .map(
      (p, i) => `
    <div style="display:flex;gap:10px;align-items:flex-start">
      <div style="min-width:20px;height:20px;border-radius:5px;background:rgba(59,114,240,0.25);display:flex;align-items:center;justify-content:center;font-size:10px;font-weight:800;margin-top:2px">${i + 1}</div>
      <div style="font-size:12px;color:var(--text-secondary);line-height:1.5">${esc(p)}</div>
    </div>
  `,
    )
    .join("");
}

async function generateMalla() {
  const faculty = document.getElementById("m-faculty").value.trim();
  const program = document.getElementById("m-program").value.trim();
  const cycles = parseInt(document.getElementById("m-cycles").value) || 10;
  const target_credits =
    parseInt(document.getElementById("m-credits").value) || 200;
  const profile_text = document.getElementById("m-profile").value.trim();
  const emphasis = document.getElementById("m-emphasis").value.trim();
  if (!faculty || !program) {
    toast("Completa Facultad y Programa", "error");
    return;
  }
  const btn = document.getElementById("btn-gen-malla");
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> JoMelAi generando...';
  const r = await api("POST", "/api/curriculum/generate-plan", {
    faculty,
    program,
    cycles,
    target_credits,
    profile_text,
    emphasis,
    use_ai: true,
  });
  btn.disabled = false;
  btn.innerHTML = "🤖 Generar con JoMelAi";
  if (!r.ok) {
    toast(r.message || "Error al generar", "error");
    return;
  }
  STATE.mallaResult = r;
  renderMallaResult(r, program, faculty, cycles, target_credits);
}

function renderMallaResult(r, program, faculty, cycles, credits) {
  document.getElementById("malla-result-section").style.display = "block";
  document.getElementById("malla-meta").textContent =
    `${faculty} · ${program} · ${cycles} ciclos · ${credits} créditos`;
  const grid = document.getElementById("malla-grid");
  const plan = r.plan || {};
  const coursesData = plan.courses_by_cycle || {};
  if (Object.keys(coursesData).length > 0) {
    grid.innerHTML = Object.entries(coursesData)
      .map(
        ([cycle, courses]) => `
      <div class="cycle-row">
        <div class="cycle-label">CICLO<br>${cycle}</div>
        <div class="cycle-courses">
          ${(courses || [])
            .map(
              (c) => `
            <div class="course-chip">
              ${esc(c.name || c)}
              ${c.credits ? `<span class="chip-credits">${c.credits} cr</span>` : ""}
            </div>
          `,
            )
            .join("")}
        </div>
      </div>
    `,
      )
      .join("");
  } else {
    grid.innerHTML = "";
  }
  if (r.ai_note || r.markdown) {
    const noteEl = document.getElementById("malla-ai-note");
    noteEl.textContent = r.ai_note || r.markdown || "";
    noteEl.style.display = "block";
  }
  document
    .getElementById("malla-result-section")
    .scrollIntoView({ behavior: "smooth" });
  toast("✅ Malla generada exitosamente", "success");
}

async function saveMallaProject() {
  const faculty = document.getElementById("m-faculty").value.trim();
  const program = document.getElementById("m-program").value.trim();
  if (!faculty || !program) {
    toast("Completa Facultad y Programa", "error");
    return;
  }
  const r = await api("POST", "/api/curriculum/projects", {
    faculty,
    program,
    cycles: parseInt(document.getElementById("m-cycles").value) || 10,
    target_credits: parseInt(document.getElementById("m-credits").value) || 200,
    profile_text: document.getElementById("m-profile").value,
    modality: "Presencial",
  });
  if (r.ok) {
    toast("✅ Proyecto guardado", "success");
    loadDashboard();
  } else {
    toast(r.message || "Error al guardar", "error");
  }
}

function copyMalla() {
  const text = document.getElementById("malla-ai-note").textContent;
  navigator.clipboard
    .writeText(text)
    .then(() => toast("✅ Copiado al portapapeles", "success"));
}

/* ══════════════════════════════════════════════════════
   PLAN DE ESTUDIOS — WIZARD
══════════════════════════════════════════════════════ */
const PLAN_FIELDS = [
  [
    {
      id: "pf-program",
      label: "Programa académico",
      ph: "Ej: Ingeniería de Sistemas",
    },
    {
      id: "pf-faculty",
      label: "Facultad",
      ph: "Ej: Facultad de Ingeniería y Arquitectura",
    },
    {
      id: "pf-modality",
      label: "Modalidad",
      ph: "Presencial / Virtual / Semipresencial",
      type: "select",
      opts: ["Presencial", "Virtual", "Semipresencial"],
    },
    { id: "pf-cycles", label: "Duración (ciclos)", ph: "10", type: "number" },
    { id: "pf-credits", label: "Créditos totales", ph: "200", type: "number" },
    {
      id: "pf-purpose",
      label: "Propósito formativo",
      ph: "Describe el propósito de la carrera...",
      type: "textarea",
    },
  ],
  [
    {
      id: "pf-competencies",
      label: "Competencias profesionales del egresado",
      ph: "Lista las competencias principales...",
      type: "textarea",
    },
    {
      id: "pf-values",
      label: "Formación integral y valores",
      ph: "Ética, servicio, fe-aprendizaje, ética profesional...",
      type: "textarea",
    },
  ],
  [
    {
      id: "pf-malla-note",
      label: "Observaciones para la malla",
      ph: "Areas formativas, énfasis curricular, prerrequisitos especiales...",
      type: "textarea",
    },
  ],
  [
    {
      id: "pf-competency-map",
      label: "Relación cursos-competencias (descripción)",
      ph: "¿Cómo se distribuyen las competencias a través de los cursos?",
      type: "textarea",
    },
  ],
  [
    {
      id: "pf-coherence",
      label: "Observaciones de coherencia vertical/horizontal",
      ph: "Progresión académica, distribución crediticia...",
      type: "textarea",
    },
  ],
  [
    {
      id: "pf-version-notes",
      label: "Notas de la versión curricular",
      ph: "Cambios principales respecto a versión anterior...",
      type: "textarea",
    },
  ],
];

function initPlanWizard() {
  renderPlanSteps();
  renderPlanStep(0);
}

function renderPlanSteps() {
  const stepsEl = document.getElementById("plan-wizard-steps");
  const steps = STATE.planSteps.length
    ? STATE.planSteps
    : [
        { title: "Proyecto" },
        { title: "Perfil" },
        { title: "Malla" },
        { title: "Competencias" },
        { title: "Plan" },
        { title: "Versión" },
      ];
  stepsEl.innerHTML = steps
    .map(
      (s, i) => `
    <div class="wizard-step ${i === STATE.planStep ? "active" : i < STATE.planStep ? "done" : ""}" onclick="goToPlanStep(${i})">
      <div class="step-num">${i < STATE.planStep ? "✓" : i + 1}</div>
      ${s.title || s.step}
    </div>
  `,
    )
    .join("");

  const dots = document.getElementById("plan-step-dots");
  dots.innerHTML = steps
    .map(
      (_, i) =>
        `<div class="psi-dot ${i === STATE.planStep ? "active" : i < STATE.planStep ? "done" : ""}"></div>`,
    )
    .join("");
}

function renderPlanStep(idx) {
  const steps = STATE.planSteps.length
    ? STATE.planSteps
    : [
        { title: "Proyecto", description: "" },
        { title: "Perfil de egreso", description: "" },
        { title: "Malla curricular", description: "" },
        { title: "Mapa de competencias", description: "" },
        { title: "Plan de estudios", description: "" },
        { title: "Versión y aprobación", description: "" },
      ];
  const step = steps[idx] || {};
  document.getElementById("plan-step-title").textContent =
    `Paso ${idx + 1}: ${step.title || ""}`;
  document.getElementById("plan-step-desc").textContent =
    step.description || "";
  const fields = PLAN_FIELDS[idx] || [];
  const content = document.getElementById("plan-step-content");
  content.innerHTML = fields
    .map((f) => {
      const saved = STATE.planData[f.id] || "";
      if (f.type === "textarea")
        return `<div class="field-group"><label class="field-label">${f.label}</label><textarea class="field-textarea" id="${f.id}" placeholder="${f.ph}" style="min-height:90px">${saved}</textarea></div>`;
      if (f.type === "select")
        return `<div class="field-group"><label class="field-label">${f.label}</label><select class="field-select field-input" id="${f.id}">${(f.opts || []).map((o) => `<option ${o === saved ? "selected" : ""}>${o}</option>`).join("")}</select></div>`;
      return `<div class="field-group"><label class="field-label">${f.label}</label><input class="field-input" id="${f.id}" placeholder="${f.ph}" type="${f.type || "text"}" value="${saved}"></div>`;
    })
    .join("");
  document.getElementById("btn-plan-prev").style.display =
    idx > 0 ? "flex" : "none";
  const nextBtn = document.getElementById("btn-plan-next");
  if (idx === steps.length - 1) {
    nextBtn.textContent = "🤖 Generar plan completo";
    nextBtn.className = "btn btn-purple";
  } else {
    nextBtn.textContent = "Siguiente →";
    nextBtn.className = "btn btn-blue";
  }
}

function savePlanStepData() {
  const fields = PLAN_FIELDS[STATE.planStep] || [];
  fields.forEach((f) => {
    const el = document.getElementById(f.id);
    if (el) STATE.planData[f.id] = el.value;
  });
}

function planNext() {
  savePlanStepData();
  const maxStep = (STATE.planSteps.length || 6) - 1;
  if (STATE.planStep === maxStep) {
    generateFullPlan();
    return;
  }
  STATE.planStep = Math.min(STATE.planStep + 1, maxStep);
  renderPlanSteps();
  renderPlanStep(STATE.planStep);
}

function planPrev() {
  savePlanStepData();
  STATE.planStep = Math.max(STATE.planStep - 1, 0);
  renderPlanSteps();
  renderPlanStep(STATE.planStep);
}

function goToPlanStep(i) {
  savePlanStepData();
  STATE.planStep = i;
  renderPlanSteps();
  renderPlanStep(STATE.planStep);
}

async function planAskAi() {
  savePlanStepData();
  const step = STATE.planSteps[STATE.planStep] || {};
  const q = `Soy un curriculista en el paso: "${step.title || "diseño curricular"}". ${step.description || ""} ¿Qué me recomiendas para este paso? Programa: ${STATE.planData["pf-program"] || "por definir"}.`;
  openAiPanel();
  await sendAiMessageWith(q);
}

async function generateFullPlan() {
  savePlanStepData();
  const d = STATE.planData;
  const btn = document.getElementById("btn-plan-next");
  btn.disabled = true;
  btn.textContent = "⏳ Generando...";
  const r = await api("POST", "/api/curriculum/generate-plan", {
    faculty: d["pf-faculty"] || "",
    program: d["pf-program"] || "",
    cycles: parseInt(d["pf-cycles"]) || 10,
    target_credits: parseInt(d["pf-credits"]) || 200,
    profile_text: d["pf-competencies"] || "",
    emphasis: d["pf-values"] || "",
    use_ai: true,
  });
  btn.disabled = false;
  btn.textContent = "🤖 Generar plan completo";
  if (r.ok) {
    document.getElementById("plan-result-section").style.display = "block";
    document.getElementById("plan-ai-output").textContent =
      r.ai_note || r.markdown || JSON.stringify(r.plan || {}, null, 2);
    document
      .getElementById("plan-result-section")
      .scrollIntoView({ behavior: "smooth" });
    toast("✅ Plan generado", "success");
  } else {
    toast(r.message || "Error al generar el plan", "error");
  }
}

function copyPlan() {
  const t = document.getElementById("plan-ai-output").textContent;
  navigator.clipboard.writeText(t).then(() => toast("✅ Copiado", "success"));
}

async function savePlanVersion() {
  const projectId = STATE.projects[0]?.id;
  if (!projectId) {
    toast("Primero guarda un proyecto en Malla Curricular", "error");
    return;
  }
  const content = document.getElementById("plan-ai-output").textContent;
  const r = await api(
    "POST",
    `/api/curriculum/projects/${projectId}/versions`,
    { content, notes: "Versión generada por JoMelAi" },
  );
  if (r.ok) toast("✅ Versión guardada", "success");
  else toast(r.message || "Error al guardar", "error");
}

/* ══════════════════════════════════════════════════════
   SÍLABOS
══════════════════════════════════════════════════════ */
function switchSilaboTab(tab, el) {
  document
    .querySelectorAll(".tab")
    .forEach((t) => t.classList.remove("active"));
  el.classList.add("active");
  document.getElementById("silabo-tab-generate").style.display =
    tab === "generate" ? "block" : "none";
  document.getElementById("silabo-tab-search").style.display =
    tab === "search" ? "block" : "none";
}

async function generateSilabo() {
  const course = document.getElementById("s-course").value.trim();
  if (!course) {
    toast("El nombre del curso es obligatorio", "error");
    return;
  }

  const btn = document.getElementById("btn-gen-silabo");
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> JoMelAi generando sílabo...';

  const payload = {
    course,
    program: document.getElementById("s-program").value,
    credits: document.getElementById("s-credits").value,
    cycle: document.getElementById("s-cycle").value,
    weeks: document.getElementById("s-weeks").value,
    modality: document.getElementById("s-modal").value,
    graduate_profile: document.getElementById("s-profile").value,
    competency: document.getElementById("s-competency").value,
  };

  const r = await api("POST", "/api/assistant/generate-syllabus", payload);

  btn.disabled = false;
  btn.innerHTML = "🤖 Generar sílabo con JoMelAi";

  const raw = pickSyllabusText(r);

  if (r.ok && raw) {
    STATE.silaboResult = {
      raw,
      html: "",
      payload,
      response: r,
      savedAt: null,
    };

    document.getElementById("silabo-result").style.display = "block";
    renderSilaboDocument(raw, payload);

    document
      .getElementById("silabo-result")
      .scrollIntoView({ behavior: "smooth" });
    toast("✅ Sílabo generado", "success");
  } else {
    toast(r.message || "Error al generar el sílabo", "error");
  }
}

function pickSyllabusText(r) {
  if (!r) return "";
  return String(
    r.response || r.answer || r.markdown || r.summary || r.message || "",
  ).trim();
}

function renderSilaboDocument(raw, meta) {
  const htmlEl = document.getElementById("silabo-html");
  const rawEl = document.getElementById("silabo-text");

  const title = meta.course || "Curso sin nombre";
  const program = meta.program || "Programa no especificado";
  const credits = meta.credits || "—";
  const cycle = meta.cycle || "—";
  const weeks = meta.weeks || "—";
  const modality = meta.modality || "—";

  const bodyHtml = markdownToSyllabusHtml(raw);

  htmlEl.innerHTML = `
    <header class="syllabus-cover">
      <div class="syllabus-brand">
        <div class="syllabus-logo">JM</div>
        <div>
          <div class="syllabus-kicker">JoMelAi Curriculista</div>
          <h1>Sílabo preliminar</h1>
        </div>
      </div>

      <div class="syllabus-title-box">
        <h2>${esc(title)}</h2>
        <p>${esc(program)}</p>
      </div>

      <div class="syllabus-meta-grid">
        <div><span>Créditos</span><strong>${esc(credits)}</strong></div>
        <div><span>Ciclo</span><strong>${esc(cycle)}</strong></div>
        <div><span>Semanas</span><strong>${esc(weeks)}</strong></div>
        <div><span>Modalidad</span><strong>${esc(modality)}</strong></div>
      </div>

      <div class="syllabus-warning">
        Propuesta preliminar generada por IA. Debe ser revisada por el docente y validada por el comité curricular.
      </div>
    </header>

    ${bodyHtml}
  `;

  rawEl.value = raw;
  STATE.silaboResult.html = htmlEl.innerHTML;

  rebuildSilaboIndex();
}

function markdownToSyllabusHtml(markdown) {
  const lines = String(markdown || "")
    .replace(/^```(?:markdown|md)?/i, "")
    .replace(/```$/i, "")
    .replace(/\r\n/g, "\n")
    .split("\n");

  let html = "";
  let listOpen = false;

  function closeList() {
    if (listOpen) {
      html += "</ul>";
      listOpen = false;
    }
  }

  function openSection(title, level) {
    closeList();

    const tag = level <= 2 ? "h2" : "h3";
    const id = slugify(title);

    if (tag === "h2") {
      html += `
        <section class="syllabus-section" data-section="${esc(title)}">
          <${tag} id="${id}">${inlineMd(title)}</${tag}>
      `;
    } else {
      html += `<${tag} id="${id}">${inlineMd(title)}</${tag}>`;
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const line = rawLine.trim();

    if (!line) {
      closeList();
      continue;
    }

    if (isMarkdownTableStart(lines, i)) {
      closeList();
      const parsed = parseMarkdownTable(lines, i);
      html += parsed.html;
      i = parsed.nextIndex;
      continue;
    }

    const heading = line.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      const level = heading[1].length;
      const title = cleanHeading(heading[2]);
      openSection(title, level);
      continue;
    }

    const bullet = line.match(/^[-*]\s+(.+)$/);
    if (bullet) {
      if (!listOpen) {
        html += '<ul class="syllabus-list">';
        listOpen = true;
      }
      html += `<li>${inlineMd(bullet[1])}</li>`;
      continue;
    }

    const numbered = line.match(/^\d+\.\s+(.+)$/);
    if (numbered) {
      if (!listOpen) {
        html += '<ul class="syllabus-list numbered">';
        listOpen = true;
      }
      html += `<li>${inlineMd(numbered[1])}</li>`;
      continue;
    }

    closeList();

    if (line.includes(":") && line.length < 180) {
      const parts = line.split(":");
      const label = parts.shift();
      const value = parts.join(":").trim();

      html += `
        <div class="syllabus-field">
          <strong>${inlineMd(label)}:</strong>
          <span>${inlineMd(value)}</span>
        </div>
      `;
    } else {
      html += `<p>${inlineMd(line)}</p>`;
    }
  }

  closeList();

  return html || "<p>No se pudo interpretar el contenido del sílabo.</p>";
}

function inlineMd(text) {
  let s = esc(String(text || ""));

  s = s.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\*(.+?)\*/g, "<em>$1</em>");
  s = s.replace(/`(.+?)`/g, "<code>$1</code>");

  return s;
}

function cleanHeading(text) {
  return String(text || "")
    .replace(/\*\*/g, "")
    .replace(/:$/g, "")
    .trim();
}

function slugify(text) {
  return (
    String(text || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .substring(0, 70) || "sec-" + Date.now()
  );
}

function isMarkdownTableStart(lines, index) {
  const current = String(lines[index] || "").trim();
  const next = String(lines[index + 1] || "").trim();

  return (
    current.includes("|") &&
    /^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(next)
  );
}

function parseMarkdownTable(lines, startIndex) {
  let i = startIndex;
  const rows = [];

  while (i < lines.length) {
    const line = String(lines[i] || "").trim();
    if (!line.includes("|")) break;

    if (!/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/.test(line)) {
      rows.push(
        line
          .replace(/^\|/, "")
          .replace(/\|$/, "")
          .split("|")
          .map((c) => inlineMd(c.trim())),
      );
    }

    i++;
  }

  if (!rows.length) {
    return { html: "", nextIndex: startIndex };
  }

  const headers = rows.shift();
  const headHtml = headers.map((h) => `<th>${h}</th>`).join("");
  const bodyHtml = rows
    .map(
      (row) => `
    <tr>${headers.map((_, idx) => `<td>${row[idx] || ""}</td>`).join("")}</tr>
  `,
    )
    .join("");

  return {
    html: `
      <div class="syllabus-table-wrap">
        <table class="syllabus-table">
          <thead><tr>${headHtml}</tr></thead>
          <tbody>${bodyHtml}</tbody>
        </table>
      </div>
    `,
    nextIndex: i - 1,
  };
}

function rebuildSilaboIndex() {
  const index = document.getElementById("silabo-index");
  const doc = document.getElementById("silabo-html");

  if (!index || !doc) return;

  const headings = [...doc.querySelectorAll("h2, h3")];

  if (!headings.length) {
    index.innerHTML = "";
    return;
  }

  index.innerHTML = `
    <div class="syllabus-index-title">Secciones</div>
    ${headings
      .map((h) => {
        if (!h.id) h.id = slugify(h.textContent);
        return `
        <button class="${h.tagName === "H3" ? "sub" : ""}" onclick="document.getElementById('${h.id}').scrollIntoView({behavior:'smooth',block:'start'})">
          ${esc(h.textContent)}
        </button>
      `;
      })
      .join("")}
  `;
}

function getCurrentSilaboHtml() {
  const el = document.getElementById("silabo-html");
  return el ? el.innerHTML.trim() : "";
}

function getCurrentSilaboText() {
  const el = document.getElementById("silabo-html");
  return el ? el.innerText.trim() : "";
}

function saveSilaboDraft() {
  const html = getCurrentSilaboHtml();
  const text = getCurrentSilaboText();

  if (!html) {
    toast("No hay sílabo para guardar", "error");
    return;
  }

  const draft = {
    html,
    text,
    payload: STATE.silaboResult?.payload || {},
    savedAt: new Date().toISOString(),
  };

  localStorage.setItem("jomelai_silabo_draft", JSON.stringify(draft));

  if (STATE.silaboResult) {
    STATE.silaboResult.html = html;
    STATE.silaboResult.raw = text;
    STATE.silaboResult.savedAt = draft.savedAt;
  }

  toast("💾 Borrador guardado en este navegador", "success");
}

function copySilabo() {
  const text = getCurrentSilaboText() || STATE.silaboResult?.raw || "";

  if (!text) {
    toast("No hay contenido para copiar", "error");
    return;
  }

  navigator.clipboard.writeText(text).then(() => {
    toast("✅ Sílabo copiado", "success");
  });
}

function downloadSilaboPdf() {
  const html = getCurrentSilaboHtml();

  if (!html) {
    toast("No hay sílabo para descargar", "error");
    return;
  }

  saveSilaboDraft();

  const course = STATE.silaboResult?.payload?.course || "silabo";
  const oldTitle = document.title;

  document.title = "Silabo - " + course;
  document.body.classList.add("printing-syllabus");

  setTimeout(() => {
    window.print();

    setTimeout(() => {
      document.body.classList.remove("printing-syllabus");
      document.title = oldTitle;
    }, 500);
  }, 150);
}

async function searchSilabos() {
  const q = document.getElementById("silabo-search-q").value.trim();
  if (!q) return;
  const el = document.getElementById("silabo-search-results");
  el.innerHTML =
    '<div style="text-align:center;padding:20px;color:var(--text-muted)"><span class="spinner"></span> Buscando...</div>';
  const r = await api(
    "GET",
    `/api/syllabi/search?q=${encodeURIComponent(q)}&limit=10`,
  );
  if (!r.ok || !r.results?.length) {
    el.innerHTML =
      '<div class="empty-state"><div class="es-icon">🔍</div><p>No se encontraron resultados para "' +
      esc(q) +
      '"</p></div>';
    return;
  }
  el.innerHTML = r.results
    .map(
      (s) => `
    <div class="project-card" style="margin-bottom:10px">
      <div class="project-icon" style="background:linear-gradient(135deg,#C0192A,#7C3AED)">📄</div>
      <div class="project-info">
        <h4>${esc(s.course_name || s.name || s.title || "Sílabo")}</h4>
        <p>${esc(s.program || "")} ${s.cycle ? "· Ciclo " + esc(s.cycle) : ""} ${s.credits ? "· " + s.credits + " cr" : ""}</p>
      </div>
    </div>
  `,
    )
    .join("");
}

/* ══════════════════════════════════════════════════════
   RECURSOS DE APRENDIZAJE v2 — UPeU · JoMelAi
══════════════════════════════════════════════════════ */
/* ══════════════════════════════════════════════════════
   RECURSOS DE APRENDIZAJE v2 — UPeU · JoMelAi
   Reemplazar el bloque "RECURSOS DE APRENDIZAJE" en app.js
   (desde "function selectResourceType" hasta "function copyResource")
   y AGREGAR la llamada window.rcInit() al final del bloque
   DOMContentLoaded o después de showApp().
══════════════════════════════════════════════════════ */

/* ─── 1. DATA: UPEU – Facultades, Escuelas y Cursos ─── */
const UPEU_DATA = {
  "Ciencias de la Salud": {
    Enfermería: [
      "Anatomía y Fisiología Humana",
      "Bioquímica",
      "Microbiología y Parasitología",
      "Farmacología Clínica",
      "Cuidados de Enfermería I",
      "Cuidados de Enfermería II",
      "Cuidados de Enfermería III",
      "Salud del Niño y del Adolescente",
      "Salud del Adulto Mayor",
      "Salud Comunitaria y Familiar",
      "Enfermería Materno Perinatal",
      "Salud Mental y Psiquiatría",
      "Gestión en Servicios de Salud",
      "Bioética y Deontología Profesional",
      "Metodología de la Investigación",
      "Epidemiología",
      "Internado Hospitalario I",
      "Internado Hospitalario II",
      "Investigación en Salud",
    ],
    "Medicina Humana": [
      "Anatomía Humana I",
      "Anatomía Humana II",
      "Bioquímica Médica",
      "Histología y Embriología",
      "Fisiología Médica",
      "Genética Médica",
      "Microbiología y Parasitología",
      "Farmacología General",
      "Patología General",
      "Semiología Médica",
      "Medicina Interna I",
      "Medicina Interna II",
      "Cirugía General I",
      "Cirugía General II",
      "Pediatría I",
      "Pediatría II",
      "Ginecología y Obstetricia",
      "Neurología",
      "Psiquiatría",
      "Salud Pública y Epidemiología",
      "Bioética Médica",
      "Medicina de Emergencias",
      "Dermatología",
      "Oftalmología",
      "Otorrinolaringología",
    ],
    "Nutrición y Dietética": [
      "Bioquímica de los Alimentos",
      "Fisiología de la Nutrición",
      "Bromatología I",
      "Bromatología II",
      "Dietética I",
      "Dietética II",
      "Dietoterapia",
      "Nutrición Comunitaria",
      "Tecnología de Alimentos",
      "Evaluación Nutricional",
      "Epidemiología Nutricional",
      "Nutrición del Ciclo de Vida",
      "Micronutrientes",
      "Seguridad Alimentaria",
      "Gestión de Servicios de Alimentación",
      "Metodología de la Investigación",
    ],
    Psicología: [
      "Psicología General",
      "Fundamentos de Neurociencias",
      "Psicología del Desarrollo I",
      "Psicología del Desarrollo II",
      "Psicología Social",
      "Estadística Aplicada a Psicología",
      "Psicopatología I",
      "Psicopatología II",
      "Teorías de la Personalidad",
      "Psicología Clínica",
      "Psicología Organizacional",
      "Psicología Educativa",
      "Neuropsicología",
      "Técnicas de Evaluación Psicológica",
      "Psicoterapia I",
      "Psicoterapia II",
      "Orientación y Consejería",
      "Ética Profesional en Psicología",
    ],
    "Obstetricia y Puericultura": [
      "Anatomía del Aparato Reproductor",
      "Fisiología del Embarazo",
      "Obstetricia I",
      "Obstetricia II",
      "Neonatología",
      "Planificación Familiar",
      "Salud Sexual y Reproductiva",
      "Ginecología",
      "Psicoprofilaxis Obstétrica",
      "Bioética en Obstetricia",
      "Salud Pública Materna",
    ],
    "Tecnología Médica (Terapia Física)": [
      "Anatomía Funcional",
      "Kinesiología",
      "Fisioterapia I",
      "Fisioterapia II",
      "Electroterapia",
      "Terapia Manual",
      "Rehabilitación Neurológica",
      "Rehabilitación Traumatológica",
      "Rehabilitación Pediátrica",
      "Agentes Físicos",
      "Ergonomía y Salud Ocupacional",
      "Investigación en Salud",
    ],
  },
  "Ingeniería y Arquitectura": {
    "Ingeniería de Sistemas": [
      "Fundamentos de Programación",
      "Programación Orientada a Objetos",
      "Estructuras de Datos y Algoritmos",
      "Base de Datos I",
      "Base de Datos II",
      "Análisis y Diseño de Sistemas",
      "Ingeniería de Software",
      "Redes y Comunicaciones",
      "Sistemas Operativos",
      "Seguridad Informática",
      "Inteligencia Artificial",
      "Aprendizaje Automático",
      "Desarrollo Web Frontend",
      "Desarrollo Web Backend",
      "Arquitectura de Software",
      "Gestión de Proyectos TI",
      "Sistemas de Información Gerencial",
      "Computación en la Nube",
    ],
    "Ingeniería Civil": [
      "Cálculo Diferencial",
      "Cálculo Integral",
      "Álgebra Lineal",
      "Física General",
      "Topografía",
      "Mecánica de Fluidos",
      "Hidráulica",
      "Estática",
      "Resistencia de Materiales",
      "Análisis Estructural",
      "Mecánica de Suelos I",
      "Mecánica de Suelos II",
      "Concreto Armado I",
      "Concreto Armado II",
      "Diseño de Pavimentos",
      "Saneamiento Ambiental",
      "Construcción y Costos",
      "Gestión de Proyectos",
    ],
    Arquitectura: [
      "Diseño Arquitectónico I",
      "Diseño Arquitectónico II",
      "Diseño Arquitectónico III",
      "Historia de la Arquitectura Universal",
      "Historia de la Arquitectura Peruana",
      "Urbanismo I",
      "Urbanismo II",
      "Instalaciones Sanitarias",
      "Instalaciones Eléctricas",
      "Tecnología Constructiva",
      "Materiales de Construcción",
      "Representación Arquitectónica Digital",
      "Diseño Urbano",
      "Arquitectura Sostenible",
    ],
    "Ingeniería Ambiental": [
      "Ecología y Ecosistemas",
      "Química Ambiental",
      "Biología Ambiental",
      "Contaminación del Aire",
      "Contaminación del Agua",
      "Contaminación del Suelo",
      "Tratamiento de Aguas Residuales",
      "Gestión de Residuos Sólidos",
      "Evaluación de Impacto Ambiental",
      "Legislación Ambiental Peruana",
      "Sistemas de Información Geográfica (SIG)",
      "Remediación de Suelos",
      "Auditoría Ambiental",
      "Gestión Ambiental Empresarial",
    ],
    "Ingeniería Industrial": [
      "Procesos Industriales",
      "Investigación de Operaciones I",
      "Investigación de Operaciones II",
      "Gestión de la Calidad Total",
      "Seguridad e Higiene Industrial",
      "Ergonomía",
      "Gestión de la Cadena de Suministro",
      "Planeamiento y Control de Producción",
      "Simulación de Sistemas",
      "Lean Manufacturing y Kaizen",
      "Gestión de Proyectos",
      "Estadística Industrial",
    ],
  },
  "Ciencias Empresariales": {
    Administración: [
      "Fundamentos de Administración",
      "Contabilidad Básica",
      "Microeconomía",
      "Macroeconomía",
      "Administración de Recursos Humanos",
      "Marketing I",
      "Marketing II",
      "Finanzas I",
      "Finanzas II",
      "Finanzas Corporativas",
      "Gestión Estratégica",
      "Comportamiento Organizacional",
      "Contabilidad Gerencial",
      "Emprendimiento e Innovación",
      "Gestión de Operaciones",
      "Derecho Empresarial",
      "Ética Empresarial Adventista",
      "Negociación y Resolución de Conflictos",
    ],
    Contabilidad: [
      "Contabilidad General I",
      "Contabilidad General II",
      "Contabilidad de Costos I",
      "Contabilidad de Costos II",
      "Contabilidad Gerencial",
      "Auditoría Financiera",
      "Auditoría Interna",
      "Auditoría Tributaria",
      "Tributación Nacional",
      "Análisis de Estados Financieros",
      "Contabilidad Gubernamental",
      "NIIF – Normas Internacionales",
      "Costos y Presupuestos",
      "Ética Profesional Contable",
    ],
    "Negocios Internacionales": [
      "Economía Internacional",
      "Comercio Internacional",
      "Logística y Cadena de Suministro",
      "Logística Internacional",
      "Negociación Internacional",
      "Finanzas Internacionales",
      "Marketing Internacional",
      "Aduanas y Comercio Exterior",
      "Legislación Comercial Internacional",
      "Gestión de Exportaciones e Importaciones",
      "Gestión Aduanera",
      "Tratados de Libre Comercio del Perú",
    ],
    "Marketing y Negocios": [
      "Fundamentos de Marketing",
      "Comportamiento del Consumidor",
      "Investigación de Mercados",
      "Marketing Digital",
      "Branding y Comunicación de Marca",
      "Marketing de Servicios",
      "Publicidad y Creatividad",
      "Gestión de Redes Sociales",
      "Marketing de Contenidos",
      "Analítica de Datos para Marketing",
      "E-Commerce",
    ],
    "Turismo y Hotelería": [
      "Introducción al Turismo",
      "Geografía Turística del Perú",
      "Gestión Hotelera I",
      "Gestión Hotelera II",
      "Gastronomía Peruana",
      "Guiado Turístico",
      "Tour Operación y Agencias de Viajes",
      "Marketing Turístico",
      "Ecoturismo y Turismo Rural",
      "Gestión de Eventos y Congresos",
      "Legislación Turística",
      "Idiomas Aplicados al Turismo",
    ],
  },
  "Ciencias Humanas y Educación": {
    "Educación Primaria": [
      "Psicología Educativa",
      "Didáctica General",
      "Currículo y Programación Curricular",
      "Matemática para Educación Primaria I",
      "Matemática para Educación Primaria II",
      "Comunicación Oral y Escrita",
      "Comprensión Lectora y Producción de Textos",
      "Ciencias Sociales para Primaria",
      "Ciencias Naturales para Primaria",
      "Arte y Cultura para Primaria",
      "Educación Física y Salud",
      "Evaluación del Aprendizaje",
      "Tecnología Educativa",
      "Práctica Profesional I",
      "Práctica Profesional II",
      "Investigación Educativa",
    ],
    "Educación Inicial": [
      "Fundamentos de Educación Inicial",
      "Estimulación Temprana",
      "Psicología del Desarrollo Infantil (0-6 años)",
      "Literatura Infantil",
      "Arte y Expresión Infantil",
      "Didáctica de Educación Inicial",
      "Matemática para Educación Inicial",
      "Comunicación para Educación Inicial",
      "Juego y Aprendizaje",
      "Familia y Comunidad Educativa",
      "Evaluación en Inicial",
    ],
    "Educación – Matemática e Informática": [
      "Álgebra y Geometría",
      "Cálculo Diferencial",
      "Estadística Educativa",
      "Didáctica de la Matemática I",
      "Didáctica de la Matemática II",
      "Informática Educativa",
      "Programación Básica",
      "Tecnología e Innovación Educativa",
      "Historia de la Matemática",
      "Resolución de Problemas Matemáticos",
    ],
    "Educación – Lengua y Literatura": [
      "Gramática del Español",
      "Lingüística General",
      "Fonética y Fonología",
      "Literatura Latinoamericana",
      "Literatura Peruana",
      "Literatura Universal",
      "Didáctica de la Comunicación I",
      "Didáctica de la Comunicación II",
      "Redacción Académica y Científica",
      "Semiótica y Análisis del Discurso",
    ],
    "Ciencias de la Comunicación": [
      "Teoría de la Comunicación",
      "Semiótica y Lenguaje",
      "Periodismo Escrito",
      "Periodismo Digital",
      "Comunicación Audiovisual",
      "Fotografía y Video",
      "Opinión Pública y Medios",
      "Comunicación Organizacional",
      "Relaciones Públicas",
      "Redes Sociales y Periodismo",
      "Ética Periodística",
      "Producción Radial",
      "Producción Televisiva",
    ],
    "Trabajo Social": [
      "Introducción al Trabajo Social",
      "Fundamentos del Trabajo Social",
      "Trabajo Social Individual y Familiar",
      "Trabajo Social de Grupos",
      "Trabajo Social Comunitario",
      "Gerencia Social",
      "Políticas Sociales",
      "Derechos Humanos y Trabajo Social",
      "Trabajo Social en Salud",
      "Trabajo Social Forense",
      "Investigación en Trabajo Social",
    ],
  },
  Teología: {
    Teología: [
      "Biblia: Antiguo Testamento I",
      "Biblia: Antiguo Testamento II",
      "Biblia: Nuevo Testamento I",
      "Biblia: Nuevo Testamento II",
      "Teología Sistemática I – Doctrina de Dios",
      "Teología Sistemática II – Soteriología",
      "Teología Sistemática III – Escatología",
      "Historia de la Iglesia Universal",
      "Historia de la Iglesia Adventista del Séptimo Día",
      "Homilética I",
      "Homilética II",
      "Evangelismo y Misión",
      "Ética Cristiana y Bioética",
      "Consejería Pastoral",
      "Administración Eclesiástica",
      "Teología y Ciencia",
      "Hermenéutica Bíblica",
    ],
  },
  "Escuela de Posgrado": {
    "Maestría en Salud Pública": [
      "Epidemiología Avanzada",
      "Bioestadística",
      "Gestión de Servicios de Salud",
      "Investigación en Salud Pública",
      "Políticas y Sistemas de Salud",
      "Salud Ambiental y Ocupacional",
      "Nutrición en Salud Pública",
    ],
    "Maestría en Gestión Educativa": [
      "Gestión Curricular y Pedagógica",
      "Liderazgo Educativo Adventista",
      "Evaluación y Acreditación Educativa (SINEACE)",
      "Investigación Educativa Avanzada",
      "Políticas Educativas en el Perú",
      "TIC en Gestión Educativa",
    ],
    "Maestría en Gestión Empresarial": [
      "Dirección Estratégica Avanzada",
      "Finanzas Corporativas Avanzadas",
      "Gestión de Proyectos PMI",
      "Innovación y Emprendimiento",
      "Responsabilidad Social Empresarial",
      "Análisis de Datos para Negocios",
    ],
    "Maestría en Ingeniería de Sistemas": [
      "Arquitectura de Sistemas Avanzada",
      "Inteligencia Artificial Aplicada",
      "Seguridad en Sistemas de Información",
      "Gestión de Proyectos TI (PMI/Scrum)",
      "Minería de Datos y Big Data",
    ],
    "MBA – Administración de Negocios": [
      "Estrategia Empresarial",
      "Finanzas Avanzadas",
      "Marketing Estratégico",
      "Gestión de Operaciones y Logística",
      "Liderazgo y Desarrollo Organizacional",
      "Negocios Internacionales",
      "Emprendimiento Corporativo",
    ],
    "Doctorado en Ciencias de la Educación": [
      "Epistemología de la Educación",
      "Filosofía de la Educación Adventista",
      "Investigación Avanzada en Educación",
      "Tendencias en Educación Superior",
    ],
  },
};

/* ─── 2. TIPOS DE RECURSO ─── */
const RC_TYPES = [
  {
    id: "actividad",
    emoji: "🎯",
    label: "Actividad de Aprendizaje",
    desc: "Tarea estructurada con instrucciones, evidencia y cotejo",
    color: "rgba(59,114,240,0.45)",
    bg: "rgba(34,81,197,0.13)",
    text: "#93c5fd",
    sunedu: ["RA", "MET"],
    bloom: "Aplicar · Analizar",
  },
  {
    id: "rubrica",
    emoji: "📊",
    label: "Rúbrica de Evaluación",
    desc: "Tabla analítica con niveles de desempeño y puntajes",
    color: "rgba(192,25,42,0.45)",
    bg: "rgba(192,25,42,0.13)",
    text: "#fca5a5",
    sunedu: ["EVAL", "RA"],
    bloom: "Evaluar",
  },
  {
    id: "sesion",
    emoji: "📋",
    label: "Plan de Sesión",
    desc: "Inicio, proceso y cierre con estrategias y recursos",
    color: "rgba(8,145,178,0.45)",
    bg: "rgba(8,145,178,0.13)",
    text: "#67e8f9",
    sunedu: ["PD", "MET"],
    bloom: "Todos los niveles",
  },
  {
    id: "caso",
    emoji: "🔬",
    label: "Caso Práctico",
    desc: "Situación real peruana con problemas auténticos",
    color: "rgba(234,88,12,0.45)",
    bg: "rgba(234,88,12,0.13)",
    text: "#fdba74",
    sunedu: ["MET", "RA"],
    bloom: "Analizar · Crear",
  },
  {
    id: "secuencia",
    emoji: "🗺️",
    label: "Secuencia Didáctica",
    desc: "Progresión de actividades para una unidad completa",
    color: "rgba(5,150,105,0.45)",
    bg: "rgba(5,150,105,0.13)",
    text: "#6ee7b7",
    sunedu: ["PD", "RA", "MET"],
    bloom: "Progresión completa",
  },
  {
    id: "lectura",
    emoji: "📚",
    label: "Guía de Lectura Crítica",
    desc: "Preguntas guía, organizadores y comprensión profunda",
    color: "rgba(107,33,212,0.45)",
    bg: "rgba(107,33,212,0.13)",
    text: "#c4b5fd",
    sunedu: ["MET", "BIB"],
    bloom: "Comprender · Analizar",
  },
  {
    id: "instrumento",
    emoji: "✅",
    label: "Instrumento de Evaluación",
    desc: "Prueba, lista de cotejo o escala con indicadores SUNEDU",
    color: "rgba(217,119,6,0.45)",
    bg: "rgba(217,119,6,0.13)",
    text: "#fcd34d",
    sunedu: ["EVAL"],
    bloom: "Recordar · Aplicar",
  },
  {
    id: "mapa",
    emoji: "🧠",
    label: "Organizador Gráfico",
    desc: "Mapa conceptual, esquema o red semántica guiada",
    color: "rgba(190,24,93,0.45)",
    bg: "rgba(190,24,93,0.13)",
    text: "#f9a8d4",
    sunedu: ["MET", "RA"],
    bloom: "Comprender · Crear",
  },
];

/* ─── 3. INSTRUCCIONES DETALLADAS POR TIPO ─── */
const RC_INSTRUCTIONS = {
  actividad: `Diseña una ACTIVIDAD DE APRENDIZAJE completa lista para usar, con estas secciones:
1. **Título** y tipo (individual / grupal / colaborativa / basada en proyectos)
2. **Resultado de aprendizaje** que desarrolla (verbo Bloom observable + objeto + condición)
3. **Nivel Bloom** alcanzado y verbos principales utilizados
4. **Duración estimada** y modalidad (presencial / virtual / híbrida)
5. **Instrucciones para el estudiante** — paso a paso, numeradas y claras
6. **Recursos y materiales** necesarios
7. **Producto esperado / Evidencia de aprendizaje** (verificable y concreto)
8. **Lista de cotejo** — mínimo 5 indicadores con Sí / No / En proceso
9. **Integración fe-aprendizaje** — vínculo pertinente con valores adventistas (mayordomía, servicio, ética, vida saludable) sin forzar el contenido
10. **⚠️ Alertas curriculares** — si detectas incoherencias o vacíos SUNEDU`,

  rubrica: `Diseña una RÚBRICA DE EVALUACIÓN ANALÍTICA completa con:
1. **Título**, propósito y resultado de aprendizaje evaluado
2. **Tabla analítica** con mínimo 5 criterios relevantes al curso:
   | Criterio | Destacado (4 pts) | Logrado (3 pts) | En proceso (2 pts) | Inicial (1 pt) |
3. **Descriptores** claros y diferenciados para cada nivel en cada criterio
4. **Ponderación porcentual** de cada criterio (suma exacta 100%)
5. **Puntaje mínimo de aprobación** y tabla de conversión (escala vigesimal)
6. **Instrucciones de uso para el docente** (aplicación y retroalimentación)
7. **Instrucciones de autoevaluación para el estudiante** (antes de entregar)
8. **Nota SUNEDU**: comunicar el instrumento al estudiante antes de la actividad`,

  sesion: `Diseña un PLAN DE SESIÓN DE APRENDIZAJE completo para la UPeU con:
1. **Encabezado institucional**: UPeU | Facultad | Escuela | Curso | Ciclo | Semana/Sesión | Docente
2. **Competencia del curso** y **Resultado de aprendizaje** de la sesión (verbo observable)
3. **INICIO** (15-20 min): motivación contextualizada, recojo de saberes previos, conflicto cognitivo
4. **PROCESO** (50-60 min): actividades de construcción del aprendizaje con estrategias específicas, recursos y TIC si aplica
5. **CIERRE** (15-20 min): metacognición, síntesis colectiva, tarea o producto esperado
6. **Materiales y recursos** (físicos, digitales, bibliografía)
7. **Instrumento de evaluación** de la sesión
8. **Momento de integración fe-aprendizaje** — ubicado dentro del proceso, pertinente y no forzado
9. **Observaciones y posibles ajustes** para diferentes perfiles de estudiante`,

  caso: `Desarrolla un CASO PRÁCTICO APLICADO contextualizado en el Perú con:
1. **Título** y **contexto situacional** (realidad peruana, sector profesional del egresado UPeU)
2. **Descripción del caso** — narrativa de 200-300 palabras, realista y detallada, con datos plausibles
3. **Personajes o actores** involucrados con roles y antecedentes definidos
4. **Datos e información disponible** para el análisis (tablas, valores, indicadores)
5. **Preguntas / tareas de análisis** — mínimo 4, con nivel Bloom explícito por cada una
6. **Guía de respuesta esperada** y criterios de resolución para el docente
7. **Errores comunes** y cómo orientar al estudiante que los comete
8. **Reflexión ética o de valores** (pertinente, académica, no sermón)
9. **Variante de dificultad** — nivel básico y nivel avanzado (extender o reducir complejidad)`,

  secuencia: `Diseña una SECUENCIA DIDÁCTICA para la unidad indicada con:
1. **Mapa de la unidad** — tabla: RA | Contenidos | Evaluación sumativa | N° sesiones
2. **Progresión de sesiones** — tabla: N° | Tema | Estrategia principal | Evidencia | Tiempo
3. **Actividades de apertura** — diagnóstico de saberes previos y activación motivacional
4. **Actividades centrales** de desarrollo — mínimo 3, con nivel Bloom y descripción
5. **Actividades de cierre** y evaluación sumativa de la unidad
6. **Estrategias de diferenciación** para estudiantes con necesidades diversas
7. **Recursos digitales** recomendados y bibliografía alineada al sílabo UPeU
8. **Instrumentos de seguimiento** y feedback formativo durante la unidad
9. **⚠️ Alerta de alineación constructiva**: actividad ↔ RA ↔ evaluación (verificación)`,

  lectura: `Diseña una GUÍA DE LECTURA CRÍTICA completa con:
1. **Datos del texto** — título, autor, año, editorial/fuente, tipo (artículo/libro/reporte), disponibilidad
2. **Propósito de la lectura** en el marco del curso y del RA
3. **Activación de conocimientos previos** — 2-3 preguntas de predicción antes de leer
4. **Preguntas literales** — comprensión directa del texto (mínimo 4, con indicación de página)
5. **Preguntas inferenciales** — análisis, relación y deducción (mínimo 4)
6. **Preguntas críticas y de valoración** — juicio fundamentado y aplicación (mínimo 3)
7. **Organizador gráfico** propuesto — describe tipo (mapa, esquema, tabla, línea de tiempo) y estructura
8. **Síntesis y producto final** del estudiante (formato, extensión, criterios)
9. **Criterios de evaluación** de la guía completada`,

  instrumento: `Diseña un INSTRUMENTO DE EVALUACIÓN completo con:
1. **Tipo y justificación** — prueba escrita / lista de cotejo / escala de apreciación / portafolio
2. **Encabezado institucional**: UPeU | Facultad | Escuela | Curso | Ciclo | Fecha | Docente | Estudiante
3. **Instrucciones claras** para el estudiante (tiempo, materiales permitidos, puntaje)
4. **Ítems o indicadores** — mínimo 10, organizados por nivel Bloom o dimensión evaluada
5. **Para prueba escrita**: distribución de puntaje por sección, tipos de ítem (V/F, opción múltiple, desarrollo)
6. **Para lista de cotejo**: indicadores observables con Sí / No / En proceso
7. **Tabla de especificaciones** — RA evaluado | Nivel Bloom | N° ítems | Puntaje parcial
8. **Criterios de calificación** y nota mínima aprobatoria (escala vigesimal)
9. **Nota SUNEDU**: coherencia con sílabo aprobado; comunicar el instrumento al estudiante antes de la evaluación`,

  mapa: `Diseña un ORGANIZADOR GRÁFICO GUIADO con:
1. **Tipo** — mapa conceptual / red semántica / mapa mental / línea de tiempo / diagrama T / cuadro comparativo
2. **Justificación pedagógica** del tipo elegido para este contenido y nivel
3. **Tema central** y jerarquía: concepto central → ramas principales (3-5) → subconceptos (2-3 por rama)
4. **Palabras de enlace** — verbos y conectores específicos entre conceptos
5. **Representación textual** del mapa completo (listas anidadas con → y conectores)
6. **Instrucciones** para que el estudiante complete o reconstruya el mapa
7. **Versión ESTUDIANTE** — parcialmente completada, con espacios en blanco numerados
8. **Versión DOCENTE (clave)** — versión completa para corrección
9. **Criterios de evaluación** — coherencia jerárquica, conectores, integralidad, precisión conceptual`,
};

/* ─── 4. SUGERENCIAS RÁPIDAS POR ESCUELA ─── */
const RC_QUICK_SUGGESTIONS = {
  Enfermería: [
    "Rúbrica para cuidados de enfermería",
    "Plan de sesión: Farmacología",
    "Caso clínico de Salud Comunitaria",
  ],
  "Medicina Humana": [
    "Caso práctico de Semiología",
    "Rúbrica de ECOE",
    "Plan de sesión: Medicina Interna",
  ],
  "Nutrición y Dietética": [
    "Caso: intervención nutricional",
    "Secuencia: Evaluación Nutricional",
    "Rúbrica de Dietoterapia",
  ],
  Psicología: [
    "Caso de evaluación psicológica",
    "Rúbrica de informe psicológico",
    "Plan de sesión: Psicopatología",
  ],
  "Ingeniería de Sistemas": [
    "Actividad: diseño de base de datos",
    "Rúbrica de proyecto de software",
    "Caso: auditoría de seguridad",
  ],
  "Ingeniería Civil": [
    "Plan de sesión: Mecánica de Suelos",
    "Caso: diseño estructural",
    "Rúbrica de proyecto de construcción",
  ],
  Administración: [
    "Caso empresarial peruano",
    "Rúbrica de plan de negocios",
    "Secuencia: Gestión Estratégica",
  ],
  Contabilidad: [
    "Instrumento: prueba de NIIF",
    "Caso: auditoría tributaria",
    "Rúbrica de estados financieros",
  ],
  "Educación Primaria": [
    "Plan de sesión: Matemática Primaria",
    "Rúbrica de práctica docente",
    "Secuencia: Comunicación",
  ],
  Teología: [
    "Caso de ética pastoral",
    "Plan de sesión: Homilética",
    "Guía de lectura: Teología Sistemática",
  ],
};

/* ─── 5. ESTADO GLOBAL ─── */
STATE.rcType = "actividad";
STATE.rcResult = "";
STATE.rcCurrentTitle = "";

/* ─── 6. INICIALIZACIÓN ─── */
window.rcInit = function () {
  // Los cards de tipo ya están en HTML estático.
  // Aquí solo poblamos el select de Facultad.
  const selFac = document.getElementById("rc-facultad");
  if (!selFac || selFac.dataset.init) return;
  selFac.dataset.init = "1";
  selFac.innerHTML = '<option value="">— Selecciona facultad —</option>';
  Object.keys(UPEU_DATA).forEach((f) => {
    const opt = document.createElement("option");
    opt.value = f;
    opt.textContent = f;
    selFac.appendChild(opt);
  });
  rcUpdatePromptPreview();
};

/* ─── 7. SELECCIÓN DE TIPO ─── */
// Declaración global explícita (compatibilidad máxima con onclick inline)
function rcSelectType(typeId) {
  window.rcSelectType(typeId);
}
function rcOnFacultad() {
  window.rcOnFacultad();
}
function rcOnEscuela() {
  window.rcOnEscuela();
}
function rcOnCurso() {
  window.rcOnCurso();
}
function rcUpdatePromptPreview() {
  if (window.rcUpdatePromptPreview) window.rcUpdatePromptPreview();
}
function rcToggleCtx() {
  if (window.rcToggleCtx) window.rcToggleCtx();
}
function rcTogglePromptPreview() {
  if (window.rcTogglePromptPreview) window.rcTogglePromptPreview();
}
function generateResourceV2() {
  window.generateResourceV2();
}

window.rcSelectType = function (typeId) {
  STATE.rcType = typeId;
  document
    .querySelectorAll(".rc-card")
    .forEach((c) => c.classList.remove("sel"));
  const card = document.getElementById("rc-card-" + typeId);
  if (card) card.classList.add("sel");
  rcUpdatePromptPreview();
};

/* ─── 8. CASCADE FACULTAD → ESCUELA → CURSO ─── */
window.rcOnFacultad = function () {
  const fac = document.getElementById("rc-facultad").value;
  const selEsc = document.getElementById("rc-escuela");
  const selCurso = document.getElementById("rc-curso");

  selEsc.innerHTML = '<option value="">— Selecciona escuela —</option>';
  selCurso.innerHTML =
    '<option value="">— Selecciona escuela primero —</option>';
  selEsc.disabled = !fac;
  selCurso.disabled = true;
  document.getElementById("rc-curso-custom").style.display = "none";

  if (fac && UPEU_DATA[fac]) {
    Object.keys(UPEU_DATA[fac]).forEach((e) => {
      const opt = document.createElement("option");
      opt.value = e;
      opt.textContent = e;
      selEsc.appendChild(opt);
    });
    selEsc.disabled = false;
  }

  rcUpdateQuickSuggestions(null);
  rcUpdatePromptPreview();
};

window.rcOnEscuela = function () {
  const fac = document.getElementById("rc-facultad").value;
  const esc = document.getElementById("rc-escuela").value;
  const selCurso = document.getElementById("rc-curso");

  selCurso.innerHTML = '<option value="">— Selecciona curso —</option>';
  document.getElementById("rc-curso-custom").style.display = "none";
  selCurso.disabled = !esc;

  if (fac && esc && UPEU_DATA[fac] && UPEU_DATA[fac][esc]) {
    UPEU_DATA[fac][esc].forEach((c) => {
      const opt = document.createElement("option");
      opt.value = c;
      opt.textContent = c;
      selCurso.appendChild(opt);
    });
    // Opción "Otro curso"
    const other = document.createElement("option");
    other.value = "__custom__";
    other.textContent = "✏️ Escribir otro curso...";
    selCurso.appendChild(other);
    selCurso.disabled = false;
  }

  rcUpdateQuickSuggestions(esc);
  rcUpdatePromptPreview();
};

window.rcOnCurso = function () {
  const val = document.getElementById("rc-curso").value;
  const customInput = document.getElementById("rc-curso-custom");
  customInput.style.display = val === "__custom__" ? "block" : "none";
  if (val !== "__custom__") customInput.value = "";
  rcUpdatePromptPreview();
};

/* ─── 9. SUGERENCIAS RÁPIDAS ─── */
function rcUpdateQuickSuggestions(escuela) {
  const container = document.getElementById("rc-quick-suggestions");
  if (!container) return;
  const sugs = (escuela && RC_QUICK_SUGGESTIONS[escuela]) || [
    "Actividad de aprendizaje activo",
    "Rúbrica de trabajo en equipo",
    "Plan de sesión con aula invertida",
    "Caso práctico peruano",
  ];
  container.innerHTML = sugs
    .map(
      (s) =>
        `<button class="quick-resource-btn" onclick="window.rcApplySuggestion('${s.replace(/'/g, "\\'")}')">💡 ${s}</button>`,
    )
    .join("");
}

window.rcApplySuggestion = function (text) {
  const outcome = document.getElementById("rc-outcome");
  if (outcome) {
    outcome.value = text;
    outcome.focus();
  }
  rcUpdatePromptPreview();
};

/* ─── 10. BUILDER DE PROMPT ─── */
function rcBuildPrompt() {
  const fac = document.getElementById("rc-facultad")?.value || "";
  const esc = document.getElementById("rc-escuela")?.value || "";
  const cursoSel = document.getElementById("rc-curso")?.value || "";
  const cursoCustom =
    document.getElementById("rc-curso-custom")?.value?.trim() || "";
  const curso = cursoSel === "__custom__" ? cursoCustom : cursoSel;
  const ciclo = document.getElementById("rc-ciclo")?.value || "";
  const semana = document.getElementById("rc-semana")?.value?.trim() || "";
  const outcome = document.getElementById("rc-outcome")?.value?.trim() || "";
  const bloom = document.getElementById("rc-bloom")?.value || "";
  const contexto = document.getElementById("rc-context")?.value?.trim() || "";
  const typeData = RC_TYPES.find((t) => t.id === STATE.rcType);
  const typeName = typeData ? typeData.label : STATE.rcType;

  const lines = [
    `Eres un experto en diseño curricular de la Universidad Peruana Unión (UPeU), institución adventista del séptimo día con licenciamiento SUNEDU vigente. Trabajas bajo el marco pedagógico de diseño inverso (Understanding by Design), taxonomía revisada de Bloom-Anderson-Krathwohl y enfoque por competencias con resultados de aprendizaje verificables y evaluables.`,
    ``,
    `CONTEXTO INSTITUCIONAL:`,
    `- Universidad: Universidad Peruana Unión (UPeU) — sedes Lima, Juliaca y Tarapoto`,
    `- Tipo: Universidad adventista privada, licenciada SUNEDU`,
    `- Facultad: ${fac || "No especificada"}`,
    `- Escuela Profesional: ${esc || "No especificada"}`,
    `- Curso / Asignatura: ${curso || "No especificado"}`,
    `- Ciclo académico: ${ciclo ? "Ciclo " + ciclo : "No especificado"}`,
    `- Semana / Unidad: ${semana || "No especificada"}`,
  ];

  if (outcome) {
    lines.push(``, `RESULTADO DE APRENDIZAJE DECLARADO:`, `"${outcome}"`);
  }
  if (bloom) {
    lines.push(``, `NIVEL BLOOM ESPERADO: ${bloom}`);
  }
  if (contexto) {
    lines.push(``, `CONTEXTO ADICIONAL DEL DOCENTE:`, contexto);
  }

  lines.push(
    ``,
    `REQUISITOS SUNEDU — obligatorios en el recurso generado:`,
    `- Alinear explícitamente con el Resultado de Aprendizaje indicado`,
    `- Usar verbos de Bloom observables, medibles y congruentes con el nivel`,
    `- Especificar evidencias concretas y verificables por terceros`,
    `- Coherente con lo declarado en el sílabo vigente de la EP`,
    `- Integración de valores adventistas: pertinente, académica, no sermón`,
    `- Indicar modalidad: presencial / virtual / semipresencial`,
    `- Usar terminología institucional UPeU: EP, semana, ciclo, créditos`,
    ``,
    `ENCARGO — GENERA EL SIGUIENTE RECURSO: ${typeName.toUpperCase()}`,
    ``,
    RC_INSTRUCTIONS[STATE.rcType] ||
      "Genera el recurso completo, estructurado y listo para usar en el aula.",
    ``,
    `Responde en español, con formato Markdown estructurado, tono académico sobrio y lenguaje preciso. Incluye la sección "⚠️ Alertas curriculares" al final si detectas incoherencias, vacíos o riesgos de incumplimiento SUNEDU.`,
  );

  return lines.join("\n");
}

/* ─── 11. PREVIEW DEL PROMPT ─── */
window.rcUpdatePromptPreview = function () {
  const box = document.getElementById("rc-prompt-preview");
  if (box && box.classList.contains("visible")) {
    box.textContent = rcBuildPrompt();
  }
};

window.rcTogglePromptPreview = function () {
  const box = document.getElementById("rc-prompt-preview");
  const btn = document.getElementById("ppt-toggle");
  if (!box || !btn) return;
  const isOpen = box.classList.contains("visible");
  box.classList.toggle("visible", !isOpen);
  btn.classList.toggle("open", !isOpen);
  if (!isOpen) box.textContent = rcBuildPrompt();
};

window.rcToggleCtx = function () {
  const area = document.getElementById("rc-context");
  const btn = document.getElementById("ctx-toggle");
  if (!area || !btn) return;
  const show = area.style.display === "none";
  area.style.display = show ? "block" : "none";
  btn.classList.toggle("open", show);
};

/* ─── 12. GENERACIÓN PRINCIPAL ─── */
window.generateResourceV2 = async function () {
  const cursoSel = document.getElementById("rc-curso")?.value || "";
  const cursoCustom =
    document.getElementById("rc-curso-custom")?.value?.trim() || "";
  const curso = cursoSel === "__custom__" ? cursoCustom : cursoSel;

  if (!curso) {
    toast("Selecciona o escribe el nombre del curso", "error");
    return;
  }

  const typeData = RC_TYPES.find((t) => t.id === STATE.rcType);
  const prompt = rcBuildPrompt();
  const btn = document.getElementById("btn-gen-resource");
  const resultPanel = document.getElementById("rc-result-panel");
  const content = document.getElementById("rc-result-content");

  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> JoMelAi generando recurso...';

  // Mostrar panel en estado "cargando"
  if (resultPanel) {
    resultPanel.classList.add("visible");
    content.innerHTML = `
      <div class="resource-generating">
        <div class="gen-spinner"></div>
        <span>Generando ${typeData?.label || "recurso"}...</span>
      </div>`;
    resultPanel.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  try {
    // Llama al endpoint /api/ask de JoMelAi
    const r = await api("POST", '/api/chat-lateral/ask', {
      question: prompt,
      context: "user",
      mode: "rag",
    });

    const raw = r.answer || r.response || r.message || r.summary || "";

    if (raw) {
      STATE.rcResult = raw;
      STATE.rcCurrentTitle = typeData?.label || "Recurso";

      // Actualizar header del resultado
      const fac = document.getElementById("rc-facultad")?.value || "";
      const esc = document.getElementById("rc-escuela")?.value || "";
      const ciclo = document.getElementById("rc-ciclo")?.value || "";

      document.getElementById("rc-result-title").innerHTML =
        `${typeData?.emoji || "✅"} ${typeData?.label || "Recurso generado"}`;

      document.getElementById("rc-result-meta").innerHTML = [
        esc ? `<span class="meta-pill">${esc}</span>` : "",
        curso ? `<span class="meta-pill">${curso}</span>` : "",
        ciclo ? `<span class="meta-pill accent">Ciclo ${ciclo}</span>` : "",
        `<span class="meta-pill accent">SUNEDU ✓</span>`,
      ]
        .filter(Boolean)
        .join("");

      // Renderizar markdown
      content.innerHTML = rcRenderMarkdown(raw);
      toast("✅ Recurso generado correctamente", "success");
    } else {
      content.innerHTML = `<p style="color:var(--text-muted)">No se obtuvo respuesta. Intenta nuevamente.</p>`;
      toast("Sin respuesta del motor. Reintenta.", "error");
    }
  } catch (e) {
    content.innerHTML = `<p style="color:#f87171">Error: ${e.message}</p>`;
    toast("Error al generar: " + e.message, "error");
  } finally {
    btn.disabled = false;
    btn.innerHTML = "🤖 Generar recurso con JoMelAi";
  }
};

/* ─── 13. MARKDOWN RENDERER ─── */
function rcRenderMarkdown(md) {
  // 1. Tablas (antes de todo)
  md = md.replace(/((?:^\|.+\|\s*\n)+)/gm, function (block) {
    const rows = block.trim().split("\n");
    let out = '<table class="md-table">';
    let thead = true;
    for (const row of rows) {
      const isSep = /^\|[\s|:-]+\|$/.test(row.trim());
      if (isSep) {
        out += "</thead><tbody>";
        thead = false;
        continue;
      }
      const cells = row.split("|").slice(1, -1);
      if (thead) {
        out +=
          "<thead><tr>" +
          cells.map((c) => `<th>${rcInline(c.trim())}</th>`).join("") +
          "</tr>";
      } else {
        out +=
          "<tr>" +
          cells.map((c) => `<td>${rcInline(c.trim())}</td>`).join("") +
          "</tr>";
      }
    }
    out += "</tbody></table>";
    return out + "\n";
  });

  const lines = md.split("\n");
  let html = "";
  let inUl = false,
    inOl = false;
  let alertBlock = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Líneas de tabla ya procesadas — pasar tal cual
    if (
      line.includes("<table") ||
      line.includes("</table") ||
      line.includes("<thead") ||
      line.includes("<tbody") ||
      line.includes("<tr") ||
      line.includes("<th") ||
      line.includes("<td") ||
      line.includes("</thead") ||
      line.includes("</tbody")
    ) {
      closeLists();
      html += line + "\n";
      continue;
    }

    // Detectar bloque de alerta (⚠️)
    if (/^#{1,3}.*⚠️/.test(line) || /^⚠️/.test(line.trim())) {
      closeLists();
      alertBlock = true;
      html += `<div class="resource-alert-block"><strong>${rcInline(line.replace(/^#{1,3}\s*/, ""))}</strong>\n`;
      continue;
    }

    // Headers
    if (/^### (.+)$/.test(line)) {
      closeLists();
      endAlert();
      html += `<h3>${rcInline(line.slice(4))}</h3>\n`;
    } else if (/^## (.+)$/.test(line)) {
      closeLists();
      endAlert();
      html += `<h2>${rcInline(line.slice(3))}</h2>\n`;
    } else if (/^# (.+)$/.test(line)) {
      closeLists();
      endAlert();
      html += `<h1>${rcInline(line.slice(2))}</h1>\n`;
    }
    // Listas no ordenadas
    else if (/^[-*] (.+)$/.test(line)) {
      if (inOl) {
        html += "</ol>";
        inOl = false;
      }
      if (!inUl) {
        html += "<ul>";
        inUl = true;
      }
      html += `<li>${rcInline(line.replace(/^[-*] /, ""))}</li>\n`;
    }
    // Listas ordenadas
    else if (/^\d+\. (.+)$/.test(line)) {
      if (inUl) {
        html += "</ul>";
        inUl = false;
      }
      if (!inOl) {
        html += "<ol>";
        inOl = true;
      }
      html += `<li>${rcInline(line.replace(/^\d+\. /, ""))}</li>\n`;
    }
    // HR
    else if (/^---+$/.test(line.trim())) {
      closeLists();
      endAlert();
      html += "<hr>\n";
    }
    // Blockquote
    else if (/^> (.+)$/.test(line)) {
      closeLists();
      html += `<blockquote>${rcInline(line.slice(2))}</blockquote>\n`;
    }
    // Línea vacía
    else if (line.trim() === "") {
      closeLists();
      if (alertBlock) {
        html += "</div>";
        alertBlock = false;
      } else html += "<br>\n";
    }
    // Párrafo normal
    else {
      closeLists();
      if (alertBlock) {
        html += rcInline(line) + " ";
      } else {
        html += `<p>${rcInline(line)}</p>\n`;
      }
    }
  }

  closeLists();
  if (alertBlock) html += "</div>";

  function closeLists() {
    if (inUl) {
      html += "</ul>\n";
      inUl = false;
    }
    if (inOl) {
      html += "</ol>\n";
      inOl = false;
    }
  }
  function endAlert() {
    if (alertBlock) {
      html += "</div>";
      alertBlock = false;
    }
  }

  return `<div class="resource-markdown">${html}</div>`;
}

function rcInline(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\*\*\*(.+?)\*\*\*/g, "<strong><em>$1</em></strong>")
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\*(.+?)\*/g, "<em>$1</em>")
    .replace(/__(.+?)__/g, "<strong>$1</strong>")
    .replace(/_(.+?)_/g, "<em>$1</em>")
    .replace(/`(.+?)`/g, "<code>$1</code>")
    .replace(/~~(.+?)~~/g, "<del>$1</del>");
}

/* ─── 14. ACCIONES DEL RESULTADO ─── */
window.rcCopyResult = function () {
  navigator.clipboard
    .writeText(STATE.rcResult || "")
    .then(() => toast("✅ Copiado al portapapeles", "success"))
    .catch(() => toast("No se pudo copiar", "error"));
};

window.rcDownloadResult = function () {
  if (!STATE.rcResult) {
    toast("No hay recurso para descargar", "error");
    return;
  }
  const fac = document.getElementById("rc-facultad")?.value || "UPeU";
  const curso = document.getElementById("rc-curso")?.value || "curso";
  const type = STATE.rcCurrentTitle || "recurso";
  const fecha = new Date().toISOString().slice(0, 10);
  const name = `${type}-${curso}-${fecha}.md`
    .replace(/[^a-z0-9.\-_áéíóúñü ]/gi, "_")
    .replace(/ /g, "_");
  const blob = new Blob([STATE.rcResult], {
    type: "text/markdown;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, 100);
  toast("📄 Descargado como .md", "success");
};

/* ─── 15. COMPATIBILIDAD: mantener función legacy ─── */
window.selectResourceType = function (el, type) {
  window.rcSelectType(type);
};
window.generateResource = window.generateResourceV2;
window.copyResource = window.rcCopyResult;

/* ══════════════════════════════════════════════════════
   ACCESO TÉCNICO: DuckDB, RAG y reportes dinámicos
══════════════════════════════════════════════════════ */
function techVal(id) {
  const el = document.getElementById(id);
  return el ? el.value.trim() : "";
}
function techJson(id, obj) {
  const el = document.getElementById(id);
  if (el) el.textContent = JSON.stringify(obj, null, 2);
}
function techFilePath() {
  return techVal("tech-file-path") || "/data/syllabi/silabos.csv";
}
function techDelimiter() {
  const v = techVal("tech-delimiter");
  return v === "tab" ? "\t" : v || null;
}

async function techRefresh() {
  const st = await api("GET", "/api/setup/status");
  const statusEl = document.getElementById("tech-status");
  if (statusEl && st.ok) {
    const e = st.engine || {};
    const duck = e.duckdb || {};
    const chroma = e.chroma || {};
    statusEl.innerHTML = `
      <div class="stats-grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));margin-top:8px">
        <div class="stat-card"><div class="stat-label">DuckDB</div><div class="stat-value" style="font-size:20px">${duck.exists ? "OK" : "Pendiente"}</div><div class="stat-label">${(duck.tables || []).join(", ") || "sin tablas"}</div></div>
        <div class="stat-card"><div class="stat-label">RAG/Chroma</div><div class="stat-value" style="font-size:20px">${chroma.available ? "OK" : "No disponible"}</div><div class="stat-label">${chroma.collection_count ?? 0} fragmentos</div></div>
        <div class="stat-card"><div class="stat-label">Ollama</div><div class="stat-value" style="font-size:20px">${st.ollama?.ok ? "OK" : "Revisar"}</div><div class="stat-label">${(st.ollama?.models || []).length} modelos</div></div>
      </div>`;
  }
  const files = await api("GET", "/api/setup/csv-files");
  const sel = document.getElementById("tech-file-path");
  if (sel && files.ok) {
    const list = files.files || [];
    sel.innerHTML = list.length
      ? list
          .map(
            (f) =>
              `<option value="${esc(f.path)}">${esc(f.name)} · ${f.size_mb} MB</option>`,
          )
          .join("")
      : '<option value="/data/syllabi/silabos.csv">/data/syllabi/silabos.csv</option>';
  }
  await techLoadJobs();
}

async function techUploadFile() {
  const input = document.getElementById("tech-file");
  if (!input || !input.files.length) {
    toast("Selecciona un archivo", "error");
    return;
  }
  const fd = new FormData();
  fd.append("file", input.files[0]);
  fd.append("kind", techVal("tech-kind") || "dataset");
  const r = await fetch(API + "/api/datasets/upload", {
    method: "POST",
    credentials: "include",
    body: fd,
  });
  const j = await r
    .json()
    .catch(() => ({ ok: false, message: "Respuesta inválida" }));
  document.getElementById("tech-upload-result").textContent = j.ok
    ? `✅ ${j.name || j.file_path} cargado (${j.size_mb} MB)`
    : j.message || "Error al subir";
  toast(
    j.ok ? "Archivo cargado" : j.message || "Error al subir",
    j.ok ? "success" : "error",
  );
  await techRefresh();
}

async function techProfileCsv() {
  const r = await api("POST", "/api/setup/profile-csv", {
    file_path: techFilePath(),
    delimiter: techDelimiter(),
    sample_rows: 3000,
  });
  techJson("tech-profile", r);
}

async function techImportDuckDb() {
  const table = techVal("tech-table") || "silabos";
  const r = await api("POST", "/api/setup/duckdb-job", {
    file_path: techFilePath(),
    table,
    delimiter: techDelimiter(),
    replace: true,
    normalize_columns: true,
  });
  techJson("tech-profile", r);
  toast(
    r.ok ? "Importación DuckDB en cola" : r.message || "No se pudo iniciar",
    r.ok ? "success" : "error",
  );
  await techLoadJobs();
}

async function techBuildRag() {
  const r = await api("POST", "/api/setup/rag-job", {
    file_path: techFilePath(),
    collection: techVal("tech-collection") || "silabos",
    delimiter: techDelimiter(),
    row_limit: 0,
    chunk_size_rows: 1000,
    embed_batch_size: 16,
    reset_collection: false,
  });
  techJson("tech-profile", r);
  toast(
    r.ok ? "Construcción RAG en cola" : r.message || "No se pudo iniciar",
    r.ok ? "success" : "error",
  );
  await techLoadJobs();
}

async function techBuildRagCollections() {
  const prefix = techVal("tech-collection") || "silabos";
  const r = await api("POST", "/api/setup/rag-collections-job", {
    file_path: techFilePath(),
    collection_prefix: prefix,
    delimiter: techDelimiter(),
    row_limit: 0,
    chunk_size_rows: 1000,
    embed_batch_size: 16,
    reset_collections: false,
  });
  techJson("tech-profile", r);
  toast(
    r.ok ? "RAG por secciones en cola" : r.message || "No se pudo iniciar",
    r.ok ? "success" : "error",
  );
  await techLoadJobs();
}

async function techLoadJobs() {
  const r = await api("GET", "/api/setup/jobs?limit=12");
  const el = document.getElementById("tech-jobs");
  if (!el) return;
  const jobs = r.jobs || [];
  if (!jobs.length) {
    el.innerHTML =
      '<div class="empty-state"><div class="es-icon">✅</div><p>No hay trabajos recientes.</p></div>';
    return;
  }
  el.innerHTML = jobs
    .map(
      (j) => `<div class="project-card" style="margin-bottom:8px">
    <div class="project-icon" style="background:linear-gradient(135deg,#1D4ED8,#4F46E5)">⚙️</div>
    <div class="project-info"><h4>${esc(j.label || j.kind || "Job")}</h4><p>${esc(j.status || "")} · ${j.progress || 0}% · ${esc(j.updated_at || j.created_at || "")}<br>${esc(j.log || "")}</p></div>
    ${["queued", "running"].includes(j.status) ? `<button class="btn btn-red" onclick="techCancelJob('${esc(j.id)}')">Cancelar</button>` : ""}
  </div>`,
    )
    .join("");
}

async function techCancelJob(id) {
  const r = await api(
    "POST",
    `/api/setup/jobs/${encodeURIComponent(id)}/cancel`,
    {},
  );
  toast(
    r.ok ? "Job cancelado" : r.message || "No se pudo cancelar",
    r.ok ? "success" : "error",
  );
  await techLoadJobs();
}

async function techCancelAllJobs() {
  const r = await api("POST", "/api/setup/jobs/cancel-all", {});
  toast(
    r.ok ? "Jobs cancelados/marcados" : r.message || "No se pudo cancelar",
    r.ok ? "success" : "error",
  );
  await techLoadJobs();
}

async function techAskReport(kind) {
  const q = techVal("tech-report-q");
  if (!q) {
    toast("Escribe una pregunta", "error");
    return;
  }
  const table =
    techVal("tech-report-table") || techVal("tech-table") || "silabos";
  const endpoint =
    kind === "sql" ? "/api/duckdb/natural-sql" : "/api/charts/natural";
  const r = await api("POST", endpoint, { question: q, table, limit: 100 });
  techJson("tech-report-out", r);
}

async function techAskRag() {
  const q = techVal("tech-report-q");
  if (!q) {
    toast("Escribe una pregunta", "error");
    return;
  }
  const r = await api("POST", "/api/chat-lateral/ask", {
    question: q,
    collection: techVal("tech-collection") || "silabos",
    n_results: 5,
  });
  techJson("tech-report-out", r);
}

function initQuickPrompts() {
  const prompts = [
    "¿Cómo distribuir créditos en una malla de 10 ciclos?",
    "Sugiere actividades para un curso de investigación",
    "¿Qué verbos usar en resultados de aprendizaje?",
    "Crea una rúbrica para trabajo en equipo",
    "¿Cómo alinear el perfil de egreso con los cursos?",
    "Estrategias para enseñanza semipresencial",
  ];
  const el = document.getElementById("quick-prompts");
  if (!el) return;
  el.innerHTML = prompts
    .map(
      (p) => `
    <div onclick="quickPromptClick('${p.replace(/'/g, "\\'")}',this)" style="
      padding:8px 14px;border-radius:20px;
      background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.1);
      font-size:12px;font-weight:600;color:var(--text-secondary);
      cursor:pointer;transition:all .2s;
    " onmouseover="this.style.background='rgba(107,33,212,0.2)';this.style.borderColor='rgba(139,69,245,0.3)';this.style.color='#fff'"
      onmouseout="this.style.background='rgba(255,255,255,0.06)';this.style.borderColor='rgba(255,255,255,0.1)';this.style.color='var(--text-secondary)'"
    >💡 ${p}</div>
  `,
    )
    .join("");
}

async function quickPromptClick(prompt) {
  openAiPanel();
  navigate("recursos");
  await sendAiMessageWith(prompt);
}

/* ══════════════════════════════════════════════════════
   UTILS
══════════════════════════════════════════════════════ */
function esc(s) {
  if (typeof s !== "string") s = String(s || "");
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
function nl2br(s) {
  return s.replace(/\n/g, "<br>");
}

/* JOMELAI_GLOBAL_EXPORTS_FINAL_LAYERED_SAFE */
(function () {
  const names = [
    "checkAuth",
    "doLogin",
    "fillDemo",
    "doLogout",
    "showApp",
    "navigate",
    "dashAsk",
    "toggleAiPanel",
    "openAiPanel",
    "sendAiMessage",
    "sendAiMessageWith",
    "generateMalla",
    "saveMallaProject",
    "copyMalla",
    "planNext",
    "planPrev",
    "goToPlanStep",
    "planAskAi",
    "generateFullPlan",
    "copyPlan",
    "savePlanVersion",
    "switchSilaboTab",
    "generateSilabo",
    "copySilabo",
    "searchSilabos",
    "selectResourceType",
    "generateResource",
    "copyResource",
    "techRefresh",
    "techUploadFile",
    "techProfileCsv",
    "techImportDuckDb",
    "techBuildRag",
    "techBuildRagCollections",
    "techLoadJobs",
    "techCancelJob",
    "techCancelAllJobs",
    "techAskReport",
    "techAskRag",
    "quickPromptClick",
    "initParticles",
    "initBubbles",
    "toast",
    "api",
    "esc",
    "saveSilaboDraft",
    "downloadSilaboPdf",
    "pickSyllabusText",
    "renderSilaboDocument",
    "markdownToSyllabusHtml",
    "rebuildSilaboIndex",
    "getCurrentSilaboHtml",
    "getCurrentSilaboText",
    "nl2br",
  ];
  names.forEach(function (name) {
    try {
      const value = (0, eval)(name);
      if (typeof value !== "undefined") window[name] = value;
    } catch (e) {
      /* Some functions may not exist in partial builds; keep boot bridge alive. */
    }
  });
  window.JOMELAI_READY = true;
  if (window.__JM_PENDING_NAV && typeof window.navigate === "function") {
    const page = window.__JM_PENDING_NAV;
    window.__JM_PENDING_NAV = null;
    setTimeout(function () {
      window.navigate(page);
    }, 0);
  }
})();

/* ══════════════════════════════════════════════════════
   INIT
══════════════════════════════════════════════════════ */
document.addEventListener("DOMContentLoaded", () => {
  initParticles();
  initBubbles();
  document.getElementById("fab").style.display = "none";
  const emailEl = document.getElementById("login-email");
  const passEl = document.getElementById("login-pass");
  const loginBtn = document.getElementById("login-btn");
  if (emailEl && !emailEl.value) emailEl.value = "rv@local.test";
  if (passEl && !passEl.value) passEl.value = "123";
  if (loginBtn)
    loginBtn.addEventListener("click", (e) => {
      e.preventDefault();
      window.doLogin();
    });
  if (passEl)
    passEl.addEventListener("keydown", (e) => {
      if (e.key === "Enter") window.doLogin();
    });
  checkAuth();
  // Fallback rcInit para cuando la página ya está montada
  setTimeout(() => {
    if (window.rcInit) window.rcInit();
  }, 800);
});

/* JOMELAI_APP_STREAM_PRETTY_FULL_V1_START */
(function () {
  const JM_MODEL = 'qwen2.5:0.5b';

  const JM = window.JM_STREAM_PRETTY = window.JM_STREAM_PRETTY || {
    chat: {},
    resource: {
      raw: '',
      active: false,
      continuing: false,
      config: null,
      meta: {}
    },
    syllabus: {
      raw: '',
      active: false,
      config: null,
      meta: {}
    }
  };

  function q(id) {
    return document.getElementById(id);
  }

  function safeText(v) {
    return String(v == null ? '' : v);
  }

  function htmlEsc(v) {
    return safeText(v)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function cleanMarkers(text) {
    return safeText(text)
      .replace(/```json/gi, '')
      .replace(/```markdown/gi, '')
      .replace(/```/g, '')
      .replace(/FIN_RESPUESTA/gi, '')
      .replace(/FIN_DOCUMENTO/gi, '')
      .replace(/\bconectando\.\.\./gi, '')
      .replace(/\bcontinuando\.\.\./gi, '')
      .replace(/\bgenerando\.\.\./gi, '')
      .trim();
  }

  function norm(text) {
    return cleanMarkers(text)
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

  function injectPrettyStyles() {
    if (document.getElementById('jm-stream-pretty-full-css')) return;

    const style = document.createElement('style');
    style.id = 'jm-stream-pretty-full-css';
    style.textContent = `
      .jm-chip {
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
        text-shadow:none !important;
      }

      .jm-chat-card {
        border:1px solid rgba(139,69,245,.24) !important;
        background:linear-gradient(180deg, rgba(107,33,212,.20), rgba(30,20,70,.82)) !important;
        border-radius:16px !important;
        padding:14px !important;
      }

      .jm-chat-body,
      .jm-chat-body p,
      .jm-chat-body li {
        color:#eef2ff !important;
        line-height:1.58 !important;
        font-size:13px !important;
      }

      .jm-chat-body h2,
      .jm-chat-body h3,
      .jm-chat-body h4,
      .jm-chat-body strong,
      .jm-chat-body b {
        color:#ffffff !important;
        font-weight:900 !important;
      }

      .jm-chat-actions {
        margin-top:12px !important;
        padding-top:10px !important;
        border-top:1px solid rgba(255,255,255,.12) !important;
      }

      .jm-chat-note {
        color:#dbeafe !important;
        font-size:12px !important;
        line-height:1.45 !important;
        margin-bottom:8px !important;
      }

      .jm-chat-btn {
        display:inline-flex !important;
        align-items:center !important;
        justify-content:center !important;
        gap:7px !important;
        padding:8px 12px !important;
        border-radius:10px !important;
        border:1px solid rgba(147,197,253,.45) !important;
        background:rgba(59,130,246,.20) !important;
        color:#dbeafe !important;
        font-weight:900 !important;
        font-size:12px !important;
        cursor:pointer !important;
      }

      .jm-chat-btn:disabled,
      .jm-paper-btn:disabled {
        opacity:.55 !important;
        cursor:not-allowed !important;
      }

      .jm-paper-shell {
        background:#e5e7eb !important;
        border-radius:18px !important;
        padding:24px !important;
        color:#0f172a !important;
      }

      .jm-paper {
        max-width:960px !important;
        margin:0 auto !important;
        background:#ffffff !important;
        border-radius:10px !important;
        box-shadow:0 18px 45px rgba(15,23,42,.18) !important;
        padding:42px !important;
        color:#0f172a !important;
        font-family:Arial,Helvetica,sans-serif !important;
        line-height:1.58 !important;
      }

      .jm-paper,
      .jm-paper * {
        color:#0f172a !important;
        text-shadow:none !important;
        opacity:1 !important;
      }

      .jm-paper h1,
      .jm-paper h2,
      .jm-paper h3,
      .jm-paper h4,
      .jm-paper strong,
      .jm-paper b {
        color:#020617 !important;
        font-weight:900 !important;
      }

      .jm-paper p,
      .jm-paper li,
      .jm-paper td,
      .jm-paper th,
      .jm-paper div {
        color:#111827 !important;
      }

      .jm-paper-title {
        border-bottom:3px solid #7c3aed !important;
        padding-bottom:14px !important;
        margin-bottom:18px !important;
      }

      .jm-paper-title small {
        display:block !important;
        color:#64748b !important;
        text-transform:uppercase !important;
        letter-spacing:.14em !important;
        font-size:11px !important;
        margin-bottom:6px !important;
      }

      .jm-paper-title h2 {
        margin:0 !important;
        font-size:28px !important;
      }

      .jm-paper-meta {
        color:#475569 !important;
        margin-top:8px !important;
        font-size:14px !important;
      }

      .jm-paper-toolbar {
        display:flex !important;
        justify-content:space-between !important;
        align-items:center !important;
        gap:10px !important;
        margin-bottom:18px !important;
      }

      .jm-paper-toolbar-actions {
        display:flex !important;
        align-items:center !important;
        gap:8px !important;
        flex-wrap:wrap !important;
      }

      .jm-paper-btn {
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

      .jm-paper-btn-orange {
        background:#f97316 !important;
        color:#ffffff !important;
        border-color:#fb923c !important;
        box-shadow:0 8px 20px rgba(249,115,22,.20) !important;
      }

      .jm-paper-body {
        min-height:320px !important;
        outline:none !important;
      }

      .jm-paper-body table {
        width:100% !important;
        border-collapse:collapse !important;
        margin:12px 0 !important;
        font-size:13px !important;
      }

      .jm-paper-body th,
      .jm-paper-body td {
        border:1px solid #e5e7eb !important;
        padding:8px !important;
        vertical-align:top !important;
      }

      .jm-paper-body th {
        background:#f8fafc !important;
      }

      .jm-notice {
        margin-top:18px !important;
        padding:12px 14px !important;
        border-radius:10px !important;
        font-size:13px !important;
        font-weight:700 !important;
        line-height:1.45 !important;
      }

      .jm-notice-ok {
        background:#ecfdf5 !important;
        border:1px solid #bbf7d0 !important;
        color:#166534 !important;
      }

      .jm-notice-warn {
        background:#fff7ed !important;
        border:1px solid #fed7aa !important;
        color:#9a3412 !important;
      }

      .jm-notice-busy {
        background:#eff6ff !important;
        border:1px solid #bfdbfe !important;
        color:#1d4ed8 !important;
      }

      .jm-continuation-actions {
        display:flex !important;
        align-items:center !important;
        gap:10px !important;
        flex-wrap:wrap !important;
        margin-top:12px !important;
      }

      .jm-help {
        color:#9a3412 !important;
        font-size:12px !important;
        font-weight:700 !important;
      }

      @media print {
        body * { visibility:hidden !important; }
        .jm-paper-shell, .jm-paper-shell * { visibility:visible !important; }
        .jm-paper-shell { position:absolute !important; left:0 !important; top:0 !important; width:100% !important; padding:0 !important; background:white !important; }
        .jm-paper { max-width:none !important; box-shadow:none !important; border-radius:0 !important; }
        .jm-paper-toolbar, .jm-notice, .jm-continuation-actions { display:none !important; }
      }
    `;

    document.head.appendChild(style);
  }

  function markdownToHtml(text) {
    const safe = htmlEsc(cleanMarkers(text));
    const lines = safe.split('\n');

    let html = '';
    let inUl = false;
    let inOl = false;

    function closeLists() {
      if (inUl) {
        html += '</ul>';
        inUl = false;
      }
      if (inOl) {
        html += '</ol>';
        inOl = false;
      }
    }

    for (const line of lines) {
      const t = line.trim();

      if (!t) {
        closeLists();
        html += '<div style="height:8px"></div>';
        continue;
      }

      if (/^#{1,4}\s+/.test(t)) {
        closeLists();
        const level = Math.min((t.match(/^#+/) || ['##'])[0].length, 4);
        const tag = 'h' + Math.max(2, level);
        html += '<' + tag + '>' + t.replace(/^#{1,4}\s+/, '') + '</' + tag + '>';
        continue;
      }

      if (/^[-*]\s+/.test(t)) {
        if (!inUl) {
          closeLists();
          html += '<ul>';
          inUl = true;
        }
        html += '<li>' + t.replace(/^[-*]\s+/, '') + '</li>';
        continue;
      }

      if (/^\d+\.\s+/.test(t)) {
        if (!inOl) {
          closeLists();
          html += '<ol>';
          inOl = true;
        }
        html += '<li>' + t.replace(/^\d+\.\s+/, '') + '</li>';
        continue;
      }

      closeLists();

      const colonTitle = /^([A-ZÁÉÍÓÚÑ][^:]{2,80}):\s*(.*)$/.exec(t);

      if (colonTitle && colonTitle[2]) {
        html += '<p><strong>' + colonTitle[1] + ':</strong> ' + colonTitle[2] + '</p>';
      } else if (colonTitle && !colonTitle[2]) {
        html += '<h3>' + colonTitle[1] + '</h3>';
      } else {
        html += '<p>' + t + '</p>';
      }
    }

    closeLists();

    return html
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>');
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
    const res = await fetch(API + endpoint, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream'
      },
      body: JSON.stringify(payload || {})
    });

    if (!res.ok || !res.body) {
      throw new Error('No se pudo abrir el stream: ' + endpoint);
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

        if (handlers && typeof handlers.any === 'function') {
          handlers.any(parsed.event, parsed.data || {});
        }
      }
    }
  }

  function chips(config, label) {
    config = config || {};

    let html = `
      <span class="jm-chip">🤖 ${htmlEsc(config.model || JM_MODEL)}</span>
      <span class="jm-chip">ctx ${htmlEsc(config.num_ctx || 2048)}</span>
      <span class="jm-chip">salida ${htmlEsc(config.num_predict || config.max_tokens || '-')} tokens</span>
      <span class="jm-chip">RAG ${htmlEsc(config.n_results ?? '-')}</span>
      <span class="jm-chip">temp ${htmlEsc(config.temperature ?? '-')}</span>
    `;

    if (label) html += `<span class="jm-chip">${htmlEsc(label)}</span>`;

    return html;
  }

  function seemsIncomplete(text) {
    const raw = safeText(text).trim();

    if (!raw) return false;
    if (/FIN_RESPUESTA/i.test(raw) || /FIN_DOCUMENTO/i.test(raw)) return false;

    const last = raw.split('\n').map(x => x.trim()).filter(Boolean).pop() || '';

    if (last.length < 18) return true;
    if (/[,:;]$/.test(last)) return true;
    if (/\b(los|las|el|la|de|del|para|con|por|en|y|o|que|se|un|una|criterios|resultado|resultados|actividades|competencias|evidencias|cr[eé]d)\.?$/i.test(last)) return true;
    if (/Los R\.?$/i.test(last)) return true;
    if (!/[.!?)]$/.test(last)) return true;

    return false;
  }

  function removeDuplicateContinuation(base, append) {
    const baseClean = cleanMarkers(base);
    let a = cleanMarkers(append).replace(/^continuaci[oó]n\s*:\s*/i, '').trim();

    if (!a) return '';

    const baseNorm = norm(baseClean);
    const baseLines = new Set(
      baseClean.split('\n')
        .map(x => norm(x))
        .filter(x => x.length >= 12)
    );

    let lines = a.split('\n');

    while (lines.length) {
      const first = norm(lines[0]);

      if (!first) {
        lines.shift();
        continue;
      }

      if (first.length >= 12 && (baseLines.has(first) || baseNorm.includes(first))) {
        lines.shift();
        continue;
      }

      break;
    }

    a = lines.join('\n').trim();

    const aNorm = norm(a);

    if (aNorm && baseNorm.includes(aNorm.slice(0, Math.min(160, aNorm.length)))) return '';

    return a;
  }

  /* ══════════════════════════════════════════════════════
     CHAT STREAMING
  ══════════════════════════════════════════════════════ */

  function chatBodyEl(id) {
    return q(id + '-body');
  }

  function chatActions(id) {
    const action = q(id + '-actions');
    const item = JM.chat[id];

    if (!action || !item) return;

    if (item.active) {
      action.style.display = 'block';
      action.innerHTML = `
        <div class="jm-chat-note">Continuación en proceso. Espere a que finalice antes de solicitar otra ampliación.</div>
        <button type="button" class="jm-chat-btn" disabled>Generando...</button>
      `;
      return;
    }

    const label = seemsIncomplete(item.raw) ? '➕ Seguir generando' : '➕ Ampliar respuesta';
    const note = seemsIncomplete(item.raw)
      ? 'La respuesta parece inconclusa. Puede continuar la generación sin reiniciar la consulta.'
      : 'Puede solicitar una ampliación manteniendo el contenido y formato actual.';

    action.style.display = 'block';
    action.innerHTML = `
      <div class="jm-chat-note">${note}</div>
      <button type="button" class="jm-chat-btn" onclick="window.jmContinueChat('${htmlEsc(id)}')">${label}</button>
    `;
  }

  function renderChat(id, raw, config, label) {
    const body = chatBodyEl(id);
    const meta = q(id + '-meta');

    if (!body) return;

    JM.chat[id] = JM.chat[id] || {};
    JM.chat[id].raw = raw;

    if (config) JM.chat[id].config = config;

    body.innerHTML = markdownToHtml(raw);

    if (meta && (config || JM.chat[id].config)) {
      meta.innerHTML = chips(config || JM.chat[id].config, label || null);
    }

    chatActions(id);

    const panel = q('ai-panel-body');
    if (panel) panel.scrollTop = panel.scrollHeight;
  }

  async function sendAiMessageWithStream(question) {
    injectPrettyStyles();

    const body = q('ai-panel-body');
    if (!body) return;

    const cleanQuestion = safeText(question).trim();
    if (!cleanQuestion) return;

    body.insertAdjacentHTML('beforeend', `<div class="ai-msg"><div class="ai-msg-user">${htmlEsc(cleanQuestion)}</div></div>`);

    const id = 'jm-chat-' + Date.now() + '-' + Math.floor(Math.random() * 100000);

    const row = document.createElement('div');
    row.className = 'ai-msg';
    row.innerHTML = `
      <div class="ai-msg-bot jm-chat-card">
        <div id="${id}-meta" style="margin-bottom:10px"><span class="jm-chip">conectando...</span></div>
        <div id="${id}-body" class="jm-chat-body">
          <span class="ai-thinking"><span></span><span></span><span></span></span>
        </div>
        <div id="${id}-actions" class="jm-chat-actions" style="display:none"></div>
      </div>
    `;

    body.appendChild(row);
    body.scrollTop = body.scrollHeight;

    JM.chat[id] = {
      raw: '',
      question: cleanQuestion,
      active: true,
      config: null
    };

    let raw = '';
    let config = null;

    const controlledQuestion =
      cleanQuestion +
      '\n\nInstrucción de control: responde de forma completa, organizada y concreta. ' +
      'No cortes ideas a mitad de desarrollo. Cierra con la línea FIN_RESPUESTA.';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question: controlledQuestion,
        context: 'chat',
        model: JM_MODEL,
        max_tokens: 700,
        num_ctx: 1024,
        n_results: 2,
        temperature: 0.22,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderChat(id, raw || '', config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderChat(id, raw, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;

          if (!raw && data.answer) raw = data.answer;

          JM.chat[id].active = false;
          renderChat(id, raw, config, '✅ final');
        }
      });
    } catch (e) {
      JM.chat[id].active = false;
      raw += '\n\n⚠️ ' + e.message;
      renderChat(id, raw, config, 'error');
    } finally {
      JM.chat[id].active = false;
      chatActions(id);
    }
  }

  async function continueChat(id) {
    injectPrettyStyles();

    const item = JM.chat[id];

    if (!item) {
      toastSafe('No encontré la respuesta previa para continuar.', 'error');
      return;
    }

    if (item.active) {
      toastSafe('La respuesta aún está generándose.', 'error');
      return;
    }

    const base = cleanMarkers(item.raw || '');

    if (!base) {
      toastSafe('No hay contenido previo para continuar.', 'error');
      return;
    }

    item.active = true;
    chatActions(id);

    let append = '';
    let config = item.config || null;
    const tail = base.slice(Math.max(0, base.length - 1800));

    const prompt =
      'Continúa la respuesta anterior exactamente desde donde quedó. ' +
      'Devuelve únicamente contenido nuevo. No repitas título, encabezados ni secciones ya desarrolladas. ' +
      'Si la frase quedó cortada, complétala primero. Mantén el mismo formato. ' +
      'Cierra con FIN_RESPUESTA.\n\n' +
      'PREGUNTA ORIGINAL:\n' + item.question + '\n\n' +
      'RESPUESTA COMPLETA YA MOSTRADA AL USUARIO:\n' + base + '\n\n' +
      'ÚLTIMO FRAGMENTO DE REFERENCIA:\n' + tail + '\n\n' +
      'CONTINUACIÓN NUEVA:';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question: prompt,
        context: 'chat_continue',
        model: JM_MODEL,
        max_tokens: 700,
        num_ctx: 1024,
        n_results: 0,
        temperature: 0.14,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderChat(id, base + (removeDuplicateContinuation(base, append) ? '\n\n' + removeDuplicateContinuation(base, append) : ''), config, 'continuando...');
        },
        token(data) {
          append += data.text || '';
          const cleanAppend = removeDuplicateContinuation(base, append);
          renderChat(id, base + (cleanAppend ? '\n\n' + cleanAppend : ''), config, 'continuando...');
        },
        final(data) {
          config = data.tokens_config || config;
          const cleanAppend = removeDuplicateContinuation(base, append || data.answer || '');
          const merged = cleanAppend ? base + '\n\n' + cleanAppend : base + '\n\nFIN_RESPUESTA';
          item.active = false;
          renderChat(id, merged, config, '✅ continuación final');
        }
      });
    } catch (e) {
      item.active = false;
      renderChat(id, base + '\n\n⚠️ ' + e.message, config, 'error');
    } finally {
      item.active = false;
      chatActions(id);
    }
  }

  async function sendAiMessageOverride() {
    const input = q('ai-panel-input');
    const text = input ? input.value.trim() : '';
    if (!text) return;
    if (input) input.value = '';
    await sendAiMessageWithStream(text);
  }

  /* ══════════════════════════════════════════════════════
     RECURSOS STREAMING PDF EDITABLE
  ══════════════════════════════════════════════════════ */

  function resourceType() {
    return STATE.selectedResourceType || 'actividad';
  }

  function resourceLabel(type) {
    return (typeof RESOURCE_LABELS !== 'undefined' && RESOURCE_LABELS[type]) || 'Recurso de Aprendizaje';
  }

  function resourcePrompt(type) {
    return (typeof RESOURCE_PROMPTS !== 'undefined' && RESOURCE_PROMPTS[type]) || 'Genera un recurso de aprendizaje completo';
  }

  function resourceLooksComplete(text) {
    const raw = safeText(text);
    const n = norm(raw);

    if (/FIN_DOCUMENTO/i.test(raw)) return true;

    const checks = [
      'proposito',
      'instrucciones para el docente',
      'instrucciones para el estudiante',
      'recursos necesarios',
      'secuencia de trabajo',
      'producto esperado',
      'criterios de evaluacion',
      'recomendaciones de uso',
      'revision curricular'
    ];

    let count = 0;
    checks.forEach(x => { if (n.includes(x)) count++; });

    return raw.length > 900 &&
      count >= 6 &&
      n.includes('producto esperado') &&
      n.includes('criterios de evaluacion');
  }

  function ensureResourceShell(meta) {
    injectPrettyStyles();

    const host = q('resource-result');
    if (!host) return;

    host.style.display = 'block';
    host.innerHTML = `
      <div class="jm-paper-shell">
        <div class="jm-paper">
          <div class="jm-paper-toolbar">
            <div>
              <strong>✅ ${htmlEsc(resourceLabel(meta.type))}</strong>
              <div style="font-size:12px;color:#64748b">Editable en vivo · listo para exportar</div>
            </div>
            <div class="jm-paper-toolbar-actions">
              <button class="jm-paper-btn" onclick="window.copyResource()">📋 Copiar</button>
              <button class="jm-paper-btn" onclick="window.downloadResourcePdf()">📄 Descargar PDF</button>
            </div>
          </div>

          <div class="jm-paper-title">
            <small>JoMelAi · Recursos de aprendizaje</small>
            <h2 id="resource-result-title">${htmlEsc(resourceLabel(meta.type))}</h2>
            <div class="jm-paper-meta">${htmlEsc(meta.course || 'Curso por completar')}${meta.week ? ' · ' + htmlEsc(meta.week) : ''}</div>
          </div>

          <div id="jm-resource-config" style="margin-bottom:16px"><span class="jm-chip">conectando...</span></div>

          <div id="resource-text" class="jm-paper-body" contenteditable="true" spellcheck="true">
            <p style="color:#64748b">Generando recurso...</p>
          </div>

          <div id="jm-resource-completion" class="jm-notice jm-notice-busy">Generación en proceso.</div>
          <div id="jm-resource-actions" class="jm-continuation-actions"></div>
        </div>
      </div>
    `;
  }

  function renderResource(raw, config, label) {
    JM.resource.raw = raw;

    window.STATE = window.STATE || STATE;
    window.STATE.resourceResult = raw;
    window.STATE.resourceResultRaw = raw;

    const out = q('resource-text');
    const cfg = q('jm-resource-config');

    if (out) out.innerHTML = markdownToHtml(raw);
    if (cfg && (config || JM.resource.config)) cfg.innerHTML = chips(config || JM.resource.config, label || null);

    if (config) JM.resource.config = config;

    updateResourceNotice();
  }

  function updateResourceNotice() {
    const notice = q('jm-resource-completion');
    const actions = q('jm-resource-actions');

    if (!notice || !actions) return;

    const raw = JM.resource.raw || '';

    notice.className = 'jm-notice';

    if (JM.resource.active || JM.resource.continuing) {
      notice.classList.add('jm-notice-busy');
      notice.textContent = JM.resource.continuing
        ? 'Continuación en proceso. Espere a que finalice la generación antes de solicitar una nueva ampliación.'
        : 'Generación en proceso. La opción de continuación se habilitará cuando el modelo finalice la respuesta.';

      actions.innerHTML = `
        <button class="jm-paper-btn jm-paper-btn-orange" type="button" disabled>Generando...</button>
        <span class="jm-help">La interfaz está bloqueada temporalmente para evitar duplicaciones.</span>
      `;
      return;
    }

    if (resourceLooksComplete(raw)) {
      notice.classList.add('jm-notice-ok');
      notice.textContent = 'El recurso contiene las secciones esenciales y puede revisarse, editarse, copiarse o descargarse en PDF.';
      actions.innerHTML = '';
      return;
    }

    notice.classList.add('jm-notice-warn');
    notice.textContent = 'El contenido generado podría estar pendiente de cierre o requerir desarrollo adicional. Si observa que el documento aún no ha finalizado o que falta completar alguna sección, seleccione “Continuar generación” para ampliar el contenido sin reiniciar el proceso.';

    actions.innerHTML = `
      <button class="jm-paper-btn jm-paper-btn-orange" type="button" onclick="window.continueResourceGeneration()">➕ Continuar generación</button>
      <span class="jm-help">Se conservará el contenido actual y se agregará únicamente información nueva.</span>
    `;
  }

  async function generateResourceStream() {
    injectPrettyStyles();

    const course = q('r-course') ? q('r-course').value.trim() : '';
    const outcome = q('r-outcome') ? q('r-outcome').value.trim() : '';
    const week = q('r-week') ? q('r-week').value.trim() : '';
    const context = q('r-context') ? q('r-context').value.trim() : '';

    if (!course) {
      toastSafe('Ingresa el nombre del curso', 'error');
      return;
    }

    const type = resourceType();
    const meta = { type, course, week, outcome, context };
    const btn = q('btn-gen-resource');

    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando recurso...';
    }

    ensureResourceShell(meta);
    q('resource-result').scrollIntoView({ behavior: 'smooth' });

    JM.resource = {
      raw: '',
      active: true,
      continuing: false,
      config: null,
      meta
    };

    let raw = '';
    let config = null;

    const question =
      resourcePrompt(type) + ' para el curso "' + course + '". ' +
      'Semana/unidad: ' + (week || 'no especificada') + '. ' +
      'Resultado de aprendizaje: "' + (outcome || 'desarrollar competencias del área') + '". ' +
      'Contexto: ' + (context || 'contexto universitario') + '. ' +
      'Genera el recurso completo, estructurado y listo para usar. ' +
      'Incluye título, propósito, instrucciones para el docente, instrucciones para el estudiante, recursos necesarios, secuencia de trabajo, producto esperado, criterios de evaluación, recomendaciones de uso y revisión curricular. ' +
      'Cierra con la línea FIN_DOCUMENTO.';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question,
        context: 'resource',
        model: JM_MODEL,
        max_tokens: 1300,
        num_ctx: 1024,
        n_results: 1,
        temperature: 0.22,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          renderResource(raw, config, 'generando...');
        },
        token(data) {
          raw += data.text || '';
          renderResource(raw, config, 'generando...');
        },
        final(data) {
          config = data.tokens_config || config;
          if (!raw && data.answer) raw = data.answer;
          JM.resource.active = false;
          renderResource(raw, config, '✅ final');
          toastSafe('✅ Recurso generado', 'success');
        }
      });
    } catch (e) {
      JM.resource.active = false;
      renderResource(raw + '\n\n⚠️ ' + e.message, config, 'error');
      toastSafe('Error al generar recurso: ' + e.message, 'error');
    } finally {
      JM.resource.active = false;
      updateResourceNotice();

      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar recurso con JoMelAi';
      }
    }
  }

  async function continueResourceGeneration() {
    injectPrettyStyles();

    if (JM.resource.active || JM.resource.continuing) {
      toastSafe('La generación aún está en proceso. Espere a que finalice antes de continuar.', 'error');
      return;
    }

    const base = cleanMarkers(JM.resource.raw || (q('resource-text') ? q('resource-text').innerText : ''));

    if (!base) {
      toastSafe('No hay contenido previo para continuar.', 'error');
      return;
    }

    if (resourceLooksComplete(base)) {
      updateResourceNotice();
      toastSafe('El recurso ya contiene las secciones esenciales.', 'success');
      return;
    }

    JM.resource.continuing = true;
    updateResourceNotice();

    let append = '';
    let config = JM.resource.config || null;
    const tail = base.slice(Math.max(0, base.length - 2200));

    const prompt =
      'Continúa un recurso de aprendizaje que quedó incompleto. ' +
      'Devuelve únicamente contenido nuevo que falte después del último fragmento. ' +
      'No repitas título, propósito, instrucciones, recursos, producto, criterios ni recomendaciones que ya estén escritos. ' +
      'Si el documento ya parece completo, responde solamente FIN_DOCUMENTO. ' +
      'Mantén el mismo formato. Cierra con FIN_DOCUMENTO.\n\n' +
      'CONTENIDO YA MOSTRADO:\n' + base + '\n\n' +
      'ÚLTIMO FRAGMENTO:\n' + tail + '\n\n' +
      'CONTINUACIÓN NUEVA:';

    try {
      await streamPost('/api/chat-lateral/ask-stream', {
        question: prompt,
        context: 'resource_continue',
        model: JM_MODEL,
        max_tokens: 700,
        num_ctx: 1024,
        n_results: 0,
        temperature: 0.12,
        top_p: 0.85
      }, {
        config(data) {
          config = data.tokens_config || config;
          const cleanAppend = removeDuplicateContinuation(base, append);
          renderResource(base + (cleanAppend ? '\n\n' + cleanAppend : ''), config, 'continuando...');
        },
        token(data) {
          append += data.text || '';
          const cleanAppend = removeDuplicateContinuation(base, append);
          renderResource(base + (cleanAppend ? '\n\n' + cleanAppend : ''), config, 'continuando...');
        },
        final(data) {
          config = data.tokens_config || config;
          const cleanAppend = removeDuplicateContinuation(base, append || data.answer || '');
          const merged = cleanAppend ? base + '\n\n' + cleanAppend : base + '\n\nFIN_DOCUMENTO';
          JM.resource.continuing = false;
          renderResource(merged, config, '✅ continuación final');
          toastSafe('Continuación procesada sin duplicar contenido.', 'success');
        }
      });
    } catch (e) {
      toastSafe('Error al continuar: ' + e.message, 'error');
    } finally {
      JM.resource.continuing = false;
      updateResourceNotice();
    }
  }

  function copyResourceOverride() {
    const text = JM.resource.raw || (q('resource-text') ? q('resource-text').innerText : '') || '';
    navigator.clipboard.writeText(cleanMarkers(text)).then(() => toastSafe('✅ Copiado', 'success'));
  }

  function downloadResourcePdf() {
    const content = q('resource-text') ? q('resource-text').innerHTML : markdownToHtml(JM.resource.raw || '');
    const cfg = q('jm-resource-config') ? q('jm-resource-config').innerHTML : '';

    const win = window.open('', '_blank');

    if (!win) {
      toastSafe('No se pudo abrir la ventana de impresión.', 'error');
      return;
    }

    win.document.write(`
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Recurso JoMelAi</title>
        <style>
          body{font-family:Arial,Helvetica,sans-serif;background:#f1f5f9;margin:0;padding:24px;color:#0f172a}
          .paper{max-width:900px;margin:0 auto;background:#fff;padding:42px;border-radius:10px}
          h1,h2,h3,h4{color:#1e3a8a}
          p,li{line-height:1.6}
          .cfg span{display:inline-block;background:#eef2ff;border:1px solid #c7d2fe;color:#3730a3;padding:5px 9px;border-radius:999px;font-size:11px;font-weight:700;margin:3px}
          @media print{body{background:#fff;padding:0}.paper{max-width:none;border-radius:0}}
        </style>
      </head>
      <body>
        <div class="paper">
          <h1>Recurso de aprendizaje JoMelAi</h1>
          <div class="cfg">${cfg}</div>
          ${content}
        </div>
        <script>window.onload=function(){window.print();}</script>
      </body>
      </html>
    `);

    win.document.close();
  }

  /* ══════════════════════════════════════════════════════
     SÍLABOS STREAMING + FORMATO BONITO
  ══════════════════════════════════════════════════════ */

  function extractStringField(raw, key) {
    const marker = '"' + key + '"';
    let i = raw.indexOf(marker);
    if (i < 0) return '';

    i = raw.indexOf(':', i);
    if (i < 0) return '';

    let s = raw.slice(i + 1).trimStart();
    if (!s.startsWith('"')) return '';

    let out = '';
    let escp = false;

    for (let j = 1; j < s.length; j++) {
      const ch = s[j];

      if (escp) {
        out += ch;
        escp = false;
        continue;
      }

      if (ch === '\\') {
        escp = true;
        continue;
      }

      if (ch === '"') return out;

      out += ch;
    }

    return out;
  }

  function extractArrayStringsFromText(text) {
    const out = [];
    let inStr = false;
    let escp = false;
    let cur = '';

    for (let i = 0; i < text.length; i++) {
      const ch = text[i];

      if (!inStr) {
        if (ch === '"') {
          inStr = true;
          cur = '';
        }
        continue;
      }

      if (escp) {
        cur += ch;
        escp = false;
        continue;
      }

      if (ch === '\\') {
        escp = true;
        continue;
      }

      if (ch === '"') {
        out.push(cur);
        inStr = false;
        cur = '';
        continue;
      }

      cur += ch;
    }

    return out;
  }

  function extractArrayStrings(raw, key, limit) {
    const marker = '"' + key + '"';
    let i = raw.indexOf(marker);
    if (i < 0) return [];

    i = raw.indexOf('[', i);
    if (i < 0) return [];

    let depth = 0;
    let end = -1;
    let inStr = false;
    let escp = false;

    for (let j = i; j < raw.length; j++) {
      const ch = raw[j];

      if (inStr) {
        if (escp) escp = false;
        else if (ch === '\\') escp = true;
        else if (ch === '"') inStr = false;
        continue;
      }

      if (ch === '"') {
        inStr = true;
        continue;
      }

      if (ch === '[') depth++;
      if (ch === ']') {
        depth--;
        if (depth === 0) {
          end = j;
          break;
        }
      }
    }

    const body = end > i ? raw.slice(i + 1, end) : raw.slice(i + 1);
    const arr = extractArrayStringsFromText(body);

    return typeof limit === 'number' ? arr.slice(0, limit) : arr;
  }

  function extractObjectArray(raw, key, limit) {
    const marker = '"' + key + '"';
    let i = raw.indexOf(marker);
    if (i < 0) return [];

    i = raw.indexOf('[', i);
    if (i < 0) return [];

    const objs = [];
    let inStr = false;
    let escp = false;
    let depthObj = 0;
    let startObj = -1;

    for (let j = i + 1; j < raw.length; j++) {
      const ch = raw[j];

      if (inStr) {
        if (escp) escp = false;
        else if (ch === '\\') escp = true;
        else if (ch === '"') inStr = false;
        continue;
      }

      if (ch === '"') {
        inStr = true;
        continue;
      }

      if (ch === '{') {
        if (depthObj === 0) startObj = j;
        depthObj++;
        continue;
      }

      if (ch === '}') {
        depthObj--;
        if (depthObj === 0 && startObj >= 0) {
          objs.push(raw.slice(startObj, j + 1));
          startObj = -1;
          if (typeof limit === 'number' && objs.length >= limit) break;
        }
        continue;
      }

      if (ch === ']' && depthObj === 0) break;
    }

    return objs;
  }

  function parseSyllabusSeed(raw) {
    const clean = cleanMarkers(raw);

    let jsonText = clean;
    const fenced = clean.match(/```json\s*([\s\S]*?)```/i);
    if (fenced) jsonText = fenced[1];

    const first = jsonText.indexOf('{');
    const last = jsonText.lastIndexOf('}');

    if (first >= 0 && last > first) {
      try {
        return JSON.parse(jsonText.slice(first, last + 1));
      } catch (e) {
        /* partial fallback below */
      }
    }

    return {
      sumilla: extractStringField(clean, 'sumilla'),
      competencia_curso: extractStringField(clean, 'competencia_curso'),
      resultados_curso: extractArrayStrings(clean, 'resultados_curso', 6),
      metodologias: extractArrayStrings(clean, 'metodologias', 6),
      unidades: extractObjectArray(clean, 'unidades', 6).map((obj, idx) => ({
        unidad: extractStringField(obj, 'unidad') || String(idx + 1),
        titulo: extractStringField(obj, 'titulo'),
        resultado: extractStringField(obj, 'resultado'),
        contenidos: extractArrayStrings(obj, 'contenidos', 8),
        producto: extractStringField(obj, 'producto')
      })),
      referencias: extractObjectArray(clean, 'referencias', 8).map(obj => ({
        autor: extractStringField(obj, 'autor'),
        anio: extractStringField(obj, 'anio') || extractStringField(obj, 'fecha'),
        titulo: extractStringField(obj, 'titulo') || extractStringField(obj, 'nombre'),
        fuente: extractStringField(obj, 'fuente') || extractStringField(obj, 'editorial'),
        url: extractStringField(obj, 'url'),
        utilidad: extractStringField(obj, 'utilidad')
      })),
      enlaces: extractObjectArray(clean, 'enlaces', 8).map(obj => ({
        titulo: extractStringField(obj, 'titulo'),
        url: extractStringField(obj, 'url'),
        uso: extractStringField(obj, 'uso') || extractStringField(obj, 'utilidad')
      }))
    };
  }

  function syllabusResultHost() {
    const host = q('silabo-result');
    if (!host) return null;

    host.style.display = 'block';
    return host;
  }

  function renderSyllabus(raw, meta, config, label) {
    injectPrettyStyles();

    const host = syllabusResultHost();
    if (!host) return;

    const data = parseSyllabusSeed(raw);
    const hasStructured =
      data.sumilla ||
      data.competencia_curso ||
      (Array.isArray(data.resultados_curso) && data.resultados_curso.length) ||
      (Array.isArray(data.unidades) && data.unidades.length);

    const bodyHtml = hasStructured ? `
      <h3>1. Datos generales</h3>
      <table>
        <tbody>
          <tr><th>Curso</th><td>${htmlEsc(meta.course || '')}</td></tr>
          <tr><th>Programa</th><td>${htmlEsc(meta.program || '')}</td></tr>
          <tr><th>Créditos</th><td>${htmlEsc(meta.credits || '')}</td></tr>
          <tr><th>Ciclo</th><td>${htmlEsc(meta.cycle || '')}</td></tr>
          <tr><th>Semanas</th><td>${htmlEsc(meta.weeks || '16')}</td></tr>
          <tr><th>Modalidad</th><td>${htmlEsc(meta.modality || 'Presencial')}</td></tr>
        </tbody>
      </table>

      <h3>2. Sumilla</h3>
      <p>${htmlEsc(data.sumilla || 'Generando sumilla...')}</p>

      <h3>3. Competencia del curso</h3>
      <p>${htmlEsc(data.competencia_curso || meta.competency || 'Generando competencia...')}</p>

      <h3>4. Resultados de aprendizaje de la asignatura</h3>
      ${(data.resultados_curso || []).length ? `<ul>${data.resultados_curso.map(x => `<li>${htmlEsc(x)}</li>`).join('')}</ul>` : '<p>Generando resultados...</p>'}

      <h3>5. Unidades</h3>
      ${(data.unidades || []).length ? data.unidades.map((u, idx) => `
        <div style="border:1px solid #dbeafe;background:#f8fbff;border-radius:12px;padding:14px;margin:12px 0">
          <div style="font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:#2563eb">Unidad ${htmlEsc(u.unidad || String(idx + 1))}</div>
          <h4>${htmlEsc(u.titulo || 'Generando unidad...')}</h4>
          <p><strong>Resultado de aprendizaje:</strong> ${htmlEsc(u.resultado || 'Generando resultado...')}</p>
          ${(u.contenidos || []).length ? `<p><strong>Contenidos:</strong></p><ul>${u.contenidos.map(c => `<li>${htmlEsc(c)}</li>`).join('')}</ul>` : '<p>Generando contenidos...</p>'}
          <p><strong>Producto de unidad:</strong> ${htmlEsc(u.producto || 'Generando producto...')}</p>
        </div>
      `).join('') : '<p>Generando unidades...</p>'}

      <h3>6. Metodologías</h3>
      ${(data.metodologias || []).length ? `<ul>${data.metodologias.map(x => `<li>${htmlEsc(typeof x === 'string' ? x : JSON.stringify(x))}</li>`).join('')}</ul>` : '<p>Generando metodologías...</p>'}

      <h3>7. Referencias bibliográficas</h3>
      ${(data.referencias || []).length ? data.referencias.map(r => `
        <p><strong>${htmlEsc(r.autor || 'Autor')}</strong> (${htmlEsc(r.anio || 's/f')}). ${htmlEsc(r.titulo || 'Referencia')}. ${htmlEsc(r.fuente || '')}. ${htmlEsc(r.url || '')}</p>
      `).join('') : '<p>Generando referencias...</p>'}

      <h3>8. Enlaces de apoyo</h3>
      ${(data.enlaces || []).length ? `<ul>${data.enlaces.map(l => `<li>${htmlEsc((l.titulo || 'Recurso') + (l.url ? ' - ' + l.url : '') + (l.uso ? ' (' + l.uso + ')' : ''))}</li>`).join('')}</ul>` : '<p>Generando enlaces...</p>'}
    ` : markdownToHtml(raw);

    host.innerHTML = `
      <div class="jm-paper-shell">
        <div class="jm-paper">
          <div class="jm-paper-toolbar">
            <div>
              <strong>✅ Sílabo generado</strong>
              <div style="font-size:12px;color:#64748b">Editable en vivo · propuesta preliminar</div>
            </div>
            <div class="jm-paper-toolbar-actions">
              <button class="jm-paper-btn" onclick="window.copySilabo()">📋 Copiar</button>
            </div>
          </div>

          <div class="jm-paper-title">
            <small>JoMelAi · Sílabo preliminar</small>
            <h2>Sílabo preliminar: ${htmlEsc(meta.course || 'Curso')}</h2>
            <div class="jm-paper-meta">${htmlEsc(meta.program || 'Programa por completar')} · ${htmlEsc(meta.credits || '-')} créditos · Ciclo ${htmlEsc(meta.cycle || '-')}</div>
          </div>

          <div id="jm-syllabus-config" style="margin-bottom:16px">${config ? chips(config, label || null) : '<span class="jm-chip">generando...</span>'}</div>
          <div id="silabo-text" class="jm-paper-body" contenteditable="true" spellcheck="true">${bodyHtml}</div>
        </div>
      </div>
    `;

    JM.syllabus.raw = raw;
    JM.syllabus.meta = meta;
    if (config) JM.syllabus.config = config;

    window.STATE = window.STATE || STATE;
    window.STATE.silaboResult = raw;
  }

  async function generateSyllabusStream() {
    injectPrettyStyles();

    const course = q('s-course') ? q('s-course').value.trim() : '';

    if (!course) {
      toastSafe('El nombre del curso es obligatorio', 'error');
      return;
    }

    const meta = {
      course,
      program: q('s-program') ? q('s-program').value : '',
      credits: q('s-credits') ? q('s-credits').value : '',
      cycle: q('s-cycle') ? q('s-cycle').value : '',
      weeks: q('s-weeks') ? q('s-weeks').value : '16',
      modality: q('s-modal') ? q('s-modal').value : 'Presencial',
      graduate_profile: q('s-profile') ? q('s-profile').value : '',
      competency: q('s-competency') ? q('s-competency').value : '',
      start_date: q('s-start-date') ? q('s-start-date').value : '',
      sessions_per_week: q('s-sessions-per-week') ? q('s-sessions-per-week').value : '1'
    };

    const btn = q('btn-gen-silabo');

    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> JoMelAi generando sílabo...';
    }

    const host = syllabusResultHost();
    if (host) {
      host.innerHTML = `
        <div class="jm-paper-shell">
          <div class="jm-paper">
            <div class="jm-paper-title">
              <small>JoMelAi · Sílabo preliminar</small>
              <h2>Sílabo preliminar: ${htmlEsc(course)}</h2>
              <div class="jm-paper-meta">Preparando generación en vivo...</div>
            </div>
            <div class="jm-paper-body"><span class="ai-thinking"><span></span><span></span><span></span></span></div>
          </div>
        </div>
      `;
      host.scrollIntoView({ behavior: 'smooth' });
    }

    let raw = '';
    let config = null;

    try {
      await streamPost('/api/assistant/generate-syllabus-stream', {
        model: JM_MODEL,
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
        use_ai_seed: true,
        context_limit: 1,
        ai_timeout: 120
      }, {
        config(data) {
          config = data.tokens_config || config;
        },
        status() {
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
          toastSafe('✅ Sílabo generado', 'success');
        }
      });
    } catch (e) {
      raw += '\n\n⚠️ ' + e.message;
      renderSyllabus(raw, meta, config, 'error');
      toastSafe('Error al generar sílabo: ' + e.message, 'error');
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = '🤖 Generar sílabo con JoMelAi';
      }
    }
  }

  function copySyllabusOverride() {
    const text =
      JM.syllabus.raw ||
      (q('silabo-text') ? q('silabo-text').innerText : '') ||
      window.STATE?.silaboResult ||
      '';

    navigator.clipboard.writeText(cleanMarkers(text)).then(() => toastSafe('✅ Copiado', 'success'));
  }

  /* ══════════════════════════════════════════════════════
     EXPORTS / OVERRIDES
  ══════════════════════════════════════════════════════ */

  window.sendAiMessage = sendAiMessageOverride;
  window.sendAiMessageWith = sendAiMessageWithStream;
  window.jmContinueChat = continueChat;

  window.generateResource = generateResourceStream;
  window.continueResourceGeneration = continueResourceGeneration;
  window.copyResource = copyResourceOverride;
  window.downloadResourcePdf = downloadResourcePdf;

  window.generateSilabo = generateSyllabusStream;
  window.copySilabo = copySyllabusOverride;

  document.addEventListener('DOMContentLoaded', function () {
    injectPrettyStyles();

    setTimeout(function () {
      window.sendAiMessage = sendAiMessageOverride;
      window.sendAiMessageWith = sendAiMessageWithStream;
      window.generateResource = generateResourceStream;
      window.copyResource = copyResourceOverride;
      window.downloadResourcePdf = downloadResourcePdf;
      window.continueResourceGeneration = continueResourceGeneration;
      window.generateSilabo = generateSyllabusStream;
      window.copySilabo = copySyllabusOverride;
    }, 300);
  });
})();
/* JOMELAI_APP_STREAM_PRETTY_FULL_V1_END */
