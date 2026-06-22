import React, { useState, useEffect, useCallback } from 'react';
import {
    Users, Shield, Plus, Pencil, Trash2, KeyRound, Loader2,
    AlertTriangle, Check, X, Search, UserPlus, Eye, EyeOff,
    ShieldCheck, UserCog, Lock
} from 'lucide-react';
import { userService } from '../../services/userService';
import { partnerService } from '../../services/partnerService';

// ─── Design tokens (aligned with existing dashboard palette) ─────────────────
const C = {
    primary:       '#1B8FCD',
    primaryDark:   '#1578AD',
    primaryAlpha:  'rgba(27,143,205,0.12)',
    success:       '#22c55e',
    danger:        '#ef4444',
    warn:          '#f59e0b',
    surface:       'var(--surface)',
    bg:            'var(--bg)',
    border:        'var(--border)',
    textMain:      'var(--text-main)',
    textSub:       'var(--text-sub)',
    textMuted:     'var(--text-muted)',
    textHint:      'var(--text-hint)',
};

// ─── Keyframes injected once ─────────────────────────────────────────────────
const STYLES = `
@keyframes modalEnter {
  from { opacity: 0; transform: scale(0.95) translateY(8px); }
  to   { opacity: 1; transform: scale(1)    translateY(0);   }
}
@keyframes overlayIn {
  from { opacity: 0; }
  to   { opacity: 1; }
}
.um-row:hover { background: rgba(27,143,205,0.04) !important; }
.um-icon-btn:hover { background: rgba(27,143,205,0.1) !important; border-color: rgba(27,143,205,0.25) !important; color: ${C.primary} !important; }
.um-icon-btn-danger:hover { background: rgba(239,68,68,0.1) !important; border-color: rgba(239,68,68,0.25) !important; color: ${C.danger} !important; }
.um-input:focus { border-color: ${C.primary} !important; box-shadow: 0 0 0 3px rgba(27,143,205,0.12) !important; }
.um-perm-label:hover { background: rgba(27,143,205,0.06) !important; }
`;

if (!document.getElementById('um-styles')) {
    const el = document.createElement('style');
    el.id = 'um-styles';
    el.textContent = STYLES;
    document.head.appendChild(el);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
const AVATAR_COLORS = [
    ['#1B8FCD','#3BAAE3'], ['#0ea5e9','#06b6d4'], ['#10b981','#34d399'],
    ['#f59e0b','#fbbf24'], ['#ec4899','#f472b6'], ['#ef4444','#f87171'],
];
function getAvatarColors(str) {
    const idx = (str?.charCodeAt(0) || 0) % AVATAR_COLORS.length;
    return AVATAR_COLORS[idx];
}
function UserAvatar({ name, size = 36 }) {
    const init = (name || '?')[0].toUpperCase();
    const [c1, c2] = getAvatarColors(name);
    return (
        <div style={{
            width: size, height: size, borderRadius: '10px', flexShrink: 0,
            background: `linear-gradient(135deg, ${c1} 0%, ${c2} 100%)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: size * 0.38, fontWeight: 700, color: '#fff',
            boxShadow: `0 2px 8px ${c1}44`,
        }}>
            {init}
        </div>
    );
}

const Badge = ({ children, variant = 'default', dot = false }) => {
    const vars = {
        default: { bg: 'rgba(27,143,205,0.12)', color: '#3BAAE3', bd: 'rgba(27,143,205,0.2)' },
        success: { bg: 'rgba(34,197,94,0.1)',   color: '#22c55e', bd: 'rgba(34,197,94,0.2)' },
        danger:  { bg: 'rgba(239,68,68,0.1)',   color: '#ef4444', bd: 'rgba(239,68,68,0.2)' },
        warn:    { bg: 'rgba(245,158,11,0.12)', color: '#f59e0b', bd: 'rgba(245,158,11,0.2)' },
        super:   { bg: 'rgba(245,158,11,0.12)', color: '#f59e0b', bd: 'rgba(245,158,11,0.2)' },
    };
    const v = vars[variant] || vars.default;
    return (
        <span style={{
            padding: '2px 9px', borderRadius: '20px', fontSize: '0.7rem',
            fontWeight: 600, background: v.bg, color: v.color,
            border: `1px solid ${v.bd}`,
            display: 'inline-flex', alignItems: 'center', gap: '4px',
        }}>
            {dot && <span style={{ width: 6, height: 6, borderRadius: '50%', background: v.color }} />}
            {children}
        </span>
    );
};

// ─── Toast ───────────────────────────────────────────────────────────────────
const Toast = ({ msg, type, onDismiss }) => {
    if (!msg) return null;
    const isErr = type === 'error';
    return (
        <div style={{
            padding: '0.75rem 1rem', borderRadius: '12px', fontSize: '0.85rem',
            fontWeight: 500, marginBottom: '1.25rem',
            background: isErr ? 'rgba(239,68,68,0.08)' : 'rgba(34,197,94,0.08)',
            color: isErr ? '#ef4444' : '#22c55e',
            border: `1px solid ${isErr ? 'rgba(239,68,68,0.2)' : 'rgba(34,197,94,0.2)'}`,
            display: 'flex', alignItems: 'center', gap: '0.6rem',
            boxShadow: isErr ? '0 2px 12px rgba(239,68,68,0.08)' : '0 2px 12px rgba(34,197,94,0.08)',
        }}>
            {isErr ? <AlertTriangle size={16} /> : <Check size={16} />}
            <span style={{ flex: 1 }}>{msg}</span>
            <button onClick={onDismiss} style={{ background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', padding: '2px', lineHeight: 1 }}>
                <X size={14} />
            </button>
        </div>
    );
};

// ─── Modal ───────────────────────────────────────────────────────────────────
const Modal = ({ open, title, icon: Icon, children, onClose, width = '540px' }) => {
    if (!open) return null;
    return (
        <div onClick={onClose} style={{
            position: 'fixed', inset: 0,
            background: 'rgba(0,0,0,0.65)',
            backdropFilter: 'blur(8px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            zIndex: 1000, animation: 'overlayIn 0.18s ease',
            padding: '1rem',
        }}>
            <div onClick={e => e.stopPropagation()} style={{
                background: 'rgba(255,255,255,0.97)',
                backdropFilter: 'blur(24px)',
                WebkitBackdropFilter: 'blur(24px)',
                border: '1px solid rgba(255,255,255,0.6)',
                borderRadius: '20px', width, maxWidth: '95vw',
                maxHeight: '90vh', overflowY: 'auto',
                boxShadow: '0 24px 80px rgba(0,0,0,0.25), 0 0 0 1px rgba(255,255,255,0.8)',
                animation: 'modalEnter 0.22s cubic-bezier(0.34, 1.56, 0.64, 1)',
                color: '#1e293b',
            }}>
                {/* Header */}
                <div style={{
                    padding: '1.25rem 1.5rem 1rem',
                    borderBottom: '1px solid rgba(0,0,0,0.08)',
                    display: 'flex', alignItems: 'center', gap: '0.75rem',
                }}>
                    {Icon && (
                        <div style={{
                            width: 36, height: 36, borderRadius: '10px',
                            background: `linear-gradient(135deg, ${C.primary} 0%, #3BAAE3 100%)`,
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            boxShadow: `0 4px 12px ${C.primary}44`, flexShrink: 0,
                        }}>
                            <Icon size={18} color="#fff" />
                        </div>
                    )}
                    <h3 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 700, color: '#1e293b', flex: 1 }}>
                        {title}
                    </h3>
                    <button onClick={onClose} style={{
                        width: 32, height: 32, background: 'rgba(0,0,0,0.05)',
                        border: '1px solid rgba(0,0,0,0.1)', borderRadius: '8px',
                        cursor: 'pointer', color: '#64748b',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        transition: 'all 0.15s',
                    }}>
                        <X size={16} />
                    </button>
                </div>
                <div style={{ padding: '1.5rem' }}>
                    {children}
                </div>
            </div>
        </div>
    );
};

// ─── Input / Label ────────────────────────────────────────────────────────────
const inputStyle = {
    width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
    background: 'rgba(241,245,249,0.8)', border: '1px solid rgba(0,0,0,0.1)',
    color: '#1e293b', fontSize: '0.875rem',
    outline: 'none', transition: 'border-color 0.2s, box-shadow 0.2s',
    boxSizing: 'border-box',
};
const labelStyle = {
    display: 'block', fontSize: '0.78rem', fontWeight: 600,
    color: '#475569', marginBottom: '0.4rem', letterSpacing: '0.01em',
};
const FormField = ({ label, children, hint }) => (
    <div style={{ marginBottom: '1rem' }}>
        <label style={labelStyle}>{label}</label>
        {children}
        {hint && <p style={{ margin: '0.3rem 0 0', fontSize: '0.72rem', color: C.textHint, lineHeight: 1.4 }}>{hint}</p>}
    </div>
);

const IconBtn = ({ children, title, onClick, danger, size = 32 }) => (
    <button
        title={title} onClick={onClick}
        className={danger ? 'um-icon-btn-danger' : 'um-icon-btn'}
        style={{
            width: size, height: size, borderRadius: '8px',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: 'transparent', border: '1px solid transparent',
            color: danger ? C.danger : C.textMuted,
            cursor: 'pointer', transition: 'all 0.15s',
        }}
    >
        {children}
    </button>
);

// ─── Main Page ────────────────────────────────────────────────────────────────
const TABS = [
    { key: 'users',  label: 'Usuários',            icon: Users },
    { key: 'groups', label: 'Grupos de Permissão', icon: Shield },
];

export default function UserManagement() {
    const [tab, setTab]               = useState('users');
    const [users, setUsers]           = useState([]);
    const [groups, setGroups]         = useState([]);
    const [permissions, setPerms]     = useState([]);
    const [partners, setPartners]     = useState([]);
    const [loading, setLoading]       = useState(true);
    const [toast, setToast]           = useState({ msg: '', type: '' });

    const showToast = (msg, type = 'success') => {
        setToast({ msg, type });
        if (type === 'success') setTimeout(() => setToast({ msg: '', type: '' }), 4000);
    };

    const fetchAll = useCallback(async () => {
        setLoading(true);
        try {
            const [u, g, p, prt] = await Promise.all([
                userService.listUsers(),
                userService.listGroups(),
                userService.getAvailablePermissions(),
                partnerService.listPartners()
            ]);
            setUsers(u); setGroups(g); setPerms(p); setPartners(prt);
        } catch { showToast('Erro ao carregar dados.', 'error'); }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchAll(); }, [fetchAll]);

    return (
        <div className="animate-fade-in" style={{ maxWidth: '1100px' }}>
            {/* ── Page Header ───────────────────────────── */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.75rem', flexWrap: 'wrap', gap: '1rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                    <div style={{
                        width: 48, height: 48, borderRadius: '14px',
                        background: 'var(--gradient-primary)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        boxShadow: '0 0 24px rgba(27,143,205,0.30)',
                    }}>
                        <UserCog size={24} color="#fff" />
                    </div>
                    <div>
                        <h1 style={{ fontSize: '1.45rem', fontWeight: 800, color: C.textMain, margin: 0, letterSpacing: '-0.02em' }}>
                            Usuários & Permissões
                        </h1>
                        <p style={{ margin: 0, color: C.textMuted, fontSize: '0.82rem', marginTop: '0.1rem' }}>
                            Gerencie administradores e controle de acesso ao sistema
                        </p>
                    </div>
                </div>

                {/* Stats chips */}
                <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
                    <div style={{
                        background: C.primaryAlpha, border: '1px solid rgba(27,143,205,0.15)',
                        borderRadius: '12px', padding: '0.5rem 1rem',
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                    }}>
                        <Users size={15} style={{ color: C.primary }} />
                        <span style={{ fontSize: '0.82rem', fontWeight: 700, color: C.primary }}>{users.length} usuários</span>
                    </div>
                    <div style={{
                        background: 'rgba(34,197,94,0.08)', border: '1px solid rgba(34,197,94,0.2)',
                        borderRadius: '12px', padding: '0.5rem 1rem',
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                    }}>
                        <Shield size={15} style={{ color: C.success }} />
                        <span style={{ fontSize: '0.82rem', fontWeight: 700, color: C.success }}>{groups.length} grupos</span>
                    </div>
                </div>
            </div>

            <Toast msg={toast.msg} type={toast.type} onDismiss={() => setToast({ msg: '', type: '' })} />

            {/* ── Tabs ──────────────────────────────────── */}
            <div style={{
                display: 'flex', gap: '4px', marginBottom: '1.5rem',
                background: 'var(--bg)', borderRadius: '14px', padding: '5px',
                border: '1px solid var(--border)',
            }}>
                {TABS.map(t => {
                    const active = tab === t.key;
                    return (
                        <button key={t.key} onClick={() => setTab(t.key)} style={{
                            flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                            gap: '0.5rem', padding: '0.65rem 1rem', borderRadius: '10px',
                            fontSize: '0.875rem', fontWeight: active ? 700 : 500,
                            background: active
                                ? 'linear-gradient(135deg, rgba(27,143,205,0.15) 0%, rgba(59,192,240,0.08) 100%)'
                                : 'transparent',
                            color: active ? C.textMain : C.textMuted,
                            border: active ? '1px solid rgba(27,143,205,0.20)' : '1px solid transparent',
                            cursor: 'pointer', transition: 'all 0.2s',
                            boxShadow: active ? '0 2px 8px rgba(27,143,205,0.12)' : 'none',
                        }}>
                            <t.icon size={16} style={{ color: active ? C.primary : 'inherit' }} />
                            {t.label}
                            {active && tab === 'users' && users.length > 0 && (
                                <span style={{
                                    background: C.primary, color: '#fff',
                                    borderRadius: '20px', padding: '1px 7px',
                                    fontSize: '0.68rem', fontWeight: 700,
                                }}>{users.length}</span>
                            )}
                        </button>
                    );
                })}
            </div>

            {/* ── Content ───────────────────────────────── */}
            {loading ? (
                <div style={{ textAlign: 'center', padding: '5rem 4rem', color: C.textMuted }}>
                    <Loader2 size={32} className="animate-spin" style={{ color: C.primary }} />
                    <p style={{ marginTop: '1rem', fontSize: '0.875rem' }}>Carregando dados…</p>
                </div>
            ) : tab === 'users' ? (
                <UsersTab users={users} groups={groups} partners={partners} onRefresh={fetchAll} showToast={showToast} />
            ) : (
                <GroupsTab groups={groups} permissions={permissions} onRefresh={fetchAll} showToast={showToast} />
            )}
        </div>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Usuários
// ─────────────────────────────────────────────────────────────────────────────
function UsersTab({ users, groups, partners, onRefresh, showToast }) {
    const [showModal, setShowModal] = useState(false);
    const [editing,   setEditing]   = useState(null);
    const [pwdModal,  setPwdModal]  = useState(null);
    const [search,    setSearch]    = useState('');

    const filtered = users.filter(u =>
        u.name?.toLowerCase().includes(search.toLowerCase()) ||
        u.email?.toLowerCase().includes(search.toLowerCase())
    );

    const getPartnerInfo = (email) => {
        const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
        const link = links[email.toLowerCase()];
        if (link && link.isPartner) {
            const partner = partners.find(p => p.id === link.partnerId);
            return partner ? partner.name : 'Parceiro Associado';
        }
        return null;
    };

    return (
        <>
            {/* ── Toolbar ── */}
            <div style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                gap: '1rem', marginBottom: '1rem', flexWrap: 'wrap',
            }}>
                <div style={{ position: 'relative', flex: '1 1 260px', maxWidth: '380px' }}>
                    <Search size={15} color={C.textHint} style={{
                        position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '14px',
                    }} />
                    <input
                        type="text" placeholder="Buscar por nome ou e-mail…"
                        value={search} onChange={e => setSearch(e.target.value)}
                        className="um-input"
                        style={{ ...inputStyle, paddingLeft: '40px' }}
                    />
                </div>

                <button className="btn btn-primary" onClick={() => { setEditing(null); setShowModal(true); }}
                    style={{
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                        padding: '0.65rem 1.25rem', borderRadius: '12px',
                        background: `linear-gradient(135deg, ${C.primary} 0%, #3BAAE3 100%)`,
                        color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                        cursor: 'pointer', boxShadow: `0 4px 16px ${C.primary}44`,
                        transition: 'all 0.2s',
                    }}>
                    <UserPlus size={17} /> Novo Usuário
                </button>
            </div>

            {/* ── Table ── */}
            <div style={{
                background: C.surface, border: '1px solid var(--border)',
                borderRadius: '16px', overflow: 'hidden',
            }}>
                {/* Header */}
                <div style={{
                    display: 'grid',
                    gridTemplateColumns: '200px 1fr 1fr 90px 110px',
                    padding: '0.8rem 1.5rem', fontSize: '0.68rem', fontWeight: 700,
                    textTransform: 'uppercase', letterSpacing: '0.07em',
                    color: C.textHint, borderBottom: '1px solid var(--border)',
                    background: 'rgba(255,255,255,0.01)',
                }}>
                    <span>Usuário</span><span>E-mail</span><span>Grupo</span>
                    <span>Status</span><span style={{ textAlign: 'right' }}>Ações</span>
                </div>

                {filtered.length === 0 ? (
                    <EmptyState icon={Users} text="Nenhum usuário encontrado." action={
                        <button className="btn btn-primary" onClick={() => setShowModal(true)}
                            style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', padding: '0.5rem 1rem', marginTop: '0.75rem', border: 'none', borderRadius: '10px', background: C.primary, color: '#fff', cursor: 'pointer' }}>
                            <UserPlus size={15} /> Criar primeiro usuário
                        </button>
                    } />
                ) : filtered.map((u, i) => (
                    <div key={u.id} className="um-row" style={{
                        display: 'grid',
                        gridTemplateColumns: '200px 1fr 1fr 90px 110px',
                        padding: '0.85rem 1.5rem', alignItems: 'center',
                        borderBottom: i < filtered.length - 1 ? '1px solid var(--border)' : 'none',
                        transition: 'background 0.15s',
                    }}>
                        {/* Avatar + Nome */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.65rem' }}>
                            <UserAvatar name={u.name || u.email} size={34} />
                            <div>
                                <div style={{ fontWeight: 600, fontSize: '0.875rem', color: C.textMain, lineHeight: 1.2 }}>
                                    {u.name || <em style={{ color: C.textHint }}>Sem nome</em>}
                                </div>
                                {u.role === 'SuperAdmin' && (
                                    <div style={{ marginTop: '2px' }}>
                                        <Badge variant="super">★ Super Admin</Badge>
                                    </div>
                                )}
                                {getPartnerInfo(u.email) && (
                                    <div style={{ marginTop: '2px' }}>
                                        <Badge variant="default">🤝 {getPartnerInfo(u.email)}</Badge>
                                    </div>
                                )}
                            </div>
                        </div>

                        <span style={{ fontSize: '0.85rem', color: C.textSub, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', paddingRight: '1rem' }}>
                            {u.email}
                        </span>

                        <div>
                            {u.permissionGroupName ? (
                                <span style={{ display: 'inline-flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.82rem', color: C.textSub }}>
                                    <Shield size={12} style={{ color: C.primary, flexShrink: 0 }} />
                                    {u.permissionGroupName}
                                </span>
                            ) : (
                                <span style={{ fontSize: '0.82rem', color: C.textHint, fontStyle: 'italic' }}>Sem grupo</span>
                            )}
                        </div>

                        <span>
                            <Badge variant={u.isActive ? 'success' : 'danger'} dot>
                                {u.isActive ? 'Ativo' : 'Inativo'}
                            </Badge>
                        </span>

                        <span style={{ display: 'flex', gap: '0.25rem', justifyContent: 'flex-end' }}>
                            <IconBtn title="Editar usuário" onClick={() => { setEditing(u); setShowModal(true); }}>
                                <Pencil size={14} />
                            </IconBtn>
                            <IconBtn title="Redefinir senha" onClick={() => setPwdModal(u)}>
                                <KeyRound size={14} />
                            </IconBtn>
                            {u.role !== 'SuperAdmin' && (
                                <IconBtn title="Desativar usuário" danger onClick={async () => {
                                    if (!confirm(`Desativar ${u.name || u.email}?`)) return;
                                    try {
                                        await userService.deleteUser(u.id);
                                        showToast('Usuário desativado.');
                                        onRefresh();
                                    } catch (e) {
                                        showToast(e.response?.data?.error || 'Erro ao desativar.', 'error');
                                    }
                                }}>
                                    <Trash2 size={14} />
                                </IconBtn>
                            )}
                        </span>
                    </div>
                ))}
            </div>

            <UserFormModal
                open={showModal} user={editing} groups={groups} partners={partners}
                onClose={() => setShowModal(false)}
                onSaved={() => { setShowModal(false); onRefresh(); }}
                showToast={showToast}
            />
            <ResetPasswordModal
                open={!!pwdModal} user={pwdModal}
                onClose={() => setPwdModal(null)}
                showToast={showToast}
            />
        </>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Grupos de Permissão
// ─────────────────────────────────────────────────────────────────────────────
function GroupsTab({ groups, permissions, onRefresh, showToast }) {
    const [showModal, setShowModal] = useState(false);
    const [editing,   setEditing]   = useState(null);

    return (
        <>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1rem', flexWrap: 'wrap', gap: '1rem' }}>
                <p style={{ margin: 0, fontSize: '0.85rem', color: C.textMuted }}>
                    Grupos definem quais funcionalidades cada usuário pode acessar.
                </p>
                <button onClick={() => { setEditing(null); setShowModal(true); }}
                    style={{
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                        padding: '0.65rem 1.25rem', borderRadius: '12px',
                        background: `linear-gradient(135deg, ${C.primary} 0%, #3BAAE3 100%)`,
                        color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                        cursor: 'pointer', boxShadow: `0 4px 16px ${C.primary}44`,
                    }}>
                    <Plus size={17} /> Novo Grupo
                </button>
            </div>

            <div style={{ display: 'grid', gap: '0.75rem' }}>
                {groups.length === 0 ? (
                    <EmptyState icon={Shield} text="Nenhum grupo de permissão cadastrado." action={
                        <button onClick={() => setShowModal(true)}
                            style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', padding: '0.5rem 1rem', marginTop: '0.75rem', border: 'none', borderRadius: '10px', background: C.primary, color: '#fff', cursor: 'pointer' }}>
                            <Plus size={15} /> Criar primeiro grupo
                        </button>
                    } />
                ) : groups.map(g => (
                    <div key={g.id} style={{
                        background: C.surface, border: '1px solid var(--border)',
                        borderRadius: '16px', padding: '1.25rem 1.5rem',
                        display: 'flex', alignItems: 'center', gap: '1.25rem',
                        transition: 'border-color 0.2s, box-shadow 0.2s',
                    }}
                    onMouseEnter={e => {
                        e.currentTarget.style.borderColor = 'rgba(27,143,205,0.3)';
                        e.currentTarget.style.boxShadow = '0 4px 20px rgba(27,143,205,0.08)';
                    }}
                    onMouseLeave={e => {
                        e.currentTarget.style.borderColor = 'var(--border)';
                        e.currentTarget.style.boxShadow = 'none';
                    }}>
                        {/* Icon */}
                        <div style={{
                            width: 44, height: 44, borderRadius: '12px', flexShrink: 0,
                            background: 'linear-gradient(135deg, rgba(27,143,205,0.12) 0%, rgba(59,192,240,0.08) 100%)',
                            border: '1px solid rgba(27,143,205,0.2)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                        }}>
                            <ShieldCheck size={20} style={{ color: C.primary }} />
                        </div>

                        <div style={{ flex: 1, minWidth: 0 }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', flexWrap: 'wrap', marginBottom: '0.3rem' }}>
                                <span style={{ fontWeight: 700, fontSize: '0.95rem', color: C.textMain }}>{g.name}</span>
                                <Badge>{g.permissions?.length || 0} permissões</Badge>
                                {(g.userCount || 0) > 0 && <Badge variant="success">{g.userCount} usuário(s)</Badge>}
                            </div>
                            {g.description && (
                                <p style={{ margin: 0, fontSize: '0.8rem', color: C.textMuted, lineHeight: 1.4 }}>{g.description}</p>
                            )}
                            {/* Permission preview pills */}
                            {g.permissions?.length > 0 && (
                                <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap', marginTop: '0.5rem' }}>
                                    {g.permissions.slice(0, 5).map(p => (
                                        <span key={p} style={{
                                            padding: '1px 8px', borderRadius: '6px',
                                            fontSize: '0.65rem', fontWeight: 600,
                                            background: 'rgba(27,143,205,0.08)',
                                            color: C.primary, border: '1px solid rgba(27,143,205,0.15)',
                                        }}>{p}</span>
                                    ))}
                                    {g.permissions.length > 5 && (
                                        <span style={{ padding: '1px 8px', borderRadius: '6px', fontSize: '0.65rem', color: C.textHint }}>
                                            +{g.permissions.length - 5} mais
                                        </span>
                                    )}
                                </div>
                            )}
                        </div>

                        <div style={{ display: 'flex', gap: '0.3rem', flexShrink: 0 }}>
                            <IconBtn title="Editar grupo" onClick={() => { setEditing(g); setShowModal(true); }}>
                                <Pencil size={14} />
                            </IconBtn>
                            <IconBtn title="Remover grupo" danger onClick={async () => {
                                if (!confirm(`Remover grupo "${g.name}"?`)) return;
                                try {
                                    await userService.deleteGroup(g.id);
                                    showToast('Grupo removido.');
                                    onRefresh();
                                } catch (e) {
                                    showToast(e.response?.data?.error || 'Erro ao remover.', 'error');
                                }
                            }}>
                                <Trash2 size={14} />
                            </IconBtn>
                        </div>
                    </div>
                ))}
            </div>

            <GroupFormModal
                open={showModal} group={editing} allPermissions={permissions}
                onClose={() => setShowModal(false)}
                onSaved={() => { setShowModal(false); onRefresh(); }}
                showToast={showToast}
            />
        </>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Modais
// ─────────────────────────────────────────────────────────────────────────────
function UserFormModal({ open, user, groups, partners, onClose, onSaved, showToast }) {
    const isEdit = !!user;
    const [form,   setForm]   = useState({ name: '', email: '', password: '', permissionGroupId: '', isActive: true, isPartner: false, partnerId: '' });
    const [saving, setSaving] = useState(false);
    const [showPw, setShowPw] = useState(false);

    useEffect(() => {
        setShowPw(false);
        const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
        if (user) {
            const link = links[user.email.toLowerCase()] || {};
            setForm({
                name: user.name || '',
                email: user.email || '',
                password: '',
                permissionGroupId: user.permissionGroupId || '',
                isActive: user.isActive ?? true,
                isPartner: !!link.isPartner,
                partnerId: link.partnerId || ''
            });
        } else {
            setForm({ name: '', email: '', password: '', permissionGroupId: '', isActive: true, isPartner: false, partnerId: '' });
        }
    }, [user, open]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        
        if (form.isPartner && !form.partnerId) {
            showToast('Por favor, selecione o parceiro comercial associado.', 'error');
            return;
        }

        setSaving(true);
        try {
            if (isEdit) {
                await userService.updateUser(user.id, { name: form.name, email: form.email, permissionGroupId: form.permissionGroupId || null, isActive: form.isActive });
                
                const oldEmail = user.email.toLowerCase();
                const newEmail = form.email.toLowerCase();
                const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
                if (oldEmail !== newEmail) {
                    delete links[oldEmail];
                }
                
                if (form.isPartner && form.partnerId) {
                    links[newEmail] = { isPartner: true, partnerId: form.partnerId };
                } else {
                    delete links[newEmail];
                }
                localStorage.setItem('coliseu_user_partner_links', JSON.stringify(links));
                
                showToast('Usuário atualizado com sucesso!');
            } else {
                await userService.createUser({ name: form.name, email: form.email, password: form.password, permissionGroupId: form.permissionGroupId || null });
                
                const newEmail = form.email.toLowerCase();
                const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
                if (form.isPartner && form.partnerId) {
                    links[newEmail] = { isPartner: true, partnerId: form.partnerId };
                } else {
                    delete links[newEmail];
                }
                localStorage.setItem('coliseu_user_partner_links', JSON.stringify(links));
                
                showToast('Usuário criado com sucesso!');
            }
            onSaved();
        } catch (e) {
            showToast(e.response?.data?.error || 'Erro ao salvar.', 'error');
        } finally { setSaving(false); }
    };

    const f = (k, v) => setForm(prev => ({ ...prev, [k]: v }));

    return (
        <Modal open={open} title={isEdit ? 'Editar Usuário' : 'Novo Usuário'} icon={isEdit ? UserCog : UserPlus} onClose={onClose}>
            <form onSubmit={handleSubmit}>
                {/* Avatar preview */}
                {!isEdit && form.name && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1.25rem', padding: '0.75rem 1rem', background: C.primaryAlpha, borderRadius: '12px', border: '1px solid rgba(27,143,205,0.15)' }}>
                        <UserAvatar name={form.name} size={40} />
                        <div>
                            <div style={{ fontWeight: 700, fontSize: '0.9rem', color: C.textMain }}>{form.name}</div>
                            <div style={{ fontSize: '0.78rem', color: C.textMuted }}>{form.email || 'email@empresa.com'}</div>
                        </div>
                    </div>
                )}

                {/* Seção: Identificação */}
                <div style={{ marginBottom: '0.5rem' }}>
                    <p style={{ margin: '0 0 0.75rem', fontSize: '0.72rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: C.textHint }}>
                        Identificação
                    </p>
                    <FormField label="Nome completo *">
                        <input className="um-input" style={inputStyle} value={form.name}
                            onChange={e => f('name', e.target.value)}
                            placeholder="Ex: João Silva" required />
                    </FormField>
                    <FormField label="E-mail de acesso *">
                        <input className="um-input" style={inputStyle} type="email" value={form.email}
                            onChange={e => f('email', e.target.value)}
                            placeholder="joao@empresa.com" required />
                    </FormField>
                </div>

                {/* Seção: Senha (apenas criação) */}
                {!isEdit && (
                    <>
                        <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '0.5rem 0 1rem' }} />
                        <p style={{ margin: '0 0 0.75rem', fontSize: '0.72rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: C.textHint }}>
                            Segurança
                        </p>
                        <FormField label="Senha inicial *" hint="Mínimo 8 caracteres · 1 maiúscula · 1 minúscula · 1 número">
                            <div style={{ position: 'relative' }}>
                                <Lock size={15} color={C.textHint} style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '12px' }} />
                                <input className="um-input" style={{ ...inputStyle, paddingLeft: '38px', paddingRight: '42px' }}
                                    type={showPw ? 'text' : 'password'} value={form.password}
                                    onChange={e => f('password', e.target.value)}
                                    placeholder="••••••••" required />
                                <button type="button" onClick={() => setShowPw(v => !v)} style={{
                                    position: 'absolute', top: '50%', transform: 'translateY(-50%)', right: '12px',
                                    background: 'none', border: 'none', cursor: 'pointer', color: C.textMuted,
                                    display: 'flex', alignItems: 'center',
                                }}>
                                    {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                                </button>
                            </div>
                        </FormField>
                    </>
                )}

                {/* Seção: Permissão */}
                <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '0.5rem 0 1rem' }} />
                <p style={{ margin: '0 0 0.75rem', fontSize: '0.72rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: C.textHint }}>
                    Controle de Acesso
                </p>
                <FormField label="Grupo de Permissão" hint="Define quais funcionalidades este usuário pode acessar.">
                    <select className="um-input" style={{ ...inputStyle, cursor: 'pointer' }} value={form.permissionGroupId}
                        onChange={e => f('permissionGroupId', e.target.value)}>
                        <option value="">— Sem grupo (acesso mínimo) —</option>
                        {groups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                    </select>
                </FormField>

                {/* TIPO PARCEIRO */}
                <div style={{
                    display: 'flex', flexDirection: 'column', gap: '0.75rem',
                    padding: '0.75rem 1rem', borderRadius: '12px',
                    background: 'rgba(27,143,205,0.04)',
                    border: '1px solid rgba(27,143,205,0.15)',
                    marginBottom: '1rem',
                }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        <input type="checkbox" id="isPartner" checked={form.isPartner}
                            onChange={e => f('isPartner', e.target.checked)}
                            style={{ width: 18, height: 18, accentColor: C.primary, cursor: 'pointer' }}
                        />
                        <label htmlFor="isPartner" style={{ fontSize: '0.875rem', color: '#475569', cursor: 'pointer', fontWeight: 600 }}>
                            Este usuário é um Parceiro Comercial
                        </label>
                    </div>
                    {form.isPartner && (
                        <div style={{ marginTop: '0.25rem', animation: 'scaleIn 0.18s ease' }}>
                            <label style={{ ...labelStyle, fontSize: '0.74rem', marginBottom: '0.25rem' }}>
                                Associar Parceiro Comercial *
                            </label>
                            <select className="um-input" style={{ ...inputStyle, cursor: 'pointer', background: '#fff' }} value={form.partnerId}
                                onChange={e => f('partnerId', e.target.value)} required={form.isPartner}>
                                <option value="">— Selecione o Parceiro —</option>
                                {partners.map(p => <option key={p.id} value={p.id}>{p.name} ({p.cnpj})</option>)}
                            </select>
                        </div>
                    )}
                </div>

                {isEdit && (
                    <div style={{
                        display: 'flex', alignItems: 'center', gap: '0.75rem',
                        padding: '0.75rem 1rem', borderRadius: '12px',
                        background: form.isActive ? 'rgba(34,197,94,0.06)' : 'rgba(239,68,68,0.06)',
                        border: `1px solid ${form.isActive ? 'rgba(34,197,94,0.15)' : 'rgba(239,68,68,0.15)'}`,
                        marginBottom: '1rem',
                    }}>
                        <input type="checkbox" id="isActive" checked={form.isActive}
                            onChange={e => f('isActive', e.target.checked)}
                            style={{ width: 18, height: 18, accentColor: C.primary, cursor: 'pointer' }}
                        />
                        <label htmlFor="isActive" style={{ fontSize: '0.875rem', color: C.textSub, cursor: 'pointer', fontWeight: 500 }}>
                            {form.isActive ? '✓ Usuário ativo — pode acessar o sistema' : '✗ Usuário inativo — acesso bloqueado'}
                        </label>
                    </div>
                )}

                {/* Actions */}
                <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '0.5rem' }}>
                    <button type="button" className="btn btn-outline" onClick={onClose}
                        style={{ padding: '0.65rem 1.25rem', borderRadius: '10px' }}>
                        Cancelar
                    </button>
                    <button type="submit" disabled={saving} style={{
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                        padding: '0.65rem 1.5rem', borderRadius: '10px',
                        background: `linear-gradient(135deg, ${C.primary} 0%, #3BAAE3 100%)`,
                        color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                        cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1,
                        boxShadow: `0 4px 14px ${C.primary}44`, transition: 'all 0.2s',
                    }}>
                        {saving ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                        {saving ? 'Salvando…' : isEdit ? 'Salvar alterações' : 'Criar usuário'}
                    </button>
                </div>
            </form>
        </Modal>
    );
}

function ResetPasswordModal({ open, user, onClose, showToast }) {
    const [password, setPassword] = useState('');
    const [showPw,   setShowPw]   = useState(false);
    const [saving,   setSaving]   = useState(false);

    useEffect(() => { setPassword(''); setShowPw(false); }, [open]);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            await userService.resetPassword(user.id, password);
            showToast('Senha redefinida com sucesso.');
            onClose();
        } catch (e) {
            showToast(e.response?.data?.error || 'Erro ao redefinir senha.', 'error');
        } finally { setSaving(false); }
    };

    return (
        <Modal open={open} title={`Redefinir Senha`} icon={KeyRound} onClose={onClose} width="440px">
            {user && (
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1.25rem', padding: '0.75rem 1rem', background: 'rgba(245,158,11,0.06)', borderRadius: '12px', border: '1px solid rgba(245,158,11,0.15)' }}>
                    <UserAvatar name={user.name || user.email} size={36} />
                    <div>
                        <div style={{ fontWeight: 700, fontSize: '0.875rem', color: C.textMain }}>{user.name || 'Usuário'}</div>
                        <div style={{ fontSize: '0.78rem', color: C.textMuted }}>{user.email}</div>
                    </div>
                </div>
            )}
            <form onSubmit={handleSubmit}>
                <FormField label="Nova senha *" hint="Mínimo 8 caracteres · 1 maiúscula · 1 minúscula · 1 número">
                    <div style={{ position: 'relative' }}>
                        <Lock size={15} color={C.textHint} style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '12px' }} />
                        <input className="um-input" style={{ ...inputStyle, paddingLeft: '38px', paddingRight: '42px' }}
                            type={showPw ? 'text' : 'password'} value={password}
                            onChange={e => setPassword(e.target.value)}
                            placeholder="Nova senha segura" required />
                        <button type="button" onClick={() => setShowPw(v => !v)} style={{
                            position: 'absolute', top: '50%', transform: 'translateY(-50%)', right: '12px',
                            background: 'none', border: 'none', cursor: 'pointer', color: C.textMuted,
                            display: 'flex', alignItems: 'center',
                        }}>
                            {showPw ? <EyeOff size={15} /> : <Eye size={15} />}
                        </button>
                    </div>
                </FormField>
                <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end' }}>
                    <button type="button" className="btn btn-outline" onClick={onClose}
                        style={{ padding: '0.65rem 1.25rem', borderRadius: '10px' }}>
                        Cancelar
                    </button>
                    <button type="submit" disabled={saving} style={{
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                        padding: '0.65rem 1.25rem', borderRadius: '10px',
                        background: `linear-gradient(135deg, #f59e0b 0%, #ef4444 100%)`,
                        color: '#fff', fontWeight: 700, border: 'none',
                        cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1,
                    }}>
                        {saving ? <Loader2 size={16} className="animate-spin" /> : <KeyRound size={16} />}
                        {saving ? 'Salvando…' : 'Redefinir senha'}
                    </button>
                </div>
            </form>
        </Modal>
    );
}

function GroupFormModal({ open, group, allPermissions, onClose, onSaved, showToast }) {
    const isEdit = !!group;
    const [form,   setForm]   = useState({ name: '', description: '', permissions: [] });
    const [saving, setSaving] = useState(false);

    useEffect(() => {
        if (group) setForm({ name: group.name || '', description: group.description || '', permissions: group.permissions || [] });
        else        setForm({ name: '', description: '', permissions: [] });
    }, [group, open]);

    const togglePerm  = (key) => setForm(f => ({
        ...f, permissions: f.permissions.includes(key) ? f.permissions.filter(k => k !== key) : [...f.permissions, key],
    }));
    const allKeys = allPermissions.map(p => p.key);
    const toggleAll   = () => setForm(f => ({ ...f, permissions: allKeys.every(k => f.permissions.includes(k)) ? [] : allKeys }));

    const byModule = allPermissions.reduce((acc, p) => {
        (acc[p.module] = acc[p.module] || []).push(p);
        return acc;
    }, {});

    const handleSubmit = async (e) => {
        e.preventDefault();
        setSaving(true);
        try {
            if (isEdit) { await userService.updateGroup(group.id, form); showToast('Grupo atualizado!'); }
            else        { await userService.createGroup(form);            showToast('Grupo criado!'); }
            onSaved();
        } catch (e) {
            showToast(e.response?.data?.error || 'Erro ao salvar.', 'error');
        } finally { setSaving(false); }
    };

    const selected = form.permissions.length;

    return (
        <Modal open={open} title={isEdit ? 'Editar Grupo' : 'Novo Grupo de Permissão'} icon={ShieldCheck} onClose={onClose} width="620px">
            <form onSubmit={handleSubmit}>
                <FormField label="Nome do grupo *">
                    <input className="um-input" style={inputStyle} value={form.name}
                        onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                        placeholder="Ex: Operador Básico" required />
                </FormField>
                <FormField label="Descrição (opcional)">
                    <input className="um-input" style={inputStyle} value={form.description}
                        onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
                        placeholder="Descreva o que este grupo pode fazer" />
                </FormField>

                <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '0.25rem 0 1rem' }} />

                {/* Permission header */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.75rem' }}>
                    <div>
                        <p style={{ margin: 0, fontSize: '0.72rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: C.textHint }}>
                            Permissões
                        </p>
                        <p style={{ margin: '0.15rem 0 0', fontSize: '0.8rem', color: C.textMuted }}>
                            <span style={{ color: C.primary, fontWeight: 700 }}>{selected}</span> de {allPermissions.length} selecionadas
                        </p>
                    </div>
                    <button type="button" onClick={toggleAll} style={{
                        padding: '0.4rem 0.9rem', borderRadius: '8px', border: `1px solid rgba(27,143,205,0.2)`,
                        background: C.primaryAlpha, color: C.primary, fontSize: '0.78rem', fontWeight: 600, cursor: 'pointer',
                    }}>
                        {allKeys.every(k => form.permissions.includes(k)) ? 'Desmarcar todos' : 'Selecionar todos'}
                    </button>
                </div>

                {/* Progress bar */}
                <div style={{ height: 4, borderRadius: 4, background: 'var(--border)', marginBottom: '1rem', overflow: 'hidden' }}>
                    <div style={{
                        height: '100%', borderRadius: 4, transition: 'width 0.3s ease',
                        width: `${(selected / (allPermissions.length || 1)) * 100}%`,
                        background: `linear-gradient(90deg, ${C.primary} 0%, #3BAAE3 100%)`,
                    }} />
                </div>

                {/* Permissions grid */}
                <div style={{
                    background: C.bg, border: '1px solid var(--border)',
                    borderRadius: '14px', padding: '1rem', maxHeight: '280px', overflowY: 'auto',
                }}>
                    {Object.entries(byModule).map(([module, perms]) => (
                        <div key={module} style={{ marginBottom: '1rem' }}>
                            <div style={{
                                fontSize: '0.68rem', fontWeight: 800, textTransform: 'uppercase',
                                letterSpacing: '0.08em', color: C.primary,
                                marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.4rem',
                            }}>
                                <Shield size={11} /> {module}
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.4rem' }}>
                                {perms.map(p => {
                                    const checked = form.permissions.includes(p.key);
                                    return (
                                        <label key={p.key} className="um-perm-label" style={{
                                            display: 'flex', alignItems: 'center', gap: '0.6rem',
                                            padding: '0.5rem 0.7rem', borderRadius: '10px',
                                            cursor: 'pointer', fontSize: '0.82rem',
                                            color: checked ? C.textMain : C.textMuted,
                                            background: checked ? 'rgba(27,143,205,0.1)' : 'transparent',
                                            border: `1px solid ${checked ? 'rgba(27,143,205,0.2)' : 'transparent'}`,
                                            transition: 'all 0.15s',
                                        }}>
                                            <input type="checkbox" checked={checked}
                                                onChange={() => togglePerm(p.key)}
                                                style={{ width: 15, height: 15, accentColor: C.primary, flexShrink: 0 }}
                                            />
                                            <span style={{ fontWeight: checked ? 600 : 400 }}>{p.label}</span>
                                        </label>
                                    );
                                })}
                            </div>
                        </div>
                    ))}
                </div>

                <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
                    <button type="button" className="btn btn-outline" onClick={onClose}
                        style={{ padding: '0.65rem 1.25rem', borderRadius: '10px' }}>
                        Cancelar
                    </button>
                    <button type="submit" disabled={saving} style={{
                        display: 'flex', alignItems: 'center', gap: '0.5rem',
                        padding: '0.65rem 1.5rem', borderRadius: '10px',
                        background: `linear-gradient(135deg, ${C.primary} 0%, #3BAAE3 100%)`,
                        color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                        cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1,
                        boxShadow: `0 4px 14px ${C.primary}44`,
                    }}>
                        {saving ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                        {saving ? 'Salvando…' : isEdit ? 'Salvar grupo' : 'Criar grupo'}
                    </button>
                </div>
            </form>
        </Modal>
    );
}

// ─── Empty State ──────────────────────────────────────────────────────────────
function EmptyState({ icon: Icon, text, action }) {
    return (
        <div style={{
            padding: '3.5rem 2rem', textAlign: 'center',
            background: C.surface, borderRadius: '16px',
            border: '1px dashed var(--border)',
        }}>
            <div style={{
                width: 52, height: 52, borderRadius: '16px', margin: '0 auto 1rem',
                background: C.primaryAlpha, border: '1px solid rgba(99,102,241,0.15)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
                <Icon size={24} style={{ color: C.primary }} />
            </div>
            <p style={{ margin: 0, color: C.textMuted, fontSize: '0.875rem', fontWeight: 500 }}>{text}</p>
            {action}
        </div>
    );
}
