import React, { useState, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
import {
    Server, RefreshCw, Activity, Settings, FileText,
    CheckCircle2, XCircle, AlertTriangle, Loader2,
    Clock, Shield, Zap, Database, TrendingUp,
    Package, Users, Building2, AlertCircle, Calendar, Eye, Trash2
} from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

/**
 * StatCard — Metric card premium dark com accent strip colorido.
 * @param {{ icon, label, value, gradient, sub }} props
 */
const StatCard = ({ icon: Icon, label, value, gradient, sub, delay = 0 }) => (
    <div
        className="metric-card fade-slide-up"
        style={{
            '--metric-accent': gradient || 'var(--gradient-primary)',
            animationDelay: `${delay}ms`,
        }}
    >
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
            <span className="metric-label">{label}</span>
            <div
                className="metric-icon"
                style={{ background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}
            >
                <Icon size={15} style={{ color: 'var(--text-muted)' }} />
            </div>
        </div>
        <div className="metric-value">{value ?? '—'}</div>
        {sub && <div style={{ fontSize: '0.75rem', color: 'var(--text-hint)', marginTop: '0.25rem' }}>{sub}</div>}
    </div>
);

// ─── Tab: Status ─────────────────────────────────────────────────────────────
function TabStatus({ stats, healthData, isLoading, onRefresh }) {
    const formatUptime = (s) => {
        if (!s) return '—';
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        return d > 0 ? `${d}d ${h}h ${m}m` : h > 0 ? `${h}h ${m}m` : `${m}m`;
    };

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.75rem' }}>

            {/* Saúde geral */}
            <div className={healthData ? 'status-banner-online' : 'status-banner-offline'}>
                {healthData ? (
                    <>
                        <div style={{
                            width: 42, height: 42, borderRadius: '50%',
                            background: 'var(--success-bg)', border: '2px solid var(--success-border)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            flexShrink: 0,
                        }}>
                            <div className="status-dot status-dot-green glow-pulse" style={{ width: 12, height: 12 }} />
                        </div>
                        <div style={{ flex: 1 }}>
                            <div style={{ fontWeight: 700, color: 'var(--success-text)', fontSize: '0.9375rem' }}>Sales API Online</div>
                            <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: 2 }}>
                                DB: {healthData.db || 'ok'} · Uptime: {formatUptime(stats?.uptime)} · Última sync: {new Date().toLocaleTimeString('pt-BR')}
                            </div>
                        </div>
                    </>
                ) : (
                    <>
                        <XCircle size={22} style={{ color: 'var(--danger-text)', flexShrink: 0 }} />
                        <div>
                            <div style={{ fontWeight: 700, color: 'var(--danger-text)' }}>Sales API Offline</div>
                            <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: 2 }}>Verifique se o serviço está rodando na VPS</div>
                        </div>
                    </>
                )}
                <button
                    onClick={onRefresh}
                    disabled={isLoading}
                    className="btn-icon"
                    style={{ marginLeft: 'auto' }}
                    title="Atualizar"
                >
                    <RefreshCw size={15} className={isLoading ? 'animate-spin' : ''} />
                </button>
            </div>

            {/* KPIs de pedidos */}
            <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem' }}>
                    <Package size={16} style={{ color: 'var(--primary-light)' }} />
                    <h3 style={{ margin: 0, fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-sub)' }}>Pedidos</h3>
                </div>
                <div className="metrics-grid-5">
                    <StatCard icon={TrendingUp} label="Total"       value={stats?.orders?.total}      gradient="var(--gradient-primary)" delay={0} />
                    <StatCard icon={Clock}      label="Pendentes"    value={stats?.orders?.pending}    gradient="var(--gradient-amber)"   delay={50} />
                    <StatCard icon={Zap}        label="Processando"  value={stats?.orders?.processing} gradient="var(--gradient-blue)"    delay={100} />
                    <StatCard icon={CheckCircle2} label="Sincronizados" value={stats?.orders?.synced}  gradient="var(--gradient-green)"   delay={150} />
                    <StatCard icon={XCircle}    label="Erros"        value={stats?.orders?.error}      gradient="var(--gradient-rose)"    delay={200} />
                </div>
            </div>

            {/* Catálogo e Empresas */}
            <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '1rem' }}>
                    <Database size={16} style={{ color: 'var(--accent-cyan)' }} />
                    <h3 style={{ margin: 0, fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-sub)' }}>Catálogo e Empresas</h3>
                </div>
                <div className="metrics-grid-3">
                    <StatCard icon={Package}    label="Produtos"  value={stats?.catalog?.products?.toLocaleString('pt-BR')}  gradient="var(--gradient-primary)" delay={0} />
                    <StatCard icon={Users}      label="Clientes"  value={stats?.catalog?.customers?.toLocaleString('pt-BR')} gradient="linear-gradient(135deg,#06B6D4,#3B82F6)"  delay={50} />
                    <StatCard icon={Building2}  label="Empresas"  value={stats?.companies}                                    gradient="linear-gradient(135deg,#10B981,#06B6D4)"  delay={100} />
                </div>
                {stats?.lastSync && (
                    <div style={{ textAlign: 'right', fontSize: '0.75rem', color: 'var(--text-hint)', marginTop: '0.75rem' }}>
                        Último sync bem-sucedido: <strong style={{ color: 'var(--text-muted)' }}>{new Date(stats.lastSync).toLocaleString('pt-BR')}</strong>
                    </div>
                )}
            </div>
        </div>
    );
}

// ─── Tab: Configuração ──────────────────────────────────────────────────────
function TabConfig({ config }) {
    if (!config) return (
        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Settings size={32} style={{ opacity: 0.3, marginBottom: 12 }} /><br />
            Configurações não disponíveis
        </div>
    );
    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            {Object.entries(config).map(([k, v]) => (
                <div key={k} style={{
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                    padding: '0.75rem 1rem',
                    background: 'var(--glass-bg)', border: '1px solid var(--glass-border)',
                    borderRadius: 'var(--radius-md)',
                }}>
                    <span style={{ fontSize: '0.8125rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{k}</span>
                    <span style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)' }}>
                        {typeof v === 'object' && v !== null ? JSON.stringify(v) : String(v)}
                    </span>
                </div>
            ))}
        </div>
    );
}

// ─── Tab: Logs ───────────────────────────────────────────────────────────────
const methodBadge = (m) => {
    const colors = { GET: '#22c55e', POST: '#3b82f6', PUT: '#f59e0b', DELETE: '#ef4444', PATCH: '#1B8FCD' };
    const c = colors[m] ?? '#94a3b8';
    return (
        <span style={{
            display: 'inline-block', padding: '1px 7px', borderRadius: 4,
            fontSize: '0.65rem', fontWeight: 700, letterSpacing: '0.05em',
            background: c + '22', color: c, border: `1px solid ${c}44`,
        }}>{m}</span>
    );
};

function TabLogs({ logs }) {
    if (!logs?.length) return (
        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
            <FileText size={32} style={{ opacity: 0.3, marginBottom: 12 }} /><br />Sem logs recentes
        </div>
    );
    return (
        <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.8125rem' }}>
                <thead>
                    <tr>
                        {['Hora', 'Método', 'Rota', 'Status', 'ms', 'Empresa'].map(h => (
                            <th key={h} style={{
                                padding: '0.625rem 1rem', textAlign: 'left',
                                color: 'var(--text-hint)', fontSize: '0.68rem',
                                fontWeight: 700, textTransform: 'uppercase',
                                letterSpacing: '0.08em',
                                borderBottom: '1px solid var(--border)',
                                background: 'rgba(255,255,255,0.02)',
                            }}>{h}</th>
                        ))}
                    </tr>
                </thead>
                <tbody>
                    {logs.map((log, i) => (
                        <tr key={i} style={{ transition: 'background var(--t-fast)' }}
                            onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.03)'}
                            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
                        >
                            <td style={{ padding: '0.625rem 1rem', color: 'var(--text-muted)', fontFamily: 'monospace', whiteSpace: 'nowrap' }}>
                                {log.timestamp ? new Date(log.timestamp).toLocaleTimeString('pt-BR') : '—'}
                            </td>
                            <td style={{ padding: '0.625rem 1rem' }}>{methodBadge(log.method)}</td>
                            <td style={{ padding: '0.625rem 1rem', color: 'var(--text-sub)', fontFamily: 'monospace', fontSize: '0.75rem', maxWidth: 240, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {log.path || log.route || '—'}
                            </td>
                            <td style={{ padding: '0.625rem 1rem' }}>
                                <span style={{
                                    padding: '1px 7px', borderRadius: 4, fontSize: '0.72rem', fontWeight: 700,
                                    background: log.status >= 400 ? 'var(--danger-bg)' : 'var(--success-bg)',
                                    color: log.status >= 400 ? 'var(--danger-text)' : 'var(--success-text)',
                                }}>{log.status || '—'}</span>
                            </td>
                            <td style={{ padding: '0.625rem 1rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{log.duration ?? log.ms ?? '—'}</td>
                            <td style={{ padding: '0.625rem 1rem', color: 'var(--text-hint)', fontSize: '0.75rem', maxWidth: 160, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                {log.company || log.companyId || '—'}
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    );
}

// ─── Tab: Fila & Pendências ──────────────────────────────────────────────────
function TabStuckOrders({ stuckOrders, stuckCustomers, isLoading, stuckError, onRefresh, from, to, setFrom, setTo }) {
    const [selectedItem, setSelectedItem] = useState(null);
    const [retrying, setRetrying] = useState(null);
    const [deleting, setDeleting] = useState(null);
    const [bulkProgress, setBulkProgress] = useState(null);
    const [bulkType, setBulkType] = useState(null);

    const handleRetry = async (id, isCustomer) => {
        if (!window.confirm('Tem certeza que deseja liberar este item para reprocessamento na fila?')) return;
        setRetrying(id);
        try {
            if (isCustomer) await salesApiService.retryStuckCustomer(id);
            else await salesApiService.retryStuckOrder(id);
            
            // Recarrega apos 1 seg para dar tempo do backend mudar
            setTimeout(onRefresh, 500);
            if (selectedItem && (selectedItem.id === id || selectedItem.localId === id)) {
                setSelectedItem(null);
            }
        } catch (err) {
            alert('Falha ao tentar liberar: ' + (err.response?.data?.error || err.message));
        } finally {
            setRetrying(null);
        }
    };

    const handleDelete = async (id, isCustomer) => {
        const msg = isCustomer 
            ? 'Tem certeza que deseja descartar este cliente travado? Ele será removido definitivamente da fila de integração.'
            : 'Tem certeza que deseja descartar este pedido? O status dele será marcado como sincronizado e ele será removido da fila ativa.';
        
        if (!window.confirm(msg)) return;
        
        setDeleting(id);
        try {
            if (isCustomer) await salesApiService.deleteStuckCustomer(id);
            else await salesApiService.deleteStuckOrder(id);
            
            setTimeout(onRefresh, 500);
            if (selectedItem && (selectedItem.id === id || selectedItem.localId === id)) {
                setSelectedItem(null);
            }
        } catch (err) {
            alert('Falha ao tentar descartar: ' + (err.response?.data?.error || err.message));
        } finally {
            setDeleting(null);
        }
    };

    const handleBulkRetry = async (isCustomer) => {
        const items = isCustomer ? stuckCustomers : stuckOrders;
        if (!items || items.length === 0) return;

        const targetItems = items.slice(0, 50);
        const total = targetItems.length;

        if (!window.confirm(`Tem certeza que deseja liberar estes ${total} itens em lote para reprocessamento na fila?`)) return;

        setBulkType(isCustomer ? 'customers' : 'orders');
        setBulkProgress({ current: 0, total });

        try {
            for (let i = 0; i < total; i++) {
                const item = targetItems[i];
                const id = isCustomer ? item.localId : item.id;
                setBulkProgress({ current: i + 1, total });
                try {
                    if (isCustomer) {
                        await salesApiService.retryStuckCustomer(id);
                    } else {
                        await salesApiService.retryStuckOrder(id);
                    }
                } catch (err) {
                    console.error(`Erro ao processar item ${id}:`, err);
                }
                await new Promise(resolve => setTimeout(resolve, 100));
            }
            setTimeout(onRefresh, 500);
        } catch (err) {
            alert('Erro no reprocessamento em lote: ' + err.message);
        } finally {
            setBulkProgress(null);
            setBulkType(null);
        }
    };

    if (isLoading && !stuckOrders?.length && !stuckCustomers?.length) return (
        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
            <Loader2 size={32} className="animate-spin" style={{ opacity: 0.5, margin: '0 auto 12px' }} />
            Buscando gargalos...
        </div>
    );

    const hasOrders = stuckOrders?.length > 0;
    const hasCustomers = stuckCustomers?.length > 0;

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2rem' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', flexWrap: 'wrap' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.8125rem', color: 'var(--text-muted)' }}>
                        <Calendar size={14} />
                        <span>De</span>
                    </div>
                    <input type="date" value={from} onChange={e => setFrom(e.target.value)} className="input-field" style={{ width: 145, height: 36, fontSize: '0.8125rem' }} />
                    <span style={{ fontSize: '0.8125rem', color: 'var(--text-hint)' }}>Até</span>
                    <input type="date" value={to} onChange={e => setTo(e.target.value)} className="input-field" style={{ width: 145, height: 36, fontSize: '0.8125rem' }} />
                    <button onClick={onRefresh} disabled={isLoading || !!bulkType} className="btn btn-primary" style={{ height: 36 }}>
                        <RefreshCw size={14} className={(isLoading || !!bulkType) ? 'animate-spin' : ''} />
                        Atualizar
                    </button>
                    <button 
                        onClick={() => { setFrom('all'); setTimeout(onRefresh, 100); }} 
                        disabled={isLoading || !!bulkType} 
                        style={{ height: 36, background: 'transparent', border: '1px dashed var(--border)', color: 'var(--text-sub)', padding: '0 12px', borderRadius: 'var(--radius-md)', fontSize: '0.8125rem', display: 'flex', alignItems: 'center', gap: 6, cursor: (isLoading || !!bulkType) ? 'not-allowed' : 'pointer' }}>
                        <span style={{ fontSize: 16 }}>👻</span> Buscar Todo Histórico
                    </button>
                </div>
            </div>

            {!hasOrders && !hasCustomers ? (
                stuckError ? (
                    <div style={{ padding: '3rem 2rem', textAlign: 'center', color: 'var(--danger-text)' }}>
                        <XCircle size={40} style={{ opacity: 0.5, marginBottom: 12 }} /><br />
                        <span style={{ fontSize: '1.1rem', fontWeight: 600 }}>Erro no Servidor</span>
                        <p style={{ fontSize: '0.875rem', marginTop: 4 }}>{typeof stuckError === 'object' ? JSON.stringify(stuckError) : String(stuckError)}</p>
                    </div>
                ) : (
                    <div style={{ padding: '3rem 2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                        <CheckCircle2 size={40} style={{ opacity: 0.3, marginBottom: 12, color: 'var(--success-text)' }} /><br />
                        <span style={{ fontSize: '1.1rem', fontWeight: 600 }}>Fila Limpa</span>
                        <p style={{ fontSize: '0.875rem', marginTop: 4 }}>Nenhum detalhe travado neste período.</p>
                    </div>
                )
            ) : (
                <>

            {hasOrders && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
                        <h3 style={{ margin: 0, fontSize: '0.9rem', color: 'var(--text-sub)' }}>Pedidos Retidos (Pending/Error)</h3>
                        {bulkType === 'orders' && bulkProgress ? (
                            <span style={{ fontSize: '0.8rem', color: 'var(--amber-text)', display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'var(--amber-bg)', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(245, 158, 11, 0.2)' }}>
                                <Loader2 size={12} className="animate-spin" />
                                Reprocessando: {bulkProgress.current} de {bulkProgress.total}
                            </span>
                        ) : (
                            <button
                                onClick={() => handleBulkRetry(false)}
                                disabled={!!bulkType || isLoading}
                                className="btn"
                                style={{
                                    padding: '5px 12px',
                                    fontSize: '0.75rem',
                                    background: 'var(--amber-bg)',
                                    color: 'var(--amber-text)',
                                    border: '1px solid rgba(245, 158, 11, 0.2)',
                                    borderRadius: '6px',
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '0.375rem',
                                    cursor: (bulkType || isLoading) ? 'not-allowed' : 'pointer'
                                }}
                            >
                                <Zap size={12} />
                                Reprocessar Lote (Máx 50)
                            </button>
                        )}
                    </div>
                    <div style={{ overflowX: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-md)' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.8125rem' }}>
                            <thead>
                                <tr style={{ background: 'var(--glass-bg-strong)', borderBottom: '1px solid var(--border)' }}>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Ped. ID</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Cliente</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Status</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Tempo Preso</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Motivo / Erro</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'center', color: 'var(--text-hint)' }}>Ação</th>
                                </tr>
                            </thead>
                            <tbody>
                                {stuckOrders.map((order, i) => (
                                    <tr key={i} style={{ borderBottom: '1px solid var(--glass-border)' }}>
                                        <td style={{ padding: '0.75rem 1rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                                            {order.id.substring(0, 8)}...
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', fontWeight: 500 }}>{order.customerName || 'S/N'}</td>
                                        <td style={{ padding: '0.75rem 1rem' }}>
                                            <span style={{
                                                padding: '2px 8px', borderRadius: 4, fontSize: '0.7rem', fontWeight: 600,
                                                background: order.status === 'error' ? 'var(--danger-bg)' : 'var(--amber-bg)',
                                                color: order.status === 'error' ? 'var(--danger-text)' : 'var(--amber-text)'
                                            }}>
                                                {order.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', color: order.elapsedMinutes > 30 ? 'var(--danger-text)' : 'var(--text-sub)' }}>
                                            {order.elapsedMinutes} mins
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', color: 'var(--danger-text)', maxWidth: 250, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={order.errorMessage}>
                                            {order.errorMessage || '—'}
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', textAlign: 'center' }}>
                                            <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                                                <button onClick={() => setSelectedItem({ type: 'order', data: order })} className="btn btn-secondary" style={{ padding: '4px 8px', fontSize: '0.75rem' }} title="Detalhes">
                                                    <Eye size={14} />
                                                </button>
                                                <button onClick={() => handleRetry(order.id, false)} disabled={deleting === order.id || retrying === order.id || !!bulkType} className="btn" style={{ padding: '4px 8px', fontSize: '0.75rem', background: 'var(--amber-bg)', color: 'var(--amber-text)', border: 'none', cursor: (deleting === order.id || retrying === order.id || !!bulkType) ? 'not-allowed' : 'pointer' }} title="Liberar para Processar">
                                                    {retrying === order.id ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
                                                </button>
                                                <button onClick={() => handleDelete(order.id, false)} disabled={deleting === order.id || retrying === order.id || !!bulkType} className="btn" style={{ padding: '4px 8px', fontSize: '0.75rem', background: 'var(--danger-bg)', color: 'var(--danger-text)', border: 'none', cursor: (deleting === order.id || retrying === order.id || !!bulkType) ? 'not-allowed' : 'pointer' }} title="Descartar da Fila">
                                                    {deleting === order.id ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            {hasCustomers && (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '0.5rem' }}>
                        <h3 style={{ margin: 0, fontSize: '0.9rem', color: 'var(--text-sub)' }}>Clientes Retidos (Falha no Cadastro)</h3>
                        {bulkType === 'customers' && bulkProgress ? (
                            <span style={{ fontSize: '0.8rem', color: 'var(--amber-text)', display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'var(--amber-bg)', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(245, 158, 11, 0.2)' }}>
                                <Loader2 size={12} className="animate-spin" />
                                Reprocessando: {bulkProgress.current} de {bulkProgress.total}
                            </span>
                        ) : (
                            <button
                                onClick={() => handleBulkRetry(true)}
                                disabled={!!bulkType || isLoading}
                                className="btn"
                                style={{
                                    padding: '5px 12px',
                                    fontSize: '0.75rem',
                                    background: 'var(--amber-bg)',
                                    color: 'var(--amber-text)',
                                    border: '1px solid rgba(245, 158, 11, 0.2)',
                                    borderRadius: '6px',
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '0.375rem',
                                    cursor: (bulkType || isLoading) ? 'not-allowed' : 'pointer'
                                }}
                            >
                                <Zap size={12} />
                                Reprocessar Lote (Máx 50)
                            </button>
                        )}
                    </div>
                    <div style={{ overflowX: 'auto', border: '1px solid var(--border)', borderRadius: 'var(--radius-md)' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.8125rem' }}>
                            <thead>
                                <tr style={{ background: 'var(--glass-bg-strong)', borderBottom: '1px solid var(--border)' }}>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Local ID</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Cliente</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Documento</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Status</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Tempo Preso</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'left', color: 'var(--text-hint)' }}>Erro Encontrado</th>
                                    <th style={{ padding: '0.75rem 1rem', textAlign: 'center', color: 'var(--text-hint)' }}>Ação</th>
                                </tr>
                            </thead>
                            <tbody>
                                {stuckCustomers.map((cust, i) => {
                                    const payload = cust.payload;
                                    const name = payload?.name || payload?.nm_pessoa || 'S/N';
                                    const cnpjc = payload?.cnpj || payload?.cd_cpf_cnpj || '—';
                                    
                                    return (
                                    <tr key={i} style={{ borderBottom: '1px solid var(--glass-border)' }}>
                                        <td style={{ padding: '0.75rem 1rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                                            {cust.localId || '—'}
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', fontWeight: 500 }}>{name}</td>
                                        <td style={{ padding: '0.75rem 1rem', color: 'var(--text-muted)' }}>{cnpjc}</td>
                                        <td style={{ padding: '0.75rem 1rem' }}>
                                            <span style={{
                                                padding: '2px 8px', borderRadius: 4, fontSize: '0.7rem', fontWeight: 600,
                                                background: cust.status === 'error' ? 'var(--danger-bg)' : 'var(--amber-bg)',
                                                color: cust.status === 'error' ? 'var(--danger-text)' : 'var(--amber-text)'
                                            }}>
                                                {cust.status.toUpperCase()}
                                            </span>
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', color: cust.elapsedMinutes > 30 ? 'var(--danger-text)' : 'var(--text-sub)' }}>
                                            {cust.elapsedMinutes} mins
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', color: 'var(--danger-text)', maxWidth: 250, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={cust.errorMessage}>
                                            {cust.errorMessage || '—'}
                                        </td>
                                        <td style={{ padding: '0.75rem 1rem', textAlign: 'center' }}>
                                            <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'center' }}>
                                                <button onClick={() => setSelectedItem({ type: 'customer', data: cust })} className="btn btn-secondary" style={{ padding: '4px 8px', fontSize: '0.75rem' }} title="Detalhes">
                                                    <Eye size={14} />
                                                </button>
                                                <button onClick={() => handleRetry(cust.localId, true)} disabled={deleting === cust.localId || retrying === cust.localId || !!bulkType} className="btn" style={{ padding: '4px 8px', fontSize: '0.75rem', background: 'var(--amber-bg)', color: 'var(--amber-text)', border: 'none', cursor: (deleting === cust.localId || retrying === cust.localId || !!bulkType) ? 'not-allowed' : 'pointer' }} title="Liberar para Processar">
                                                    {retrying === cust.localId ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
                                                </button>
                                                <button onClick={() => handleDelete(cust.localId, true)} disabled={deleting === cust.localId || retrying === cust.localId || !!bulkType} className="btn" style={{ padding: '4px 8px', fontSize: '0.75rem', background: 'var(--danger-bg)', color: 'var(--danger-text)', border: 'none', cursor: (deleting === cust.localId || retrying === cust.localId || !!bulkType) ? 'not-allowed' : 'pointer' }} title="Descartar da Fila">
                                                    {deleting === cust.localId ? <Loader2 size={14} className="animate-spin" /> : <Trash2 size={14} />}
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}
                </>
            )}

            {/* Modal de Detalhes */}
            {selectedItem && (() => {
                const getErrorDiagnosis = (errorStr) => {
                    if (!errorStr) return {
                        diagnosis: "O item está pendente na fila, mas nenhuma mensagem de erro foi reportada ainda.",
                        solution: "Aguarde o processamento automático do Worker ou clique em 'Liberar na Fila' para forçar uma nova tentativa."
                    };

                    const err = errorStr.toLowerCase();

                    if (err.includes("multiple rows in singleton select")) {
                        return {
                            diagnosis: "Busca retornou múltiplos registros duplicados no banco de dados Firebird (Stored Procedure).",
                            solution: "Geralmente ocorre por haver mais de um cliente cadastrado com o mesmo CPF/CNPJ, ou duplicidade no código interno. Verifique no ERP e remova o cadastro duplicado."
                        };
                    }
                    if (err.includes("lock conflict") || err.includes("deadlock") || err.includes("update conflict")) {
                        return {
                            diagnosis: "Bloqueio ou conflito de transação simultânea no banco de dados (o registro estava travado por outro processo).",
                            solution: "Esse erro é temporário. Você pode clicar no botão de 'Liberar na Fila (Retry)' para reprocessar com segurança."
                        };
                    }
                    if (err.includes("validation error") || err.includes("value exceeds size") || err.includes("string right truncation")) {
                        return {
                            diagnosis: "Erro de validação de tamanho de dado. Algum campo (como nome, endereço ou e-mail) excede o limite máximo de caracteres no ERP.",
                            solution: "Verifique os dados cadastrais no payload JSON abaixo. Ajuste o campo que estiver longo demais no ERP ou no app e reprocesso o item."
                        };
                    }
                    if (err.includes("foreign key") || err.includes("violation of foreign key")) {
                        return {
                            diagnosis: "Erro de integridade referencial. Algum código enviado (como portador, vendedor, condição de pagamento ou filial) não existe cadastrado no ERP.",
                            solution: "Verifique os códigos vinculados no payload JSON. Cadastre a entidade correspondente no ERP (ex: vendedor com ID correto) e reprocesso."
                        };
                    }
                    if (err.includes("not null") || err.includes("required field") || err.includes("must be provided")) {
                        return {
                            diagnosis: "Erro de campo obrigatório ausente. Uma informação indispensável para o cadastro do ERP não foi preenchida.",
                            solution: "Verifique qual campo está nulo no payload JSON (por exemplo, 'bairro', 'município' ou 'cnpj') e complete-o para liberar o cadastro."
                        };
                    }

                    return {
                        diagnosis: "Ocorreu um erro técnico de execução da Stored Procedure ou Query no ERP.",
                        solution: "Analise a mensagem do Worker e verifique os logs locais do sistema para corrigir a inconsistência correspondente."
                    };
                };

                const diag = getErrorDiagnosis(selectedItem.data.errorMessage);

                return createPortal(
                    <div style={{
                        position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, 
                        background: 'rgba(10, 15, 30, 0.75)', backdropFilter: 'blur(8px)', 
                        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 10000,
                        padding: '1.5rem'
                    }} onClick={() => setSelectedItem(null)}>
                        <div className="card" style={{ 
                            width: '100%', maxWidth: 750, maxHeight: '92vh', overflowY: 'auto',
                            background: '#111622', border: '1px solid var(--border)',
                            borderRadius: '16px', boxShadow: '0 20px 40px rgba(0, 0, 0, 0.5)'
                        }} onClick={e => e.stopPropagation()}>
                            
                            {/* Modal Header */}
                            <div style={{ 
                                display: 'flex', justifyContent: 'space-between', alignItems: 'center', 
                                padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--border)',
                                background: 'rgba(255,255,255,0.01)'
                            }}>
                                <h3 style={{ margin: 0, fontSize: '1.1rem', display: 'flex', alignItems: 'center', gap: 10, fontWeight: 700, color: 'var(--text-main)' }}>
                                    <FileText size={20} className="text-primary" />
                                    Detalhes do {selectedItem.type === 'order' ? 'Pedido' : 'Cliente'} Retido
                                </h3>
                                <button onClick={() => setSelectedItem(null)} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', transition: 'color 0.2s' }}>
                                    <XCircle size={22} />
                                </button>
                            </div>
                            
                            <div style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
                                
                                {/* Meta cards grid */}
                                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '0.75rem' }}>
                                    <div style={{ background: 'rgba(255,255,255,0.02)', border: '1px solid var(--border)', borderRadius: '10px', padding: '0.75rem 1rem' }}>
                                        <span style={{ fontSize: '0.7rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600, display: 'block', marginBottom: '2px' }}>Empresa</span>
                                        <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-sub)' }}>{selectedItem.data.companyName || 'Desconhecida'}</span>
                                    </div>
                                    <div style={{ background: 'rgba(255,255,255,0.02)', border: '1px solid var(--border)', borderRadius: '10px', padding: '0.75rem 1rem' }}>
                                        <span style={{ fontSize: '0.7rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600, display: 'block', marginBottom: '2px' }}>Ocorrido Em</span>
                                        <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-sub)' }}>{selectedItem.data.createdAt ? new Date(selectedItem.data.createdAt).toLocaleString('pt-BR') : '—'}</span>
                                    </div>
                                    <div style={{ background: 'rgba(255,255,255,0.02)', border: '1px solid var(--border)', borderRadius: '10px', padding: '0.75rem 1rem' }}>
                                        <span style={{ fontSize: '0.7rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600, display: 'block', marginBottom: '2px' }}>Tempo Retido</span>
                                        <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-sub)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                            <Clock size={12} className="text-warning" />
                                            {selectedItem.data.elapsedMinutes} minutos
                                        </span>
                                    </div>
                                </div>

                                {/* ID Original */}
                                <div>
                                    <h4 style={{ margin: '0 0 6px 0', fontSize: '0.8rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600 }}>ID Original</h4>
                                    <code style={{ display: 'block', padding: '8px 12px', background: 'var(--bg-subtle)', border: '1px solid var(--border)', borderRadius: 8, fontSize: '0.85rem', color: 'var(--text-muted)', fontFamily: 'monospace' }}>
                                        {selectedItem.data.id || selectedItem.data.localId}
                                    </code>
                                </div>

                                {/* Diagnostic Section */}
                                <div style={{ 
                                    background: 'rgba(59, 130, 246, 0.05)', 
                                    border: '1px solid rgba(59, 130, 246, 0.25)', 
                                    borderRadius: '12px', 
                                    padding: '1.25rem',
                                    display: 'flex',
                                    flexDirection: 'column',
                                    gap: '0.75rem'
                                }}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                        <Zap size={16} style={{ color: '#3b82f6' }} />
                                        <span style={{ fontWeight: 700, fontSize: '0.875rem', color: '#60a5fa' }}>Diagnóstico & Resolução (Recomendado)</span>
                                    </div>
                                    <div style={{ fontSize: '0.85rem', lineHeight: '1.4' }}>
                                        <strong style={{ color: 'var(--text-main)', display: 'block', marginBottom: '2px' }}>Problema Detectado:</strong>
                                        <span style={{ color: 'var(--text-sub)' }}>{diag.diagnosis}</span>
                                    </div>
                                    <div style={{ fontSize: '0.85rem', lineHeight: '1.4', background: 'rgba(59, 130, 246, 0.08)', padding: '10px 12px', borderRadius: '8px' }}>
                                        <strong style={{ color: 'var(--text-main)', display: 'block', marginBottom: '2px' }}>Como resolver:</strong>
                                        <span style={{ color: 'var(--text-sub)' }}>{diag.solution}</span>
                                    </div>
                                </div>

                                {/* Raw Technical Error Message */}
                                <div>
                                    <h4 style={{ margin: '0 0 6px 0', fontSize: '0.8rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600 }}>Mensagem Técnica do Worker (Inglês)</h4>
                                    <div style={{ 
                                        background: 'var(--danger-bg)', 
                                        border: '1px solid rgba(239, 68, 68, 0.2)', 
                                        padding: '12px 16px', 
                                        borderRadius: 8, 
                                        color: 'var(--danger-text)', 
                                        whiteSpace: 'pre-wrap', 
                                        fontSize: '0.825rem',
                                        fontFamily: 'monospace',
                                        lineHeight: '1.4'
                                    }}>
                                        {selectedItem.data.errorMessage || 'Sem erro detalhado reportado pelo Worker.'}
                                    </div>
                                </div>

                                {/* Payload JSON */}
                                {selectedItem.data.payload && (
                                    <div>
                                        <h4 style={{ margin: '0 0 6px 0', fontSize: '0.8rem', color: 'var(--text-hint)', textTransform: 'uppercase', fontWeight: 600 }}>Dados de Payload (JSON)</h4>
                                        <pre style={{ 
                                            margin: 0, 
                                            padding: '12px 16px', 
                                            background: 'var(--bg-subtle)', 
                                            border: '1px solid var(--border)', 
                                            borderRadius: 8, 
                                            fontSize: '0.8rem', 
                                            color: 'var(--text-muted)', 
                                            maxHeight: 200, 
                                            overflow: 'auto',
                                            fontFamily: 'monospace'
                                        }}>
                                            {typeof selectedItem.data.payload === 'string' 
                                                ? JSON.stringify(JSON.parse(selectedItem.data.payload), null, 2) 
                                                : JSON.stringify(selectedItem.data.payload, null, 2)}
                                        </pre>
                                    </div>
                                )}

                            </div>
                            
                            {/* Modal Footer */}
                            <div style={{ 
                                padding: '1rem 1.5rem', 
                                borderTop: '1px solid var(--border)', 
                                display: 'flex', 
                                justifyContent: 'flex-end', 
                                gap: '0.75rem', 
                                background: 'rgba(0,0,0,0.1)' 
                            }}>
                                <button className="btn btn-secondary" onClick={() => setSelectedItem(null)} style={{ padding: '0 1.25rem', height: 38, borderRadius: 8 }}>Fechar</button>
                                <button 
                                    className="btn" 
                                    style={{ 
                                        background: 'var(--danger-bg)', 
                                        color: 'var(--danger-text)', 
                                        border: '1px solid rgba(239,68,68,0.2)', 
                                        cursor: (deleting === (selectedItem.data.id || selectedItem.data.localId) || retrying === (selectedItem.data.id || selectedItem.data.localId) || !!bulkType) ? 'not-allowed' : 'pointer',
                                        padding: '0 1.25rem',
                                        height: 38,
                                        borderRadius: 8,
                                        display: 'flex',
                                        alignItems: 'center',
                                        gap: '6px'
                                    }}
                                    onClick={() => handleDelete(selectedItem.data.id || selectedItem.data.localId, selectedItem.type === 'customer')}
                                    disabled={deleting === (selectedItem.data.id || selectedItem.data.localId) || retrying === (selectedItem.data.id || selectedItem.data.localId) || !!bulkType}
                                >
                                    {deleting === (selectedItem.data.id || selectedItem.data.localId) ? <Loader2 size={16} className="animate-spin" /> : <Trash2 size={16} />}
                                    Descartar da Fila
                                </button>
                                <button 
                                    className="btn" 
                                    style={{ 
                                        background: 'var(--amber-bg)', 
                                        color: 'var(--amber-text)', 
                                        border: '1px solid rgba(245,158,11,0.2)', 
                                        cursor: (deleting === (selectedItem.data.id || selectedItem.data.localId) || retrying === (selectedItem.data.id || selectedItem.data.localId) || !!bulkType) ? 'not-allowed' : 'pointer',
                                        padding: '0 1.25rem',
                                        height: 38,
                                        borderRadius: 8,
                                        display: 'flex',
                                        alignItems: 'center',
                                        gap: '6px'
                                    }}
                                    onClick={() => handleRetry(selectedItem.data.id || selectedItem.data.localId, selectedItem.type === 'customer')}
                                    disabled={deleting === (selectedItem.data.id || selectedItem.data.localId) || retrying === (selectedItem.data.id || selectedItem.data.localId) || !!bulkType}
                                >
                                    {retrying === (selectedItem.data.id || selectedItem.data.localId) ? <Loader2 size={16} className="animate-spin" /> : <RefreshCw size={16} />}
                                    Liberar na Fila (Retry)
                                </button>
                            </div>
                        </div>
                    </div>,
                    document.body
                );
            })()}
        </div>
    );
}

// ─── Main ─────────────────────────────────────────────────────────────────────
const TABS = [
    { id: 'status', label: 'Status & Métricas', icon: Activity },
    { id: 'stuck',  label: 'Fila & Pendências', icon: AlertCircle },
    { id: 'config', label: 'Configuração', icon: Settings },
    { id: 'logs',   label: 'Logs de Requisições', icon: FileText },
];

/**
 * SalesApiManager — Dashboard de status e métricas da Sales API.
 */
export default function SalesApiManager() {
    const [tab, setTab]           = useState('status');
    const [stats, setStats]       = useState(null);
    const [healthData, setHealth]   = useState(null);
    const [config, setConfig]     = useState(null);
    const [logs, setLogs]         = useState([]);
    const [logError, setLogError] = useState(null);
    const [stuckOrders, setStuckOrders] = useState([]);
    const [stuckCustomers, setStuckCustomers] = useState([]);
    const [isStuckLoading, setStuckLoading] = useState(false);
    const [stuckError, setStuckError] = useState(null);
    const [isLoading, setLoading] = useState(false);
    const [lastUpdated, setLastUpdated] = useState(null);

    const today = new Date();
    const [stuckFrom, setStuckFrom] = useState(
        new Date(today.getFullYear(), today.getMonth() - 1, today.getDate()).toISOString().slice(0, 10)
    );
    const [stuckTo, setStuckTo] = useState(today.toISOString().slice(0, 10));

    const loadData = useCallback(async () => {
        setLoading(true);
        try {
            const [health, statsData] = await Promise.allSettled([
                salesApiService.checkHealth(),
                salesApiService.getStats(),
            ]);
            if (health.status === 'fulfilled')  setHealth(health.value);
            else                                setHealth(null);
            if (statsData.status === 'fulfilled') setStats(statsData.value);
            setLastUpdated(new Date());
        } catch { /* handled above */ }
        finally { setLoading(false); }
    }, []);

    const loadConfig = useCallback(async () => {
        if (config) return;
        try { const d = await salesApiService.getConfig(); setConfig(d); } catch { setConfig({}); }
    }, [config]);

    const loadLogs = useCallback(async () => {
        setLogError(null);
        try { 
            const d = await salesApiService.getLogs(); 
            setLogs(d?.logs ?? d ?? []); 
        } catch (err) { 
            setLogError(err.response?.status || err.message);
            setLogs([]); 
        }
    }, []);

    const loadStuckOrders = useCallback(async () => {
        setStuckLoading(true);
        setStuckError(null);
        try {
            const result = await salesApiService.getStuckOrders({ from: stuckFrom, to: stuckTo });
            setStuckOrders(result?.stuckOrders || result?.orders || []);
            setStuckCustomers(result?.stuckCustomers || result?.customers || []);
        } catch (err) {
            setStuckOrders([]);
            setStuckCustomers([]);
            setStuckError(err.response?.data?.error || err.message || 'Erro ao carregar fila');
        } finally {
            setStuckLoading(false);
        }
    }, [stuckFrom, stuckTo]);

    useEffect(() => { loadData(); }, [loadData]);

    useEffect(() => {
        if (tab === 'config') loadConfig();
        if (tab === 'logs')   loadLogs();
        if (tab === 'stuck')  loadStuckOrders();
    }, [tab, loadConfig, loadLogs, loadStuckOrders]);

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
                            boxShadow: 'var(--shadow-primary)',
                        }}>
                            <Server size={20} color="white" />
                        </div>
                        <h1 style={{ margin: 0 }}>Sales API Manager</h1>
                    </div>
                    <p className="page-subtext">Visualize métricas, configurações e logs do Sales API em tempo real</p>
                </div>
                {lastUpdated && (
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-hint)', alignSelf: 'flex-end' }}>
                        Atualizado às {lastUpdated.toLocaleTimeString('pt-BR')}
                    </div>
                )}
            </div>

            {/* Tabs */}
            <div style={{ display: 'flex', gap: '0.25rem', background: 'rgba(255,255,255,0.04)', padding: '4px', borderRadius: 'var(--radius-md)', border: '1px solid var(--border)', width: 'fit-content' }}>
                {TABS.map(({ id, label, icon: Icon }) => (
                    <button
                        key={id}
                        onClick={() => setTab(id)}
                        style={{
                            display: 'flex', alignItems: 'center', gap: '0.5rem',
                            padding: '0.5rem 1rem',
                            borderRadius: '8px',
                            fontSize: '0.875rem', fontWeight: tab === id ? 600 : 500,
                            color: tab === id ? 'var(--text-main)' : 'var(--text-muted)',
                            background: tab === id ? 'var(--glass-bg-strong)' : 'transparent',
                            border: tab === id ? '1px solid var(--glass-border)' : '1px solid transparent',
                            transition: 'all var(--t-fast)',
                            cursor: 'pointer',
                        }}
                    >
                        <Icon size={15} />
                        {label}
                    </button>
                ))}
            </div>

            {/* Content */}
            <div className="card" style={{ padding: '1.5rem' }}>
                {tab === 'status' && <TabStatus stats={stats} healthData={healthData} isLoading={isLoading} onRefresh={loadData} />}
                {tab === 'stuck'  && <TabStuckOrders stuckOrders={stuckOrders} stuckCustomers={stuckCustomers} isLoading={isStuckLoading} stuckError={stuckError} onRefresh={loadStuckOrders} from={stuckFrom} to={stuckTo} setFrom={setStuckFrom} setTo={setStuckTo} />}
                {tab === 'config' && <TabConfig config={config} />}
                {tab === 'logs'   && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                        {logError && (
                            <div style={{ padding: '1rem', background: 'var(--danger-bg)', border: '1px solid var(--danger-border)', borderRadius: 'var(--radius-md)', display: 'flex', alignItems: 'center', gap: '0.75rem', color: 'var(--danger-text)' }}>
                                <AlertTriangle size={20} />
                                <div>
                                    <h4 style={{ margin: 0, fontSize: '0.9rem' }}>Acesso Negado aos Logs ({logError})</h4>
                                    <p style={{ margin: '4px 0 0 0', fontSize: '0.8rem', opacity: 0.9 }}>
                                        A chave ADMIN_API_KEY do servidor não confere com a chave configurada no front-end (VITE_SALES_API_KEY).
                                    </p>
                                </div>
                            </div>
                        )}
                        <TabLogs logs={logs} />
                    </div>
                )}
            </div>
        </div>
    );
}
