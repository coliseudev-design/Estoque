import React, { useState, useEffect, useMemo } from 'react';
import {
    BarChart2, TrendingUp, ShoppingCart, DollarSign,
    ArrowDown, ArrowUp, Filter, RefreshCw, Search
} from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

// ── Gráfico SVG com gradiente ─────────────────────────────────────────────────
function SalesBarChart({ orders }) {
    const [tooltip, setTooltip] = useState(null);

    const days = useMemo(() => {
        const map = {};
        orders.forEach(o => {
            const day = (o.createdAt || o.created_at || o.updatedAt || '').slice(0, 10);
            if (!day) return;
            if (!map[day]) map[day] = { day, total: 0, count: 0 };
            map[day].total += o.totalAmount || 0;
            map[day].count++;
        });
        return Object.values(map).sort((a, b) => a.day.localeCompare(b.day)).slice(-30);
    }, [orders]);

    if (!days.length) return null;

    const maxTotal = Math.max(...days.map(d => d.total), 1);
    const barW = Math.max(10, Math.min(32, Math.floor(580 / days.length) - 6));
    const chartH = 130;
    const fmt = v => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

    return (
        <div className="card" style={{ padding: '1.25rem 1.5rem' }}>
            <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 14 }}>
                Vendas por Dia
            </div>
            <div style={{ overflowX: 'auto' }}>
                <svg width={Math.max(580, days.length * (barW + 6))} height={chartH + 36} style={{ display: 'block' }}>
                    <defs>
                        <linearGradient id="salesBarGrad" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#3B82F6" stopOpacity="1" />
                            <stop offset="100%" stopColor="#06B6D4" stopOpacity="0.5" />
                        </linearGradient>
                    </defs>
                    {[0.25, 0.5, 0.75, 1].map(p => (
                        <line key={p} x1={0} y1={chartH * (1 - p)} x2={Math.max(580, days.length * (barW + 6))} y2={chartH * (1 - p)}
                            stroke="rgba(255,255,255,0.05)" strokeWidth={1} strokeDasharray="4 4" />
                    ))}
                    {days.map((d, i) => {
                        const barH = Math.max(4, (d.total / maxTotal) * chartH);
                        const x = i * (barW + 6);
                        const y = chartH - barH;
                        const isHov = tooltip?.i === i;
                        return (
                            <g key={d.day}
                                onMouseEnter={() => setTooltip({ i, d })}
                                onMouseLeave={() => setTooltip(null)}
                                style={{ cursor: 'pointer' }}
                            >
                                <rect x={x} y={y} width={barW} height={barH}
                                    fill="url(#salesBarGrad)"
                                    opacity={isHov ? 1 : 0.75} rx={4}
                                    style={{ filter: isHov ? 'drop-shadow(0 0 6px rgba(59,130,246,0.5))' : 'none', transition: 'filter 0.2s, opacity 0.2s' }}
                                />
                                {days.length <= 15 && (
                                    <text x={x + barW / 2} y={chartH + 20} textAnchor="middle" fontSize={9} fill="var(--text-hint)" fontFamily="Inter, sans-serif">
                                        {d.day.slice(5)}
                                    </text>
                                )}
                                {isHov && (
                                    <foreignObject x={Math.max(0, x - 45)} y={y - 60} width={140} height={52}>
                                        <div xmlns="http://www.w3.org/1999/xhtml" style={{
                                            background: 'rgba(14,21,37,0.96)', border: '1px solid rgba(59,130,246,0.4)',
                                            borderRadius: 8, padding: '6px 10px', fontSize: 11,
                                            boxShadow: '0 4px 20px rgba(0,0,0,0.6)', pointerEvents: 'none'
                                        }}>
                                            <div style={{ fontWeight: 700, color: '#F1F5F9', marginBottom: 2 }}>{d.day}</div>
                                            <div style={{ color: '#60A5FA' }}>{fmt(d.total)} · {d.count} pedidos</div>
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

// ── Status badge inline ───────────────────────────────────────────────────────
const statusStyles = {
    synced:     { bg: 'var(--success-bg)',  color: 'var(--success-text)',  border: 'var(--success-border)',  label: 'Integrado' },
    pending:    { bg: 'var(--warning-bg)',  color: 'var(--warning-text)',  border: 'var(--warning-border)',  label: 'Pendente' },
    error:      { bg: 'var(--danger-bg)',   color: 'var(--danger-text)',   border: 'var(--danger-border)',   label: 'Erro' },
    processing: { bg: 'var(--info-bg)',     color: 'var(--info-text)',     border: 'var(--info-border)',     label: 'Processando' },
};

const StatusPill = ({ s }) => {
    const st = statusStyles[s] || { bg: 'rgba(255,255,255,0.06)', color: 'var(--text-muted)', border: 'var(--border)', label: s };
    return (
        <span style={{
            padding: '2px 8px', borderRadius: 20, fontSize: '0.7rem', fontWeight: 700,
            textTransform: 'uppercase', letterSpacing: '0.05em',
            background: st.bg, color: st.color, border: `1px solid ${st.border}`,
        }}>
            {st.label}
        </span>
    );
};

/**
 * SalesReport — Relatório de pedidos com tabela dark e gráfico de barras.
 */
export default function SalesReport() {
    const [orders, setOrders]   = useState([]);
    const [loading, setLoad]    = useState(false);
    const [error, setError]     = useState(null);
    const [sort, setSort]       = useState({ field: 'createdAt', dir: 'desc' });
    const [search, setSearch]   = useState('');
    const [statusFilter, setStatusFilter] = useState('');
    const [meta, setMeta]       = useState(null);

    const today = new Date();
    const [from, setFrom] = useState(
        new Date(today.getFullYear(), today.getMonth() - 1, today.getDate()).toISOString().slice(0, 10)
    );
    const [to, setTo] = useState(today.toISOString().slice(0, 10));

    const fetchOrders = async () => {
        setLoad(true); setError(null);
        try {
            const data = await salesApiService.getOrders({ from, to });
            setOrders(Array.isArray(data) ? data : (data.orders || data.data || []));
            if (!Array.isArray(data)) setMeta(data);
        } catch (e) { setError(e.message); }
        finally { setLoad(false); }
    };

    useEffect(() => { fetchOrders(); }, []);

    const sorted = useMemo(() => {
        let list = [...orders];
        if (search) {
            const q = search.toLowerCase();
            list = list.filter(o =>
                String(o.customerId || o.customer_id || '').toLowerCase().includes(q) ||
                String(o.id || '').toLowerCase().includes(q) ||
                String(o.sellerId || o.seller_id || '').toLowerCase().includes(q)
            );
        }
        if (statusFilter) list = list.filter(o => (o.status || '').toLowerCase() === statusFilter);
        list.sort((a, b) => {
            const va = a[sort.field] ?? a[sort.field.replace(/([A-Z])/g, '_$1').toLowerCase()];
            const vb = b[sort.field] ?? b[sort.field.replace(/([A-Z])/g, '_$1').toLowerCase()];
            if (va === vb) return 0;
            return sort.dir === 'asc' ? (va > vb ? 1 : -1) : (va < vb ? 1 : -1);
        });
        return list;
    }, [orders, sort, search, statusFilter]);

    const totalRevenue = useMemo(() => sorted.reduce((s, o) => s + (o.totalAmount || 0), 0), [sorted]);
    const avgTicket = sorted.length ? totalRevenue / sorted.length : 0;
    const fmt = v => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

    const sortBy = (field) => {
        setSort(s => ({ field, dir: s.field === field && s.dir === 'asc' ? 'desc' : 'asc' }));
    };

    const SortIcon = ({ field }) => sort.field === field
        ? (sort.dir === 'asc' ? <ArrowUp size={12} style={{ marginLeft: 3 }} /> : <ArrowDown size={12} style={{ marginLeft: 3 }} />)
        : null;

    // Summary cards data
    const summaryCards = [
        { label: 'Receita Total',   value: fmt(totalRevenue), gradient: 'var(--gradient-primary)' },
        { label: 'Pedidos',         value: sorted.length.toLocaleString('pt-BR'), gradient: 'var(--gradient-blue)' },
        { label: 'Ticket Médio',    value: fmt(avgTicket), gradient: 'var(--gradient-amber)' },
    ];

    return (
        <div className="page-enter" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>

            {/* Header */}
            <div className="page-header">
                <div className="page-header-info">
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.25rem' }}>
                        <div style={{
                            width: 40, height: 40,
                            background: 'var(--gradient-blue)',
                            borderRadius: 'var(--radius-md)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            boxShadow: '0 0 24px rgba(59,130,246,0.35)',
                        }}>
                            <BarChart2 size={20} color="white" />
                        </div>
                        <h1 style={{ margin: 0 }}>Relatório de Vendas</h1>
                    </div>
                    <p className="page-subtext">Analise pedidos, revenue e tendências do período selecionado</p>
                </div>
                <button onClick={fetchOrders} disabled={loading} className="btn btn-outline hover-lift">
                    <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                    Atualizar
                </button>
            </div>

            {/* Summary cards */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '1rem' }}>
                {summaryCards.map((c, i) => (
                    <div key={i} className="metric-card fade-slide-up" style={{ '--metric-accent': c.gradient, animationDelay: `${i * 60}ms` }}>
                        <span className="metric-label">{c.label}</span>
                        <div className="metric-value">{c.value}</div>
                    </div>
                ))}
            </div>

            {/* Filtros */}
            <div className="card" style={{ padding: '1rem 1.25rem', display: 'flex', gap: '0.75rem', alignItems: 'flex-end', flexWrap: 'wrap' }}>
                <Filter size={14} style={{ color: 'var(--text-muted)', alignSelf: 'center', flexShrink: 0 }} />
                <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', flex: 1, minWidth: 130 }}>
                    De
                    <input type="date" value={from} onChange={e => setFrom(e.target.value)} className="input-field" style={{ height: 36, fontSize: '0.8125rem' }} />
                </label>
                <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', flex: 1, minWidth: 130 }}>
                    Até
                    <input type="date" value={to} onChange={e => setTo(e.target.value)} className="input-field" style={{ height: 36, fontSize: '0.8125rem' }} />
                </label>
                <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', flex: 1, minWidth: 130 }}>
                    Status
                    <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)} className="input-field" style={{ height: 36, fontSize: '0.8125rem' }}>
                        <option value="">Todos</option>
                        <option value="synced">Integrado</option>
                        <option value="pending">Pendente</option>
                        <option value="processing">Processando</option>
                        <option value="error">Erro</option>
                    </select>
                </label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', flex: 1, minWidth: 180, position: 'relative' }}>
                    Buscar
                    <div style={{ position: 'relative' }}>
                        <Search size={13} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-hint)', pointerEvents: 'none' }} />
                        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Cliente, vendedor, ID..." className="input-field" style={{ paddingLeft: 30, height: 36, fontSize: '0.8125rem' }} />
                    </div>
                </div>
                <button onClick={fetchOrders} disabled={loading} className="btn btn-primary" style={{ height: 36, padding: '0 1.25rem' }}>
                    Filtrar
                </button>
            </div>

            {error && (
                <div style={{ padding: '0.875rem', background: 'var(--danger-bg)', color: 'var(--danger-text)', borderRadius: 'var(--radius-md)', border: '1px solid var(--danger-border)', fontSize: '0.875rem' }}>
                    ⚠ {error}
                </div>
            )}

            {/* Gráfico */}
            {sorted.length > 0 && <SalesBarChart orders={sorted} />}

            {/* Tabela */}
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{
                    padding: '1rem 1.5rem', borderBottom: '1px solid var(--border)',
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                }}>
                    <div style={{ fontWeight: 600, color: 'var(--text-main)' }}>
                        Pedidos
                        <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)', fontWeight: 400, marginLeft: 8 }}>
                            ({sorted.length} {sorted.length !== orders.length ? `de ${orders.length}` : ''})
                        </span>
                    </div>
                    {loading && <div style={{ width: 16, height: 16, border: '2px solid var(--border)', borderTopColor: 'var(--primary)', borderRadius: '50%', animation: 'spin 0.7s linear infinite' }} />}
                </div>

                {loading && orders.length === 0 ? (
                    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                        {Array.from({ length: 5 }).map((_, i) => (
                            <div key={i} className="skeleton" style={{ height: 48, borderRadius: 'var(--radius-md)' }} />
                        ))}
                    </div>
                ) : sorted.length > 0 ? (
                    <div style={{ overflowX: 'auto' }}>
                        <table className="data-table">
                            <thead>
                                <tr>
                                    {[
                                        { l: 'ID',          f: 'id' },
                                        { l: 'Data',        f: 'createdAt' },
                                        { l: 'Cliente',     f: 'customerId' },
                                        { l: 'Vendedor',    f: 'sellerId' },
                                        { l: 'Status',      f: 'status' },
                                        { l: 'Total (R$)',  f: 'totalAmount' },
                                    ].map(({ l, f }) => (
                                        <th key={l} onClick={() => f && sortBy(f)} style={{ cursor: f ? 'pointer' : 'default', userSelect: 'none' }}>
                                            <span style={{ display: 'inline-flex', alignItems: 'center' }}>
                                                {l}<SortIcon field={f} />
                                            </span>
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody>
                                {sorted.map((o, i) => (
                                    <tr key={o.id || i} className="fade-slide-up" style={{ animationDelay: `${Math.min(i, 12) * 15}ms` }}>
                                        <td>
                                            <code style={{ fontSize: '0.75rem', color: 'var(--accent-blue)', background: 'rgba(59,130,246,0.08)', padding: '2px 6px', borderRadius: 4 }}>
                                                {String(o.id || '—').slice(0, 8)}…
                                            </code>
                                        </td>
                                        <td style={{ color: 'var(--text-muted)', fontSize: '0.8125rem', whiteSpace: 'nowrap' }}>
                                            {o.createdAt || o.created_at ? new Date(o.createdAt || o.created_at).toLocaleDateString('pt-BR') : '—'}
                                        </td>
                                        <td style={{ color: 'var(--text-sub)', fontSize: '0.8125rem' }}>
                                            {o.customerId || o.customer_name || '—'}
                                        </td>
                                        <td style={{ color: 'var(--text-sub)', fontSize: '0.8125rem' }}>
                                            {o.sellerId || o.seller_name || '—'}
                                        </td>
                                        <td><StatusPill s={String(o.status || '').toLowerCase()} /></td>
                                        <td style={{ fontWeight: 700, color: 'var(--text-main)', fontVariantNumeric: 'tabular-nums' }}>
                                            {fmt(o.totalAmount || 0)}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                ) : (
                    <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                        <BarChart2 size={36} style={{ opacity: 0.2, marginBottom: 12 }} />
                        <p style={{ fontSize: '0.875rem' }}>Selecione um período e pressione Filtrar</p>
                    </div>
                )}
            </div>
        </div>
    );
}
