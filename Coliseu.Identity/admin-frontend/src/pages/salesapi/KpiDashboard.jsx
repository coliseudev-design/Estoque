import React, { useState, useEffect } from 'react';
import {
    TrendingUp, ShoppingCart, DollarSign, Package,
    Users, Award, RefreshCw, Calendar
} from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

// ── Gráfico de barras SVG com gradiente ──────────────────────────────────────
function BarChart({ data, xKey, yKey, label }) {
    const [tooltip, setTooltip] = useState(null);
    if (!data?.length) return (
        <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-hint)', fontSize: '0.875rem' }}>
            Sem dados para exibir
        </div>
    );
    const max = Math.max(...data.map(d => d[yKey]), 1);
    const barW = Math.max(12, Math.min(36, Math.floor(580 / data.length) - 6));
    const chartH = 130;
    const fmt = v => v > 1000
        ? v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
        : Number(v).toLocaleString('pt-BR');

    return (
        <div>
            {label && <div style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: 12, textTransform: 'uppercase', letterSpacing: '0.06em' }}>{label}</div>}
            <div style={{ overflowX: 'auto' }}>
                <svg
                    width={Math.max(580, data.length * (barW + 6))}
                    height={chartH + 36}
                    style={{ display: 'block' }}
                >
                    {/* Gradient definition */}
                    <defs>
                        <linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#1B8FCD" stopOpacity="1" />
                            <stop offset="100%" stopColor="#3BAAE3" stopOpacity="0.6" />
                        </linearGradient>
                        <linearGradient id="barGradHov" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#3BAAE3" stopOpacity="1" />
                            <stop offset="100%" stopColor="#1B8FCD" stopOpacity="1" />
                        </linearGradient>
                    </defs>
                    {/* Gridlines */}
                    {[0.25, 0.5, 0.75, 1].map(p => (
                        <line
                            key={p}
                            x1={0} y1={chartH * (1 - p)} x2={Math.max(580, data.length * (barW + 6))} y2={chartH * (1 - p)}
                            stroke="rgba(255,255,255,0.05)" strokeWidth={1} strokeDasharray="4 4"
                        />
                    ))}
                    {data.map((d, i) => {
                        const barH = Math.max(4, (d[yKey] / max) * chartH);
                        const x = i * (barW + 6);
                        const y = chartH - barH;
                        const isHov = tooltip?.i === i;
                        return (
                            <g key={i}
                                onMouseEnter={() => setTooltip({ i, d })}
                                onMouseLeave={() => setTooltip(null)}
                                style={{ cursor: 'pointer' }}
                            >
                                <rect
                                    x={x} y={y} width={barW} height={barH}
                                    fill={isHov ? 'url(#barGradHov)' : 'url(#barGrad)'}
                                    rx={4} ry={4}
                                    style={{ filter: isHov ? 'drop-shadow(0 0 8px rgba(27,143,205,0.5))' : 'none', transition: 'filter 0.2s' }}
                                />
                                {data.length <= 20 && (
                                    <text x={x + barW / 2} y={chartH + 20}
                                        textAnchor="middle" fontSize={9}
                                        fill="var(--text-hint)"
                                        fontFamily="Inter, sans-serif"
                                    >
                                        {String(d[xKey]).slice(-5)}
                                    </text>
                                )}
                                {isHov && (
                                    <foreignObject x={Math.max(0, x - 40)} y={y - 60} width={130} height={52}>
                                        <div xmlns="http://www.w3.org/1999/xhtml" style={{
                                            background: 'rgba(14,21,37,0.95)',
                                            border: '1px solid rgba(27,143,205,0.4)',
                                            borderRadius: 8, padding: '6px 10px',
                                            fontSize: 11, boxShadow: '0 4px 20px rgba(0,0,0,0.6)',
                                            pointerEvents: 'none'
                                        }}>
                                            <div style={{ fontWeight: 700, color: '#F1F5F9', marginBottom: 2 }}>{d[xKey]}</div>
                                            <div style={{ color: '#3BAAE3' }}>{fmt(d[yKey])}</div>
                                        </div>
                                    </foreignObject>
                                )}
                            </g>
                        );
                    })}
                </svg>
            </div>
        </div>
    );
}

// ── Ranking list premium ──────────────────────────────────────────────────────
function RankList({ items, nameKey = 'name', valueKey = 'revenue', gradient }) {
    if (!items?.length) return (
        <div style={{ color: 'var(--text-muted)', fontSize: '0.875rem', padding: '1rem', textAlign: 'center' }}>Sem dados</div>
    );
    const max = Math.max(...items.map(r => r[valueKey]), 1);
    const fmt = v => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

    const medals = ['🥇', '🥈', '🥉'];

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            {items.map((item, i) => (
                <div key={i} style={{
                    padding: '0.75rem',
                    background: 'rgba(255,255,255,0.03)',
                    border: '1px solid var(--border-light)',
                    borderRadius: 'var(--radius-md)',
                    transition: 'all var(--t-fast)',
                }}
                    onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.06)'}
                    onMouseLeave={e => e.currentTarget.style.background = 'rgba(255,255,255,0.03)'}
                >
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <span style={{ fontSize: '1rem', width: 24 }}>{medals[i] || `${i + 1}.`}</span>
                            <div style={{
                                width: 28, height: 28, borderRadius: '50%',
                                background: gradient || 'var(--gradient-primary)',
                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                fontSize: '0.65rem', fontWeight: 700, color: 'white',
                            }}>
                                {String(item[nameKey] || '').slice(0, 2).toUpperCase()}
                            </div>
                            <span style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)' }}>
                                {item[nameKey]}
                            </span>
                        </div>
                        <span style={{ fontSize: '0.8125rem', fontWeight: 700, color: 'var(--text-main)', fontVariantNumeric: 'tabular-nums' }}>
                            {fmt(item[valueKey] || 0)}
                        </span>
                    </div>
                    <div style={{ height: 4, borderRadius: 2, background: 'rgba(255,255,255,0.06)' }}>
                        <div style={{
                            height: '100%',
                            width: `${((item[valueKey] || 0) / max) * 100}%`,
                            borderRadius: 2,
                            background: gradient || 'var(--gradient-primary)',
                            transition: 'width 0.6s cubic-bezier(0.4,0,0.2,1)',
                        }} />
                    </div>
                </div>
            ))}
        </div>
    );
}

// ── KPI Card ─────────────────────────────────────────────────────────────────
const KpiCard = ({ label, value, icon: Icon, gradient, sub, delay = 0 }) => (
    <div
        className="metric-card fade-slide-up"
        style={{ '--metric-accent': gradient, animationDelay: `${delay}ms` }}
    >
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
            <span className="metric-label">{label}</span>
            <div className="metric-icon" style={{ background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}>
                <Icon size={15} style={{ color: 'var(--text-muted)' }} />
            </div>
        </div>
        <div className="metric-value">{value ?? '—'}</div>
        {sub && <div style={{ fontSize: '0.75rem', color: 'var(--text-hint)', marginTop: '0.25rem' }}>{sub}</div>}
    </div>
);

/**
 * KpiDashboard — Dashboard de KPIs de vendas agregadas.
 */
export default function KpiDashboard() {
    const [data, setData]     = useState(null);
    const [loading, setLoad]  = useState(false);
    const [error, setError]   = useState(null);
    
    // Filtros
    const today = new Date();
    const [from, setFrom] = useState(
        new Date(today.getFullYear(), today.getMonth() - 1, today.getDate()).toISOString().slice(0, 10)
    );
    const [to, setTo] = useState(today.toISOString().slice(0, 10));
    
    const [companies, setCompanies] = useState([]);
    const [selectedCompanyId, setSelectedCompanyId] = useState('');
    const [branches, setBranches] = useState([]);
    const [selectedBranchId, setSelectedBranchId] = useState('');
    const [source, setSource] = useState('app');

    // Carregar empresas no mount
    useEffect(() => {
        const loadCompanies = async () => {
            try {
                const list = await salesApiService.getAdminCompanies();
                setCompanies(list || []);
                if (list?.length > 0) {
                    setSelectedCompanyId(list[0].id);
                }
            } catch (e) {
                console.error('Erro ao carregar empresas:', e);
            }
        };
        loadCompanies();
    }, []);

    // Carregar filiais quando a empresa muda
    useEffect(() => {
        if (!selectedCompanyId) {
            setBranches([]);
            setSelectedBranchId('');
            return;
        }
        const loadBranches = async () => {
            try {
                const res = await salesApiService.getBranches(selectedCompanyId);
                setBranches(res?.branches || []);
                setSelectedBranchId('');
            } catch (e) {
                console.error('Erro ao carregar filiais:', e);
            }
        };
        loadBranches();
    }, [selectedCompanyId]);

    const fetchKpi = async () => {
        setLoad(true); setError(null);
        try {
            const d = await salesApiService.getKpi({
                from,
                to,
                companyId: selectedCompanyId,
                branchId: selectedBranchId,
                source
            });
            setData(d);
        } catch (e) { setError(e.message); }
        finally { setLoad(false); }
    };

    // Reatividade: atualiza sempre que qualquer filtro mudar
    useEffect(() => {
        if (selectedCompanyId) {
            fetchKpi();
        }
    }, [selectedCompanyId, selectedBranchId, source, from, to]);

    const fmt = v => Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

    return (
        <div className="page-enter" style={{ display: 'flex', flexDirection: 'column', gap: '1.75rem' }}>

            {/* Header */}
            <div className="page-header">
                <div className="page-header-info">
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.25rem' }}>
                        <div style={{
                            width: 40, height: 40,
                            background: 'var(--gradient-primary)',
                            borderRadius: 'var(--radius-md)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            boxShadow: 'var(--shadow-primary)',
                        }}>
                            <TrendingUp size={20} color="white" />
                        </div>
                        <div>
                            <h1 style={{ margin: 0 }}>Dashboard KPI</h1>
                            {data?.company && (
                                <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: 2 }}>
                                    Origem: {data.company}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
                {/* Filtros de período */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', flexWrap: 'wrap' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.8125rem', color: 'var(--text-muted)' }}>
                        <Calendar size={14} />
                        <span>De</span>
                    </div>
                    <input type="date" value={from} onChange={e => setFrom(e.target.value)} className="input-field" style={{ width: 145, height: 36, fontSize: '0.8125rem' }} />
                    <span style={{ fontSize: '0.8125rem', color: 'var(--text-hint)' }}>Até</span>
                    <input type="date" value={to} onChange={e => setTo(e.target.value)} className="input-field" style={{ width: 145, height: 36, fontSize: '0.8125rem' }} />
                    <button onClick={fetchKpi} disabled={loading} className="btn btn-primary" style={{ height: 36 }}>
                        <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                        Atualizar
                    </button>
                </div>
            </div>

            {/* Painel de Filtros e Segmentação */}
            <div className="card" style={{ padding: '1.25rem', display: 'flex', flexDirection: 'column', gap: '1rem', background: 'rgba(30, 41, 59, 0.4)', backdropFilter: 'blur(12px)', border: '1px solid rgba(255, 255, 255, 0.05)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '1.25rem' }}>
                    
                    {/* Source Toggle */}
                    <div style={{ display: 'flex', gap: '4px', background: 'rgba(15, 23, 42, 0.6)', padding: '4px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.05)' }}>
                        <button
                            onClick={() => setSource('app')}
                            style={{
                                padding: '8px 16px',
                                borderRadius: '6px',
                                border: 'none',
                                fontSize: '0.8125rem',
                                fontWeight: 600,
                                cursor: 'pointer',
                                background: source === 'app' ? 'var(--gradient-primary)' : 'transparent',
                                color: source === 'app' ? '#ffffff' : 'var(--text-muted)',
                                transition: 'all 0.2s',
                                boxShadow: source === 'app' ? 'var(--shadow-primary)' : 'none'
                            }}
                        >
                            Vendas APP (Enviadas)
                        </button>
                        <button
                            onClick={() => setSource('erp')}
                            style={{
                                padding: '8px 16px',
                                borderRadius: '6px',
                                border: 'none',
                                fontSize: '0.8125rem',
                                fontWeight: 600,
                                cursor: 'pointer',
                                background: source === 'erp' ? 'var(--gradient-primary)' : 'transparent',
                                color: source === 'erp' ? '#ffffff' : 'var(--text-muted)',
                                transition: 'all 0.2s',
                                boxShadow: source === 'erp' ? 'var(--shadow-primary)' : 'none'
                            }}
                        >
                            Vendas ERP (Processadas)
                        </button>
                    </div>

                    {/* Seletores */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
                        
                        {/* Selector Empresa */}
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-hint)' }}>Empresa</label>
                            <select
                                value={selectedCompanyId}
                                onChange={e => setSelectedCompanyId(e.target.value)}
                                className="input-field"
                                style={{ width: 220, height: 38, fontSize: '0.8125rem', cursor: 'pointer' }}
                            >
                                <option value="">Todas as Empresas</option>
                                {companies.map(c => (
                                    <option key={c.id} value={c.id}>{c.name}</option>
                                ))}
                            </select>
                        </div>

                        {/* Selector Filial / Depto */}
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                            <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-hint)' }}>Filial / Departamento</label>
                            <select
                                value={selectedBranchId}
                                onChange={e => setSelectedBranchId(e.target.value)}
                                className="input-field"
                                style={{ width: 220, height: 38, fontSize: '0.8125rem', cursor: 'pointer' }}
                                disabled={!selectedCompanyId}
                            >
                                <option value="">Todas as Filiais</option>
                                {branches.map(b => (
                                    <option key={b.id} value={b.id}>
                                        {b.name} {b.erpDeptoPadrao ? `(Depto: ${b.erpDeptoPadrao})` : ''}
                                    </option>
                                ))}
                            </select>
                        </div>

                    </div>
                </div>
            </div>

            {error && (
                <div style={{ padding: '0.875rem 1rem', background: 'var(--danger-bg)', color: 'var(--danger-text)', borderRadius: 'var(--radius-md)', border: '1px solid var(--danger-border)', fontSize: '0.875rem' }}>
                    ⚠ {error}
                </div>
            )}

            {loading && !data && (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '1rem' }}>
                    {Array.from({ length: 6 }).map((_, i) => (
                        <div key={i} className="skeleton" style={{ height: 100, borderRadius: 'var(--radius-lg)' }} />
                    ))}
                </div>
            )}

            {data && (
                <>
                    {/* KPI Cards */}
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(175px, 1fr))', gap: '1rem' }}>
                        <KpiCard label="Total Vendido"    value={fmt(data.summary?.totalRevenue)}   icon={DollarSign}  gradient="var(--gradient-primary)" delay={0} />
                        <KpiCard label="Pedidos"          value={data.summary?.totalOrders}          icon={ShoppingCart} gradient="var(--gradient-blue)"    delay={60} />
                        <KpiCard label="Ticket Médio"     value={fmt(data.summary?.avgTicket)}       icon={TrendingUp}  gradient="var(--gradient-amber)"   delay={120} />
                        <KpiCard label="Integrados (R$)"  value={fmt(data.summary?.syncedRevenue)}   icon={Package}     gradient="var(--gradient-green)"   delay={180} />
                        <KpiCard label="Pendentes"        value={data.byStatus?.find(s => s.status === 'pending')?.count ?? 0} icon={Users} gradient="linear-gradient(135deg,#F59E0B,#FCD34D)" delay={240} />
                        <KpiCard label="Com Erro"         value={data.byStatus?.find(s => s.status === 'error')?.count ?? 0}   icon={Award} gradient="var(--gradient-rose)"    delay={300} />
                    </div>

                    {/* Gráfico diário */}
                    <div className="card" style={{ padding: '1.5rem' }}>
                        <BarChart
                            data={data.dailySales}
                            xKey="day"
                            yKey="revenue"
                            label="Vendas por Dia (R$)"
                        />
                    </div>

                    {/* Rankings e Filiais */}
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1.25rem' }}>
                        <div className="card" style={{ padding: '1.25rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1.25rem' }}>
                                <div style={{
                                    width: 32, height: 32, borderRadius: 'var(--radius-sm)',
                                    background: 'linear-gradient(135deg, #3B82F6, #06B6D4)',
                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                }}>
                                    <Users size={15} color="white" />
                                </div>
                                <h3 style={{ margin: 0, fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-sub)' }}>Top Clientes</h3>
                            </div>
                            <RankList items={data.topCustomers} gradient="linear-gradient(135deg,#3B82F6,#06B6D4)" />
                        </div>

                        <div className="card" style={{ padding: '1.25rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1.25rem' }}>
                                <div style={{
                                    width: 32, height: 32, borderRadius: 'var(--radius-sm)',
                                    background: 'var(--gradient-green)',
                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                }}>
                                    <Award size={15} color="white" />
                                </div>
                                <h3 style={{ margin: 0, fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-sub)' }}>Top Vendedores</h3>
                            </div>
                            <RankList items={data.topSellers} gradient="var(--gradient-green)" />
                        </div>

                        <div className="card" style={{ padding: '1.25rem' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1.25rem' }}>
                                <div style={{
                                    width: 32, height: 32, borderRadius: 'var(--radius-sm)',
                                    background: 'linear-gradient(135deg, #F59E0B, #EF4444)',
                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                }}>
                                    <ShoppingCart size={15} color="white" />
                                </div>
                                <h3 style={{ margin: 0, fontSize: '0.9rem', fontWeight: 600, color: 'var(--text-sub)' }}>Desempenho por Filial / Depto</h3>
                            </div>
                            <RankList items={data.branchSales} nameKey="branchName" valueKey="totalRevenue" gradient="linear-gradient(135deg, #F59E0B, #EF4444)" />
                        </div>
                    </div>
                </>
            )}

            {!data && !loading && !error && (
                <div className="card" style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                    <TrendingUp size={40} style={{ opacity: 0.2, marginBottom: 16 }} />
                    <p>Selecione uma empresa e período para visualizar os indicadores.</p>
                </div>
            )}
        </div>
    );
}
