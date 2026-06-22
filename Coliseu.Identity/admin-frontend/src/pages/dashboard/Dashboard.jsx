import React, { useState, useEffect } from 'react';
import { Building2, Smartphone, Shield, TrendingUp, RefreshCw, AlertCircle, CheckCircle, Clock } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import api from '../../services/api';
import '../../animations.css';

/* ─── URL base da Identity API (sem o prefixo /admin) ─── */
const API_BASE = import.meta.env.VITE_API_URL || '';

/* Deriva a URL de health do serviço a partir da base da API */
function healthUrl(base, path = '/health') {
    try {
        const u = new URL(base);
        return `${u.origin}${path}`;
    } catch {
        return base + path;
    }
}

/* ─── Status card para serviços ─── */
function ServiceStatusCard({ name, url, color }) {
    const [status, setStatus] = useState('checking');

    useEffect(() => {
        const check = async () => {
            try {
                // NOTA: não usar mode:'no-cors' para URLs cross-origin protegidas por
                // Cross-Origin-Resource-Policy: same-origin (helmet.js no middleware).
                // Usar fetch padrão (cors) — URLs de health são públicas e o CORS do
                // middleware permite adminlicencas.coliseusistemas.com.br.
                // Para o middleware, usamos /api/sales/health (same-origin via nginx proxy).
                const res = await fetch(url, { signal: AbortSignal.timeout(4000) });
                setStatus(res.ok ? 'online' : 'offline');
            } catch {
                setStatus('offline');
            }
        };
        check();
        const id = setInterval(check, 30_000);
        return () => clearInterval(id);
    }, [url]);

    const dot = status === 'online' ? 'var(--success)' : status === 'offline' ? 'var(--danger)' : 'var(--warning)';
    const label = status === 'online' ? 'Online' : status === 'offline' ? 'Offline' : 'Verificando...';

    return (
        <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '0.75rem 1rem',
            background: 'var(--bg-body)',
            borderRadius: '8px',
            border: '1px solid var(--border)',
        }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                <div style={{ width: '8px', height: '8px', borderRadius: '50%', background: dot, flexShrink: 0 }} className={status === 'online' ? 'animate-pulse-dot' : ''} />
                <span style={{ fontSize: '0.8125rem', fontWeight: 500, color: 'var(--text-sub)' }}>{name}</span>
            </div>
            <span style={{ fontSize: '0.75rem', fontWeight: 600, color: dot }}>{label}</span>
        </div>
    );
}

/* ─── KPI card ─── */
function KpiCard({ icon: Icon, value, label, sub, color, loading }) {
    return (
        <div className="metric-card animate-slide-up" style={{ display: 'flex', alignItems: 'flex-start', gap: '1rem' }}>
            <div style={{
                width: '48px', height: '48px', borderRadius: '12px', flexShrink: 0,
                background: `${color}18`, display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
                <Icon size={22} color={color} strokeWidth={2} />
            </div>
            <div style={{ flex: 1 }}>
                {loading ? (
                    <>
                        <div className="skeleton" style={{ height: '28px', width: '60px', marginBottom: '6px' }} />
                        <div className="skeleton" style={{ height: '14px', width: '100px' }} />
                    </>
                ) : (
                    <>
                        <div style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--text-main)', lineHeight: 1, letterSpacing: '-0.03em' }}
                            className="animate-count">
                            {value}
                        </div>
                        <div style={{ fontSize: '0.8125rem', color: 'var(--text-muted)', marginTop: '4px', fontWeight: 500 }}>{label}</div>
                        {sub && <div style={{ fontSize: '0.75rem', color: 'var(--text-hint)', marginTop: '2px' }}>{sub}</div>}
                    </>
                )}
            </div>
        </div>
    );
}

export default function DashboardHome() {
    const navigate = useNavigate();
    const [companies, setCompanies] = useState([]);
    const [totalCompanies, setTotalCompanies] = useState(0);
    const [auditCount, setAuditCount] = useState('—');
    const [loading, setLoading] = useState(true);
    const [lastRefresh, setLastRefresh] = useState(new Date());

    const [identityOnline, setIdentityOnline] = useState(true);
    const [salesOnline, setSalesOnline] = useState(true);

    useEffect(() => {
        const checkServices = async () => {
            try {
                const idRes = await fetch(healthUrl(API_BASE, '/health'), { signal: AbortSignal.timeout(4000) });
                setIdentityOnline(idRes.ok);
            } catch {
                setIdentityOnline(false);
            }
            try {
                const saRes = await fetch('/api/sales/health', { signal: AbortSignal.timeout(4000) });
                setSalesOnline(saRes.ok);
            } catch {
                setSalesOnline(false);
            }
        };
        checkServices();
        const intervalId = setInterval(checkServices, 30_000);
        return () => clearInterval(intervalId);
    }, []);

    const loadData = async () => {
        setLoading(true);
        try {
            // BUG FIX: chamava /companies (sem /admin) → 401. Agora usa /admin/companies
            const res = await api.get('/admin/companies?page=1&pageSize=5');
            const data = res.data;
            // API retorna { items: [...], total: N, page: N, pageSize: N }
            setCompanies(data.items || []);
            setTotalCompanies(data.total ?? data.items?.length ?? 0);
        } catch (err) {
            console.warn('companies load failed', err);
        }

        try {
            const res = await api.get('/audit?page=1&pageSize=1');
            setAuditCount(res.data.total ?? '—');
        } catch { /* ok */ }

        setLoading(false);
        setLastRefresh(new Date());
    };

    useEffect(() => { loadData(); }, []);

    // CompanyDto retorna activeDevices (número de dispositivos ativos por empresa)
    const activeCompanies = companies.filter(c => c.status === 'Active' || c.status === 'ACTIVE').length;
    const totalDevices = companies.reduce((sum, c) => sum + (c.activeDevices ?? 0), 0);

    return (
        <div className="animate-fade-in">

            {(!identityOnline || !salesOnline) && (
                <div style={{
                    background: 'rgba(239, 68, 68, 0.08)',
                    border: '1px solid rgba(239, 68, 68, 0.25)',
                    borderRadius: '12px',
                    padding: '1rem 1.25rem',
                    marginBottom: '1.5rem',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '0.75rem',
                    color: '#ef4444',
                    fontSize: '0.875rem',
                    fontWeight: 500,
                }} className="animate-pulse">
                    <AlertCircle size={20} style={{ flexShrink: 0 }} />
                    <div>
                        <strong style={{ display: 'block', fontWeight: 700, marginBottom: '2px' }}>Atenção: Instabilidade Detectada na Infraestrutura</strong>
                        <span>
                            {!identityOnline && '· O serviço central Identity API está inacessível. '}
                            {!salesOnline && '· O microsserviço Sales API está offline (sincronizações mobile/worker inoperantes).'}
                        </span>
                    </div>
                </div>
            )}

            {/* ── Page header ── */}
            <div className="page-header" style={{ marginBottom: '1.75rem' }}>
                <div>
                    <h1 style={{ fontSize: '1.5rem' }}>Bom dia, Admin 👋</h1>
                    <p className="page-subtext">Visão geral do ecossistema Coliseu Identity em tempo real.</p>
                </div>
                <button
                    onClick={loadData}
                    className="btn btn-outline btn-sm"
                    disabled={loading}
                    style={{ display: 'flex', alignItems: 'center', gap: '0.375rem' }}
                >
                    <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                    Atualizar
                </button>
            </div>

            {/* ── KPI Grid ── */}
            <div className="stagger" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '1rem', marginBottom: '1.5rem' }}>
                <KpiCard
                    icon={Building2} value={loading ? '—' : totalCompanies}
                    label="Empresas Cadastradas"
                    sub={`${activeCompanies} ativas`}
                    color="var(--primary)" loading={loading}
                />
                <KpiCard
                    icon={Smartphone} value={loading ? '—' : totalDevices}
                    label="Dispositivos Ativos"
                    sub="Nesta página"
                    color="var(--success)" loading={loading}
                />
                <KpiCard
                    icon={Shield} value={loading ? '—' : auditCount}
                    label="Eventos de Auditoria"
                    sub="Total registrado"
                    color="var(--warning)" loading={loading}
                />
                <KpiCard
                    icon={TrendingUp} value={loading ? '—' : `${totalCompanies > 0 ? Math.round((activeCompanies / totalCompanies) * 100) : 0}%`}
                    label="Taxa de Ativação"
                    sub="Empresas ativas/total"
                    color="var(--primary)" loading={loading}
                />
            </div>

            {/* ── Bottom Row ── */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: '1rem' }}>

                {/* Empresas recentes */}
                <div className="card">
                    <div style={{ padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                            <h3 style={{ margin: 0 }}>Empresas Recentes</h3>
                            <p style={{ fontSize: '0.8125rem', color: 'var(--text-muted)', marginTop: '2px' }}>Últimas {companies.length} cadastradas</p>
                        </div>
                        <button onClick={() => navigate('/dashboard/companies')} className="btn btn-outline btn-sm">
                            Ver todas
                        </button>
                    </div>

                    {loading ? (
                        <div style={{ padding: '1.25rem' }}>
                            {[...Array(3)].map((_, i) => (
                                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.875rem' }}>
                                    <div className="skeleton" style={{ width: 36, height: 36, borderRadius: '8px' }} />
                                    <div style={{ flex: 1 }}>
                                        <div className="skeleton" style={{ height: 14, width: '60%', marginBottom: 6 }} />
                                        <div className="skeleton" style={{ height: 12, width: '40%' }} />
                                    </div>
                                </div>
                            ))}
                        </div>
                    ) : companies.length === 0 ? (
                        <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                            <Building2 size={32} style={{ margin: '0 auto 0.75rem', opacity: 0.3 }} />
                            <p style={{ fontSize: '0.875rem' }}>Nenhuma empresa ainda</p>
                            <button onClick={() => navigate('/dashboard/companies')} className="btn btn-primary btn-sm" style={{ marginTop: '0.75rem' }}>
                                Adicionar empresa
                            </button>
                        </div>
                    ) : (
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Empresa</th>
                                    <th style={{ textAlign: 'center' }}>Dispositivos</th>
                                    <th>Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                {companies.map(c => (
                                    <tr key={c.id} onClick={() => navigate(`/dashboard/companies/${c.id}`)} style={{ cursor: 'pointer' }}>
                                        <td>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                                                <div style={{
                                                    width: '32px', height: '32px', borderRadius: '8px', flexShrink: 0,
                                                    background: 'linear-gradient(135deg, var(--primary), var(--primary-light))',
                                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                    color: 'white', fontWeight: 700, fontSize: '0.75rem',
                                                }}>
                                                    {c.name?.charAt(0).toUpperCase()}
                                                </div>
                                                <div>
                                                    <div style={{ fontWeight: 600, fontSize: '0.875rem' }}>{c.name}</div>
                                                    <div style={{ fontSize: '0.7rem', color: 'var(--text-hint)', fontFamily: 'monospace' }}>{c.id?.split('-')[0]}…</div>
                                                </div>
                                            </div>
                                        </td>
                                        <td style={{ textAlign: 'center' }}>
                                            <span style={{ fontSize: '0.8125rem', fontWeight: 600 }}>
                                                {c.activeDevices ?? 0} <span style={{ color: 'var(--text-hint)', fontWeight: 400 }}>/ {c.deviceLimit ?? 10}</span>
                                            </span>
                                        </td>
                                        <td>
                                            <span className={`badge ${c.status === 'Active' ? 'badge-active' : 'badge-inactive'}`}>
                                                {c.status}
                                            </span>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>

                {/* Right col: Services + Quick Actions */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>

                    {/* Services Health */}
                    <div className="card" style={{ padding: '1.25rem' }}>
                        <h3 style={{ marginBottom: '0.875rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <div className="status-dot status-dot-green" />
                            Status dos Serviços
                        </h3>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                            {/* URLs derivadas de VITE_API_URL para funcionar em produção */}
                            <ServiceStatusCard name="Identity API"  url={healthUrl(API_BASE, '/health')} />
                            <ServiceStatusCard name="Sales API"     url="/api/sales/health" />
                            <ServiceStatusCard name="Identity Admin" url={window.location.origin} />
                        </div>
                        <div style={{ marginTop: '0.875rem', paddingTop: '0.75rem', borderTop: '1px solid var(--border)', display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                            <Clock size={12} color="var(--text-hint)" />
                            <span style={{ fontSize: '0.7rem', color: 'var(--text-hint)' }}>
                                Atualizado {lastRefresh.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
                            </span>
                        </div>
                    </div>

                    {/* Quick Actions */}
                    <div className="card" style={{ padding: '1.25rem' }}>
                        <h3 style={{ marginBottom: '0.875rem' }}>Ações Rápidas</h3>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                            {[
                                { label: 'Nova Empresa', desc: 'Cadastrar tenant', path: '/dashboard/companies', icon: Building2, color: 'var(--primary)' },
                                { label: 'Ver Auditoria', desc: 'Logs de segurança', path: '/dashboard/audit', icon: Shield, color: 'var(--warning)' },
                                { label: 'KPI Dashboard', desc: 'Métricas de vendas', path: '/dashboard/kpi', icon: TrendingUp, color: 'var(--primary)' },
                            ].map(a => (
                                <button
                                    key={a.path}
                                    onClick={() => navigate(a.path)}
                                    style={{
                                        width: '100%', display: 'flex', alignItems: 'center', gap: '0.75rem',
                                        padding: '0.625rem 0.75rem', borderRadius: '8px', border: '1px solid var(--border)',
                                        background: 'var(--bg-body)', cursor: 'pointer', transition: 'all 0.18s', textAlign: 'left',
                                    }}
                                    onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--bg-card-hover)'; e.currentTarget.style.borderColor = a.color; }}
                                    onMouseLeave={(e) => { e.currentTarget.style.background = 'var(--bg-body)'; e.currentTarget.style.borderColor = 'var(--border)'; }}
                                >
                                    <div style={{ width: '32px', height: '32px', borderRadius: '8px', background: `${a.color}15`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                                        <a.icon size={15} color={a.color} />
                                    </div>
                                    <div>
                                        <div style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-main)' }}>{a.label}</div>
                                        <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>{a.desc}</div>
                                    </div>
                                </button>
                            ))}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
