import React, { useState, useEffect, useCallback } from 'react';
import { Outlet, useNavigate, useLocation } from 'react-router-dom';
import {
    Building2, Settings, ShieldCheck, LogOut, Search, Bell, ChevronRight,
    Activity, Server, BarChart2, TrendingUp, History, Webhook,
    LayoutDashboard, Menu, X, Zap, Users, ClipboardList, Handshake
} from 'lucide-react';
import '../../animations.css';

const NAV_GROUPS = [
    {
        label: 'Principal',
        items: [
            { label: 'Dashboard',  path: '/dashboard/home',        icon: LayoutDashboard,  permission: null },
            { label: 'Empresas',   path: '/dashboard/companies',   icon: Building2,         permission: 'companies.read' },
            { label: 'Parceiros',  path: '/dashboard/partners',    icon: Handshake,         permission: 'partners.read' },
            { label: 'Requisições', path: '/dashboard/requests',    icon: ClipboardList,     permission: 'requests.read' },
            { label: 'Auditoria',  path: '/dashboard/audit',       icon: Activity,          permission: 'audit.read' },
        ]
    },
    {
        label: 'Analytics',
        items: [
            { label: 'Sales API',       path: '/dashboard/sales-api',    icon: Server,      permission: 'reports.read' },
            { label: 'Relatório',       path: '/dashboard/sales-report', icon: BarChart2,   permission: 'reports.read' },
            { label: 'KPI Dashboard',   path: '/dashboard/kpi',          icon: TrendingUp,  permission: 'kpi.read' },
        ]
    },
    {
        label: 'Gestão',
        items: [
            { label: 'Usuários',      path: '/dashboard/users',       icon: Users,    permission: 'users.manage' },
            { label: 'Audit Trail',   path: '/dashboard/audit-trail', icon: History,  permission: 'audit.read' },
            { label: 'Webhooks',      path: '/dashboard/webhooks',    icon: Webhook,  permission: 'webhooks.manage' },
            { label: 'Configurações', path: '/dashboard/settings',    icon: Settings, permission: 'settings.read' },
        ]
    }
];

const PAGE_LABELS = {
    '/dashboard/home':        'Dashboard',
    '/dashboard/companies':   'Empresas',
    '/dashboard/partners':    'Parceiros',
    '/dashboard/requests':    'Requisições',
    '/dashboard/audit':       'Auditoria',
    '/dashboard/sales-api':   'Sales API',
    '/dashboard/sales-report':'Relatório',
    '/dashboard/kpi':         'KPI Dashboard',
    '/dashboard/users':       'Usuários & Permissões',
    '/dashboard/audit-trail': 'Audit Trail',
    '/dashboard/webhooks':    'Webhooks',
    '/dashboard/settings':    'Configurações',
};

export default function DashboardLayout() {
    const navigate = useNavigate();
    const location = useLocation();
    const [sidebarOpen, setSidebarOpen] = useState(true);
    const [isMobile, setIsMobile] = useState(false);
    const [user, setUser] = useState({ name: 'Super Admin', email: 'admin@coliseu.com.br', role: 'SuperAdmin', permissions: ['*'] });

    // ── Media query hook ──
    useEffect(() => {
        const mq = window.matchMedia('(max-width: 1024px)');
        const handler = (e) => {
            setIsMobile(e.matches);
            if (e.matches) setSidebarOpen(false);
            else setSidebarOpen(true);
        };
        handler(mq);
        mq.addEventListener('change', handler);
        return () => mq.removeEventListener('change', handler);
    }, []);

    useEffect(() => {
        try {
            const stored = localStorage.getItem('adminUser');
            if (stored) {
                const parsed = JSON.parse(stored);
                // Enriquecer com dados do parceiro logado
                const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
                const link = links[parsed.email.toLowerCase()];
                if (link && link.isPartner) {
                    parsed.isPartner = true;
                    parsed.partnerId = link.partnerId;
                }
                setUser(parsed);
            }
        } catch { /* ok */ }
    }, []);

    // Redirecionamento de segurança para parceiros comerciais
    useEffect(() => {
        if (user && user.isPartner && location.pathname !== '/dashboard/requests') {
            navigate('/dashboard/requests');
        }
    }, [user, location.pathname, navigate]);

    // Close sidebar on route change (mobile)
    useEffect(() => {
        if (isMobile) setSidebarOpen(false);
    }, [location.pathname, isMobile]);

    /** Verifica se o usuário pode ver um item do menu. */
    const canSee = (permission) => {
        if (!permission) return true;                           // sem restrição
        if (user.role === 'SuperAdmin') return true;           // SuperAdmin vê tudo
        const perms = user.permissions || [];
        return perms.includes('*') || perms.includes(permission);
    };

    const handleLogout = () => {
        localStorage.removeItem('adminToken');
        localStorage.removeItem('adminUser');
        navigate('/');
    };

    const currentLabel = user.isPartner ? 'Requisições' : (Object.entries(PAGE_LABELS).find(([path]) =>
        location.pathname.startsWith(path)
    )?.[1] || 'Painel');

    const initials = user.name
        .split(' ')
        .map(w => w[0])
        .slice(0, 2)
        .join('')
        .toUpperCase();

    const filteredNavGroups = NAV_GROUPS.map(group => {
        const items = group.items.filter(item => {
            if (user.isPartner) {
                return item.path === '/dashboard/requests';
            }
            return canSee(item.permission);
        });
        return { ...group, items };
    }).filter(group => group.items.length > 0);

    return (
        <div className="app-container">

            {/* ── Mobile Backdrop ── */}
            {isMobile && sidebarOpen && (
                <div
                    className="sidebar-overlay active"
                    onClick={() => setSidebarOpen(false)}
                    style={{
                        position: 'fixed', inset: 0,
                        background: 'rgba(0,0,0,0.45)',
                        zIndex: 25,
                        animation: 'overlayIn 0.18s ease',
                    }}
                />
            )}

            {/* ─────────── SIDEBAR DARK PREMIUM ─────────── */}
            <aside style={{
                width: sidebarOpen ? '258px' : '0px',
                minWidth: sidebarOpen ? '258px' : '0px',
                background: 'var(--sidebar-bg)',
                display: 'flex',
                flexDirection: 'column',
                borderRight: '1px solid var(--sidebar-border)',
                overflow: 'hidden',
                transition: 'min-width 0.28s cubic-bezier(0.4,0,0.2,1), width 0.28s cubic-bezier(0.4,0,0.2,1)',
                zIndex: isMobile ? 30 : 20,
                position: isMobile ? 'fixed' : 'relative',
                top: 0,
                left: 0,
                height: isMobile ? '100dvh' : 'auto',
                boxShadow: isMobile && sidebarOpen ? '4px 0 24px rgba(0,0,0,0.18)' : 'none',
            }}>

                {/* Subtle brand glow accent top-right */}
                <div style={{
                    position: 'absolute', top: 0, right: 0,
                    width: '120px', height: '120px',
                    background: 'radial-gradient(circle, rgba(27,143,205,0.10) 0%, transparent 70%)',
                    pointerEvents: 'none',
                }} />

                {/* Logo — imagem oficial Coliseu Sistemas */}
                <div style={{
                    padding: '1.375rem 1.375rem',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '0.75rem',
                    borderBottom: '1px solid var(--sidebar-border)',
                }}>
                    <img
                        src="/coliseu-logo.png"
                        alt="Coliseu Sistemas"
                        style={{ height: '38px', width: 'auto' }}
                    />
                </div>

                {/* Navigation */}
                <nav style={{ flex: 1, padding: '0.75rem 0', overflowY: 'auto' }}>
                    {filteredNavGroups.map((group) => (
                        <div key={group.label} style={{ marginBottom: '0.25rem' }}>
                            {/* Group label */}
                            <div style={{
                                padding: '0.625rem 1.25rem 0.25rem',
                                fontSize: '0.6rem',
                                fontWeight: 700,
                                textTransform: 'uppercase',
                                letterSpacing: '0.1em',
                                color: 'var(--text-hint)',
                            }}>
                                {group.label}
                            </div>

                            {group.items.map((item) => {
                                const isActive = location.pathname === item.path ||
                                    (item.path !== '/dashboard/home' && location.pathname.startsWith(item.path));
                                return (
                                    <div key={item.path} style={{ padding: '2px 0.625rem' }}>
                                        <button
                                            onClick={() => navigate(item.path)}
                                            style={{
                                                width: '100%',
                                                display: 'flex',
                                                alignItems: 'center',
                                                gap: '0.75rem',
                                                padding: '0.5625rem 0.875rem',
                                                borderRadius: 'var(--radius-md)',
                                                color: isActive ? 'var(--text-main)' : 'var(--sidebar-text)',
                                                background: isActive
                                                    ? 'linear-gradient(135deg, rgba(27,143,205,0.15) 0%, rgba(59,192,240,0.08) 100%)'
                                                    : 'transparent',
                                                border: isActive
                                                    ? '1px solid rgba(27,143,205,0.20)'
                                                    : '1px solid transparent',
                                                fontWeight: isActive ? 600 : 500,
                                                fontSize: '0.875rem',
                                                cursor: 'pointer',
                                                transition: 'all 0.18s ease',
                                                textAlign: 'left',
                                                boxShadow: isActive ? '0 0 16px rgba(27,143,205,0.12)' : 'none',
                                                position: 'relative',
                                            }}
                                            onMouseEnter={(e) => {
                                                if (!isActive) {
                                                    e.currentTarget.style.background = 'var(--sidebar-hover-bg)';
                                                    e.currentTarget.style.color = 'var(--sidebar-text-hover)';
                                                }
                                            }}
                                            onMouseLeave={(e) => {
                                                if (!isActive) {
                                                    e.currentTarget.style.background = 'transparent';
                                                    e.currentTarget.style.color = 'var(--sidebar-text)';
                                                }
                                            }}
                                        >
                                            {/* Active indicator bar */}
                                            {isActive && (
                                                <div style={{
                                                    position: 'absolute',
                                                    left: 0, top: '20%', bottom: '20%',
                                                    width: '3px',
                                                    background: 'var(--gradient-primary)',
                                                    borderRadius: '0 2px 2px 0',
                                                }} />
                                            )}
                                            <item.icon
                                                size={17}
                                                strokeWidth={isActive ? 2.5 : 2}
                                                style={{
                                                    color: isActive ? 'var(--primary-light)' : 'var(--text-hint)',
                                                    flexShrink: 0,
                                                    transition: 'color 0.18s',
                                                }}
                                            />
                                            <span style={{ flex: 1 }}>{item.label}</span>
                                            {isActive && (
                                                <div style={{
                                                    width: '6px', height: '6px', borderRadius: '50%',
                                                    background: 'var(--primary)',
                                                    boxShadow: '0 0 8px var(--primary-glow)',
                                                    flexShrink: 0,
                                                }} />
                                            )}
                                        </button>
                                    </div>
                                );
                            })}
                        </div>
                    ))}
                </nav>

                {/* User footer */}
                <div style={{ padding: '0.875rem', borderTop: '1px solid var(--sidebar-border)' }}>
                    <div style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.625rem',
                        padding: '0.625rem 0.75rem',
                        borderRadius: 'var(--radius-md)',
                        marginBottom: '0.625rem',
                        background: 'rgba(255,255,255,0.04)',
                        border: '1px solid var(--border)',
                    }}>
                        <div style={{
                            width: '34px', height: '34px', borderRadius: '50%', flexShrink: 0,
                            background: 'var(--gradient-primary)',
                            color: 'white', display: 'flex', alignItems: 'center', justifyContent: 'center',
                            fontWeight: 700, fontSize: '0.8125rem',
                            boxShadow: '0 0 12px rgba(27,143,205,0.25)',
                        }}>
                            {initials}
                        </div>
                        <div style={{ overflow: 'hidden', flex: 1 }}>
                            <div style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-main)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                {user.name}
                            </div>
                            <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                {user.email}
                            </div>
                        </div>
                    </div>

                    <button
                        onClick={handleLogout}
                        style={{
                            width: '100%',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            gap: '0.5rem',
                            padding: '0.5rem',
                            borderRadius: 'var(--radius-sm)',
                            color: 'var(--danger-text)',
                            background: 'var(--danger-bg)',
                            border: '1px solid var(--danger-border)',
                            cursor: 'pointer',
                            fontWeight: 600,
                            fontSize: '0.8125rem',
                            transition: 'all 0.18s',
                        }}
                        onMouseEnter={(e) => {
                            e.currentTarget.style.filter = 'brightness(1.15)';
                        }}
                        onMouseLeave={(e) => {
                            e.currentTarget.style.filter = 'none';
                        }}
                    >
                        <LogOut size={14} /> Sair do Sistema
                    </button>
                </div>
            </aside>

            {/* ─────────── MAIN CONTENT ─────────── */}
            <main className="main-content">

                {/* Topbar — glass dark */}
                <header style={{
                    height: '60px',
                    background: 'rgba(255, 255, 255, 0.82)',
                    backdropFilter: 'blur(20px)',
                    WebkitBackdropFilter: 'blur(20px)',
                    borderBottom: '1px solid var(--border)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '0 1.75rem',
                    position: 'sticky',
                    top: 0,
                    zIndex: 10,
                }}>
                    {/* Left: Toggle + Breadcrumb */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                        <button
                            onClick={() => setSidebarOpen(s => !s)}
                            style={{
                                width: '34px', height: '34px', borderRadius: '8px',
                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                color: 'var(--text-muted)', border: '1px solid var(--border)',
                                background: 'var(--glass-bg)',
                                transition: 'all 0.18s',
                                cursor: 'pointer',
                            }}
                        >
                            <Menu size={16} />
                        </button>

                        <nav style={{ display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                            <span style={{ fontSize: '0.8rem', color: 'var(--text-hint)' }}>Coliseu</span>
                            <ChevronRight size={13} color="var(--text-hint)" />
                            <span style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-main)' }}>{currentLabel}</span>
                        </nav>
                    </div>

                    {/* Right: Search + Bell */}
                    <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
                        {!user.isPartner && (
                            <div style={{ position: 'relative', display: isMobile ? 'none' : 'block' }}>
                                <Search size={14} color="var(--text-hint)" style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '12px', pointerEvents: 'none' }} />
                                <input
                                    type="text"
                                    placeholder="Buscar empresa..."
                                    className="input-field"
                                    style={{ paddingLeft: '34px', borderRadius: 'var(--radius-full)', width: '240px', height: '34px', fontSize: '0.8rem' }}
                                />
                            </div>
                        )}

                        <button style={{
                            position: 'relative', width: '34px', height: '34px', borderRadius: '50%',
                            background: 'var(--glass-bg)', border: '1px solid var(--border)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            color: 'var(--text-muted)', cursor: 'pointer',
                            transition: 'all var(--t-fast)',
                        }}>
                            <Bell size={15} />
                            <span style={{
                                position: 'absolute', top: '6px', right: '6px',
                                width: '7px', height: '7px',
                                background: 'var(--danger)', borderRadius: '50%',
                                border: '1.5px solid var(--bg-body)',
                            }} />
                        </button>
                    </div>
                </header>

                {/* Page Outlet */}
                <div style={{ flex: 1, padding: isMobile ? '1rem' : '1.75rem 2rem', width: '100%', maxWidth: '1500px', margin: '0 auto' }}>
                    <Outlet />
                </div>
            </main>
        </div>
    );
}
