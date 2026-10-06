/* Coliseu Estoque — Dashboard (SPA sem build).
 *
 * Usa exatamente a mesma API do app mobile. O perfil do usuário define o que aparece:
 * operador faz conferência cega; supervisor/admin acompanham, aprovam e configuram.
 *
 * Dois fluxos, mesma conferência cega:
 *   Entradas (recebimento) — NF-e de compra: bipa o DANFE / importa o XML → confere → recebe.
 *   Saídas (expedição)     — pedidos e notas do ERP: separa → confere → libera para faturar.
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
  const fmtQty = (v) => {
    if (v === null || v === undefined || v === '') return '—';
    const n = Number(v);
    return Number.isInteger(n) ? n.toLocaleString('pt-BR') : n.toLocaleString('pt-BR', { maximumFractionDigits: 4 });
  };
  const fmtMoney = (v) => (v == null || v === '' ? '—' : Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' }));
  const fmtCnpj = (v) => {
    const d = String(v || '').replace(/\D/g, '');
    return d.length === 14 ? d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5') : (v || '—');
  };
  const fmtKey = (k) => String(k || '').replace(/\D/g, '').replace(/(\d{4})(?=\d)/g, '$1 ');
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
  const shortDate = (v) => {
    if (!v) return '—';
    const d = new Date(v);
    return d.toDateString() === new Date().toDateString() ? 'Hoje' : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  };

  const RESULT_LABEL = { OK: 'OK', FALTA: 'Falta', SOBRA: 'Sobra', PENDENTE: 'Pendente' };
  const WB_LABEL = { NAO_APLICAVEL: '—', PENDENTE: 'Pendente', GRAVADO: 'Gravado', ERRO: 'Erro' };
  const ROLE_LABEL = { operador: 'Operador', supervisor: 'Supervisor', admin: 'Administrador' };
  const badge = (code, label) => html`<span class="badge b-${code}">${label}</span>`;

  // ── Fluxos ────────────────────────────────────────────────────────────────
  const flowOf = (d) => d.flow || (d.source === 'NFE' ? 'entrada' : 'saida');
  const FLOW = {
    entrada: {
      key: 'entrada', href: '#/entradas', label: 'Entradas', area: 'Recebimento', noun: 'Nota', nounPl: 'notas',
      party: 'Fornecedor', countVerb: 'conferência', icon: 'inbox',
      steps: [
        ['Chegou a mercadoria', 'Bipe o código de barras do DANFE ou importe o XML da NF-e.'],
        ['Revise as críticas', 'Vincule itens sem cadastro, confira validade e destinatário.'],
        ['Conferência cega', 'O conferente bipa item a item sem ver a quantidade da nota.'],
        ['Divergência?', 'Falta ou sobra volta para recontagem; persistindo, vai ao supervisor.'],
        ['Recebido', 'Nota conferida — pronta para dar entrada no ERP.'],
      ],
    },
    saida: {
      key: 'saida', href: '#/saidas', label: 'Saídas', area: 'Expedição', noun: 'Pedido', nounPl: 'pedidos',
      party: 'Cliente', countVerb: 'separação', icon: 'truck',
      steps: [
        ['Pedido no ERP', 'O Worker traz os pedidos de venda automaticamente.'],
        ['Separação', 'O separador pega os itens e bipa cada produto (conferência cega).'],
        ['Divergência?', 'Falta ou sobra volta para recontagem; persistindo, vai ao supervisor.'],
        ['Liberado', 'Conferido — o faturamento pode emitir a nota.'],
        ['Faturado', 'NF emitida; a mercadoria pode sair.'],
      ],
    },
  };
  const docTitle = (d) => `${d.source === 'NFE' ? 'NF' : d.source === 'NFS' ? 'Nota' : 'Pedido'} ${d.number || d.erpKey}${d.source === 'NFE' && d.series ? `-${d.series}` : ''}`;

  /**
   * Status como o armazém fala — cor própria e consistente em todas as telas.
   * Saída conferida = liberada para faturar; com NF emitida = faturada.
   * Entrada conferida = recebida (com ou sem divergência aprovada).
   */
  function statusInfo(d) {
    const entrada = flowOf(d) === 'entrada';
    switch (d.status) {
      case 'AGUARDANDO': return { cls: 's-wait', label: entrada ? 'Aguardando conferência' : 'Aguardando separação', stage: 0 };
      case 'EM_CONFERENCIA': return { cls: 's-sep', label: entrada ? 'Em conferência' : 'Em separação', pulse: true, stage: 1 };
      case 'DIVERGENTE': return { cls: 's-recount', label: 'Recontagem', pulse: true, stage: 2 };
      case 'AGUARDANDO_APROVACAO': return { cls: 's-approval', label: 'Divergência · supervisor', stage: 2 };
      case 'CONCLUIDO':
        if (entrada) return { cls: 's-done', label: d.hasDivergence ? 'Recebido c/ divergência' : 'Recebido', stage: 3 };
        if (d.source === 'PED') return d.invoiceNumber ? { cls: 's-invoiced', label: 'Faturado', stage: 4 } : { cls: 's-done', label: 'Liberado p/ faturar', stage: 3 };
        return { cls: 's-done', label: 'Conferido', stage: 3 };
      default: return { cls: 's-cancel', label: 'Cancelado', stage: -1 };
    }
  }
  const docStatus = (d) => {
    const s = statusInfo(d);
    return html`<span class="status ${s.cls}${s.pulse ? ' pulse' : ''}">${s.label}</span>`;
  };
  const flowTag = (d) => {
    const f = flowOf(d);
    return html`<span class="flow-tag f-${f}">${raw(ICON[f === 'entrada' ? 'arrowIn' : 'arrowOut'])}${f === 'entrada' ? 'Entrada' : 'Saída'}</span>`;
  };
  /** Barra de progresso: produtos já lidos ÷ produtos do documento (não revela quantidade esperada). */
  const progressBar = (d) => {
    if (!d.productCount) return html`<span class="muted">—</span>`;
    const n = d.status === 'CONCLUIDO' ? d.productCount : Math.min(d.countedProducts || 0, d.productCount);
    const pct = Math.round((n / d.productCount) * 100);
    return html`<div class="progress ${statusInfo(d).cls}" title="${n} de ${d.productCount} produtos lidos">
      <div class="bar"><i style="width:${pct}%"></i></div><span class="txt">${n}/${d.productCount}</span></div>`;
  };

  // ── Críticas ──────────────────────────────────────────────────────────────
  const LEVEL = {
    erro: { label: 'Grave', cls: 'lv-erro', icon: 'alert' },
    alerta: { label: 'Atenção', cls: 'lv-alerta', icon: 'warn' },
    info: { label: 'Info', cls: 'lv-info', icon: 'info' },
  };
  /** Chips compactos para a tabela: contagem por nível, com o texto no tooltip. */
  function alertChips(alerts) {
    if (!alerts?.length) return html`<span class="ok-mark" title="Sem críticas">${raw(ICON.check)}</span>`;
    return html`<span class="crit-chips">${['erro', 'alerta', 'info'].map((lv) => {
      const list = alerts.filter((a) => a.level === lv);
      return list.length ? html`<span class="crit ${LEVEL[lv].cls}" title="${list.map((a) => `• ${a.message}`).join('\n')}">${raw(ICON[LEVEL[lv].icon])}${list.length}</span>` : '';
    })}</span>`;
  }
  /** Lista completa, com orientação do que fazer. */
  function critiqueList(list, { empty = 'Nenhuma crítica. Tudo certo para seguir.' } = {}) {
    if (!list?.length) return html`<div class="crit-empty">${raw(ICON.check)}<span>${empty}</span></div>`;
    return html`<ul class="crit-list">${list.map((c) => html`<li class="${LEVEL[c.level].cls}">
      <span class="ic">${raw(ICON[LEVEL[c.level].icon])}</span>
      <div><div class="msg">${c.message}</div>${CRIT_HELP[c.code] ? html`<div class="hint">${CRIT_HELP[c.code]}</div>` : ''}</div>
      <span class="lv">${LEVEL[c.level].label}</span></li>`)}</ul>`;
  }
  const CRIT_HELP = {
    DEST_MISMATCH: 'Não receba a mercadoria sem confirmar com o comprador — pode ser nota de outra filial.',
    NOT_AUTHORIZED: 'Nota sem autorização não tem validade fiscal. Recuse ou peça a nota correta ao fornecedor.',
    NO_PROTOCOL: 'Importe o XML de distribuição (procNFe), que contém o protocolo, ou consulte a chave no portal.',
    HOMOLOGATION: 'XML de teste. Peça ao fornecedor o XML de produção.',
    OLD_INVOICE: 'Confirme no ERP se a nota já não teve entrada para evitar duplicidade.',
    NO_PURCHASE_ORDER: 'Confira com o comprador se a compra foi autorizada.',
    UNLINKED: 'Use “Vincular” nos itens marcados. O vínculo fica salvo para as próximas notas do fornecedor.',
    NO_GTIN: 'Na conferência, o conferente digita o código do fornecedor ou o código do produto.',
    UNIT_DIFF: 'Confira o fator de conversão antes de dar entrada no ERP.',
    LOT_EXPIRED: 'Não receba lote vencido: separe para devolução.',
    LOT_SHORT_EXPIRY: 'Avalie aceitar ou devolver; priorize a saída deste lote (PVPS/FEFO).',
    INVOICED_EARLY: 'A NF saiu antes de terminar a conferência — confirme se a mercadoria já foi entregue.',
    WRITEBACK_ERROR: 'O Worker tenta de novo a cada 5 minutos. Persistindo, verifique o serviço no servidor do cliente.',
    ERP_CHANGED: 'Confira os itens; se mudou muito, zere a conferência.',
    NEEDS_APPROVAL: 'Abra o documento, analise falta/sobra e aprove com justificativa ou reabra a recontagem.',
    RECOUNT: 'O conferente precisa recontar só os itens destacados.',
    SLA: 'Priorize este documento ou redistribua a equipe.',
    STALLED: 'Alguém começou e não terminou. Retome a conferência ou libere o documento.',
    CANCELLED_AFTER: 'Se a mercadoria já saiu, providencie o retorno.',
    ENTRY_ERRORS: 'Abra a nota e resolva as críticas graves antes de receber.',
    ENTRY_WARNINGS: 'Abra a nota e revise as críticas.',
  };

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
  function modal({ title, body, submitLabel = 'Confirmar', danger = false, onSubmit, cancelLabel = 'Cancelar', wide = false }) {
    const bg = document.createElement('div');
    bg.className = 'modal-bg';
    bg.innerHTML = html`
      <form class="modal${wide ? ' wide' : ''}" novalidate>
        <header>${title}<button type="button" class="x" data-close aria-label="Fechar">×</button></header>
        <div class="body">${body}</div>
        ${cancelLabel || submitLabel ? html`<footer>
          ${cancelLabel ? html`<button type="button" class="btn" data-close>${cancelLabel}</button>` : ''}
          ${submitLabel ? html`<button type="submit" class="btn ${danger ? 'danger-solid' : 'primary'}">${submitLabel}</button>` : ''}
        </footer>` : ''}
      </form>`.s;
    document.body.appendChild(bg);
    const form = $('form', bg);
    const close = () => bg.remove();
    $$('[data-close]', bg).forEach((b) => b.addEventListener('click', close));
    bg.addEventListener('mousedown', (e) => { if (e.target === bg) close(); });
    bg.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
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
    setTimeout(() => $('input:not([type=file]), textarea, select', form)?.focus(), 30);
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
    const setLive = (on) => {
      $('#live-status')?.classList.toggle('on', on);
      const t = $('#live-text'); if (t) t.textContent = on ? 'Tempo real' : 'Reconectando…';
    };
    stream.onopen = () => setLive(true);
    stream.onerror = () => setLive(false);
    for (const type of ['document.updated', 'scan.added', 'documents.synced', 'worker.heartbeat']) {
      stream.addEventListener(type, (e) => {
        try { state.view?.onEvent?.({ type, ...JSON.parse(e.data) }); } catch { /* evento malformado */ }
      });
    }
  }
  function stopStream() { stream?.close(); stream = null; }
  function restartStream() { stopStream(); startStream(); }

  // ───────────────────────────────────────────────────────────────────────────
  // Layout
  // ───────────────────────────────────────────────────────────────────────────
  const svg = (body, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${body}</svg>`;
  const ICON = {
    panel: svg('<rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/>'),
    inbox: svg('<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>'),
    truck: svg('<path d="M1 3h15v13H1z"/><path d="M16 8h4l3 3v5h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/>'),
    box: svg('<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="M3.3 7L12 12l8.7-5M12 22V12"/>'),
    users: svg('<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>'),
    gear: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>'),
    log: svg('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>'),
    menu: svg('<path d="M3 12h18M3 6h18M3 18h18"/>', 'width="22" height="22"'),
    scan: svg('<path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M7 8v8M10 8v8M13 8v8M16 8v8"/>'),
    upload: svg('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5M12 3v12"/>'),
    file: svg('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 15l2 2 4-4"/>'),
    clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    boxes: svg('<path d="M3 9l9-5 9 5-9 5-9-5z"/><path d="M3 9v6l9 5 9-5V9"/><path d="M12 14v6"/>'),
    check: svg('<path d="M4 12l5 5L20 6"/>', 'stroke-width="3"'),
    alert: svg('<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16.5v.01"/>', 'stroke-width="2.4"'),
    warn: svg('<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>', 'stroke-width="2.2"'),
    info: svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>', 'stroke-width="2.2"'),
    trend: svg('<path d="M3 17l6-6 4 4 8-8"/><path d="M14 7h7v7"/>'),
    arrowIn: svg('<path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 21h14"/>', 'stroke-width="2.4"'),
    arrowOut: svg('<path d="M12 15V3M7 8l5-5 5 5"/><path d="M5 21h14"/>', 'stroke-width="2.4"'),
    link: svg('<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>'),
    print: svg('<path d="M6 9V2h12v7"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 14h12v8H6z"/>'),
    back: svg('<path d="M15 18l-6-6 6-6"/>', 'stroke-width="2.4"'),
    search: svg('<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>'),
    help: svg('<circle cx="12" cy="12" r="9"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01"/>'),
  };

  const NAV = [
    { section: 'Visão geral' },
    { href: '#/', label: 'Painel', icon: 'panel', sup: true },
    { section: 'Operação' },
    { href: '#/entradas', label: 'Entradas', hint: 'Recebimento', icon: 'inbox', flow: 'entrada' },
    { href: '#/saidas', label: 'Saídas', hint: 'Expedição', icon: 'truck', flow: 'saida' },
    { section: 'Cadastros' },
    { href: '#/produtos', label: 'Produtos', icon: 'box' },
    { href: '#/usuarios', label: 'Usuários', icon: 'users', sup: true },
    { section: 'Controle', sup: true },
    { href: '#/auditoria', label: 'Auditoria', icon: 'log', sup: true },
    { href: '#/configuracoes', label: 'Configurações', icon: 'gear', sup: true },
  ];

  let shellBuilt = false;
  function buildShell() {
    const links = NAV.filter((n) => !n.sup || isSup());
    $('#root').innerHTML = html`
      <div class="shell">
        <aside class="sidebar" id="sidebar">
          <div class="brand">
            <img class="brand-logo" src="img/coliseu_logo.png" alt="Coliseu Sistemas" width="150" height="38">
            <span class="brand-sub">Estoque · ${state.company?.name || ''}</span>
          </div>
          <nav>${links.map((n) => (n.section ? html`<div class="nav-section">${n.section}</div>`
            : html`<a class="nav-link ${n.flow ? `nf-${n.flow}` : ''}" href="${n.href}" data-nav="${n.href}">
                <span class="nav-ic">${raw(ICON[n.icon])}</span>
                <span class="nav-txt">${n.label}${n.hint ? html`<small>${n.hint}</small>` : ''}</span>
                ${n.flow ? html`<span class="nav-count" id="nc-${n.flow}"></span>` : ''}</a>`))}</nav>
          <div class="sidebar-foot">
            <div class="me"><div class="avatar">${(state.user.name || '?').trim().charAt(0).toUpperCase()}</div>
              <div><div class="who">${state.user.name}</div><div class="muted">${ROLE_LABEL[state.user.role]}</div></div></div>
            <button class="btn sm ghost" id="logout" style="margin-top:12px;width:100%">Sair</button>
          </div>
        </aside>
        <div class="main-col">
          <header class="topbar">
            <button class="btn sm topbar-mobile" id="menu-btn" aria-label="Menu">${raw(ICON.menu)}</button>
            <div class="tb-titles"><div class="crumb" id="tb-crumb"></div><h1 id="tb-title">Coliseu Estoque</h1><div class="sub" id="tb-sub"></div></div>
            <div class="spacer"></div>
            <span class="pstatus" id="live-status"><span class="live-dot"></span><span id="live-text">Conectando…</span></span>
            ${isSup() ? html`<button class="btn btn-xml" id="xml-btn" title="Importar XML de NF-e de entrada">${raw(ICON.upload)}<span>Importar XML</span></button>` : ''}
            <button class="btn btn-scan" id="scan-btn" title="Ler código de barras (F2)">
              <span class="reader-dot" id="reader-dot"></span>${raw(ICON.scan)}<span>Ler código</span><kbd>F2</kbd></button>
          </header>
          <main id="main"></main>
        </div>
      </div>`.s;
    $('#scan-btn').addEventListener('click', () => openScanner());
    $('#xml-btn')?.addEventListener('click', () => openImport());
    $('#logout').addEventListener('click', () => logout());
    $('#menu-btn').addEventListener('click', () => $('#sidebar').classList.toggle('open'));
    $$('.nav-link').forEach((a) => a.addEventListener('click', () => $('#sidebar').classList.remove('open')));
    shellBuilt = true;
    startStream();
    refreshNavCounts();
  }

  /** Contadores na barra lateral: quanto trabalho há em cada fluxo. */
  const refreshNavCounts = debounce(async () => {
    for (const flow of ['entrada', 'saida']) {
      try {
        const c = await api('GET', `/v1/documents/counts?flow=${flow}&days=1`);
        const open = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE', 'AGUARDANDO_APROVACAO'].reduce((s, k) => s + (c.byStatus[k] || 0), 0);
        const el = $(`#nc-${flow}`);
        if (el) { el.textContent = open || ''; el.classList.toggle('hot', c.attention > 0); el.title = c.attention ? `${c.attention} com críticas` : ''; }
      } catch { /* silencioso */ }
    }
  }, 600);

  function markNav(hash, flow) {
    $$('.nav-link').forEach((a) => {
      const href = a.dataset.nav;
      const active = href === '#/' ? hash === '#/' : hash.startsWith(href) || Boolean(flow && href === FLOW[flow].href);
      a.classList.toggle('active', active);
    });
  }

  const main = () => $('#main');
  /** Título vai para o cabeçalho fixo; na página ficam só as ações. */
  const pageHead = (title, sub, actions = '', crumb = '') => {
    const t = $('#tb-title');
    if (t) {
      t.textContent = title; $('#tb-sub').textContent = sub || '';
      $('#tb-crumb').innerHTML = crumb ? out(crumb) : '';
      document.title = `${title} · Coliseu Estoque`;
    }
    const hasActions = Array.isArray(actions) ? actions.some(Boolean) : Boolean(actions);
    return hasActions ? html`<div class="page-head"><div></div><div class="btn-row">${actions}</div></div>` : html``;
  };

  /** Passo a passo do fluxo (didático), recolhível e lembrado por navegador. */
  function flowGuide(flow, current = -1) {
    const f = FLOW[flow];
    // No celular começa recolhido para a fila aparecer logo.
    const pref = store.get(`est.guide.${flow}`);
    const hidden = pref === '0' || (pref === null && window.innerWidth < 760);
    return html`<details class="guide f-${flow}" ${hidden ? '' : 'open'} data-guide="${flow}">
      <summary>${raw(ICON.help)}<span>Como funciona ${f.area === 'Recebimento' ? 'o recebimento' : 'a expedição'}</span></summary>
      <ol class="steps">${f.steps.map(([t, d], i) => html`<li class="${i < current ? 'done' : i === current ? 'now' : ''}">
        <span class="n">${i < current ? raw(ICON.check) : i + 1}</span><div><strong>${t}</strong><span>${d}</span></div></li>`)}</ol>
    </details>`;
  }
  function bindGuide(root = document) {
    $$('details[data-guide]', root).forEach((d) => d.addEventListener('toggle', () => store.set(`est.guide.${d.dataset.guide}`, d.open ? '1' : '0')));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Roteador
  // ───────────────────────────────────────────────────────────────────────────
  const ROUTES = [
    { re: /^#\/login$/, view: viewLogin, public: true },
    { re: /^#\/$/, view: viewPanel, sup: true },
    { re: /^#\/entradas$/, view: () => viewQueue('entrada') },
    { re: /^#\/saidas$/, view: () => viewQueue('saida') },
    { re: /^#\/documentos$/, view: () => { location.hash = '#/saidas'; } },
    { re: /^#\/documentos\/([0-9a-f-]{36})$/, view: viewDocument },
    { re: /^#\/conferir\/([0-9a-f-]{36})$/, view: viewConference },
    { re: /^#\/produtos$/, view: viewProducts },
    { re: /^#\/usuarios$/, view: viewUsers, sup: true },
    { re: /^#\/auditoria$/, view: viewAudit, sup: true },
    { re: /^#\/configuracoes$/, view: viewSettings, sup: true },
  ];
  const home = () => (isSup() ? '#/' : '#/saidas');

  async function render() {
    const hash = location.hash || '#/';
    state.view?.dispose?.();
    state.view = null;
    // Modal aberto não sobrevive à troca de tela (ex.: importação → abrir a nota).
    $$('.modal-bg').forEach((m) => m.remove());
    scannerModal = null;

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
    if (hash === '#/login') { location.hash = home(); return; }

    const routeDef = ROUTES.find((r) => r.re.test(hash));
    if (!routeDef || (routeDef.sup && !isSup())) { location.hash = home(); return; }
    if (!shellBuilt) buildShell();
    markNav(hash);
    main().innerHTML = '<div class="skeleton"><i></i><i></i><i></i></div>';
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
      $('#root').innerHTML = html`<div class="auth">
        <div class="auth-art" aria-hidden="true">
          <div class="art-title">Conferência cega de<br>entradas e saídas</div>
          <ul><li>${raw(ICON.arrowIn)} Recebimento por XML e DANFE</li><li>${raw(ICON.arrowOut)} Separação de pedidos do ERP</li><li>${raw(ICON.warn)} Críticas automáticas</li></ul>
        </div>
        <div class="card"><div class="brand-mark">C</div>${inner}</div></div>`.s;
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
          location.hash = home();
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
  // Tabela de documentos (painel e filas usam a mesma)
  // ───────────────────────────────────────────────────────────────────────────
  function docsTable(items, flow, { compact = false } = {}) {
    const sup = isSup();
    const entrada = flow === 'entrada';
    return html`<div class="table-wrap"><table class="docs">
      <thead><tr>
        <th>${entrada ? 'Nota fiscal' : 'Pedido'}</th><th>${entrada ? 'Fornecedor' : 'Cliente'}</th>
        ${entrada && sup && !compact ? html`<th class="num">Valor</th>` : ''}
        <th class="num">Itens</th><th>${entrada ? 'Chegada' : 'Emissão'}</th>
        <th>Progresso</th><th>Status</th><th>Críticas</th>${compact ? '' : html`<th>Responsável</th>`}
      </tr></thead>
      <tbody>${items.map((d) => {
        const s = statusInfo(d);
        return html`<tr class="clickable row-s ${s.cls}" data-id="${d.id}">
          <td><div class="doc-no">${entrada ? `${d.number || '—'}${d.series ? `-${d.series}` : ''}` : d.number || d.erpKey}
              ${d.priority > 0 ? html`<span class="badge b-URG">${d.priority >= 10 ? 'Urgente' : 'Alta'}</span>` : ''}</div>
            <div class="sub">${entrada
              ? (d.orderNumber ? `Pedido de compra ${d.orderNumber}` : 'Sem pedido de compra')
              : html`${d.source === 'NFS' ? `Nota de saída${d.orderNumber ? ` · pedido ${d.orderNumber}` : ''}` : 'Pedido de venda'}${d.invoiceNumber ? html` · <span class="nf">NF ${d.invoiceNumber}</span>` : ''}`}</div></td>
          <td><div class="party">${d.customerName || '—'}</div><div class="sub">${entrada ? fmtCnpj(d.customerCode) : d.sellerName || ''}</div></td>
          ${entrada && sup && !compact ? html`<td class="num">${fmtMoney(d.entry?.totalValue)}</td>` : ''}
          <td class="num">${d.itemCount ?? '—'}</td>
          <td>${shortDate(entrada ? d.importedAt || d.issuedAt : d.issuedAt)}<div class="sub">${entrada ? `emitida ${shortDate(d.issuedAt)}` : `atualizado ${ago(d.updatedAt)}`}</div></td>
          <td>${progressBar(d)}</td>
          <td>${docStatus(d)}</td>
          <td>${alertChips(d.alerts)}</td>
          ${compact ? '' : html`<td>${d.lock ? html`<span class="lock" title="Reservado até ${fmtDateTime(d.lock.expiresAt)}">🔒 ${d.lock.userName}</span>` : (d.finishedByName || d.startedByName || html`<span class="muted">—</span>`)}</td>`}
        </tr>`;
      })}</tbody></table></div>`;
  }

  function bindRows(container) {
    $$('tr[data-id]', container).forEach((tr) => tr.addEventListener('click', () => { location.hash = `#/documentos/${tr.dataset.id}`; }));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Painel operacional
  // ───────────────────────────────────────────────────────────────────────────
  async function viewPanel() {
    const load = async () => {
      const s = await api('GET', '/v1/dashboard/summary');
      const workerAge = s.worker.seenAt ? (Date.now() - new Date(s.worker.seenAt)) / 60000 : Infinity;
      const workerOk = workerAge < 15;
      const ativos = s.operators.filter((o) => o.ultima_leitura && Date.now() - new Date(o.ultima_leitura) < 10 * 60000).length;

      const flowCard = (flow) => {
        const f = FLOW[flow];
        const st = s.flows?.[flow]?.byStatus || {};
        const done = st.CONCLUIDO || 0;
        const div = (st.DIVERGENTE || 0) + (st.AGUARDANDO_APROVACAO || 0);
        const divToday = s.flows?.[flow]?.divergentToday || 0;
        const conf = done ? ((done - divToday) / done) * 100 : null;
        const mini = (cls, label, value, tab, hint) => html`<button class="mini ${cls}" data-flow="${flow}" data-tab="${tab}">
          <span class="v">${value}</span><span class="l">${label}</span>${hint ? html`<span class="h">${hint}</span>` : ''}</button>`;
        return html`<section class="card flow-card f-${flow}">
          <div class="flow-head">
            <div class="fic">${raw(ICON[f.icon])}</div>
            <div><h2>${f.label}</h2><div class="muted">${f.area} · ${flow === 'entrada' ? 'notas de compra' : 'pedidos de venda'}</div></div>
            <a class="btn sm" href="${f.href}">Abrir fila</a>
          </div>
          <div class="minis">
            ${mini('s-wait', flow === 'entrada' ? 'Aguardando' : 'Aguardando', st.AGUARDANDO || 0, 'ag')}
            ${mini('s-sep', flow === 'entrada' ? 'Em conferência' : 'Em separação', st.EM_CONFERENCIA || 0, 'conf')}
            ${mini('s-approval', 'Divergências', div, 'div', st.AGUARDANDO_APROVACAO ? `${st.AGUARDANDO_APROVACAO} c/ supervisor` : '')}
            ${mini('s-done', flow === 'entrada' ? 'Recebidas hoje' : 'Liberados hoje', done, 'ok', done ? `${fmtDuration(s.flows?.[flow]?.avgSeconds)} médio` : '')}
          </div>
          <div class="conformity">
            <div class="row"><span>Conformidade hoje</span><strong class="${conf === null ? '' : conf >= 95 ? 'good' : conf >= 85 ? 'mid' : 'bad'}">${conf === null ? '—' : `${conf.toFixed(1).replace('.', ',')}%`}</strong></div>
            <div class="meter"><i style="width:${conf ?? 0}%" class="${conf === null ? '' : conf >= 95 ? 'good' : conf >= 85 ? 'mid' : 'bad'}"></i></div>
            <div class="muted small">${conf === null ? 'Sem conferências concluídas hoje.' : `${done - divToday} de ${done} sem divergência`}</div>
          </div>
        </section>`;
      };

      main().innerHTML = html`
        ${pageHead('Painel operacional', `Tempo real · ${state.company.name}`, '', 'Visão geral')}
        ${!workerOk ? html`<div class="alert-box warn">${raw(ICON.warn)}<div><strong>Worker do ERP sem comunicação ${s.worker.seenAt ? ago(s.worker.seenAt) : 'desde a instalação'}.</strong> Pedidos novos e o retorno ao ERP estão parados — verifique o serviço ColiseuWorkervett no servidor do cliente.</div></div>` : ''}
        ${s.writeback.erros ? html`<div class="alert-box danger">${raw(ICON.alert)}<div>${s.writeback.erros} conferência(s) com erro ao gravar no ERP. <a href="#/saidas" data-wb="ERRO">Ver documentos</a></div></div>` : ''}
        ${!s.settings?.companyCnpj && isAdmin() ? html`<div class="alert-box info">${raw(ICON.info)}<div>Informe o <strong>CNPJ da empresa</strong> em <a href="#/configuracoes">Configurações</a> para o sistema criticar notas de entrada destinadas a outro CNPJ e separar DANFE de fornecedor do DANFE próprio.</div></div>` : ''}

        <div class="grid flows">${flowCard('entrada')}${flowCard('saida')}</div>

        <div class="grid two" style="margin-top:20px">
          <section class="card">
            <div class="card-head"><h2>${raw(ICON.warn)} Críticas — resolva agora</h2><span class="muted small">${s.attention.length ? `${s.attention.length} documento(s)` : ''}</span></div>
            ${s.attention.length ? html`<ul class="todo">${s.attention.map((a) => html`<li data-id="${a.id}">
                ${flowTag(a)}<div class="t"><strong>${docTitle(a)}</strong> <span class="muted">${a.customerName || ''}</span>
                <div class="why">${a.alerts.slice(0, 2).map((x) => html`<span class="${LEVEL[x.level].cls}">${raw(ICON[LEVEL[x.level].icon])}${x.message}</span>`)}</div></div>
                ${docStatus(a)}</li>`)}</ul>`
              : html`<div class="crit-empty big">${raw(ICON.check)}<span>Nenhuma crítica aberta. Operação em dia.</span></div>`}
          </section>
          <section class="card card-pad">
            <h2>Integração com o ERP</h2>
            <div class="meta-grid" style="grid-template-columns:1fr 1fr">
              <div><div class="k">Worker</div><div class="v">${workerOk ? html`<span class="status s-done">Online</span>` : html`<span class="status s-approval">Offline</span>`}</div><div class="muted small" style="margin-top:4px">${ago(s.worker.seenAt)}</div></div>
              <div><div class="k">Versão</div><div class="v">${s.worker.info?.version || '—'}</div></div>
              <div><div class="k">Retorno ao ERP</div><div class="v">${s.worker.info?.writebackEnabled ? 'Ativo' : 'Desligado'}</div></div>
              <div><div class="k">Pendentes</div><div class="v">${s.writeback.pendentes}</div></div>
            </div>
            <div style="margin-top:14px">${s.sync.map((x) => html`<div class="kv-row"><span>${x.entity}</span><span class="muted">${ago(x.last_at)}</span></div>`)}</div>
          </section>
        </div>

        <section class="card" style="margin-top:20px">
          <div class="card-head"><h2>Produtividade de hoje</h2><span class="muted small">${ativos ? `${ativos} operador(es) lendo agora` : 'ninguém lendo agora'}</span></div>
          ${s.operators.length ? html`<div class="table-wrap"><table>
            <thead><tr><th>Operador</th><th class="num">Documentos</th><th class="num">Leituras</th><th class="num">Unidades</th><th>Última leitura</th></tr></thead>
            <tbody>${s.operators.map((o) => html`<tr><td><strong>${o.name}</strong></td><td class="num">${o.documentos}</td><td class="num">${o.leituras}</td><td class="num">${fmtQty(o.unidades)}</td><td>${ago(o.ultima_leitura)}</td></tr>`)}</tbody>
          </table></div>` : html`<div class="empty">Nenhuma leitura hoje.</div>`}
        </section>`.s;

      $$('[data-flow][data-tab]').forEach((b) => b.addEventListener('click', () => {
        store.set(`est.q.${b.dataset.flow}.tab`, b.dataset.tab);
        location.hash = FLOW[b.dataset.flow].href;
      }));
      $$('.todo li[data-id]').forEach((li) => li.addEventListener('click', () => { location.hash = `#/documentos/${li.dataset.id}`; }));
    };
    await load();
    state.view = { onEvent: debounce(() => { load().catch(() => {}); refreshNavCounts(); }, 1500) };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filas: Entradas e Saídas
  // ───────────────────────────────────────────────────────────────────────────
  const OPEN_ST = 'AGUARDANDO,EM_CONFERENCIA,DIVERGENTE,AGUARDANDO_APROVACAO';
  const queueTabs = (flow) => [
    { key: 'fila', label: 'Na fila', status: OPEN_ST },
    { key: 'ag', label: flow === 'entrada' ? 'Aguardando conferência' : 'Aguardando separação', status: 'AGUARDANDO', cls: 's-wait' },
    { key: 'conf', label: flow === 'entrada' ? 'Em conferência' : 'Em separação', status: 'EM_CONFERENCIA', cls: 's-sep' },
    { key: 'div', label: 'Divergências', status: 'DIVERGENTE,AGUARDANDO_APROVACAO', cls: 's-approval' },
    { key: 'ok', label: flow === 'entrada' ? 'Recebidas' : 'Liberados / faturados', status: 'CONCLUIDO', cls: 's-done' },
    { key: 'canc', label: 'Cancelados', status: 'CANCELADO', cls: 's-cancel' },
    { key: 'all', label: 'Todos', status: '' },
  ];

  async function viewQueue(flow) {
    const F = FLOW[flow];
    const TABS = queueTabs(flow);
    markNav(location.hash, flow);
    const k = (n) => `est.q.${flow}.${n}`;
    const savedTab = store.get(k('tab'));
    const f = {
      tab: TABS.some((t) => t.key === savedTab) ? savedTab : 'fila',
      q: '',
      days: store.get(k('days')) || '7',
      attention: store.get(k('att')) === '1',
      priority: false,
      mine: false,
      writeback: flow === 'saida' ? pendingWritebackFilter : null,
    };
    pendingWritebackFilter = null;
    let items = [];
    let hasMore = false;

    const actions = flow === 'entrada' ? [
      html`<button class="btn" id="q-scan">${raw(ICON.scan)} Bipar DANFE</button>`,
      isSup() ? html`<button class="btn primary" id="q-import">${raw(ICON.upload)} Importar XML</button>` : '',
    ] : [html`<button class="btn" id="q-scan">${raw(ICON.scan)} Ler pedido</button>`];

    main().innerHTML = html`
      ${pageHead(F.label, flow === 'entrada'
        ? 'Recebimento de mercadorias — conferência cega das notas de compra'
        : 'Expedição — separação e conferência cega dos pedidos de venda do ERP', actions, F.area)}
      ${flowGuide(flow)}
      ${flow === 'entrada' && isSup() ? html`<div class="dropzone slim" id="q-drop">${raw(ICON.file)}<span><strong>Arraste os XML das NF-e aqui</strong> ou clique para escolher — vários de uma vez.</span>
        <input type="file" id="q-file" accept=".xml,text/xml,application/xml" multiple hidden></div>` : ''}
      <section class="card">
        <div class="tabs" id="tabs"></div>
        <div class="toolbar">
          <label class="search">${raw(ICON.search)}<input class="input" id="q" placeholder="${flow === 'entrada' ? 'NF, fornecedor, CNPJ, chave ou pedido de compra' : 'Pedido, NF, cliente ou chave'}"></label>
          <select class="input" id="days" title="Período dos concluídos (pendentes aparecem sempre)">
            ${[['1', 'Hoje'], ['3', '3 dias'], ['7', '7 dias'], ['30', '30 dias'], ['90', '90 dias'], ['180', '180 dias'], ['365', '1 ano']].map(([v, l]) => html`<option value="${v}" ${v === f.days ? 'selected' : ''}>${l}</option>`)}
          </select>
          <button class="toggle tone-danger ${f.attention ? 'on' : ''}" id="t-att" type="button">${raw(ICON.warn)} Com críticas <span class="n" id="att-n"></span></button>
          ${flow === 'saida' ? html`<button class="toggle ${f.priority ? 'on' : ''}" id="t-prio" type="button">Urgentes</button>` : ''}
          <button class="toggle" id="t-mine" type="button">Minhas reservas</button>
          ${f.writeback ? html`<span class="filter-chip">Retorno ERP: ${WB_LABEL[f.writeback]} <button type="button" id="wb-x" aria-label="Remover filtro">×</button></span>` : ''}
        </div>
        <div id="list"></div>
      </section>`.s;
    bindGuide();

    const drawTabs = (counts) => {
      const n = (t) => (t.status ? t.status.split(',').reduce((s, x) => s + (counts?.byStatus?.[x] || 0), 0) : null);
      $('#tabs').innerHTML = TABS.map((t) => html`<button class="tab ${t.cls || ''} ${t.key === f.tab ? 'active' : ''}" data-tab="${t.key}">
        ${t.cls ? html`<i class="dot"></i>` : ''}${t.label}${n(t) !== null ? html`<span class="n">${n(t)}</span>` : ''}</button>`.s).join('');
      $('#att-n').textContent = counts?.attention ? counts.attention : '';
      $$('#tabs .tab').forEach((b) => b.addEventListener('click', () => {
        f.tab = b.dataset.tab; store.set(k('tab'), f.tab);
        $$('#tabs .tab').forEach((x) => x.classList.toggle('active', x === b));
        load().catch((e) => toast(e.message, true));
      }));
    };

    const load = async (append = false) => {
      const tab = TABS.find((t) => t.key === f.tab);
      const params = new URLSearchParams({ flow, limit: '50', offset: String(append ? items.length : 0), days: f.days });
      if (tab.status) params.set('status', tab.status);
      if (f.q) params.set('q', f.q);
      if (f.writeback) params.set('writeback', f.writeback);
      if (f.attention) params.set('attention', '1');
      if (f.priority) params.set('priority', '1');
      if (f.mine) params.set('mine', '1');
      const [r, counts] = await Promise.all([
        api('GET', `/v1/documents?${params}`),
        append ? null : api('GET', `/v1/documents/counts?flow=${flow}&days=${f.days}`),
      ]);
      items = append ? items.concat(r.items) : r.items;
      hasMore = r.items.length === 50;
      if (counts) drawTabs(counts);
      draw();
    };

    const draw = () => {
      const empty = f.attention ? 'Nenhum documento com críticas neste filtro. 👌'
        : flow === 'entrada' && f.tab === 'fila' ? html`Nenhuma nota na fila. ${isSup() ? 'Importe o XML ou bipe o DANFE da mercadoria que chegou.' : 'Peça ao supervisor para importar o XML da nota.'}`
          : `Nenhum${flow === 'entrada' ? 'a nota' : ' pedido'} neste filtro.`;
      $('#list').innerHTML = items.length
        ? docsTable(items, flow).s + (hasMore ? '<div class="more"><button class="btn" id="more">Carregar mais</button></div>' : '')
        : html`<div class="empty">${raw(ICON[F.icon])}<div>${empty}</div></div>`.s;
      bindRows($('#list'));
      $('#more')?.addEventListener('click', () => load(true).catch((e) => toast(e.message, true)));
    };

    const reload = () => load().catch((er) => toast(er.message, true));
    $('#q').addEventListener('input', debounce((e) => { f.q = e.target.value.trim(); reload(); }, 300));
    $('#days').addEventListener('change', (e) => { f.days = e.target.value; store.set(k('days'), f.days); reload(); });
    const toggle = (id, key, persist) => $(id)?.addEventListener('click', (e) => {
      f[key] = !f[key]; e.currentTarget.classList.toggle('on', f[key]);
      if (persist) store.set(k(persist), f[key] ? '1' : '0');
      reload();
    });
    toggle('#t-att', 'attention', 'att');
    toggle('#t-prio', 'priority');
    toggle('#t-mine', 'mine');
    $('#wb-x')?.addEventListener('click', (e) => { f.writeback = null; e.currentTarget.parentElement.remove(); reload(); });
    $('#q-scan').addEventListener('click', () => openScanner());
    $('#q-import')?.addEventListener('click', () => openImport());
    const drop = $('#q-drop');
    if (drop) {
      drop.addEventListener('click', () => $('#q-file').click());
      $('#q-file').addEventListener('change', (e) => { if (e.target.files.length) openImport({ files: [...e.target.files] }); e.target.value = ''; });
      bindDrop(drop, (files) => openImport({ files }));
    }

    await load();
    state.view = { onEvent: debounce((ev) => { if (ev.type !== 'worker.heartbeat') { reload(); refreshNavCounts(); } }, 1200) };
  }

  /** Arrastar e soltar arquivos XML. */
  function bindDrop(el, onFiles) {
    ['dragenter', 'dragover'].forEach((t) => el.addEventListener(t, (e) => { e.preventDefault(); el.classList.add('over'); }));
    ['dragleave', 'drop'].forEach((t) => el.addEventListener(t, (e) => { e.preventDefault(); el.classList.remove('over'); }));
    el.addEventListener('drop', (e) => {
      const files = [...(e.dataTransfer?.files || [])].filter((f) => /\.xml$/i.test(f.name) || /xml/.test(f.type));
      if (files.length) onFiles(files); else toast('Solte arquivos .xml de NF-e', true);
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Importação de XML (entradas)
  // ───────────────────────────────────────────────────────────────────────────
  /**
   * Modal de recebimento: bipa o DANFE (opcional) e escolhe/arrasta os XML.
   * Com a chave do DANFE informada, o XML precisa ser da mesma nota (evita trocar notas).
   */
  function openImport({ files = [], expectedKey = '' } = {}) {
    if (!isSup()) { toast('Somente supervisor ou administrador importa XML. Peça a ele para importar a nota.', true); return; }
    const m = modal({
      title: 'Receber nota fiscal (entrada)',
      wide: true,
      submitLabel: null,
      cancelLabel: 'Fechar',
      body: html`
        <ol class="mini-steps"><li><span>1</span>Bipe o DANFE <em>(opcional)</em></li><li><span>2</span>Selecione o XML</li><li><span>3</span>Revise as críticas e confira</li></ol>
        <div class="field"><label for="im-key">Chave de acesso do DANFE</label>
          <input class="input mono scan-like" id="im-key" value="${fmtKey(expectedKey)}" placeholder="Bipe o código de barras do DANFE (44 dígitos)" autocomplete="off">
          <div class="help" id="im-key-help">Garante que o XML importado é da mesma nota que chegou fisicamente.</div></div>
        <div class="dropzone" id="im-drop">${raw(ICON.upload)}<strong>Arraste os arquivos XML aqui</strong><span class="muted">ou clique para escolher — pode selecionar vários</span>
          <input type="file" id="im-file" accept=".xml,text/xml,application/xml" multiple hidden></div>
        <div id="im-results" class="im-results"></div>`,
    });
    const el = m.el;
    const keyInput = $('#im-key', el);
    const keyDigits = () => keyInput.value.replace(/\D/g, '');
    keyInput.addEventListener('input', () => {
      const d = keyDigits();
      $('#im-key-help', el).textContent = d.length === 44 ? `NF ${Number(d.slice(25, 34))} · série ${Number(d.slice(22, 25))} · emitente ${fmtCnpj(d.slice(6, 20))}`
        : d.length ? `${d.length}/44 dígitos` : 'Garante que o XML importado é da mesma nota que chegou fisicamente.';
    });
    keyInput.dispatchEvent(new Event('input'));
    // Leitor manda Enter no fim: não submete o modal, vai para a escolha do arquivo.
    keyInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); if (keyDigits().length === 44) $('#im-file', el).click(); } });

    const results = $('#im-results', el);
    const row = (name) => {
      const r = document.createElement('div');
      r.className = 'im-row busy';
      r.innerHTML = html`<div class="ic">${raw(ICON.file)}</div><div class="t"><strong>${name}</strong><div class="muted">Importando…</div></div><div class="act"></div>`.s;
      results.prepend(r);
      return r;
    };
    const send = async (file, r, force = false) => {
      const xml = await file.text();
      const key = keyDigits();
      try {
        const res = await api('POST', '/v1/entries/import', { xml, ...(key.length === 44 && files.length <= 1 ? { expectedKey: key } : {}), ...(force ? { force: true } : {}) });
        const counts = { erro: 0, alerta: 0, info: 0 };
        res.critiques.forEach((c) => { counts[c.level]++; });
        r.className = `im-row ${counts.erro ? 'err' : counts.alerta ? 'warn' : 'ok'}`;
        r.innerHTML = html`<div class="ic">${raw(ICON[counts.erro ? 'alert' : counts.alerta ? 'warn' : 'check'])}</div>
          <div class="t"><strong>NF ${res.number} · ${res.supplier || ''}</strong>
            <div class="muted">${res.items} itens${res.unlinked ? ` · ${res.unlinked} sem vínculo` : ''} · ${counts.erro ? `${counts.erro} crítica(s) grave(s)` : counts.alerta ? `${counts.alerta} crítica(s) para revisar` : 'sem críticas'}</div></div>
          <div class="act"><a class="btn sm primary" href="#/documentos/${res.documentId}">Abrir</a></div>`.s;
        beep(!counts.erro);
        refreshNavCounts();
        return true;
      } catch (err) {
        beep(false);
        const dup = err.code === 'DUPLICATE';
        r.className = `im-row ${dup ? 'warn' : 'err'}`;
        r.innerHTML = html`<div class="ic">${raw(ICON[dup ? 'warn' : 'alert'])}</div><div class="t"><strong>${file.name}</strong><div>${err.message}</div></div>
          <div class="act">${dup ? html`<a class="btn sm" href="#/documentos/${err.data.documentId}">Abrir existente</a>` : ''}
          ${err.code === 'DEST_MISMATCH' ? html`<button type="button" class="btn sm danger">Importar mesmo assim</button>` : ''}</div>`.s;
        $('button.danger', r)?.addEventListener('click', () => { r.className = 'im-row busy'; send(file, r, true); });
        return false;
      } finally {
        $$('a', r).forEach((a) => a.addEventListener('click', () => m.close()));
      }
    };
    const handle = async (list) => {
      files = list;
      let allOk = true;
      for (const file of list) allOk = (await send(file, row(file.name))) && allOk;
      // Chave do DANFE só é limpa quando deu certo — no erro o operador corrige e tenta de novo.
      if (allOk) { keyInput.value = ''; keyInput.dispatchEvent(new Event('input')); }
    };
    const drop = $('#im-drop', el);
    drop.addEventListener('click', () => $('#im-file', el).click());
    $('#im-file', el).addEventListener('change', (e) => { if (e.target.files.length) handle([...e.target.files]); e.target.value = ''; });
    bindDrop(drop, handle);
    if (files.length) handle(files);
    return m;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Detalhe do documento
  // ───────────────────────────────────────────────────────────────────────────
  async function viewDocument(id) {
    let tab = 'itens';
    const load = async () => {
      const d = await api('GET', `/v1/documents/${id}`);
      const flow = flowOf(d);
      const F = FLOW[flow];
      markNav(location.hash, flow);
      const sup = isSup();
      const entrada = flow === 'entrada';
      const canCount = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE'].includes(d.status) && !d.erpCancelled;
      const lockedByOther = d.lock && !d.lock.mine;
      const st = statusInfo(d);
      const critErrors = (d.critiques || []).filter((c) => c.level === 'erro').length;

      const actions = [
        canCount ? html`<button class="btn primary" id="a-count" ${lockedByOther && !sup ? 'disabled' : ''}>${raw(ICON.scan)} ${d.lock?.mine ? 'Continuar conferência' : d.status === 'DIVERGENTE' ? 'Recontar' : entrada ? 'Conferir nota' : 'Separar e conferir'}</button>` : '',
        sup && ['AGUARDANDO_APROVACAO', 'DIVERGENTE'].includes(d.status) ? html`<button class="btn ok" id="a-approve">Aprovar</button>` : '',
        sup && (['AGUARDANDO_APROVACAO', 'DIVERGENTE'].includes(d.status) || (d.status === 'CONCLUIDO' && d.writebackStatus !== 'GRAVADO')) ? html`<button class="btn" id="a-reopen">Reabrir recontagem</button>` : '',
        sup && d.lock ? html`<button class="btn" id="a-release">Liberar reserva</button>` : '',
        sup && d.status !== 'CANCELADO' && d.writebackStatus !== 'GRAVADO' && (d.startedAt || d.round > 0) ? html`<button class="btn danger" id="a-reset">Zerar conferência</button>` : '',
        sup && entrada && d.status === 'AGUARDANDO' && !d.startedAt ? html`<button class="btn danger" id="a-delete">Excluir importação</button>` : '',
        sup && d.status !== 'AGUARDANDO' ? html`<button class="btn ghost" id="a-print" title="Imprimir relatório da conferência">${raw(ICON.print)}</button>` : '',
      ];

      const diff = (i) => {
        if (i.countedQty === null || i.countedQty === undefined) return '';
        const n = Number(i.countedQty) - Number(i.expectedQty);
        return n === 0 ? '0' : (n > 0 ? '+' : '') + fmtQty(n);
      };
      const critBySeq = new Map();
      for (const c of d.critiques || []) for (const s of c.seqs || []) critBySeq.set(s, [...(critBySeq.get(s) || []), c]);
      const isPlaceholder = (pid) => String(pid).startsWith('NFE:');
      const lotsCell = (i) => (i.meta?.lots?.length ? i.meta.lots.map((l) => html`<div class="lot">${l.lot || 's/ lote'}${l.expiresAt ? html` · <span class="${(critBySeq.get(i.seq) || []).some((c) => /LOT_/.test(c.code)) ? 'warn-t' : ''}">val. ${new Date(`${l.expiresAt}T12:00:00`).toLocaleDateString('pt-BR')}</span>` : ''}</div>`) : html`<span class="muted">—</span>`);

      const stages = entrada ? ['Importada', 'Em conferência', 'Divergência', 'Recebida'] : ['Na fila', 'Em separação', 'Divergência', 'Liberado', 'Faturado'];
      const stageIdx = st.stage;

      main().innerHTML = html`
        ${pageHead(docTitle(d), d.customerName || '', actions, html`<a href="${F.href}" class="back">${raw(ICON.back)}${F.label}</a>`)}
        ${d.erpCancelled ? html`<div class="alert-box danger">${raw(ICON.alert)}<div>Documento cancelado no ERP${d.status === 'CONCLUIDO' ? ' depois de conferido' : ''}.</div></div>` : ''}
        ${d.source === 'PED' && d.status === 'CONCLUIDO' && !d.invoiceNumber ? html`<div class="alert-box ok">${raw(ICON.check)}<div>Conferido — pedido liberado para o faturamento emitir a nota.</div></div>` : ''}
        ${entrada && d.status === 'CONCLUIDO' ? html`<div class="alert-box ok">${raw(ICON.check)}<div>Nota conferida${d.hasDivergence ? ' com divergência aprovada' : ''}. Dê entrada no ERP com as quantidades <strong>contadas</strong>${d.hasDivergence ? ' e acione o fornecedor sobre a diferença' : ''}.</div></div>` : ''}
        ${entrada && critErrors && canCount ? html`<div class="alert-box danger">${raw(ICON.alert)}<div><strong>${critErrors} crítica(s) grave(s).</strong> Resolva antes de receber a mercadoria — veja abaixo.</div></div>` : ''}
        ${d.writebackStatus === 'ERRO' && sup ? html`<div class="alert-box danger">${raw(ICON.alert)}<div>Erro ao gravar no ERP: ${d.writebackError || 'desconhecido'}. O Worker tenta novamente a cada 5 minutos.</div></div>` : ''}
        ${lockedByOther ? html`<div class="alert-box info">${raw(ICON.info)}<div>Em conferência por <strong>${d.lock.userName}</strong> até ${fmtDateTime(d.lock.expiresAt)}.</div></div>` : ''}

        <section class="card doc-hero f-${flow}">
          <div class="hero-top">
            ${flowTag(d)} ${docStatus(d)} ${d.round > 0 ? html`<span class="muted">rodada ${d.round + 1}</span>` : ''}
            <div class="spacer"></div>
            ${sup && !['CONCLUIDO', 'CANCELADO'].includes(d.status) ? html`<label class="prio">Prioridade <select class="input" id="prio">
              ${[[0, 'Normal'], [5, 'Alta'], [10, 'Urgente']].map(([v, l]) => html`<option value="${v}" ${Number(d.priority) === v ? 'selected' : ''}>${l}</option>`)}</select></label>` : ''}
          </div>
          ${stageIdx >= 0 ? html`<ol class="track">${stages.map((s, i) => html`<li class="${i < stageIdx ? 'done' : i === stageIdx ? `now ${st.cls}` : ''} ${i === 2 && !d.hasDivergence && stageIdx > 2 ? 'skipped' : ''}"><span class="dot">${i < stageIdx ? raw(ICON.check) : ''}</span>${s}</li>`)}</ol>` : ''}
          <div class="meta-grid">
            ${entrada ? html`
              <div><div class="k">Fornecedor</div><div class="v">${d.entry?.supplier?.name || d.customerName || '—'}</div><div class="muted small">${fmtCnpj(d.customerCode)}${d.entry?.supplier?.uf ? ` · ${d.entry.supplier.uf}` : ''}</div></div>
              <div><div class="k">Emissão</div><div class="v">${fmtDateTime(d.issuedAt)}</div></div>
              <div><div class="k">Importada</div><div class="v">${fmtDateTime(d.importedAt)}</div></div>
              ${sup ? html`<div><div class="k">Valor da nota</div><div class="v strong">${fmtMoney(d.entry?.totalValue)}</div></div>` : ''}
              <div><div class="k">Pedido de compra</div><div class="v">${d.orderNumber || html`<span class="muted">não informado</span>`}</div></div>
              ${sup ? html`<div><div class="k">Natureza</div><div class="v">${d.entry?.operation || '—'}</div></div>` : ''}
              <div class="wide"><div class="k">Chave de acesso</div><div class="v mono key">${fmtKey(d.erpKey)}</div></div>
              ${sup && d.entry?.protocol ? html`<div><div class="k">Protocolo SEFAZ</div><div class="v">${d.entry.protocol.number || '—'} <span class="muted small">${d.entry.protocol.status}</span></div></div>` : ''}`
            : html`
              <div><div class="k">Cliente</div><div class="v">${d.customerName || '—'}</div></div>
              <div><div class="k">Emissão</div><div class="v">${fmtDateTime(d.issuedAt)}</div></div>
              <div><div class="k">Vendedor</div><div class="v">${d.sellerName || '—'}</div></div>
              ${d.invoiceNumber ? html`<div><div class="k">Nota fiscal</div><div class="v">${d.invoiceNumber} <span class="muted">${fmtDateTime(d.invoicedAt)}</span></div></div>` : ''}
              ${d.orderNumber ? html`<div><div class="k">Pedido</div><div class="v">${d.orderNumber}</div></div>` : ''}
              <div><div class="k">Chave ERP</div><div class="v mono">${d.erpKey}</div></div>
              ${sup ? html`<div><div class="k">Retorno ERP</div><div class="v">${badge(d.writebackStatus === 'NAO_APLICAVEL' ? 'PENDENTE' : d.writebackStatus, WB_LABEL[d.writebackStatus])}</div></div>` : ''}`}
            <div><div class="k">Início</div><div class="v">${fmtDateTime(d.startedAt)}</div><div class="muted small">${d.startedByName || ''}</div></div>
            <div><div class="k">Fim</div><div class="v">${fmtDateTime(d.finishedAt)}</div><div class="muted small">${d.finishedByName || ''}</div></div>
            ${d.approvedAt ? html`<div><div class="k">Aprovação</div><div class="v">${fmtDateTime(d.approvedAt)}</div><div class="muted small">${d.approvedByName || ''}</div></div>` : ''}
          </div>
          ${d.justification ? html`<div class="justif"><div class="k">Justificativa</div><div>${d.justification}</div></div>` : ''}
        </section>

        ${sup ? html`<section class="card card-pad crit-card">
          <h2>${raw(ICON.warn)} Críticas ${entrada ? 'da nota e da operação' : 'da operação'}</h2>
          ${critiqueList([...(d.critiques || []), ...(d.alerts || []).filter((a) => !/^ENTRY_/.test(a.code))])}
        </section>` : ''}

        ${sup ? html`<div class="tabs inline" style="margin:18px 0 10px">
          ${[['itens', 'Itens'], ['leituras', 'Leituras'], ['historico', 'Histórico']].map(([kk, l]) => html`<button class="tab ${tab === kk ? 'active' : ''}" data-dtab="${kk}">${l}</button>`)}</div>` : html`<div style="height:16px"></div>`}
        <section class="card" id="tab-body">
          ${sup ? html`<div class="table-wrap"><table class="items">
            <thead><tr><th>#</th><th>Produto</th>${entrada ? html`<th>Fornecedor / GTIN</th><th>Lote · validade</th>` : ''}<th>Un</th><th class="num">Esperado</th><th class="num">Contado</th><th class="num">Dif.</th><th>Resultado</th></tr></thead>
            <tbody>${d.items.map((i) => {
              const unlinked = entrada && isPlaceholder(i.productErpId);
              const crit = critBySeq.get(i.seq) || [];
              return html`<tr class="${i.result === 'FALTA' ? 'r-falta' : i.result === 'SOBRA' ? 'r-sobra' : ''}">
              <td class="muted">${i.isExtra ? 'extra' : i.seq}</td>
              <td><div class="pname">${i.description}</div>
                <div class="sub">${unlinked ? html`<span class="badge b-FALTA">Sem vínculo</span>` : html`<span class="mono">${i.productErpId}</span>${i.meta?.catalogDescription && i.meta.catalogDescription !== i.description ? ` · ${i.meta.catalogDescription}` : ''}`}
                ${entrada && !i.isExtra && canCount ? html` <button class="link-btn" data-link="${i.seq}">${raw(ICON.link)}${unlinked ? 'Vincular' : 'Trocar'}</button>` : ''}
                ${crit.filter((c) => !/^LOT_/.test(c.code) && c.code !== 'UNLINKED').map((c) => html` <span class="crit ${LEVEL[c.level].cls}" title="${c.message}">${raw(ICON[LEVEL[c.level].icon])}</span>`)}</div></td>
              ${entrada ? html`<td><div class="mono small">${i.meta?.supplierCode || '—'}</div><div class="mono small muted">${i.meta?.gtin || i.meta?.gtinTrib || 'sem GTIN'}${i.meta?.packFactor > 1 ? ` · cx ${i.meta.packFactor}` : ''}</div></td><td>${lotsCell(i)}</td>` : ''}
              <td>${i.unit || ''}</td>
              <td class="num">${fmtQty(i.expectedQty)}</td><td class="num strong">${fmtQty(i.countedQty)}</td><td class="num">${diff(i)}</td>
              <td>${badge(i.result, RESULT_LABEL[i.result])}</td></tr>`;
            })}</tbody></table></div>`
            : html`<div class="table-wrap"><table>
              <thead><tr><th>Código</th><th>Descrição</th><th>Un</th><th class="num">Contado (rodada)</th><th></th></tr></thead>
              <tbody>${d.items.map((i) => html`<tr><td class="mono">${String(i.productErpId).replace(/^NFE:/, '')}</td><td>${i.description}</td><td>${i.unit || ''}</td>
                <td class="num">${fmtQty(d.counts[i.productErpId] ?? 0)}</td><td>${i.mustRecount ? badge('SOBRA', 'Recontar') : ''}</td></tr>`)}</tbody></table></div>`}
        </section>
        ${sup ? printReport(d) : ''}`.s;

      $('#a-count')?.addEventListener('click', () => { location.hash = `#/conferir/${id}`; });
      $('#a-print')?.addEventListener('click', () => window.print());
      $('#a-release')?.addEventListener('click', async () => {
        try { await api('POST', `/v1/documents/${id}/release`); toast('Reserva liberada'); load(); } catch (e) { toast(e.message, true); }
      });
      $('#prio')?.addEventListener('change', async (e) => {
        try { await api('PATCH', `/v1/documents/${id}`, { priority: Number(e.target.value) }); toast('Prioridade atualizada'); } catch (er) { toast(er.message, true); }
      });
      $('#a-approve')?.addEventListener('click', () => modal({
        title: 'Aprovar conferência',
        body: html`${d.hasDivergence ? html`<div class="alert-box warn">${raw(ICON.warn)}<div>Este documento tem divergência. A aprovação ${entrada ? 'registra o recebimento com' : 'grava no ERP'} as quantidades <strong>contadas</strong>.</div></div>` : ''}
          ${divergenceSummary(d)}
          <div class="field"><label for="just">Justificativa</label><textarea class="input" id="just" ${d.hasDivergence && state.settings.requireJustification ? 'required' : ''} placeholder="${entrada ? 'Ex.: fornecedor enviou 2 cx a menos; comprador avisado, aguarda nota de devolução' : 'Ex.: falta confirmada no estoque; cliente avisado'}"></textarea></div>`,
        submitLabel: 'Aprovar',
        onSubmit: async (form) => { await api('POST', `/v1/documents/${id}/approve`, { justification: $('#just', form).value }); toast('Conferência aprovada'); load(); },
      }));
      $('#a-reopen')?.addEventListener('click', () => {
        const products = [...new Map(d.items.map((i) => [i.productErpId, i])).values()];
        modal({
          title: 'Reabrir para recontagem',
          body: html`<p class="muted" style="margin-top:0">Marque os produtos que o conferente deve recontar. Os divergentes já vêm marcados.</p>
            <div class="pick-scroll">${products.map((i) => html`<label class="check"><input type="checkbox" name="p" value="${i.productErpId}" ${i.result !== 'OK' ? 'checked' : ''}> <span class="mono">${String(i.productErpId).replace(/^NFE:/, '')}</span> ${i.description} ${i.result !== 'OK' ? badge(i.result, RESULT_LABEL[i.result]) : ''}</label>`)}</div>`,
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
      $('#a-delete')?.addEventListener('click', () => modal({
        title: 'Excluir importação',
        body: html`<p style="margin-top:0">A nota ${d.number} sai da fila de entradas. Use quando o XML foi importado por engano ou a mercadoria foi recusada. Você pode importar o XML de novo depois.</p>`,
        submitLabel: 'Excluir', danger: true,
        onSubmit: async () => { await api('DELETE', `/v1/entries/${id}`); toast('Importação excluída'); location.hash = '#/entradas'; },
      }));
      $$('[data-link]').forEach((b) => b.addEventListener('click', () => linkModal(d, Number(b.dataset.link), load)));
      $$('[data-dtab]').forEach((b) => b.addEventListener('click', async () => {
        tab = b.dataset.dtab;
        $$('[data-dtab]').forEach((x) => x.classList.toggle('active', x === b));
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
          <tbody>${r.items.map((s) => html`<tr class="${s.voided ? 'voided' : ''}">
            <td>${fmtDateTime(s.scanned_at)}</td><td>${s.round + 1}</td><td class="mono">${s.barcode || '—'}</td>
            <td>${s.product_erp_id ? html`<span class="mono">${String(s.product_erp_id).replace(/^NFE:/, '')}</span> ${s.description || ''}` : badge('FALTA', 'Não reconhecido')}</td>
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

  /** Resumo falta/sobra para a decisão do supervisor. */
  function divergenceSummary(d) {
    const div = d.items.filter((i) => i.result === 'FALTA' || i.result === 'SOBRA');
    if (!div.length) return '';
    return html`<div class="div-sum">${div.map((i) => {
      const n = Number(i.countedQty) - Number(i.expectedQty);
      return html`<div class="${i.result === 'FALTA' ? 'falta' : 'sobra'}"><span>${i.description}</span><strong>${n > 0 ? '+' : ''}${fmtQty(n)} ${i.unit || ''}</strong></div>`;
    })}</div>`;
  }

  /** Relatório só para impressão (fica oculto na tela). */
  function printReport(d) {
    const entrada = flowOf(d) === 'entrada';
    const div = d.items.filter((i) => i.result === 'FALTA' || i.result === 'SOBRA');
    return html`<div class="print-only report">
      <h1>Relatório de conferência — ${docTitle(d)}</h1>
      <p>${entrada ? 'Fornecedor' : 'Cliente'}: <strong>${d.customerName || '—'}</strong> ${entrada ? fmtCnpj(d.customerCode) : ''}<br>
        ${entrada ? html`Chave: ${fmtKey(d.erpKey)}<br>` : ''}Status: ${statusInfo(d).label} · Conferido por ${d.finishedByName || d.startedByName || '—'} em ${fmtDateTime(d.finishedAt)}
        ${d.approvedByName ? html`<br>Aprovado por ${d.approvedByName} em ${fmtDateTime(d.approvedAt)}` : ''}</p>
      ${d.justification ? html`<p>Justificativa: ${d.justification}</p>` : ''}
      <h2>${div.length ? `Divergências (${div.length})` : 'Sem divergências'}</h2>
      <table><thead><tr><th>Item</th><th>Produto</th><th>Un</th><th>Esperado</th><th>Contado</th><th>Diferença</th></tr></thead>
        <tbody>${(div.length ? div : d.items).map((i) => html`<tr><td>${i.isExtra ? 'extra' : i.seq}</td><td>${i.description}</td><td>${i.unit || ''}</td><td>${fmtQty(i.expectedQty)}</td><td>${fmtQty(i.countedQty)}</td><td>${fmtQty(Number(i.countedQty || 0) - Number(i.expectedQty))}</td></tr>`)}</tbody></table>
      <p class="sign">_______________________________<br>Conferente &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; _______________________________<br>${entrada ? 'Transportador / fornecedor' : 'Supervisor'}</p>
    </div>`;
  }

  /** Vincula um item da nota a um produto do cadastro (aprende o de-para do fornecedor). */
  function linkModal(d, seq, onDone) {
    const item = d.items.find((i) => i.seq === seq);
    const m = modal({
      title: `Vincular item ${seq}`,
      wide: true,
      submitLabel: null,
      cancelLabel: 'Fechar',
      body: html`<div class="link-src"><div class="k">Na nota do fornecedor</div><strong>${item.description}</strong>
          <div class="muted small mono">cód. ${item.meta?.supplierCode || '—'} · GTIN ${item.meta?.gtin || item.meta?.gtinTrib || 'sem GTIN'} · ${fmtQty(item.expectedQty)} ${item.unit || ''}</div></div>
        <label class="search big">${raw(ICON.search)}<input class="input" id="ls-q" placeholder="Buscar no cadastro: descrição, código ou EAN" value="${item.description.split(/\s+/).slice(0, 2).join(' ')}"></label>
        <div id="ls-res" class="pick-list"></div>
        <div class="help">O vínculo fica salvo: as próximas notas deste fornecedor já chegam com o item vinculado.</div>`,
    });
    const res = $('#ls-res', m.el);
    const search = async () => {
      const q = $('#ls-q', m.el).value.trim();
      if (!q) { res.innerHTML = ''; return; }
      const r = await api('GET', `/v1/products?q=${encodeURIComponent(q)}&limit=20`);
      res.innerHTML = r.items.length ? r.items.map((p) => html`<button type="button" class="pick" data-pid="${p.erpId}">
          <div><strong>${p.description}</strong><div class="muted small"><span class="mono">${p.erpId}</span>${p.brand ? ` · ${p.brand}` : ''} · ${p.unit || ''}</div></div>
          <span class="muted small">saldo ${fmtQty(p.stock)}</span></button>`.s).join('')
        : '<div class="empty small">Nenhum produto encontrado. Tente outra palavra ou o EAN.</div>';
      $$('[data-pid]', res).forEach((b) => b.addEventListener('click', async () => {
        try {
          await api('POST', `/v1/entries/${d.id}/items/${seq}/link`, { productErpId: b.dataset.pid });
          toast('Item vinculado'); m.close(); onDone();
        } catch (err) { toast(err.message, true); }
      }));
    };
    $('#ls-q', m.el).addEventListener('input', debounce(() => search().catch(() => {}), 300));
    $('#ls-q', m.el).addEventListener('keydown', (e) => { if (e.key === 'Enter') e.preventDefault(); });
    search().catch(() => {});
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
    const flow = flowOf(d);
    const entrada = flow === 'entrada';
    markNav(location.hash, flow);

    const products = new Map(d.items.map((i) => [i.productErpId, i]));
    const docProducts = new Set(d.items.filter((i) => !i.isExtra).map((i) => i.productErpId));
    const barcodes = new Map(d.barcodes.map((b) => [b.barcode, b]));
    const session = []; // leituras feitas nesta tela (para estorno rápido)
    let counts = d.counts;
    let unknown = d.unknownScans;
    let busy = false;

    const describe = async (code) => {
      const b = barcodes.get(code);
      if (b) return { productErpId: b.productErpId, description: products.get(b.productErpId)?.description || '', factor: Number(b.factor), extra: docProducts.size > 0 && !docProducts.has(b.productErpId) };
      if (products.has(code)) return { productErpId: code, description: products.get(code).description, factor: 1 };
      try {
        const p = await api('GET', `/v1/products/barcode/${encodeURIComponent(code)}`);
        barcodes.set(code, { barcode: code, productErpId: p.erpId, factor: p.factor });
        if (!products.has(p.erpId)) products.set(p.erpId, { productErpId: p.erpId, description: p.description, unit: p.unit });
        return { productErpId: p.erpId, description: p.description, factor: Number(p.factor), extra: docProducts.size > 0 && !docProducts.has(p.erpId) };
      } catch { return null; }
    };

    main().innerHTML = html`
      ${pageHead(`${entrada ? 'Conferindo' : 'Separando'} ${docTitle(d)}`, `${d.customerName || ''}${d.round > 0 ? ` · Recontagem (rodada ${d.round + 1})` : ''}`,
        html`<button class="btn" id="leave">Sair e manter reserva</button><button class="btn" id="release">Liberar documento</button>`,
        html`<a href="${FLOW[flow].href}" class="back">${raw(ICON.back)}${FLOW[flow].label}</a>`)}
      <div class="conf-banner f-${flow}">
        <span class="fic">${raw(ICON[entrada ? 'inbox' : 'truck'])}</span>
        <div><strong>${entrada ? 'Recebimento — conferência cega da nota' : 'Expedição — separação e conferência cega'}</strong>
          <div>${d.round > 0 ? 'Reconte somente os produtos destacados em amarelo. O que já bateu está travado.'
            : entrada ? 'Bipe cada volume/unidade recebida. Caixa fechada com código próprio soma a caixa inteira. Sem código? Digite o código do fornecedor.'
              : 'Pegue cada item do pedido e bipe. Você não vê a quantidade pedida: conte o que separou.'}</div></div>
        <div class="conf-progress" id="cprog"></div>
      </div>
      <div class="conf">
        <div>
          <div class="card scan-box">
            <form id="scan-form" autocomplete="off">
              <div class="scan-row">
                <input class="input scan-input mono" id="code" placeholder="Bipe ou digite o código" inputmode="numeric" autofocus>
                ${d.settings.allowManualQty ? html`<input class="input qty-input" id="qty" type="number" min="1" step="1" value="1" title="Quantidade de embalagens">` : ''}
              </div>
              <button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
              ${d.settings.allowManualQty ? html`<div class="help" style="margin-top:6px">Quantidade = embalagens lidas de uma vez (ex.: 10 caixas iguais → digite 10 e bipe uma).</div>` : ''}
            </form>
            <div class="last-scan" id="last"><div class="muted">Aguardando leitura…</div></div>
          </div>
          <div class="card" style="margin-top:16px">
            <div class="card-head"><h2>Últimas leituras</h2><span class="muted small" id="session-count"></span></div>
            <div id="session"></div>
          </div>
        </div>
        <div>
          <div class="card">
            <div class="card-head"><h2>${docProducts.size ? (entrada ? 'Itens da nota' : 'Lista de separação') : 'Contado nesta rodada'}</h2><span class="muted small">quantidade que você contou</span></div>
            <div class="count-list" id="counts"></div>
          </div>
          <div id="unknown"></div>
          <button class="btn primary lg" id="finish" style="width:100%;margin-top:16px">${raw(ICON.check)} Finalizar ${entrada ? 'conferência' : 'separação'}</button>
        </div>
      </div>`.s;

    const codeInput = $('#code');
    const keepFocus = () => { if (!document.querySelector('.modal-bg')) codeInput.focus(); };
    const focusTimer = setInterval(() => { if (document.activeElement === document.body) keepFocus(); }, 800);

    const drawCounts = () => {
      const recount = new Set(d.recount);
      const ids = new Set([...docProducts, ...Object.keys(counts), ...(d.round > 0 ? recount : [])]);
      const rows = [...ids].map((pid) => ({ pid, q: counts[pid] ?? 0, p: products.get(pid), inDoc: docProducts.has(pid) }))
        .sort((a, b) => (recount.has(b.pid) - recount.has(a.pid)) || (a.q > 0) - (b.q > 0) || (a.p?.description || a.pid).localeCompare(b.p?.description || b.pid));
      $('#counts').innerHTML = rows.length ? rows.map((r) => html`<div class="count-item ${recount.has(r.pid) ? 'recount' : ''} ${Number(r.q) > 0 ? 'has' : ''} ${!r.inDoc && docProducts.size ? 'extra' : ''}">
          <span class="ck">${Number(r.q) > 0 ? raw(ICON.check) : ''}</span>
          <div class="grow"><div>${r.p?.description || 'Produto'}</div><div class="muted mono small">${String(r.pid).replace(/^NFE:/, '')}${!r.inDoc && docProducts.size ? ' · fora do documento' : ''}${recount.has(r.pid) ? ' · recontar' : ''}</div></div>
          <div class="q">${Number(r.q) > 0 ? fmtQty(r.q) : '—'}</div></div>`.s).join('')
        : '<div class="empty">Nada contado ainda.</div>';

      // Progresso: produtos do documento já bipados (nunca revela a quantidade esperada).
      const scope = d.round > 0 ? recount : docProducts;
      if (scope.size) {
        const n = [...scope].filter((pid) => Number(counts[pid] || 0) > 0).length;
        $('#cprog').innerHTML = html`<div class="big">${n}<small>/${scope.size}</small></div><div class="muted small">${d.round > 0 ? 'recontados' : 'produtos bipados'}</div>
          <div class="meter"><i style="width:${Math.round((n / scope.size) * 100)}%"></i></div>`.s;
      }

      $('#unknown').innerHTML = unknown.length ? html`<div class="card unknown-card" style="margin-top:16px">
        <div class="card-head"><h2>${raw(ICON.alert)} Códigos não reconhecidos</h2></div>
        <div class="muted small" style="padding:0 18px 8px">Estorne antes de finalizar ou peça ao supervisor para cadastrar o código.</div>
        ${unknown.map((u) => html`<div class="count-item"><div class="mono grow">${u.barcode}</div><button class="btn sm danger" data-void="${u.eventId}">Estornar</button></div>`)}
      </div>`.s : '';
      $$('[data-void]', $('#unknown')).forEach((b) => b.addEventListener('click', () => voidScan(b.dataset.void)));
    };

    const drawSession = () => {
      $('#session-count').textContent = session.length ? `${session.length} nesta sessão` : '';
      $('#session').innerHTML = session.length ? session.slice(0, 15).map((s) => html`<div class="count-item ${s.voided ? 'voided' : ''}">
          <div class="grow"><div>${s.description || s.code}</div><div class="muted mono small">${s.code} · ${new Date(s.at).toLocaleTimeString('pt-BR')}</div></div>
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
          beep(!recounting && !info.extra);
          showLast(recounting || info.extra ? 'warn' : 'ok', info.description || 'Produto',
            recounting ? 'Este produto não está na recontagem — a leitura será ignorada.'
              : `+${fmtQty(units)}${info.extra ? ` · fora ${entrada ? 'da nota' : 'do pedido'} — vai como SOBRA` : ''}${info.factor > 1 ? ` (embalagem com ${fmtQty(info.factor)})` : ''} · total contado ${fmtQty(counts[info.productErpId] ?? 0)}`);
        } else {
          beep(false);
          showLast('err', 'Código não cadastrado', `${code} — estorne ou verifique a etiqueta`);
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

    $('#leave').addEventListener('click', () => { location.hash = FLOW[flow].href; });
    $('#release').addEventListener('click', async () => {
      try { await api('POST', `/v1/documents/${id}/release`); location.hash = FLOW[flow].href; } catch (e) { toast(e.message, true); }
    });
    $('#finish').addEventListener('click', () => {
      const missing = (d.round > 0 ? d.recount : [...docProducts]).filter((pid) => !(Number(counts[pid] || 0) > 0));
      modal({
        title: `Finalizar ${entrada ? 'conferência' : 'separação'}`,
        body: html`<p style="margin-top:0">Confirma que terminou de contar ${d.round > 0 ? 'os itens da recontagem' : 'todos os itens'}? O sistema vai comparar com ${entrada ? 'a nota' : 'o pedido'}.</p>
          ${missing.length ? html`<div class="alert-box warn">${raw(ICON.warn)}<div><strong>${missing.length} produto(s) sem nenhuma leitura</strong> — serão considerados como <strong>falta</strong>:
            <ul class="tight">${missing.slice(0, 8).map((pid) => html`<li>${products.get(pid)?.description || pid}</li>`)}${missing.length > 8 ? html`<li>e mais ${missing.length - 8}…</li>` : ''}</ul></div></div>` : ''}`,
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
      });
    });

    function resultModal(r) {
      const next = () => { location.hash = FLOW[flow].href; };
      if (r.status === 'CONCLUIDO') {
        beep(true);
        modal({ title: entrada ? 'Nota conferida' : 'Separação concluída',
          body: html`<div class="result-ok">${raw(ICON.check)}<div><strong>Tudo confere.</strong><div>${entrada ? 'Mercadoria recebida conforme a nota.' : 'Pedido liberado para o faturamento.'}</div></div></div>`,
          submitLabel: 'Próximo documento', cancelLabel: null, onSubmit: next });
      } else if (r.status === 'DIVERGENTE') {
        beep(false);
        modal({
          title: 'Recontagem necessária',
          body: html`<div class="alert-box warn">${raw(ICON.warn)}<div>A contagem não bateu. Reconte <strong>somente</strong> os produtos abaixo:</div></div>
            ${r.recount.map((p) => html`<div class="count-item recount"><div class="grow">${p.description || 'Produto'}</div><div class="mono muted">${String(p.productErpId).replace(/^NFE:/, '')}</div></div>`)}`,
          submitLabel: 'Começar recontagem', cancelLabel: null,
          onSubmit: () => { render(); },
        });
      } else {
        modal({ title: 'Enviado ao supervisor', body: html`<div class="alert-box info">${raw(ICON.info)}<div>A divergência persiste após a recontagem e foi enviada para aprovação do supervisor.</div></div>`,
          submitLabel: 'Próximo documento', cancelLabel: null, onSubmit: next });
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
    // Filtros lembrados neste navegador; a busca de texto começa sempre vazia.
    let saved = {};
    try { saved = JSON.parse(store.get('est.prod.filters') || '{}'); } catch { /* ignora */ }
    const f = { q: '', brand: saved.brand || '', group: saved.group || '', inStock: Boolean(saved.inStock) };
    let items = [];
    let hasMore = false;
    const persist = () => store.set('est.prod.filters', JSON.stringify({ brand: f.brand, group: f.group, inStock: f.inStock }));

    main().innerHTML = html`
      ${pageHead('Produtos', 'Catálogo sincronizado do ERP', '', 'Cadastros')}
      <section class="card">
        <div class="toolbar">
          <label class="search">${raw(ICON.search)}<input class="input" id="q" placeholder="Buscar por descrição, código ou EAN"></label>
          <select class="input" id="brand"><option value="">Todas as marcas</option></select>
          <select class="input" id="group"><option value="">Todos os grupos</option></select>
          <button class="toggle tone-ok ${f.inStock ? 'on' : ''}" id="instock" type="button" aria-pressed="${f.inStock}">Somente com estoque</button>
          <button class="btn sm ghost" id="clear" type="button" style="margin-left:auto">Limpar filtros</button>
        </div>
        <div class="toolbar sub-bar muted" id="summary"></div>
        <div id="list"></div>
      </section>`.s;

    const fillFacets = async () => {
      const r = await api('GET', `/v1/products/facets${f.inStock ? '?inStock=1' : ''}`);
      const opts = (list, current, all) => [html`<option value="">${all}</option>`,
        ...list.map((x) => html`<option value="${x.name}" ${x.name === current ? 'selected' : ''}>${x.name} (${x.n})</option>`)];
      // Filtro salvo que deixou de existir (ex.: marca sem estoque) é descartado.
      if (f.brand && !r.brands.some((b) => b.name === f.brand)) f.brand = '';
      if (f.group && !r.groups.some((g) => g.name === f.group)) f.group = '';
      $('#brand').innerHTML = html`${opts(r.brands, f.brand, 'Todas as marcas')}`.s;
      $('#group').innerHTML = html`${opts(r.groups, f.group, 'Todos os grupos')}`.s;
      $('#summary').textContent = `${r.total.toLocaleString('pt-BR')} produtos no catálogo · ${r.com_estoque.toLocaleString('pt-BR')} com estoque`;
    };

    const load = async (append = false) => {
      const params = new URLSearchParams({ limit: '100', offset: String(append ? items.length : 0) });
      if (f.q) params.set('q', f.q);
      if (f.brand) params.set('brand', f.brand);
      if (f.group) params.set('group', f.group);
      if (f.inStock) params.set('inStock', '1');
      const r = await api('GET', `/v1/products?${params}`);
      items = append ? items.concat(r.items) : r.items;
      hasMore = r.hasMore;
      draw();
    };

    const stockCell = (s) => {
      const n = Number(s);
      return n > 0 ? html`<strong class="good-t">${fmtQty(s)}</strong>`
        : n < 0 ? html`<strong class="bad-t" title="Saldo negativo no ERP">${fmtQty(s)}</strong>`
          : html`<span class="muted">0</span>`;
    };

    const draw = () => {
      const active = [f.q && `"${f.q}"`, f.brand, f.group, f.inStock && 'com estoque'].filter(Boolean);
      $('#list').innerHTML = items.length ? html`<div class="table-wrap"><table>
        <thead><tr><th>Código</th><th>Descrição</th><th>Un</th><th>Marca</th><th>Grupo</th><th>Códigos de barras</th><th class="num">Saldo</th></tr></thead>
        <tbody>${items.map((p) => html`<tr>
          <td class="mono">${p.erpId}</td><td><strong style="font-weight:600">${p.description}</strong>${!(p.barcodes || []).length ? html` <span class="crit lv-alerta" title="Sem código de barras: a conferência depende de digitar o código">${raw(ICON.warn)}</span>` : ''}</td><td>${p.unit || ''}</td>
          <td>${p.brand ? html`<a href="#" data-brand="${p.brand}">${p.brand}</a>` : ''}</td>
          <td>${p.group ? html`<a href="#" data-group="${p.group}">${p.group}</a>` : ''}</td>
          <td class="mono muted">${(p.barcodes || []).join(', ')}</td><td class="num">${stockCell(p.stock)}</td></tr>`)}</tbody></table></div>
        <div class="toolbar sub-bar muted foot">
          <span>${items.length} produto(s)${hasMore ? ' — há mais' : ''}${active.length ? ` · filtro: ${active.join(' · ')}` : ''}</span>
          ${hasMore ? html`<button class="btn sm" id="more">Carregar mais</button>` : ''}</div>`.s
        : html`<div class="empty">Nenhum produto encontrado${active.length ? ` para ${active.join(' · ')}` : ''}.</div>`.s;
      $('#more')?.addEventListener('click', () => load(true).catch((e) => toast(e.message, true)));
      // Clicar numa marca/grupo da tabela aplica o filtro.
      $$('[data-brand]', $('#list')).forEach((a) => a.addEventListener('click', (e) => { e.preventDefault(); f.brand = a.dataset.brand; $('#brand').value = f.brand; persist(); load().catch(() => {}); }));
      $$('[data-group]', $('#list')).forEach((a) => a.addEventListener('click', (e) => { e.preventDefault(); f.group = a.dataset.group; $('#group').value = f.group; persist(); load().catch(() => {}); }));
    };

    const reload = () => load().catch((er) => toast(er.message, true));
    $('#q').addEventListener('input', debounce((e) => { f.q = e.target.value.trim(); reload(); }, 300));
    $('#brand').addEventListener('change', (e) => { f.brand = e.target.value; persist(); reload(); });
    $('#group').addEventListener('change', (e) => { f.group = e.target.value; persist(); reload(); });
    $('#instock').addEventListener('click', async (e) => {
      f.inStock = !f.inStock;
      e.currentTarget.classList.toggle('on', f.inStock);
      e.currentTarget.setAttribute('aria-pressed', String(f.inStock));
      persist();
      await fillFacets().catch(() => {});
      reload();
    });
    $('#clear').addEventListener('click', async () => {
      Object.assign(f, { q: '', brand: '', group: '', inStock: false });
      $('#q').value = '';
      $('#instock').classList.remove('on');
      persist();
      await fillFacets().catch(() => {});
      reload();
    });

    await fillFacets();
    await load();
    $('#q').focus();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Usuários
  // ───────────────────────────────────────────────────────────────────────────
  async function viewUsers() {
    const load = async () => {
      const r = await api('GET', '/v1/users');
      main().innerHTML = html`
        ${pageHead('Usuários', 'Operadores entram no app com usuário + PIN; supervisores no painel com senha', html`<button class="btn primary" id="new">Novo usuário</button>`, 'Cadastros')}
        <section class="card"><div class="table-wrap"><table>
          <thead><tr><th>Nome</th><th>Usuário</th><th>Perfil</th><th>Acesso</th><th>Último acesso</th><th></th></tr></thead>
          <tbody>${r.items.map((u) => html`<tr style="${u.active ? '' : 'opacity:.5'}">
            <td><div class="user-cell"><span class="avatar sm">${(u.name || '?').charAt(0).toUpperCase()}</span><strong>${u.name}</strong></div></td><td class="mono">${u.login}</td><td>${ROLE_LABEL[u.role]}</td>
            <td>${u.has_pin ? badge('OK', 'App') : ''} ${u.has_password ? badge('EM_CONFERENCIA', 'Painel') : ''} ${u.active ? '' : badge('CANCELADO', 'Inativo')}</td>
            <td>${ago(u.last_login_at)}</td>
            <td class="num">${isAdmin() || u.role === 'operador' ? html`<button class="btn sm" data-edit="${u.id}">Editar</button>` : ''}</td></tr>`)}</tbody>
        </table></div></section>`.s;
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
        <div class="field"><label>Perfil</label><select class="input" name="role">${roleOptions(u?.role || 'operador')}</select>
          <div class="help">Operador: confere às cegas. Supervisor: importa XML, aprova divergências, vê esperado × contado. Administrador: tudo + configurações.</div></div>
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
    'erp.invoiced': 'ERP faturou o pedido', 'erp.invoiced_before_conference': 'ERP faturou antes da conferência',
    'entry.imported': 'Importou XML de entrada', 'entry.item_linked': 'Vinculou item da nota', 'entry.deleted': 'Excluiu importação',
    'user.created': 'Criou usuário', 'user.updated': 'Alterou usuário', 'settings.updated': 'Alterou configurações',
  };
  const auditTable = (items) => (items.length ? html`<div class="table-wrap"><table>
    <thead><tr><th>Quando</th><th>Usuário</th><th>Ação</th><th>Documento</th><th>Detalhes</th></tr></thead>
    <tbody>${items.map((a) => html`<tr><td>${fmtDateTime(a.at)}</td><td>${a.user_name || 'Sistema/ERP'}</td><td>${AUDIT_LABEL[a.action] || a.action}</td>
      <td>${a.document_id ? html`<a href="#/documentos/${a.document_id}">${a.document_number || 'abrir'}</a>` : ''}</td>
      <td class="muted mono details">${Object.keys(a.details || {}).length ? JSON.stringify(a.details) : ''}</td></tr>`)}</tbody></table></div>`
    : html`<div class="empty">Sem registros.</div>`);

  async function viewAudit() {
    let items = [];
    const load = async (more) => {
      const before = more && items.length ? `&before=${items[items.length - 1].id}` : '';
      const r = await api('GET', `/v1/audit?limit=100${before}`);
      items = more ? items.concat(r.items) : r.items;
      $('#list').innerHTML = auditTable(items).s + (r.items.length === 100 ? '<div class="more"><button class="btn" id="more">Carregar mais</button></div>' : '');
      $('#more')?.addEventListener('click', () => load(true));
    };
    main().innerHTML = html`${pageHead('Auditoria', 'Tudo que foi feito, por quem e quando', '', 'Controle')}<section class="card" id="list"></section>`.s;
    await load(false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Configurações
  // ───────────────────────────────────────────────────────────────────────────
  async function viewSettings() {
    const s = await api('GET', '/v1/settings');
    const ro = !isAdmin();
    const dis = ro ? 'disabled' : '';
    main().innerHTML = html`
      ${pageHead('Configurações', ro ? 'Somente administradores podem alterar' : 'Regras da conferência desta empresa', '', 'Controle')}
      <form id="f" class="settings">
        <section class="card card-pad">
          <h2>Conferência cega</h2>
          <div class="field"><label>Recontagens antes de ir para o supervisor</label>
            <input class="input" name="maxRecounts" type="number" min="0" max="5" value="${s.maxRecounts}" ${dis}>
            <div class="help">0 = qualquer divergência vai direto para aprovação. Recomendado: 1.</div></div>
          <div class="field"><label>Reserva do documento (minutos)</label>
            <input class="input" name="lockMinutes" type="number" min="5" max="1440" value="${s.lockMinutes}" ${dis}>
            <div class="help">Renovada a cada leitura. Depois disso, outro operador pode assumir.</div></div>
          <label class="check"><input type="checkbox" name="allowManualQty" ${s.allowManualQty ? 'checked' : ''} ${dis}> Permitir digitar quantidade (em vez de bipar unidade por unidade)</label>
          <label class="check"><input type="checkbox" name="showItemList" ${s.showItemList ? 'checked' : ''} ${dis}> Mostrar ao operador a lista de produtos do documento (nunca as quantidades)</label>
          <label class="check"><input type="checkbox" name="requireJustification" ${s.requireJustification ? 'checked' : ''} ${dis}> Exigir justificativa para aprovar com divergência</label>
        </section>
        <section class="card card-pad">
          <h2>${raw(ICON.inbox)} Recebimento (entradas)</h2>
          <div class="field"><label>CNPJ da empresa</label>
            <input class="input mono" name="companyCnpj" value="${fmtCnpj(s.companyCnpj) === '—' ? '' : fmtCnpj(s.companyCnpj)}" placeholder="00.000.000/0000-00" ${dis}>
            <div class="help">Critica nota destinada a outro CNPJ e separa o DANFE do fornecedor do DANFE próprio no leitor.</div></div>
          <div class="field"><label>Alerta de validade curta (dias)</label>
            <input class="input" name="expiryAlertDays" type="number" min="0" max="730" value="${s.expiryAlertDays}" ${dis}>
            <div class="help">Lote da nota que vence em menos que isso gera crítica. Lote vencido é sempre crítica grave.</div></div>
          <div class="field"><label>Nota antiga (dias desde a emissão)</label>
            <input class="input" name="entryOldDays" type="number" min="1" max="365" value="${s.entryOldDays}" ${dis}>
            <div class="help">Ajuda a pegar nota já recebida sendo importada de novo.</div></div>
        </section>
        <section class="card card-pad">
          <h2>${raw(ICON.truck)} Fila e SLA</h2>
          <div class="field"><label>Meta de atendimento (horas)</label>
            <input class="input" name="outboundSlaHours" type="number" min="1" max="720" value="${s.outboundSlaHours}" ${dis}>
            <div class="help">Documento aguardando há mais tempo que isso aparece em Críticas.</div></div>
          <div class="field"><label>Dias exibidos na fila</label>
            <input class="input" name="queueDays" type="number" min="1" max="90" value="${s.queueDays}" ${dis}>
            <div class="help">Pendentes aparecem sempre; isso limita só os já concluídos no app.</div></div>
        </section>
        ${ro ? '' : html`<div class="save-bar"><button class="btn primary lg">Salvar configurações</button></div>`}
      </form>`.s;
    if (ro) return;
    $('#f').addEventListener('submit', async (e) => {
      e.preventDefault();
      const f = e.target.elements;
      try {
        state.settings = await api('PATCH', '/v1/settings', {
          maxRecounts: Number(f.maxRecounts.value), lockMinutes: Number(f.lockMinutes.value), queueDays: Number(f.queueDays.value),
          allowManualQty: f.allowManualQty.checked, showItemList: f.showItemList.checked, requireJustification: f.requireJustification.checked,
          companyCnpj: f.companyCnpj.value, outboundSlaHours: Number(f.outboundSlaHours.value),
          expiryAlertDays: Number(f.expiryAlertDays.value), entryOldDays: Number(f.entryOldDays.value),
        });
        toast('Configurações salvas');
      } catch (err) { toast(err.data?.fields?.[0]?.message || err.message, true); }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Leitor de código de barras (sem fio Bluetooth/2.4 GHz ou USB)
  //
  // Esses leitores funcionam como TECLADO (modo HID): "digitam" o código muito
  // rápido e mandam Enter. Não precisa de app nem driver. Diferenciamos leitor de
  // pessoa pelo ritmo: leitor < 40 ms entre teclas; pessoa > 80 ms.
  // ───────────────────────────────────────────────────────────────────────────
  const READER_MAX_GAP = 40;   // ms entre teclas para considerar leitor
  const READER_MIN_LEN = 4;
  const reader = { buf: '', last: 0, gaps: [] };
  let scannerModal = null;

  function markReaderDetected() {
    const dot = $('#reader-dot');
    if (dot && !dot.classList.contains('on')) {
      dot.classList.add('on');
      $('#scan-btn').title = 'Leitor de código de barras detectado — pronto (F2)';
    }
  }

  function isTypingTarget(t) {
    return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);
  }

  document.addEventListener('keydown', (e) => {
    if (!state.user || !shellBuilt) return;
    if (e.key === 'F2') { e.preventDefault(); openScanner(); return; }
    // A conferência, os modais e os campos têm tratamento próprio do leitor.
    if (scannerModal || document.querySelector('.modal-bg') || location.hash.startsWith('#/conferir/') || isTypingTarget(e.target)) return;

    const now = performance.now();
    if (e.key === 'Enter' || e.key === 'Tab') {
      const fast = reader.buf.length >= READER_MIN_LEN && reader.gaps.length > 0
        && reader.gaps.reduce((a, b) => a + b, 0) / reader.gaps.length < READER_MAX_GAP;
      const code = reader.buf;
      reader.buf = ''; reader.gaps = [];
      if (fast) { e.preventDefault(); markReaderDetected(); openScanner(code); }
      return;
    }
    if (e.key.length !== 1 || e.ctrlKey || e.metaKey || e.altKey) return;
    if (now - reader.last > 120) { reader.buf = ''; reader.gaps = []; }
    else if (reader.buf) reader.gaps.push(now - reader.last);
    reader.buf += e.key;
    reader.last = now;
  });

  /** Abre o modo leitor. Com `code`, já processa a leitura que chegou fora do modal. */
  function openScanner(code) {
    if (scannerModal) { if (code) handleScan(code); return; }
    let gaps = []; let lastKey = 0;
    scannerModal = modal({
      title: 'Leitura de código de barras',
      body: html`<div class="scanner-panel">
          <div class="scanner-visual" aria-hidden="true"></div>
          <div class="scanner-state" id="sc-state">Aponte o leitor para a etiqueta e dispare</div>
          <div class="scan-kinds"><span>${raw(ICON.arrowIn)} DANFE do fornecedor → <strong>entrada</strong></span><span>${raw(ICON.arrowOut)} Pedido, NF ou DANFE próprio → <strong>saída</strong></span></div>
          <input class="input scan-input mono" id="sc-input" autocomplete="off" placeholder="ou digite o código e tecle Enter" style="margin-top:16px;height:54px;font-size:20px">
          <div class="scanner-results" id="sc-results"></div>
          <div class="reader-tip"><strong>Leitor sem fio?</strong> Use no modo teclado (HID) com sufixo Enter — Bluetooth ou receptor USB.
            Não precisa de app nem driver: com o leitor pareado, bipe a etiqueta em qualquer tela do painel.</div>
        </div>`,
      submitLabel: null,
      cancelLabel: 'Fechar',
      onSubmit: async (form) => {
        const v = $('#sc-input', form).value.trim();
        $('#sc-input', form).value = '';
        const fast = gaps.length && gaps.reduce((a, b) => a + b, 0) / gaps.length < READER_MAX_GAP;
        if (fast) markReaderDetected();
        gaps = [];
        if (v) await handleScan(v);
        return false; // modal continua aberto para a próxima leitura
      },
    });
    const input = $('#sc-input', scannerModal.el);
    input.addEventListener('keydown', (e) => {
      const now = performance.now();
      if (e.key.length === 1) { if (lastKey && now - lastKey < 120) gaps.push(now - lastKey); lastKey = now; }
      if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); input.form.requestSubmit(); }
    });
    // Fechar o modal (botão, clique fora) libera o leitor global de novo.
    const observer = new MutationObserver(() => {
      if (!document.body.contains(scannerModal?.el)) { scannerModal = null; observer.disconnect(); }
    });
    observer.observe(document.body, { childList: true });
    setTimeout(() => input.focus(), 40);
    if (code) handleScan(code);
  }

  async function handleScan(code) {
    const stateEl = $('#sc-state');
    const results = $('#sc-results');
    if (!stateEl) return;
    stateEl.className = 'scanner-state';
    stateEl.textContent = `Buscando ${code}…`;
    results.innerHTML = '';
    try {
      const r = await api('GET', `/v1/documents/lookup?code=${encodeURIComponent(code)}`);
      const open = (d) => {
        scannerModal?.close(); scannerModal = null;
        const countable = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE'].includes(d.status) && !d.erpCancelled;
        // Entrada com crítica grave passa antes pelo detalhe (supervisor revisa).
        const grave = (d.alerts || []).some((a) => a.level === 'erro');
        location.hash = countable && !(isSup() && grave) ? `#/conferir/${d.id}` : `#/documentos/${d.id}`;
      };
      if (!r.items.length) {
        beep(false);
        stateEl.className = 'scanner-state err';
        if (r.parsed.kind === 'nfe') {
          if (!r.parsed.valid) { stateEl.textContent = 'Chave do DANFE com dígito verificador inválido — leia de novo.'; return; }
          const incoming = r.parsed.incoming !== false;
          stateEl.textContent = incoming
            ? `NF ${r.parsed.number} (CNPJ ${fmtCnpj(r.parsed.cnpj)}) ainda não foi importada`
            : `Nenhum pedido encontrado para a NF ${r.parsed.number}`;
          if (incoming) {
            results.innerHTML = isSup()
              ? html`<div class="scan-cta"><div>Para conferir esta entrada, importe o XML da nota. O sistema confere se o XML é do mesmo DANFE.</div>
                  <button type="button" class="btn primary" id="sc-import">${raw(ICON.upload)} Importar XML desta nota</button></div>`.s
              : html`<div class="scan-cta"><div>Peça ao supervisor para importar o XML desta nota.</div></div>`.s;
            $('#sc-import')?.addEventListener('click', () => {
              scannerModal?.close(); scannerModal = null;
              openImport({ expectedKey: r.parsed.key });
            });
          }
        } else {
          stateEl.textContent = `Nenhum documento com o código ${code}`;
        }
        return;
      }
      beep(true);
      if (r.items.length === 1) {
        stateEl.className = 'scanner-state ok';
        stateEl.textContent = `${docTitle(r.items[0])} — abrindo…`;
        setTimeout(() => open(r.items[0]), 250);
        return;
      }
      stateEl.className = 'scanner-state ok';
      stateEl.textContent = `${r.items.length} documentos encontrados — escolha:`;
      results.innerHTML = r.items.map((d) => html`<div class="row" data-pick="${d.id}">
          <div>${flowTag(d)} <strong>${docTitle(d)}</strong><div class="muted">${d.customerName || ''}</div></div>
          ${docStatus(d)}</div>`.s).join('');
      $$('[data-pick]', results).forEach((row) => row.addEventListener('click', () => open(r.items.find((d) => d.id === row.dataset.pick))));
    } catch (err) {
      beep(false);
      stateEl.className = 'scanner-state err';
      stateEl.textContent = err.message;
    } finally {
      $('#sc-input')?.focus();
    }
  }

  // ── Delegação: link "Ver documentos" do painel abre filtrado por erro de retorno ──
  let pendingWritebackFilter = null;
  document.addEventListener('click', (e) => {
    const a = e.target.closest('[data-wb]');
    if (a) { pendingWritebackFilter = a.dataset.wb; store.set('est.q.saida.tab', 'ok'); }
  });

  render();
})();
