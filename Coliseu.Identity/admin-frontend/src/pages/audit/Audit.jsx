import React, { useState, useEffect, useCallback } from 'react';
import { Activity, Search, Filter, RefreshCw, ChevronLeft, ChevronRight, User, Download } from 'lucide-react';
import { getAuditLogs, AUDIT_ACTIONS } from '../../services/auditService';

const ACTION_COLORS = {
    'company.created':          { bg: 'rgba(34,197,94,0.15)',  text: '#22c55e' },
    'company.deleted':          { bg: 'rgba(239,68,68,0.15)',  text: '#ef4444' },
    'company.updated':          { bg: 'rgba(59,130,246,0.15)', text: '#3b82f6' },
    'company_active':           { bg: 'rgba(34,197,94,0.15)',  text: '#22c55e' },
    'company_suspended':        { bg: 'rgba(234,179,8,0.15)',  text: '#eab308' },
    'company_blocked':          { bg: 'rgba(239,68,68,0.15)',  text: '#ef4444' },
    'company_key_rotated':      { bg: 'rgba(234,179,8,0.15)',  text: '#eab308' },
    'company_logo_updated':     { bg: 'rgba(100,116,139,0.15)', text: '#94a3b8' },
    'device.activated':         { bg: 'rgba(59,130,246,0.15)', text: '#3b82f6' },
    'device.revoked':           { bg: 'rgba(239,68,68,0.15)',  text: '#ef4444' },
    'admin.login':              { bg: 'rgba(168,85,247,0.15)', text: '#a855f7' },
    'admin.login.2fa':          { bg: 'rgba(168,85,247,0.15)', text: '#a855f7' },
    'key.generated':            { bg: 'rgba(234,179,8,0.15)',  text: '#eab308' },
    'key.revoked':              { bg: 'rgba(239,68,68,0.15)',  text: '#ef4444' },
};

const ActionBadge = ({ action }) => {
    const style = ACTION_COLORS[action] || { bg: 'rgba(100,116,139,0.15)', text: '#94a3b8' };
    return (
        <span style={{
            padding: '2px 8px', borderRadius: '12px', fontSize: '0.75rem',
            fontWeight: 600, background: style.bg, color: style.text,
        }}>
            {action}
        </span>
    );
};

export default function Audit() {
    const [logs, setLogs] = useState([]);
    const [total, setTotal] = useState(0);
    const [page, setPage] = useState(1);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [filters, setFilters] = useState({ action: '', from: '', to: '', adminEmail: '' });

    const pageSize = 20;
    const totalPages = Math.max(1, Math.ceil(total / pageSize));

    const loadLogs = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const data = await getAuditLogs(page, pageSize, filters);
            setLogs(data.items ?? []);
            setTotal(data.total ?? 0);
        } catch (e) {
            setError(e.response?.data?.error ?? 'Erro ao carregar logs de auditoria.');
        } finally {
            setLoading(false);
        }
    }, [page, filters]);

    const exportToCSV = () => {
        if (!logs || logs.length === 0) {
            alert('Não há logs para exportar.');
            return;
        }
        const headers = ['Data/Hora', 'Ação', 'Usuário Admin', 'ID da Empresa', 'Detalhes'];
        const rows = logs.map(log => [
            log.createdAt ? new Date(log.createdAt).toLocaleString('pt-BR') : '',
            log.action || '',
            log.adminEmail || 'sistema',
            log.companyId || '',
            `"${(log.details || '').replace(/"/g, '""')}"`
        ]);
        const csvContent = [
            headers.join(','),
            ...rows.map(r => r.join(','))
        ].join('\n');
        
        const blob = new Blob(["\uFEFF" + csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.setAttribute('href', url);
        link.setAttribute('download', `auditoria_logs_${new Date().toISOString().slice(0, 10)}.csv`);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };

    useEffect(() => { loadLogs(); }, [loadLogs]);

    const handleFilterChange = (field, value) => {
        setFilters(f => ({ ...f, [field]: value }));
        setPage(1);
    };

    const formatDate = (iso) => {
        if (!iso) return '—';
        return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
    };

    const cardStyle = {
        background: 'var(--surface)',
        border: '1px solid var(--border)',
        borderRadius: '12px',
        padding: '1.5rem',
        marginBottom: '1.5rem',
    };

    return (
        <div className="animate-fade-in" style={{ padding: '2rem', maxWidth: '1200px' }}>
            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '2rem' }}>
                <Activity size={28} style={{ color: 'var(--accent)' }} />
                <div>
                    <h1 style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-main)', margin: 0 }}>
                        Auditoria do Sistema
                    </h1>
                    <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '0.875rem' }}>
                        Registro de todas as ações administrativas
                    </p>
                </div>
                <div style={{ marginLeft: 'auto', display: 'flex', gap: '0.5rem' }}>
                    <button onClick={exportToCSV} disabled={loading || logs.length === 0} style={{
                        background: 'var(--surface)', border: '1px solid var(--border)',
                        borderRadius: '8px', padding: '0.5rem 1rem', cursor: (loading || logs.length === 0) ? 'not-allowed' : 'pointer',
                        color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '0.5rem',
                    }}>
                        <Download size={14} />
                        Exportar CSV
                    </button>
                    <button onClick={loadLogs} disabled={loading} style={{
                        background: 'var(--surface)', border: '1px solid var(--border)',
                        borderRadius: '8px', padding: '0.5rem 1rem', cursor: 'pointer',
                        color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '0.5rem',
                    }}>
                        <RefreshCw size={14} className={loading ? 'spin' : ''} />
                        Atualizar
                    </button>
                </div>
            </div>

            {/* Filtros */}
            <div style={{ ...cardStyle, display: 'flex', gap: '1rem', flexWrap: 'wrap', alignItems: 'flex-end' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <Filter size={14} style={{ color: 'var(--text-muted)' }} />
                    <span style={{ color: 'var(--text-muted)', fontSize: '0.875rem', fontWeight: 600 }}>Filtros</span>
                </div>

                <div style={{ flex: 1, minWidth: '160px' }}>
                    <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '4px' }}>Ação</label>
                    <select
                        value={filters.action}
                        onChange={e => handleFilterChange('action', e.target.value)}
                        style={{ width: '100%', padding: '0.5rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--text-main)', fontSize: '0.875rem' }}
                    >
                        <option value="">Todas as ações</option>
                        {AUDIT_ACTIONS.map(a => <option key={a} value={a}>{a}</option>)}
                    </select>
                </div>

                <div style={{ flex: 1, minWidth: '160px' }}>
                    <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '4px' }}>Usuário Admin</label>
                    <input
                        type="text" placeholder="email@admin.com"
                        value={filters.adminEmail}
                        onChange={e => handleFilterChange('adminEmail', e.target.value)}
                        style={{ width: '100%', padding: '0.5rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--text-main)', fontSize: '0.875rem' }}
                    />
                </div>

                <div style={{ flex: 1, minWidth: '140px' }}>
                    <input type="date" value={filters.from} onChange={e => handleFilterChange('from', e.target.value)}
                        style={{ width: '100%', padding: '0.5rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--text-main)', fontSize: '0.875rem' }} />
                </div>

                <div style={{ flex: 1, minWidth: '140px' }}>
                    <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '4px' }}>Até</label>
                    <input type="date" value={filters.to} onChange={e => handleFilterChange('to', e.target.value)}
                        style={{ width: '100%', padding: '0.5rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--text-main)', fontSize: '0.875rem' }} />
                </div>

                <button onClick={() => { setFilters({ action: '', from: '', to: '', adminEmail: '' }); setPage(1); }}
                    style={{ padding: '0.5rem 1rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '0.875rem' }}>
                    Limpar
                </button>
            </div>

            {/* Tabela */}
            <div style={cardStyle}>
                {error && (
                    <div style={{ padding: '1rem', background: 'rgba(239,68,68,0.1)', borderRadius: '8px', color: '#ef4444', marginBottom: '1rem', fontSize: '0.875rem' }}>
                        {error}
                    </div>
                )}

                {loading ? (
                    <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--text-muted)' }}>
                        Carregando logs...
                    </div>
                ) : logs.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '3rem', color: 'var(--text-muted)' }}>
                        <Activity size={48} style={{ opacity: 0.2, marginBottom: '1rem' }} />
                        <p>Nenhum log encontrado com os filtros selecionados.</p>
                    </div>
                ) : (
                    <>
                        <div style={{ overflowX: 'auto' }}>
                            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem' }}>
                                <thead>
                                    <tr style={{ borderBottom: '1px solid var(--border)' }}>
                                        {['Data/Hora', 'Ação', 'Usuário', 'Empresa', 'Detalhes'].map(h => (
                                            <th key={h} style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-muted)', fontWeight: 600, fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                                                {h}
                                            </th>
                                        ))}
                                    </tr>
                                </thead>
                                <tbody>
                                    {logs.map((log, i) => (
                                        <tr key={log.id ?? i} style={{ borderBottom: '1px solid var(--border)', transition: 'background 0.15s' }}
                                            onMouseEnter={e => e.currentTarget.style.background = 'var(--surface-hover)'}
                                            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                                            <td style={{ padding: '0.75rem 1rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                                                {formatDate(log.createdAt)}
                                            </td>
                                            <td style={{ padding: '0.75rem 1rem' }}>
                                                <ActionBadge action={log.action} />
                                            </td>
                                            <td style={{ padding: '0.75rem 1rem', maxWidth: '160px' }}>
                                                {log.adminEmail ? (
                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem' }}>
                                                        <User size={12} color="var(--text-muted)" />
                                                        <span style={{ fontSize: '0.75rem', color: 'var(--text-main)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                                            {log.adminEmail}
                                                        </span>
                                                    </div>
                                                ) : (
                                                    <span style={{ color: 'var(--text-hint)', fontSize: '0.75rem' }}>sistema</span>
                                                )}
                                            </td>
                                            <td style={{ padding: '0.75rem 1rem', color: 'var(--text-main)', fontFamily: 'monospace', fontSize: '0.75rem' }}>
                                                {log.companyId ? log.companyId.substring(0, 8) + '…' : '—'}
                                            </td>
                                            <td style={{ padding: '0.75rem 1rem', color: 'var(--text-main)', maxWidth: '280px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={log.details}>
                                                {log.details ?? '—'}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>

                        {/* Paginação */}
                        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: '1rem', paddingTop: '1rem', borderTop: '1px solid var(--border)' }}>
                            <span style={{ fontSize: '0.875rem', color: 'var(--text-muted)' }}>
                                {total} registro{total !== 1 ? 's' : ''} · Página {page} de {totalPages}
                            </span>
                            <div style={{ display: 'flex', gap: '0.5rem' }}>
                                <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                                    style={{ padding: '0.35rem 0.75rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', cursor: page === 1 ? 'not-allowed' : 'pointer', color: 'var(--text-main)', opacity: page === 1 ? 0.4 : 1 }}>
                                    <ChevronLeft size={16} />
                                </button>
                                <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                                    style={{ padding: '0.35rem 0.75rem', borderRadius: '6px', border: '1px solid var(--border)', background: 'transparent', cursor: page === totalPages ? 'not-allowed' : 'pointer', color: 'var(--text-main)', opacity: page === totalPages ? 0.4 : 1 }}>
                                    <ChevronRight size={16} />
                                </button>
                            </div>
                        </div>
                    </>
                )}
            </div>
        </div>
    );
}
