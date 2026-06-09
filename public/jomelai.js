/* JOMELAI_LAYERED_BOOT_BRIDGE_V1
   Early bridge for legacy inline handlers. Keeps login/navigation alive even if app.js has a runtime issue.
*/
(function(){
  function qs(id){ return document.getElementById(id); }
  function showError(msg){ const el = qs('login-error'); if (el){ el.textContent = msg; el.style.display = 'block'; } else { console.error(msg); } }
  function setRoleText(role){ return role === 'superadmin' ? 'Superadmin' : (role === 'admin' ? 'Administrador' : 'Curriculista'); }
  function preferredPage(){
    const h = (location.hash || '').replace('#','').trim();
    if (h.startsWith('tecnico')) return 'tecnico';
    return h && document.getElementById('page-' + h) ? h : 'dashboard';
  }
  window.navigate = window.navigate || function(page){
    page = page || preferredPage();
    window.__JM_PENDING_NAV = page;
    document.querySelectorAll('.page').forEach(function(p){ p.classList.remove('active'); });
    document.querySelectorAll('.nav-item').forEach(function(n){ n.classList.remove('active'); });
    const target = qs('page-' + page);
    const nav = document.querySelector('[data-page="' + page + '"]');
    if (target) target.classList.add('active');
    if (nav) nav.classList.add('active');
    const bg = qs('bg-layer');
    if (bg) bg.className = 'bg-layer ' + ({dashboard:'bg-mixed',malla:'bg-blue',plan:'bg-purple',silabos:'bg-red',recursos:'bg-purple',tecnico:'bg-blue'}[page] || 'bg-mixed');
    if (page === 'tecnico' && typeof window.techShowRoute === 'function') {
      const h=(location.hash||'').replace('#','');
      window.techShowRoute(h.startsWith('tecnico/') ? h.split('/')[1] : 'setup');
    }
  };
  window.showApp = window.showApp || function(user){
    const login = qs('login-page'), app = qs('app'), fab = qs('fab');
    if (login) login.style.display = 'none';
    if (app) app.style.display = 'flex';
    if (fab) fab.style.display = 'flex';
    user = user || (window.STATE && window.STATE.user) || null;
    if (user) {
      const n = user.name || 'Curriculista';
      const role = user.role || 'curriculista';
      if (qs('welcome-name')) qs('welcome-name').textContent = n.split(' ')[0];
      if (qs('sidebar-name')) qs('sidebar-name').textContent = n;
      if (qs('sidebar-role')) qs('sidebar-role').textContent = setRoleText(role);
      if (qs('sidebar-avatar')) qs('sidebar-avatar').textContent = n.charAt(0).toUpperCase();
    }
    window.navigate(preferredPage());
  };
  window.doLogin = window.doLogin || async function(){
    const emailEl = qs('login-email');
    const passEl = qs('login-pass');
    const btn = qs('login-btn');
    const txt = qs('login-btn-text');
    const email = emailEl ? emailEl.value.trim() : '';
    const password = passEl ? passEl.value : '';
    if (!email || !password) { showError('Completa todos los campos.'); return; }
    if (btn) btn.disabled = true;
    if (txt) txt.innerHTML = '<span class="spinner"></span> Verificando...';
    try {
      const res = await fetch((window.API_BASE || '') + '/api/auth/login', {
        method:'POST', credentials:'include', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({email:email, password:password})
      });
      const data = await res.json();
      if (data.ok) {
        window.STATE = window.STATE || {};
        window.STATE.user = data.user || null;
        window.showApp(data.user || null);
      } else {
        showError(data.message || 'Credenciales inválidas.');
      }
    } catch(e) { showError('Error de conexión: ' + e.message); }
    finally { if (btn) btn.disabled = false; if (txt) txt.textContent = 'Ingresar a la plataforma'; }
  };
  window.fillDemo = window.fillDemo || function(){
    if (qs('login-email')) qs('login-email').value = 'rv@local.test';
    if (qs('login-pass')) qs('login-pass').value = '123';
  };
  document.addEventListener('DOMContentLoaded', function(){
    if (qs('login-email') && !qs('login-email').value) qs('login-email').value = 'rv@local.test';
    if (qs('login-pass') && !qs('login-pass').value) qs('login-pass').value = '123';
    document.querySelectorAll('[data-page]').forEach(function(el){
      el.addEventListener('click', function(){ const p = el.getAttribute('data-page'); if (typeof window.navigate === 'function') window.navigate(p); });
    });
  });
})();
