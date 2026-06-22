import React, { useState, useEffect, useCallback } from 'react';
import { History, RefreshCw, Filter, Search, ArrowLeftRight, CheckCircle2, Clock, XCircle } from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

// ─── Status config ────────────────────────────────────────────────────────────
const STATUS = {
    synced:  { bg: 'var(--success-bg)', color: 'var(--success-text)', border: 'var(--success-border)', icon: CheckCircle2, label: 'Integrado' },
    pending: { bg: 'var(--warning-bg)', color: 'var(--warning-text)', border: 'var(--warning-border)', icon: Clock,         label: 'Pendente' },
    error:   { bg: 'var(--danger-bg)',  color: 'var(--danger-text)',  border: 'var(--danger-border)',  icon: XCircle,        label: 'Erro' },
};

const StatusBadge = ({ status }) => {
    const s = STATUS[status] || { bg: 'rgba(148,163,184,0.12)', color: 'var(--text-muted)', border: 'rgba(148,163,184,0.2)', icon: ArrowLeftRight, label: status };
    const Icon = s.icon;
    return (
        <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '3px 8px', borderRadius: 20,
            fontSize: '0.7rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em',
            background: s.bg, color: s.color, border: `1px solid ${s.border}`,
        }}>
            <Icon size={10} strokeWidth={2.5} />
            {s.label}
        </span>
    );
};

const dotColor = (status) => {
    if (status === 'synced')  return { bg: 'var(--success-bg)', border: 'var(--success-border)', dot: 'var(--success)' };
    if (status === 'pending') return { bg: 'var(--warning-bg)', border: 'var(--warning-border)', dot: 'var(--warning)' };
    if (status === 'error')   return { bg: 'var(--danger-bg)',  border: 'var(--danger-border)',  dot: 'var(--danger)' };
    return { bg: 'rgba(255,255,255,0.06)', border: 'var(--border)', dot: 'var(--text-hint)' };
};

/**
 * AuditTrail — Histórico de mudanças de status (timeline visual premium).
 */
export default function AuditTrail() {
    const [events, setEvents]     = useState([]);
    const [loading, setLoading]   = useState(false);
    const [error, setError]       = useState(null);
    const [orderId, setOrderId]   = useState('');
    const [page, setPage]         = useState(1);
    const [pagination, setPagination] = useState(null);
    const [statusFilter, setStatusFilter] = useState('');

    const fetchEvents = useCallback(async (p = 1) => {
        setLoading(true); setError(null);
        try {
            const data = await salesApiService.getEvents({ page: p, limit: 50, orderId });
            setEvents(data.events || []);
            setPagination(data.pagination || null);
            setPage(p);
        } catch (e) { setError(e.message); }
        finally { setLoading(false); }
    }, [orderId]);

    useEffect(() => { fetchEvents(1); }, []);

    const formatDate = (s) => {
        if (!s) return '—';
        try { return new Date(s).toLocaleString('pt-BR'); }
        catch { return s; }
    };

    const metadataDetail = (meta) => {
        if (!meta) return null;
        if (typeof meta === 'string') {
            try { meta = JSON.parse(meta); } catch { return meta; }
        }
        if (meta?.erpId)    return `ERP: ${meta.erpId}`;
        if (meta?.erp_id)   return `ERP: ${meta.erp_id}`;
        if (meta?.error)    return `Erro: ${String(meta.error).slice(0, 60)}`;
        const keys = Object.keys(meta);
        if (keys.length === 0) return null;
        return `${keys[0]}: ${String(meta[keys[0]]).slice(0, 60)}`;
    };

    const filteredEvents = events.filter(ev => !statusFilter || String(ev.new_status || '').toLowerCase() === statusFilter.toLowerCase());

    return (
        <div className="page-enter" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>

            {/* Header */}
            <div className="page-header">
                <div className="page-header-info">
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '0.25rem' }}>
                        <div style={{
                            width: 40, height: 40,
                            background: 'var(--gradient-primary)',
                            borderRadius: 'var(--radius-md)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            boxShadow: '0 0 24px rgba(27,143,205,0.30)',
                        }}>
                            <History size={20} color="white" />
                        </div>
                        <div>
                            <h1 style={{ margin: 0 }}>Audit Trail</h1>
                            <p className="page-subtext" style={{ margin: 0 }}>Histórico de mudanças de status dos pedidos</p>
                        </div>
                    </div>
                </div>
                <button onClick={() => fetchEvents(1)} disabled={loading} className="btn btn-outline hover-lift">
                    <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
                    Atualizar
                </button>
            </div>

            {/* Filtro */}
            <div className="card" style={{ padding: '1rem 1.25rem', display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
                <Filter size={14} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />
                <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', flex: 1, minWidth: 200 }}>
                    Filtrar por ID do Pedido
                    <input
                        value={orderId}
                        onChange={e => setOrderId(e.target.value)}
                        placeholder="UUID do pedido..."
                        className="input-field"
                        style={{ padding: '6px 10px', height: 36 }}
                        onKeyDown={e => e.key === 'Enter' && fetchEvents(1)}
                    />
                </label>
                <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8rem', color: 'var(--text-muted)', width: 180 }}>
                    Status
                    <select
                        value={statusFilter}
                        onChange={e => setStatusFilter(e.target.value)}
                        className="input-field"
                        style={{ padding: '6px 10px', height: 36, cursor: 'pointer' }}
                    >
                        <option value="">Todos</option>
                        <option value="synced">Integrado</option>
                        <option value="pending">Pendente</option>
                        <option value="error">Erro</option>
                    </select>
                </label>
                <button onClick={() => fetchEvents(1)} className="btn btn-primary" style={{ height: 36, padding: '0 1.25rem', alignSelf: 'flex-end' }}>
                    <Search size={14} />
                    Buscar
                </button>
            </div>

            {error && (
                <div style={{ padding: '0.875rem 1rem', background: 'var(--danger-bg)', color: 'var(--danger-text)', borderRadius: 'var(--radius-md)', border: '1px solid var(--danger-border)', fontSize: '0.875rem' }}>
                    ⚠ {error}
                </div>
            )}

            {/* Timeline */}
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                {/* Card header */}
                <div style={{
                    padding: '1rem 1.5rem',
                    borderBottom: '1px solid var(--border)',
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                }}>
                    <div style={{ fontWeight: 600, fontSize: '0.9375rem', color: 'var(--text-main)' }}>
                        Eventos
                        {pagination && (
                            <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)', fontWeight: 400, marginLeft: 8 }}>
                                ({pagination.total} total)
                            </span>
                        )}
                    </div>
                    {loading && <div style={{ width: 16, height: 16, border: '2px solid var(--border)', borderTopColor: 'var(--primary)', borderRadius: '50%', animation: 'spin 0.7s linear infinite' }} />}
                </div>

                {/* Table */}
                {filteredEvents.length > 0 ? (
                    <div style={{ overflowX: 'auto' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem' }}>
                            <thead>
                                <tr>
                                    {['Data/Hora', 'Pedido', 'Evento', 'Status Anterior', 'Novo Status', 'Detalhes'].map(h => (
                                        <th key={h} style={{
                                            padding: '0.75rem 1.25rem',
                                            textAlign: 'left',
                                            color: 'var(--text-hint)',
                                            fontSize: '0.675rem',
                                            fontWeight: 700,
                                            textTransform: 'uppercase',
                                            letterSpacing: '0.08em',
                                            borderBottom: '1px solid var(--border)',
                                            background: 'rgba(255,255,255,0.02)',
                                            whiteSpace: 'nowrap',
                                        }}>{h}</th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody>
                                {filteredEvents.map((ev, i) => (
                                    <tr key={ev.id || i}
                                        className="fade-slide-up"
                                        style={{ animationDelay: `${Math.min(i, 10) * 20}ms` }}
                                        onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.03)'}
                                        onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
                                    >
                                        <td style={{ padding: '0.875rem 1.25rem', color: 'var(--text-muted)', whiteSpace: 'nowrap', fontFamily: 'monospace', fontSize: '0.8rem' }}>
                                            {formatDate(ev.created_at)}
                                        </td>
                                        <td style={{ padding: '0.875rem 1.25rem' }}>
                                            <code style={{
                                                fontSize: '0.75rem', color: 'var(--accent-blue)',
                                                background: 'rgba(59,130,246,0.08)',
                                                padding: '2px 6px', borderRadius: 4,
                                            }}>
                                                {String(ev.order_id || '—').slice(0, 8)}…
                                            </code>
                                        </td>
                                        <td style={{ padding: '0.875rem 1.25rem' }}>
                                            <span style={{
                                                fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-sub)',
                                                background: 'rgba(255,255,255,0.05)',
                                                padding: '2px 8px', borderRadius: 4,
                                                border: '1px solid var(--border)',
                                            }}>
                                                {ev.event_type || '—'}
                                            </span>
                                        </td>
                                        <td style={{ padding: '0.875rem 1.25rem' }}>
                                            {ev.old_status ? <StatusBadge status={ev.old_status} /> : <span style={{ color: 'var(--text-hint)' }}>—</span>}
                                        </td>
                                        <td style={{ padding: '0.875rem 1.25rem' }}>
                                            {ev.new_status ? <StatusBadge status={ev.new_status} /> : <span style={{ color: 'var(--text-hint)' }}>—</span>}
                                        </td>
                                        <td style={{ padding: '0.875rem 1.25rem', color: 'var(--text-muted)', fontSize: '0.8rem', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                            {metadataDetail(ev.metadata) || '—'}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                ) : !loading ? (
                    <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                        <History size={36} style={{ opacity: 0.2, marginBottom: 12 }} />
                        <p style={{ fontSize: '0.875rem' }}>Nenhum evento encontrado</p>
                    </div>
                ) : (
                    <div style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                        {Array.from({ length: 5 }).map((_, i) => (
                            <div key={i} className="skeleton" style={{ height: 48, borderRadius: 'var(--radius-md)' }} />
                        ))}
                    </div>
                )}

                {/* Paginação */}
                {pagination && pagination.totalPages > 1 && (
                    <div style={{
                        padding: '1rem 1.5rem',
                        borderTop: '1px solid var(--border)',
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        gap: '1rem',
                    }}>
                        <span style={{ fontSize: '0.8125rem', color: 'var(--text-muted)' }}>
                            Página {page} de {pagination.totalPages}
                        </span>
                        <div style={{ display: 'flex', gap: '0.5rem' }}>
                            <button onClick={() => fetchEvents(page - 1)} disabled={page <= 1 || loading} className="btn btn-outline btn-sm">
                                ← Anterior
                            </button>
                            <button onClick={() => fetchEvents(page + 1)} disabled={page >= pagination.totalPages || loading} className="btn btn-outline btn-sm">
                                Próxima →
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}
