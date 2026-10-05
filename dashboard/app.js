/* Coliseu Estoque — Dashboard (SPA sem build).
 *
 * Usa exatamente a mesma API do app mobile. O perfil do usuário define o que aparece:
 * operador faz conferência cega; supervisor/admin acompanham, aprovam e configuram.
 */
'use strict';

(() => {
  // ───────────────────────────────────────────────────────────────────────────
  // Utilitários
  // ───────────────────────────────────────────────────────────────────────────
  class Raw { constructor(s) { this.s = s; } }
  const raw = (s) => new Raw(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const out = (v) => (v instanceof Raw ? v.s : Array.isArray(v) ? v.map(out).join('') : v == null || v === false ? '' : esc(v));
  /** Template com escape automático. Use raw() só para HTML gerado por html``. */
  const html = (strings, ...vals) => raw(strings.reduce((acc, str, i) => acc + str + (i < vals.length ? out(vals[i]) : ''), ''));

  const $ = (sel, el = document) => el.querySelector(sel);
  const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
  const store = {
    get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
    set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* modo privado */ } },
    del: (k) => { try { localStorage.removeItem(k); } catch { /* modo privado */ } },
  };
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (crypto.getRandomValues(new Uint8Array(1))[0] & 15);
      return (c === 'x' ? r : (r & 3) | 8).toString(16);
    }));
  const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

  const fmtDateTime = (v) => (v ? new Date(v).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '—');
  const fmtDate = (v) => (v ? new Date(v).toLocaleDateString('pt-BR') : '—');
  const fmtQty = (v) => {
    if (v === null || v === undefined || v === '') return '—';
    const n = Number(v);
    return Number.isInteger(n) ? n.toLocaleString('pt-BR') : n.toLocaleString('pt-BR', { maximumFractionDigits: 4 });
  };
  const fmtDuration = (s) => {
    if (!s) return '—';
    const m = Math.round(s / 60);
    return m < 60 ? `${m} min` : `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}`;
  };
  const ago = (v) => {
    if (!v) return 'nunca';
    const s = Math.round((Date.now() - new Date(v).getTime()) / 1000);
    if (s < 60) return 'agora';
    if (s < 3600) return `há ${Math.round(s / 60)} min`;
    if (s < 86400) return `há ${Math.round(s / 3600)} h`;
    return `há ${Math.round(s / 86400)} d`;
  };

  const STATUS_LABEL = {
    AGUARDANDO: 'Aguardando', EM_CONFERENCIA: 'Em conferência', DIVERGENTE: 'Recontagem',
    AGUARDANDO_APROVACAO: 'Aprovação', CONCLUIDO: 'Concluído', CANCELADO: 'Cancelado',
  };
  const RESULT_LABEL = { OK: 'OK', FALTA: 'Falta', SOBRA: 'Sobra', PENDENTE: 'Pendente' };
  const WB_LABEL = { NAO_APLICAVEL: '—', PENDENTE: 'Pendente', GRAVADO: 'Gravado', ERRO: 'Erro' };
  const ROLE_LABEL = { operador: 'Operador', supervisor: 'Supervisor', admin: 'Administrador' };
  const badge = (code, label) => html`<span class="badge b-${code}">${label}</span>`;

  // ── Toasts, sons e modais ─────────────────────────────────────────────────
  function toast(msg, isError = false) {
    const el = document.createElement('div');
    el.className = `toast${isError ? ' err' : ''}`;
    el.textContent = msg;
    $('#toasts').appendChild(el);
    setTimeout(() => el.remove(), isError ? 6000 : 3500);
  }

  let audioCtx;
  function beep(ok) {
    try {
      audioCtx ??= new (window.AudioContext || window.webkitAudioContext)();
      const o = audioCtx.createOscillator();
      const g = audioCtx.createGain();
      o.frequency.value = ok ? 1250 : 220;
      o.type = ok ? 'sine' : 'square';
      g.gain.value = 0.08;
      o.connect(g).connect(audioCtx.destination);
      o.start();
      o.stop(audioCtx.currentTime + (ok ? 0.08 : 0.35));
    } catch { /* sem áudio */ }
  }

  /** Abre um modal. `onSubmit(form)` retorna false para manter aberto. */
  function modal({ title, body, submitLabel = 'Confirmar', danger = false, onSubmit, cancelLabel = 'Cancelar' }) {
    const bg = document.createElement('div');
    bg.className = 'modal-bg';
    bg.innerHTML = html`
      <form class="modal" novalidate>
        <header>${title}</header>
        <div class="body">${body}</div>
        <footer>
          ${cancelLabel ? html`<button type="button" class="btn" data-close>${cancelLabel}</button>` : ''}
          ${submitLabel ? html`<button type="submit" class="btn ${danger ? 'danger' : 'primary'}">${submitLabel}</button>` : ''}
        </footer>
      </form>`.s;
    document.body.appendChild(bg);
    const form = $('form', bg);
    const close = () => bg.remove();
    $$('[data-close]', bg).forEach((b) => b.addEventListener('click', close));
    bg.addEventListener('mousedown', (e) => { if (e.target === bg) close(); });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = $('button[type=submit]', form);
      if (btn) btn.disabled = true;
      try {
        const keep = onSubmit ? await onSubmit(form) : true;
        if (keep !== false) close();
      } catch (err) {
        toast(err.message, true);
      } finally {
        if (btn) btn.disabled = false;
      }
    });
    setTimeout(() => $('input, textarea, select', form)?.focus(), 30);
    return { close, el: bg };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sessão e API
  // ───────────────────────────────────────────────────────────────────────────
  const state = {
    token: store.get('est.token'),
    user: null,
    company: null,
    settings: {},
    view: null, // { onEvent?, dispose? }
  };
  const isSup = () => state.user && (state.user.role === 'supervisor' || state.user.role === 'admin');
  const isAdmin = () => state.user?.role === 'admin';

  class ApiError extends Error {
    constructor(message, status, data) { super(message); this.status = status; this.code = data?.code; this.data = data; }
  }

  async function api(method, path, body) {
    const res = await fetch(path, {
      method,
      headers: {
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (res.status === 204) return null;
    const data = await res.json().catch(() => ({}));
    if (res.status === 401 && state.token && !path.startsWith('/v1/auth/')) {
      logout('Sua sessão expirou. Entre novamente.');
      throw new ApiError(data.error || 'Sessão expirada', 401, data);
    }
    if (!res.ok) throw new ApiError(data.error || `Erro ${res.status}`, res.status, data);
    return data;
  }

  function setSession(s) {
    state.token = s.token;
    state.user = s.user;
    state.company = s.company;
    state.settings = s.settings || {};
    store.set('est.token', s.token);
  }

  function logout(message) {
    state.token = null;
    state.user = null;
    store.del('est.token');
    stopStream();
    shellBuilt = false;
    if (message) toast(message, true);
    location.hash = '#/login';
    render();
  }

  // Renova o token a cada 4 h com o painel aberto (token vale 12 h).
  setInterval(async () => {
    if (!state.token) return;
    try { const r = await api('POST', '/v1/auth/refresh'); state.token = r.token; store.set('est.token', r.token); restartStream(); } catch { /* 401 já trata */ }
  }, 4 * 3600_000);

  // ── Tempo real ────────────────────────────────────────────────────────────
  let stream = null;
  function startStream() {
    if (stream || !state.token) return;
    stream = new EventSource(`/v1/stream?access_token=${encodeURIComponent(state.token)}`);
    const setLive = (on) => { const d = $('#live-dot'); if (d) d.classList.toggle('on', on); const t = $('#live-text'); if (t) t.textContent = on ? 'Ao vivo' : 'Reconectando…'; };
    stream.onopen = () => setLive(true);
    stream.onerror = () => setLive(false);
    for (const type of ['document.updated', 'scan.added', 'documents.synced', 'worker.heartbeat']) {
      stream.addEventListener(type, (e) => {
        try { state.view?.onEvent?.(JSON.parse(e.data)); } catch { /* evento malformado */ }
      });
    }
  }
  function stopStream() { stream?.close(); stream = null; }
  function restartStream() { stopStream(); startStream(); }

  // ───────────────────────────────────────────────────────────────────────────
  // Layout
  // ───────────────────────────────────────────────────────────────────────────
  const ICON = {
    panel: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/></svg>',
    docs: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>',
    box: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7L12 12l8.7-5M12 22V12"/></svg>',
    users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
    log: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/></svg>',
    menu: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 12h18M3 6h18M3 18h18"/></svg>',
  };

  const NAV = [
    { href: '#/', label: 'Painel', icon: 'panel', sup: true },
    { href: '#/documentos', label: 'Documentos', icon: 'docs' },
    { href: '#/produtos', label: 'Produtos', icon: 'box' },
    { href: '#/usuarios', label: 'Usuários', icon: 'users', sup: true },
    { href: '#/auditoria', label: 'Auditoria', icon: 'log', sup: true },
    { href: '#/configuracoes', label: 'Configurações', icon: 'gear', sup: true },
  ];

  let shellBuilt = false;
  function buildShell() {
    const links = NAV.filter((n) => !n.sup || isSup());
    $('#root').innerHTML = html`
      <div class="shell">
        <aside class="sidebar" id="sidebar">
          <div class="brand"><div class="brand-mark">C</div><div>Coliseu Estoque<small>${state.company?.name || ''}</small></div></div>
          ${links.map((n) => html`<a class="nav-link" href="${n.href}" data-nav="${n.href}">${raw(ICON[n.icon])}<span>${n.label}</span></a>`)}
          <div class="sidebar-foot">
            <div class="who">${state.user.name}</div>
            <div class="muted">${ROLE_LABEL[state.user.role]}</div>
            <div class="muted" style="margin-top:8px"><span class="live-dot" id="live-dot"></span><span id="live-text">Conectando…</span></div>
            <button class="btn sm" id="logout" style="margin-top:12px;width:100%">Sair</button>
          </div>
        </aside>
        <div>
          <div class="topbar-mobile"><button class="btn sm" id="menu-btn" aria-label="Menu">${raw(ICON.menu)}</button><strong>Coliseu Estoque</strong></div>
          <main id="main"></main>
        </div>
      </div>`.s;
    $('#logout').addEventListener('click', () => logout());
    $('#menu-btn').addEventListener('click', () => $('#sidebar').classList.toggle('open'));
    $$('.nav-link').forEach((a) => a.addEventListener('click', () => $('#sidebar').classList.remove('open')));
    shellBuilt = true;
    startStream();
  }

  function markNav(hash) {
    $$('.nav-link').forEach((a) => {
      const href = a.dataset.nav;
      a.classList.toggle('active', href === '#/' ? hash === '#/' : hash.startsWith(href));
    });
  }

  const main = () => $('#main');
  const pageHead = (title, sub, actions = '') => html`
    <div class="page-head"><div><h1>${title}</h1>${sub ? html`<div class="sub">${sub}</div>` : ''}</div><div class="btn-row">${actions}</div></div>`;

  // ───────────────────────────────────────────────────────────────────────────
  // Roteador
  // ───────────────────────────────────────────────────────────────────────────
  const ROUTES = [
    { re: /^#\/login$/, view: viewLogin, public: true },
    { re: /^#\/$/, view: viewPanel, sup: true },
    { re: /^#\/documentos$/, view: viewDocuments },
    { re: /^#\/documentos\/([0-9a-f-]{36})$/, view: viewDocument },
    { re: /^#\/conferir\/([0-9a-f-]{36})$/, view: viewConference },
    { re: /^#\/produtos$/, view: viewProducts },
    { re: /^#\/usuarios$/, view: viewUsers, sup: true },
    { re: /^#\/auditoria$/, view: viewAudit, sup: true },
    { re: /^#\/configuracoes$/, view: viewSettings, sup: true },
  ];

  async function render() {
    const hash = location.hash || '#/';
    state.view?.dispose?.();
    state.view = null;

    if (!state.token) {
      if (hash !== '#/login') { location.hash = '#/login'; return; }
      return viewLogin();
    }
    if (!state.user) {
      try {
        const me = await api('GET', '/v1/auth/me');
        state.user = me.user; state.company = me.company; state.settings = me.settings;
      } catch (err) {
        if (err.status === 401 || err.status === 403) logout(err.message);
        else $('#root').innerHTML = html`<div class="auth"><div class="card">Não foi possível conectar à API: ${err.message}</div></div>`.s;
        return;
      }
    }
    if (hash === '#/login') { location.hash = isSup() ? '#/' : '#/documentos'; return; }

    const routeDef = ROUTES.find((r) => r.re.test(hash));
    if (!routeDef || (routeDef.sup && !isSup())) { location.hash = isSup() ? '#/' : '#/documentos'; return; }
    if (!shellBuilt) buildShell();
    markNav(hash);
    main().innerHTML = '<div class="empty">Carregando…</div>';
    try {
      await routeDef.view(...(hash.match(routeDef.re).slice(1)));
    } catch (err) {
      if (err.status !== 401) main().innerHTML = html`<div class="card empty">${err.message}</div>`.s;
    }
  }
  window.addEventListener('hashchange', render);

  // ───────────────────────────────────────────────────────────────────────────
  // Login / primeiro acesso
  // ───────────────────────────────────────────────────────────────────────────
  function viewLogin() {
    shellBuilt = false;
    const serial = store.get('est.serial') || '';
    const key = store.get('est.key') || '';
    let company = null;

    const shell = (inner) => {
      $('#root').innerHTML = html`<div class="auth"><div class="card">
        <div class="brand-mark">C</div>
        ${inner}
      </div></div>`.s;
    };

    const stepCompany = () => {
      shell(html`
        <h1>Coliseu Estoque</h1>
        <div class="sub">Identifique a empresa com os dados do painel de licenças.</div>
        <form id="f">
          <div class="field"><label for="serial">Serial da empresa</label>
            <input class="input mono" id="serial" required value="${serial}" placeholder="00000000-0000-0000-0000-000000000000" autocomplete="off">
            <div class="help">Em Empresas, no painel de licenças (campo "Serial").</div></div>
          <div class="field"><label for="key">Chave do módulo Estoque</label>
            <input class="input mono" id="key" required value="${key}" placeholder="COL-XXXX-XXXX-XXXX" autocomplete="off"></div>
          <label class="check"><input type="checkbox" id="remember" ${key ? 'checked' : ''}> Lembrar neste computador</label>
          <button class="btn primary lg" style="width:100%">Continuar</button>
        </form>`);
      $('#f').addEventListener('submit', async (e) => {
        e.preventDefault();
        const s = $('#serial').value.trim();
        const k = $('#key').value.trim().toUpperCase();
        try {
          company = await api('POST', '/v1/auth/company', { tenantId: s, companyKey: k });
          store.set('est.serial', s);
          if ($('#remember').checked) store.set('est.key', k); else store.del('est.key');
          company.serial = s; company.key = k;
          company.needsSetup ? stepSetup() : stepLogin();
        } catch (err) { toast(err.message, true); }
      });
    };

    const stepLogin = () => {
      shell(html`
        <h1>${company.name || 'Entrar'}</h1>
        <div class="sub">Entre com seu usuário. <a href="#" id="change">Trocar empresa</a></div>
        <form id="f">
          <div class="field"><label for="login">Usuário</label><input class="input" id="login" required autocomplete="username"></div>
          <div class="field"><label for="pass">Senha</label><input class="input" id="pass" type="password" required autocomplete="current-password"></div>
          <button class="btn primary lg" style="width:100%">Entrar</button>
        </form>`);
      $('#change').addEventListener('click', (e) => { e.preventDefault(); stepCompany(); });
      $('#f').addEventListener('submit', async (e) => {
        e.preventDefault();
        try {
          setSession(await api('POST', '/v1/auth/login', {
            tenantId: company.serial, companyKey: company.key, login: $('#login').value, password: $('#pass').value,
          }));
          location.hash = isSup() ? '#/' : '#/documentos';
          render();
        } catch (err) { toast(err.message, true); }
      });
    };

    const stepSetup = () => {
      shell(html`
        <h1>Primeiro acesso</h1>
        <div class="sub">${company.name || 'Empresa'} ainda não tem usuários. Crie o administrador.</div>
        <form id="f">
          <div class="field"><label for="name">Seu nome</label><input class="input" id="name" required></div>
          <div class="field"><label for="login">Usuário</label><input class="input" id="login" required autocomplete="username"></div>
          <div class="field"><label for="pass">Senha</label><input class="input" id="pass" type="password" minlength="8" required autocomplete="new-password">
            <div class="help">Mínimo de 8 caracteres.</div></div>
          <div class="field"><label for="pass2">Confirme a senha</label><input class="input" id="pass2" type="password" required autocomplete="new-password"></div>
          <button class="btn primary lg" style="width:100%">Criar administrador</button>
        </form>`);
      $('#f').addEventListener('submit', async (e) => {
        e.preventDefault();
        if ($('#pass').value !== $('#pass2').value) return toast('As senhas não conferem', true);
        try {
          setSession(await api('POST', '/v1/auth/setup', {
            tenantId: company.serial, companyKey: company.key,
            name: $('#name').value, login: $('#login').value, password: $('#pass').value,
          }));
          toast('Empresa configurada. Cadastre os operadores em Usuários.');
          location.hash = '#/';
          render();
        } catch (err) { toast(err.message, true); }
      });
    };

    stepCompany();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Painel
  // ───────────────────────────────────────────────────────────────────────────
  async function viewPanel() {
    const load = async () => {
      const [s, attention] = await Promise.all([
        api('GET', '/v1/dashboard/summary'),
        api('GET', '/v1/documents?status=AGUARDANDO_APROVACAO,DIVERGENTE&limit=8&days=30'),
      ]);
      const st = s.byStatus;
      const workerAge = s.worker.seenAt ? (Date.now() - new Date(s.worker.seenAt)) / 60000 : Infinity;
      const workerOk = workerAge < 15;
      const divRate = s.today.concluidos ? Math.round((s.today.com_divergencia / s.today.concluidos) * 100) : 0;

      main().innerHTML = html`
        ${pageHead('Painel', `${state.company.name} · hoje, ${new Date().toLocaleDateString('pt-BR')}`)}
        ${!workerOk ? html`<div class="alert-box warn">O Worker do ERP não se comunica ${s.worker.seenAt ? ago(s.worker.seenAt) : 'desde a instalação'}. Novos pedidos e o retorno ao ERP estão parados — verifique o serviço ColiseuWorkervett no servidor do cliente.</div>` : ''}
        ${s.writeback.erros ? html`<div class="alert-box danger">${s.writeback.erros} conferência(s) com erro ao gravar no ERP. <a href="#/documentos" data-wb="ERRO">Ver documentos</a></div>` : ''}
        <div class="grid kpis">
          <div class="card kpi"><div class="label">Na fila</div><div class="value">${st.AGUARDANDO || 0}</div><div class="hint">aguardando conferência</div></div>
          <div class="card kpi"><div class="label">Em conferência</div><div class="value">${st.EM_CONFERENCIA || 0}</div><div class="hint">agora</div></div>
          <div class="card kpi ${st.DIVERGENTE ? 'alert' : ''}"><div class="label">Recontagem</div><div class="value">${st.DIVERGENTE || 0}</div><div class="hint">com divergência</div></div>
          <div class="card kpi ${st.AGUARDANDO_APROVACAO ? 'danger' : ''}"><div class="label">Aprovação</div><div class="value">${st.AGUARDANDO_APROVACAO || 0}</div><div class="hint">aguardando supervisor</div></div>
          <div class="card kpi"><div class="label">Concluídos hoje</div><div class="value">${s.today.concluidos}</div><div class="hint">${divRate}% com divergência · ${fmtDuration(s.today.tempo_medio_s)} em média</div></div>
        </div>
        <div class="grid two" style="margin-top:16px">
          <div class="card">
            <div class="card-pad" style="padding-bottom:0"><h2>Precisam de atenção</h2></div>
            ${attention.items.length ? html`<div class="table-wrap"><table>
              <thead><tr><th>Documento</th><th>Cliente</th><th>Status</th><th>Operador</th></tr></thead>
              <tbody>${attention.items.map((d) => html`<tr class="clickable" data-href="#/documentos/${d.id}">
                <td><strong>${d.number || d.erpKey}</strong></td><td>${d.customerName || '—'}</td>
                <td>${badge(d.status, STATUS_LABEL[d.status])}</td><td>${d.finishedByName || d.lock?.userName || d.startedByName || '—'}</td></tr>`)}
              </tbody></table></div>` : html`<div class="empty">Nada pendente. 👌</div>`}
          </div>
          <div class="card card-pad">
            <h2>Integração com o ERP</h2>
            <div class="meta-grid" style="grid-template-columns:1fr 1fr">
              <div><div class="k">Worker</div><div class="v">${workerOk ? badge('OK', 'Online') : badge('ERRO', 'Offline')} <span class="muted">${ago(s.worker.seenAt)}</span></div></div>
              <div><div class="k">Versão</div><div class="v">${s.worker.info?.version || '—'}</div></div>
              <div><div class="k">Retorno ao ERP</div><div class="v">${s.worker.info?.writebackEnabled ? 'Ativo' : 'Desligado'}</div></div>
              <div><div class="k">Pendentes</div><div class="v">${s.writeback.pendentes}</div></div>
            </div>
            <div style="margin-top:14px">${s.sync.map((x) => html`<div class="count-item" style="padding:6px 0"><span>${x.entity}</span><span class="muted">${ago(x.last_at)}</span></div>`)}</div>
          </div>
        </div>
        <div class="card" style="margin-top:16px">
          <div class="card-pad" style="padding-bottom:0"><h2>Produtividade de hoje</h2></div>
          ${s.operators.length ? html`<div class="table-wrap"><table>
            <thead><tr><th>Operador</th><th class="num">Documentos</th><th class="num">Leituras</th><th class="num">Unidades</th><th>Última leitura</th></tr></thead>
            <tbody>${s.operators.map((o) => html`<tr><td>${o.name}</td><td class="num">${o.documentos}</td><td class="num">${o.leituras}</td><td class="num">${fmtQty(o.unidades)}</td><td>${ago(o.ultima_leitura)}</td></tr>`)}</tbody>
          </table></div>` : html`<div class="empty">Nenhuma leitura hoje.</div>`}
        </div>`.s;
      $$('tr[data-href]').forEach((tr) => tr.addEventListener('click', () => { location.hash = tr.dataset.href; }));
    };
    await load();
    state.view = { onEvent: debounce(() => load().catch(() => {}), 1500) };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Documentos
  // ───────────────────────────────────────────────────────────────────────────
  const FILTERS = [
    { key: 'AGUARDANDO,EM_CONFERENCIA,DIVERGENTE,AGUARDANDO_APROVACAO', label: 'Ativos' },
    { key: '', label: 'Todos' },
    { key: 'AGUARDANDO', label: 'Aguardando' },
    { key: 'EM_CONFERENCIA', label: 'Em conferência' },
    { key: 'DIVERGENTE', label: 'Recontagem' },
    { key: 'AGUARDANDO_APROVACAO', label: 'Aprovação' },
    { key: 'CONCLUIDO', label: 'Concluídos' },
    { key: 'CANCELADO', label: 'Cancelados' },
  ];

  async function viewDocuments() {
    const f = {
      status: store.get('est.docs.status') ?? FILTERS[0].key,
      q: '',
      days: store.get('est.docs.days') || '7',
      offset: 0,
      // Filtro de retorno ao ERP vem só do link do painel e vale uma vez.
      writeback: pendingWritebackFilter,
    };
    pendingWritebackFilter = null;
    let items = [];
    let hasMore = false;

    main().innerHTML = html`
      ${pageHead('Documentos', 'Notas e pedidos recebidos do ERP para conferência')}
      <div class="card">
        <div class="toolbar">
          <div class="chips" id="chips">${FILTERS.map((x) => html`<button class="chip ${x.key === f.status ? 'active' : ''}" data-status="${x.key}">${x.label}</button>`)}</div>
          <input class="input" id="q" placeholder="Número, cliente ou chave" style="margin-left:auto">
          <select class="input" id="days" style="width:150px">
            ${[['1', 'Hoje'], ['3', '3 dias'], ['7', '7 dias'], ['30', '30 dias'], ['90', '90 dias']].map(([v, l]) => html`<option value="${v}" ${v === f.days ? 'selected' : ''}>${l}</option>`)}
          </select>
        </div>
        <div id="list"></div>
      </div>`.s;

    const load = async (append = false) => {
      f.offset = append ? items.length : 0;
      const params = new URLSearchParams({ limit: '50', offset: String(f.offset), days: f.days });
      if (f.status) params.set('status', f.status);
      if (f.q) params.set('q', f.q);
      if (f.writeback) params.set('writeback', f.writeback);
      const r = await api('GET', `/v1/documents?${params}`);
      items = append ? items.concat(r.items) : r.items;
      hasMore = r.items.length === 50;
      draw();
    };

    const draw = () => {
      $('#list').innerHTML = items.length ? html`<div class="table-wrap"><table>
        <thead><tr><th>Documento</th><th>Cliente</th><th>Emissão</th><th class="num">Itens</th><th>Status</th><th>Responsável</th>${isSup() ? html`<th>ERP</th>` : ''}</tr></thead>
        <tbody>${items.map((d) => html`<tr class="clickable" data-id="${d.id}">
          <td><strong>${d.number || d.erpKey}</strong>${d.priority > 0 ? html` <span class="badge b-SOBRA">Prioridade</span>` : ''}<div class="muted">${d.source === 'NFS' ? 'Nota de saída' : 'Pedido'}${d.series ? ` · série ${d.series}` : ''}</div></td>
          <td>${d.customerName || '—'}<div class="muted">${d.sellerName || ''}</div></td>
          <td>${fmtDateTime(d.issuedAt)}</td>
          <td class="num">${d.itemCount ?? '—'}</td>
          <td>${badge(d.status, STATUS_LABEL[d.status])}${d.erpChanged ? html` <span class="badge b-FALTA" title="O ERP alterou o documento durante a conferência">ERP alterou</span>` : ''}</td>
          <td>${d.lock ? html`<span title="Reservado até ${fmtDateTime(d.lock.expiresAt)}">🔒 ${d.lock.userName}</span>` : (d.finishedByName || d.startedByName || '—')}</td>
          ${isSup() ? html`<td>${d.writebackStatus !== 'NAO_APLICAVEL' ? badge(d.writebackStatus, WB_LABEL[d.writebackStatus]) : ''}</td>` : ''}
        </tr>`)}</tbody></table></div>
        ${hasMore ? html`<div style="padding:14px;text-align:center"><button class="btn" id="more">Carregar mais</button></div>` : ''}`.s
        : '<div class="empty">Nenhum documento neste filtro.</div>';
      $$('#list tr[data-id]').forEach((tr) => tr.addEventListener('click', () => { location.hash = `#/documentos/${tr.dataset.id}`; }));
      $('#more')?.addEventListener('click', () => load(true).catch((e) => toast(e.message, true)));
    };

    $$('#chips .chip').forEach((c) => c.addEventListener('click', () => {
      f.status = c.dataset.status;
      f.writeback = null;
      store.set('est.docs.status', f.status);
      $$('#chips .chip').forEach((x) => x.classList.toggle('active', x === c));
      load().catch((e) => toast(e.message, true));
    }));
    $('#q').addEventListener('input', debounce((e) => { f.q = e.target.value.trim(); load().catch((er) => toast(er.message, true)); }, 300));
    $('#days').addEventListener('change', (e) => { f.days = e.target.value; store.set('est.docs.days', f.days); load().catch((er) => toast(er.message, true)); });

    await load();
    state.view = { onEvent: debounce((ev) => { if (ev.type !== 'worker.heartbeat') load().catch(() => {}); }, 1200) };
  }

  async function viewDocument(id) {
    let tab = 'itens';
    const load = async () => {
      const d = await api('GET', `/v1/documents/${id}`);
      const sup = isSup();
      const canCount = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE'].includes(d.status) && !d.erpCancelled;
      const lockedByOther = d.lock && !d.lock.mine;

      const actions = [
        canCount ? html`<button class="btn primary" id="a-count" ${lockedByOther && !sup ? 'disabled' : ''}>${d.lock?.mine ? 'Continuar conferência' : d.status === 'DIVERGENTE' ? 'Recontar' : 'Conferir'}</button>` : '',
        sup && ['AGUARDANDO_APROVACAO', 'DIVERGENTE'].includes(d.status) ? html`<button class="btn ok" id="a-approve">Aprovar</button>` : '',
        sup && (['AGUARDANDO_APROVACAO', 'DIVERGENTE'].includes(d.status) || (d.status === 'CONCLUIDO' && d.writebackStatus !== 'GRAVADO')) ? html`<button class="btn" id="a-reopen">Reabrir recontagem</button>` : '',
        sup && d.lock ? html`<button class="btn" id="a-release">Liberar reserva</button>` : '',
        sup && d.status !== 'CANCELADO' && d.writebackStatus !== 'GRAVADO' && (d.startedAt || d.round > 0) ? html`<button class="btn danger" id="a-reset">Zerar conferência</button>` : '',
      ];

      const diff = (i) => {
        if (i.countedQty === null || i.countedQty === undefined) return '';
        const n = Number(i.countedQty) - Number(i.expectedQty);
        return n === 0 ? '0' : (n > 0 ? '+' : '') + fmtQty(n);
      };

      main().innerHTML = html`
        ${pageHead(`${d.source === 'NFS' ? 'Nota' : 'Pedido'} ${d.number || d.erpKey}`, d.customerName || '', actions)}
        ${d.erpCancelled ? html`<div class="alert-box danger">Documento cancelado no ERP${d.status === 'CONCLUIDO' ? ' depois de conferido' : ''}.</div>` : ''}
        ${d.erpChanged ? html`<div class="alert-box warn">O ERP alterou este documento depois que a conferência começou. Confira os itens e, se necessário, zere a conferência.</div>` : ''}
        ${d.writebackStatus === 'ERRO' && sup ? html`<div class="alert-box danger">Erro ao gravar no ERP: ${d.writebackError || 'desconhecido'}. O Worker tenta novamente a cada 5 minutos.</div>` : ''}
        ${lockedByOther ? html`<div class="alert-box info">Em conferência por <strong>${d.lock.userName}</strong> até ${fmtDateTime(d.lock.expiresAt)}.</div>` : ''}
        <div class="card card-pad">
          <div class="meta-grid">
            <div><div class="k">Status</div><div class="v">${badge(d.status, STATUS_LABEL[d.status])}${d.round > 0 ? html` <span class="muted">rodada ${d.round + 1}</span>` : ''}</div></div>
            <div><div class="k">Emissão</div><div class="v">${fmtDateTime(d.issuedAt)}</div></div>
            <div><div class="k">Vendedor</div><div class="v">${d.sellerName || '—'}</div></div>
            <div><div class="k">Chave ERP</div><div class="v mono">${d.erpKey}</div></div>
            <div><div class="k">Início</div><div class="v">${fmtDateTime(d.startedAt)} <span class="muted">${d.startedByName || ''}</span></div></div>
            <div><div class="k">Fim</div><div class="v">${fmtDateTime(d.finishedAt)} <span class="muted">${d.finishedByName || ''}</span></div></div>
            ${d.approvedAt ? html`<div><div class="k">Aprovação</div><div class="v">${fmtDateTime(d.approvedAt)} <span class="muted">${d.approvedByName || ''}</span></div></div>` : ''}
            ${sup ? html`<div><div class="k">Retorno ERP</div><div class="v">${badge(d.writebackStatus === 'NAO_APLICAVEL' ? 'PENDENTE' : d.writebackStatus, WB_LABEL[d.writebackStatus])}</div></div>` : ''}
            ${sup && !['CONCLUIDO', 'CANCELADO'].includes(d.status) ? html`<div><div class="k">Prioridade</div><div class="v"><select class="input" id="prio" style="height:30px;width:120px">
              ${[[0, 'Normal'], [5, 'Alta'], [10, 'Urgente']].map(([v, l]) => html`<option value="${v}" ${Number(d.priority) === v ? 'selected' : ''}>${l}</option>`)}</select></div></div>` : ''}
          </div>
          ${d.justification ? html`<div style="margin-top:14px"><div class="k muted" style="font-size:12px;font-weight:600">JUSTIFICATIVA</div><div>${d.justification}</div></div>` : ''}
        </div>
        ${sup ? html`<div class="chips" style="margin:16px 0 10px">
          ${[['itens', 'Itens'], ['leituras', 'Leituras'], ['historico', 'Histórico']].map(([k, l]) => html`<button class="chip ${tab === k ? 'active' : ''}" data-tab="${k}">${l}</button>`)}</div>` : html`<div style="height:16px"></div>`}
        <div class="card" id="tab-body">
          ${sup ? html`<div class="table-wrap"><table>
            <thead><tr><th>Seq</th><th>Código</th><th>Descrição</th><th>Un</th><th class="num">Esperado</th><th class="num">Contado</th><th class="num">Dif.</th><th>Resultado</th></tr></thead>
            <tbody>${d.items.map((i) => html`<tr>
              <td class="muted">${i.isExtra ? 'extra' : i.seq}</td><td class="mono">${i.productErpId}</td><td>${i.description}</td><td>${i.unit || ''}</td>
              <td class="num">${fmtQty(i.expectedQty)}</td><td class="num">${fmtQty(i.countedQty)}</td><td class="num">${diff(i)}</td>
              <td>${badge(i.result, RESULT_LABEL[i.result])}</td></tr>`)}</tbody></table></div>`
            : html`<div class="table-wrap"><table>
              <thead><tr><th>Código</th><th>Descrição</th><th>Un</th><th class="num">Contado (rodada)</th><th></th></tr></thead>
              <tbody>${d.items.map((i) => html`<tr><td class="mono">${i.productErpId}</td><td>${i.description}</td><td>${i.unit || ''}</td>
                <td class="num">${fmtQty(d.counts[i.productErpId] ?? 0)}</td><td>${i.mustRecount ? badge('SOBRA', 'Recontar') : ''}</td></tr>`)}</tbody></table></div>`}
        </div>`.s;

      $('#a-count')?.addEventListener('click', () => { location.hash = `#/conferir/${id}`; });
      $('#a-release')?.addEventListener('click', async () => {
        try { await api('POST', `/v1/documents/${id}/release`); toast('Reserva liberada'); load(); } catch (e) { toast(e.message, true); }
      });
      $('#prio')?.addEventListener('change', async (e) => {
        try { await api('PATCH', `/v1/documents/${id}`, { priority: Number(e.target.value) }); toast('Prioridade atualizada'); } catch (er) { toast(er.message, true); }
      });
      $('#a-approve')?.addEventListener('click', () => modal({
        title: 'Aprovar conferência',
        body: html`${d.hasDivergence ? html`<div class="alert-box warn">Este documento tem divergência. A aprovação grava no ERP as quantidades contadas.</div>` : ''}
          <div class="field"><label for="just">Justificativa</label><textarea class="input" id="just" ${d.hasDivergence && state.settings.requireJustification ? 'required' : ''} placeholder="Ex.: falta confirmada no estoque; cliente avisado"></textarea></div>`,
        submitLabel: 'Aprovar',
        onSubmit: async (form) => { await api('POST', `/v1/documents/${id}/approve`, { justification: $('#just', form).value }); toast('Conferência aprovada'); load(); },
      }));
      $('#a-reopen')?.addEventListener('click', () => {
        const products = [...new Map(d.items.map((i) => [i.productErpId, i])).values()];
        modal({
          title: 'Reabrir para recontagem',
          body: html`<p class="muted" style="margin-top:0">Marque os produtos que o operador deve recontar. Os divergentes já vêm marcados.</p>
            <div style="max-height:320px;overflow-y:auto">${products.map((i) => html`<label class="check"><input type="checkbox" name="p" value="${i.productErpId}" ${i.result !== 'OK' ? 'checked' : ''}> <span class="mono">${i.productErpId}</span> ${i.description}</label>`)}</div>`,
          submitLabel: 'Reabrir',
          onSubmit: async (form) => {
            const sel = $$('input[name=p]:checked', form).map((c) => c.value);
            await api('POST', `/v1/documents/${id}/reopen`, { products: sel });
            toast('Documento reaberto para recontagem'); load();
          },
        });
      });
      $('#a-reset')?.addEventListener('click', () => modal({
        title: 'Zerar conferência',
        body: html`<p style="margin-top:0">Todas as leituras serão estornadas e o documento volta para a fila. Esta ação fica registrada na auditoria.</p>`,
        submitLabel: 'Zerar', danger: true,
        onSubmit: async () => { await api('POST', `/v1/documents/${id}/reset`); toast('Conferência zerada'); load(); },
      }));
      $$('[data-tab]').forEach((b) => b.addEventListener('click', async () => {
        tab = b.dataset.tab;
        $$('[data-tab]').forEach((x) => x.classList.toggle('active', x === b));
        if (tab === 'itens') return load();
        await drawTab();
      }));
      if (tab !== 'itens') await drawTab();
    };

    const drawTab = async () => {
      const body = $('#tab-body');
      if (tab === 'leituras') {
        const r = await api('GET', `/v1/documents/${id}/scans`);
        body.innerHTML = r.items.length ? html`<div class="table-wrap"><table>
          <thead><tr><th>Quando</th><th>Rodada</th><th>Código lido</th><th>Produto</th><th class="num">Qtd</th><th>Origem</th><th>Operador</th></tr></thead>
          <tbody>${r.items.map((s) => html`<tr style="${s.voided ? 'opacity:.45;text-decoration:line-through' : ''}">
            <td>${fmtDateTime(s.scanned_at)}</td><td>${s.round + 1}</td><td class="mono">${s.barcode || '—'}</td>
            <td>${s.product_erp_id ? html`<span class="mono">${s.product_erp_id}</span> ${s.description || ''}` : badge('FALTA', 'Não reconhecido')}</td>
            <td class="num">${fmtQty(s.qty)}</td><td>${s.origin}</td><td>${s.user_name || '—'}</td></tr>`)}</tbody></table></div>`.s
          : '<div class="empty">Nenhuma leitura.</div>';
      } else if (tab === 'historico') {
        const r = await api('GET', `/v1/audit?documentId=${id}&limit=200`);
        body.innerHTML = auditTable(r.items).s;
      }
    };

    await load();
    state.view = { onEvent: debounce((ev) => { if (ev.documentId === id && tab === 'itens') load().catch(() => {}); }, 800) };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Conferência cega (estação com leitor USB)
  // ───────────────────────────────────────────────────────────────────────────
  async function viewConference(id) {
    let d;
    try {
      d = await api('POST', `/v1/documents/${id}/claim`, {});
    } catch (err) {
      if (err.code === 'LOCKED' && isSup()) {
        return modal({
          title: 'Documento reservado',
          body: html`<p style="margin-top:0">${err.message}. Assumir a conferência mesmo assim?</p>`,
          submitLabel: 'Assumir',
          onSubmit: async () => { await api('POST', `/v1/documents/${id}/claim`, { force: true }); render(); },
        });
      }
      toast(err.message, true);
      location.hash = `#/documentos/${id}`;
      return;
    }

    const products = new Map(d.items.map((i) => [i.productErpId, i]));
    const barcodes = new Map(d.barcodes.map((b) => [b.barcode, b]));
    const session = []; // leituras feitas nesta tela (para estorno rápido)
    let counts = d.counts;
    let unknown = d.unknownScans;
    let busy = false;

    const describe = async (code) => {
      const b = barcodes.get(code);
      if (b) return { productErpId: b.productErpId, description: products.get(b.productErpId)?.description || '', factor: Number(b.factor) };
      if (products.has(code)) return { productErpId: code, description: products.get(code).description, factor: 1 };
      try {
        const p = await api('GET', `/v1/products/barcode/${encodeURIComponent(code)}`);
        barcodes.set(code, { barcode: code, productErpId: p.erpId, factor: p.factor });
        if (!products.has(p.erpId)) products.set(p.erpId, { productErpId: p.erpId, description: p.description, unit: p.unit });
        return { productErpId: p.erpId, description: p.description, factor: Number(p.factor), extra: !d.items.some((i) => i.productErpId === p.erpId) };
      } catch { return null; }
    };

    main().innerHTML = html`
      ${pageHead(`Conferindo ${d.number || d.erpKey}`, `${d.customerName || ''}${d.round > 0 ? ` · Recontagem (rodada ${d.round + 1})` : ''}`,
        html`<button class="btn" id="leave">Sair e manter reserva</button><button class="btn" id="release">Liberar documento</button>`)}
      ${d.round > 0 ? html`<div class="alert-box warn">Reconte somente os produtos destacados. As quantidades da rodada anterior foram descartadas para estes itens.</div>` : ''}
      <div class="conf">
        <div>
          <div class="card scan-box">
            <form id="scan-form" autocomplete="off">
              <div class="scan-row">
                <input class="input scan-input mono" id="code" placeholder="Bipe ou digite o código" inputmode="numeric" autofocus>
                ${d.settings.allowManualQty ? html`<input class="input qty-input" id="qty" type="number" min="1" step="1" value="1" title="Quantidade de embalagens">` : ''}
              </div>
            </form>
            <div class="last-scan" id="last"><div class="muted">Aguardando leitura…</div></div>
          </div>
          <div class="card" style="margin-top:16px">
            <div class="card-pad" style="padding-bottom:6px;display:flex;justify-content:space-between;align-items:center">
              <h2 style="margin:0">Últimas leituras</h2><span class="muted" id="session-count"></span></div>
            <div id="session"></div>
          </div>
        </div>
        <div>
          <div class="card">
            <div class="card-pad" style="padding-bottom:6px"><h2 style="margin:0">Contado nesta rodada</h2></div>
            <div class="count-list" id="counts"></div>
          </div>
          <div id="unknown"></div>
          <button class="btn primary lg" id="finish" style="width:100%;margin-top:16px">Finalizar conferência</button>
        </div>
      </div>`.s;

    const codeInput = $('#code');
    const keepFocus = () => { if (!document.querySelector('.modal-bg')) codeInput.focus(); };
    const focusTimer = setInterval(() => { if (document.activeElement === document.body) keepFocus(); }, 800);

    const drawCounts = () => {
      const recount = new Set(d.recount);
      const ids = new Set([...Object.keys(counts), ...(d.round > 0 ? recount : [])]);
      const rows = [...ids].map((pid) => ({ pid, q: counts[pid] ?? 0, p: products.get(pid) }))
        .sort((a, b) => (a.p?.description || a.pid).localeCompare(b.p?.description || b.pid));
      $('#counts').innerHTML = rows.length ? rows.map((r) => html`<div class="count-item ${recount.has(r.pid) ? 'recount' : ''}">
          <div><div>${r.p?.description || 'Produto'}</div><div class="muted mono">${r.pid}</div></div><div class="q">${fmtQty(r.q)}</div></div>`.s).join('')
        : '<div class="empty">Nada contado ainda.</div>';

      $('#unknown').innerHTML = unknown.length ? html`<div class="card" style="margin-top:16px">
        <div class="card-pad" style="padding-bottom:6px"><h2 style="margin:0;color:var(--danger)">Códigos não reconhecidos</h2>
        <div class="muted">Estorne antes de finalizar.</div></div>
        ${unknown.map((u) => html`<div class="count-item"><div class="mono">${u.barcode}</div><button class="btn sm danger" data-void="${u.eventId}">Estornar</button></div>`)}
      </div>`.s : '';
      $$('[data-void]', $('#unknown')).forEach((b) => b.addEventListener('click', () => voidScan(b.dataset.void)));
    };

    const drawSession = () => {
      $('#session-count').textContent = session.length ? `${session.length} nesta sessão` : '';
      $('#session').innerHTML = session.length ? session.slice(0, 15).map((s) => html`<div class="count-item" style="${s.voided ? 'opacity:.45;text-decoration:line-through' : ''}">
          <div><div>${s.description || s.code}</div><div class="muted mono">${s.code} · ${new Date(s.at).toLocaleTimeString('pt-BR')}</div></div>
          <div style="display:flex;gap:10px;align-items:center"><span class="q">${s.qty > 0 ? '+' : ''}${fmtQty(s.qty)}</span>
          ${!s.voided && s.ok ? html`<button class="btn sm" data-undo="${s.id}">Estornar</button>` : ''}</div></div>`.s).join('')
        : '<div class="empty">Nenhuma leitura nesta sessão.</div>';
      $$('[data-undo]', $('#session')).forEach((b) => b.addEventListener('click', () => voidScan(b.dataset.undo)));
    };

    const showLast = (cls, title, sub) => {
      const el = $('#last');
      el.className = `last-scan ${cls}`;
      el.innerHTML = html`<div class="desc">${title}</div><div class="muted">${sub || ''}</div>`.s;
    };

    async function voidScan(eventId) {
      try {
        await api('POST', `/v1/documents/${id}/scans/${eventId}/void`);
        const s = session.find((x) => x.id === eventId);
        if (s) s.voided = true;
        await refresh();
        toast('Leitura estornada');
      } catch (err) { toast(err.message, true); }
      keepFocus();
    }

    async function refresh() {
      d = await api('GET', `/v1/documents/${id}`);
      counts = d.counts; unknown = d.unknownScans;
      drawCounts(); drawSession();
    }

    $('#scan-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      const code = codeInput.value.trim();
      const packs = d.settings.allowManualQty ? Math.max(1, parseInt($('#qty').value, 10) || 1) : 1;
      codeInput.value = '';
      if (!code || busy) return;
      busy = true;
      const ev = { id: uuid(), round: d.round, barcode: code, qty: packs, origin: 'web', scannedAt: new Date().toISOString() };
      try {
        const info = await describe(code);
        // Código interno digitado (não é EAN cadastrado): identifica o produto explicitamente.
        if (info && !barcodes.has(code)) ev.productErpId = info.productErpId;
        const r = await api('POST', `/v1/documents/${id}/scans`, { events: [ev] });
        if (r.rejected?.length) throw new Error('Rodada encerrada. Recarregando…');
        counts = r.counts; unknown = r.unknownScans;
        const units = packs * (info?.factor || 1);
        session.unshift({ id: ev.id, code, description: info?.description, qty: units, at: Date.now(), ok: true });
        if (info) {
          const recounting = d.round > 0 && !d.recount.includes(info.productErpId);
          beep(!recounting);
          showLast(recounting ? 'err' : 'ok', info.description,
            recounting ? 'Este produto não está na recontagem — a leitura será ignorada.'
              : `+${fmtQty(units)} ${info.extra ? '· produto fora do documento' : ''}${info.factor > 1 ? ` (embalagem com ${fmtQty(info.factor)})` : ''} · total contado ${fmtQty(counts[info.productErpId] ?? 0)}`);
        } else {
          beep(false);
          showLast('err', 'Código não cadastrado no ERP', `${code} — estorne ou verifique a etiqueta`);
        }
        if ($('#qty')) $('#qty').value = '1';
        drawCounts(); drawSession();
      } catch (err) {
        beep(false);
        showLast('err', 'Leitura não registrada', err.message);
        if (['LOCK_LOST', 'INVALID_STATUS'].includes(err.code)) { toast(err.message, true); location.hash = `#/documentos/${id}`; }
        else if (/Rodada/.test(err.message)) await refresh();
      } finally {
        busy = false;
        keepFocus();
      }
    });

    $('#leave').addEventListener('click', () => { location.hash = '#/documentos'; });
    $('#release').addEventListener('click', async () => {
      try { await api('POST', `/v1/documents/${id}/release`); location.hash = '#/documentos'; } catch (e) { toast(e.message, true); }
    });
    $('#finish').addEventListener('click', () => modal({
      title: 'Finalizar conferência',
      body: html`<p style="margin-top:0">Confirma que terminou de contar ${d.round > 0 ? 'os itens da recontagem' : 'todos os itens'}? O sistema vai comparar com o documento.</p>`,
      submitLabel: 'Finalizar',
      onSubmit: async () => {
        let r;
        try {
          r = await api('POST', `/v1/documents/${id}/finalize`);
        } catch (err) {
          if (err.code === 'UNKNOWN_BARCODES') { unknown = err.data.unknownScans; drawCounts(); }
          throw err;
        }
        resultModal(r);
      },
    }));

    function resultModal(r) {
      if (r.status === 'CONCLUIDO') {
        beep(true);
        modal({ title: 'Conferência concluída', body: html`<div class="alert-box ok">Tudo confere. O resultado será gravado no ERP.</div>`,
          submitLabel: 'Próximo documento', cancelLabel: null, onSubmit: () => { location.hash = '#/documentos'; } });
      } else if (r.status === 'DIVERGENTE') {
        beep(false);
        modal({
          title: 'Recontagem necessária',
          body: html`<div class="alert-box warn">Há divergência. Reconte os produtos abaixo:</div>
            ${r.recount.map((p) => html`<div class="count-item recount"><div>${p.description || 'Produto'}</div><div class="mono muted">${p.productErpId}</div></div>`)}`,
          submitLabel: 'Começar recontagem', cancelLabel: null,
          onSubmit: () => { render(); },
        });
      } else {
        modal({ title: 'Enviado ao supervisor', body: html`<div class="alert-box info">A divergência persiste após a recontagem e foi enviada para aprovação do supervisor.</div>`,
          submitLabel: 'Próximo documento', cancelLabel: null, onSubmit: () => { location.hash = '#/documentos'; } });
      }
    }

    drawCounts(); drawSession(); keepFocus();
    state.view = {
      dispose: () => clearInterval(focusTimer),
      // Outro operador/supervisor mexeu no documento (reabriu, zerou, assumiu): recarrega.
      onEvent: debounce(async (ev) => {
        if (ev.documentId !== id || ev.type !== 'document.updated') return;
        try {
          const fresh = await api('GET', `/v1/documents/${id}`);
          if (!fresh.lock?.mine && !['CONCLUIDO', 'AGUARDANDO_APROVACAO'].includes(fresh.status)) {
            toast('O documento foi assumido ou alterado por um supervisor.', true);
            location.hash = `#/documentos/${id}`;
          }
        } catch { /* ignora */ }
      }, 500),
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Produtos
  // ───────────────────────────────────────────────────────────────────────────
  async function viewProducts() {
    main().innerHTML = html`
      ${pageHead('Produtos', 'Catálogo sincronizado do ERP')}
      <div class="card">
        <div class="toolbar"><input class="input" id="q" placeholder="Descrição, código ou EAN" style="max-width:420px"></div>
        <div id="list"></div>
      </div>`.s;
    const load = async (q) => {
      const r = await api('GET', `/v1/products?q=${encodeURIComponent(q)}&limit=100`);
      $('#list').innerHTML = r.items.length ? html`<div class="table-wrap"><table>
        <thead><tr><th>Código</th><th>Descrição</th><th>Un</th><th>Marca</th><th>Grupo</th><th>Códigos de barras</th><th class="num">Saldo</th></tr></thead>
        <tbody>${r.items.map((p) => html`<tr><td class="mono">${p.erpId}</td><td>${p.description}</td><td>${p.unit || ''}</td><td>${p.brand || ''}</td><td>${p.group || ''}</td>
          <td class="mono muted">${(p.barcodes || []).join(', ')}</td><td class="num">${fmtQty(p.stock)}</td></tr>`)}</tbody></table></div>`.s
        : '<div class="empty">Nenhum produto encontrado.</div>';
    };
    $('#q').addEventListener('input', debounce((e) => load(e.target.value.trim()).catch((er) => toast(er.message, true)), 300));
    $('#q').focus();
    await load('');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Usuários
  // ───────────────────────────────────────────────────────────────────────────
  async function viewUsers() {
    const load = async () => {
      const r = await api('GET', '/v1/users');
      main().innerHTML = html`
        ${pageHead('Usuários', 'Operadores entram no app com usuário + PIN; supervisores no painel com senha', html`<button class="btn primary" id="new">Novo usuário</button>`)}
        <div class="card"><div class="table-wrap"><table>
          <thead><tr><th>Nome</th><th>Usuário</th><th>Perfil</th><th>Acesso</th><th>Último acesso</th><th></th></tr></thead>
          <tbody>${r.items.map((u) => html`<tr style="${u.active ? '' : 'opacity:.5'}">
            <td><strong>${u.name}</strong></td><td class="mono">${u.login}</td><td>${ROLE_LABEL[u.role]}</td>
            <td>${u.has_pin ? badge('OK', 'App') : ''} ${u.has_password ? badge('EM_CONFERENCIA', 'Painel') : ''} ${u.active ? '' : badge('CANCELADO', 'Inativo')}</td>
            <td>${ago(u.last_login_at)}</td>
            <td class="num">${isAdmin() || u.role === 'operador' ? html`<button class="btn sm" data-edit="${u.id}">Editar</button>` : ''}</td></tr>`)}</tbody>
        </table></div></div>`.s;
      $('#new').addEventListener('click', () => editUser(null));
      $$('[data-edit]').forEach((b) => b.addEventListener('click', () => editUser(r.items.find((u) => u.id === b.dataset.edit))));
    };

    const roleOptions = (current) => (isAdmin() ? ['operador', 'supervisor', 'admin'] : ['operador'])
      .map((r) => html`<option value="${r}" ${r === current ? 'selected' : ''}>${ROLE_LABEL[r]}</option>`);

    const editUser = (u) => modal({
      title: u ? `Editar ${u.name}` : 'Novo usuário',
      body: html`
        <div class="field"><label>Nome</label><input class="input" name="name" required value="${u?.name || ''}"></div>
        ${u ? '' : html`<div class="field"><label>Usuário (login)</label><input class="input" name="login" required pattern="[A-Za-z0-9._@-]+">
          <div class="help">No app o operador digita este usuário e o PIN.</div></div>`}
        <div class="field"><label>Perfil</label><select class="input" name="role">${roleOptions(u?.role || 'operador')}</select></div>
        <div class="field"><label>PIN do app ${u?.has_pin ? '(deixe vazio para manter)' : ''}</label><input class="input mono" name="pin" inputmode="numeric" pattern="\\d{4,8}" placeholder="4 a 8 dígitos"></div>
        <div class="field"><label>Senha do painel ${u?.has_password ? '(deixe vazio para manter)' : '(opcional para operador)'}</label><input class="input" name="password" type="password" minlength="8" autocomplete="new-password"></div>
        ${u ? html`<label class="check"><input type="checkbox" name="active" ${u.active ? 'checked' : ''}> Ativo</label>` : ''}`,
      submitLabel: 'Salvar',
      onSubmit: async (form) => {
        if (!form.reportValidity()) return false;
        const v = (n) => form.elements[n]?.value?.trim();
        const body = { name: v('name'), role: v('role') };
        if (v('pin')) body.pin = v('pin');
        if (v('password')) body.password = form.elements.password.value;
        if (u) {
          body.active = form.elements.active.checked;
          await api('PATCH', `/v1/users/${u.id}`, body);
        } else {
          body.login = v('login');
          await api('POST', '/v1/users', body);
        }
        toast('Usuário salvo');
        load();
      },
    });

    await load();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Auditoria
  // ───────────────────────────────────────────────────────────────────────────
  const AUDIT_LABEL = {
    'tenant.setup': 'Empresa configurada', 'document.claimed': 'Iniciou conferência', 'document.released': 'Liberou documento',
    'lock.forced': 'Assumiu documento de outro operador', 'scan.voided': 'Estornou leitura', 'round.closed': 'Finalizou rodada',
    'document.approved': 'Aprovou', 'document.reopened': 'Reabriu para recontagem', 'document.reset': 'Zerou conferência',
    'document.priority': 'Alterou prioridade', 'erp.cancelled': 'ERP cancelou o documento', 'erp.items_replaced': 'ERP alterou os itens',
    'erp.changed_during_conference': 'ERP alterou durante a conferência', 'writeback.failed': 'Falha ao gravar no ERP',
    'user.created': 'Criou usuário', 'user.updated': 'Alterou usuário', 'settings.updated': 'Alterou configurações',
  };
  const auditTable = (items) => (items.length ? html`<div class="table-wrap"><table>
    <thead><tr><th>Quando</th><th>Usuário</th><th>Ação</th><th>Documento</th><th>Detalhes</th></tr></thead>
    <tbody>${items.map((a) => html`<tr><td>${fmtDateTime(a.at)}</td><td>${a.user_name || 'Sistema/ERP'}</td><td>${AUDIT_LABEL[a.action] || a.action}</td>
      <td>${a.document_id ? html`<a href="#/documentos/${a.document_id}">${a.document_number || 'abrir'}</a>` : ''}</td>
      <td class="muted mono" style="font-size:12px;max-width:380px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${Object.keys(a.details || {}).length ? JSON.stringify(a.details) : ''}</td></tr>`)}</tbody></table></div>`
    : html`<div class="empty">Sem registros.</div>`);

  async function viewAudit() {
    let items = [];
    const load = async (more) => {
      const before = more && items.length ? `&before=${items[items.length - 1].id}` : '';
      const r = await api('GET', `/v1/audit?limit=100${before}`);
      items = more ? items.concat(r.items) : r.items;
      $('#list').innerHTML = auditTable(items).s + (r.items.length === 100 ? '<div style="padding:14px;text-align:center"><button class="btn" id="more">Carregar mais</button></div>' : '');
      $('#more')?.addEventListener('click', () => load(true));
    };
    main().innerHTML = html`${pageHead('Auditoria', 'Tudo que foi feito, por quem e quando')}<div class="card" id="list"></div>`.s;
    await load(false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Configurações
  // ───────────────────────────────────────────────────────────────────────────
  async function viewSettings() {
    const s = await api('GET', '/v1/settings');
    const ro = !isAdmin();
    main().innerHTML = html`
      ${pageHead('Configurações', ro ? 'Somente administradores podem alterar' : 'Regras da conferência desta empresa')}
      <form class="card card-pad" id="f" style="max-width:640px">
        <div class="field"><label>Recontagens antes de ir para o supervisor</label>
          <input class="input" name="maxRecounts" type="number" min="0" max="5" value="${s.maxRecounts}" ${ro ? 'disabled' : ''}>
          <div class="help">0 = qualquer divergência vai direto para aprovação.</div></div>
        <div class="field"><label>Reserva do documento (minutos)</label>
          <input class="input" name="lockMinutes" type="number" min="5" max="1440" value="${s.lockMinutes}" ${ro ? 'disabled' : ''}>
          <div class="help">Renovada a cada leitura. Depois disso, outro operador pode assumir.</div></div>
        <div class="field"><label>Dias exibidos na fila</label>
          <input class="input" name="queueDays" type="number" min="1" max="90" value="${s.queueDays}" ${ro ? 'disabled' : ''}></div>
        <label class="check"><input type="checkbox" name="allowManualQty" ${s.allowManualQty ? 'checked' : ''} ${ro ? 'disabled' : ''}> Permitir digitar quantidade (em vez de bipar unidade por unidade)</label>
        <label class="check"><input type="checkbox" name="showItemList" ${s.showItemList ? 'checked' : ''} ${ro ? 'disabled' : ''}> Mostrar ao operador a lista de produtos do documento (nunca as quantidades)</label>
        <label class="check"><input type="checkbox" name="requireJustification" ${s.requireJustification ? 'checked' : ''} ${ro ? 'disabled' : ''}> Exigir justificativa para aprovar com divergência</label>
        ${ro ? '' : html`<button class="btn primary" style="margin-top:8px">Salvar</button>`}
      </form>`.s;
    if (ro) return;
    $('#f').addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = e.target.elements;
      try {
        state.settings = await api('PATCH', '/v1/settings', {
          maxRecounts: Number(f.maxRecounts.value), lockMinutes: Number(f.lockMinutes.value), queueDays: Number(f.queueDays.value),
          allowManualQty: f.allowManualQty.checked, showItemList: f.showItemList.checked, requireJustification: f.requireJustification.checked,
        });
        toast('Configurações salvas');
      } catch (err) { toast(err.message, true); }
    });
  }

  // ── Delegação: link "Ver documentos" do painel abre filtrado por erro de retorno ──
  let pendingWritebackFilter = null;
  document.addEventListener('click', (e) => {
    const a = e.target.closest('[data-wb]');
    if (a) { pendingWritebackFilter = a.dataset.wb; store.set('est.docs.status', 'CONCLUIDO'); }
  });

  render();
})();
