import React, { useState, useEffect, useCallback } from 'react';
import { Webhook, Plus, Trash2, RefreshCw, ToggleLeft, ToggleRight } from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

const EVENTS = ['order.confirmed', 'order.error', 'order.created'];

/**
 * WebhookManager — Gestão de webhooks por empresa (A5).
 * CRUD usando /api/admin/companies/:id/webhooks.
 */
export default function WebhookManager() {
    const [webhooks, setWebhooks] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [form, setForm] = useState({ url: '', events: ['order.confirmed'] });
    const [creating, setCreating] = useState(false);

    const [companyId, setCompanyId] = useState('');
    const [allCompanies, setAllCompanies] = useState([]);

    const fetchCompanies = useCallback(async () => {
        try {
            const data = await salesApiService.getAdminCompanies();
            setAllCompanies(data.companies || []);
            if (!companyId && data.companies?.length) setCompanyId(data.companies[0].id);
        } catch { }
    }, [companyId]);

    const fetchWebhooks = useCallback(async () => {
        if (!companyId) return;
        setLoading(true); setError(null);
        try {
            const data = await salesApiService.getWebhooks(companyId);
            setWebhooks(data.webhooks || []);
        } catch (e) { setError(e.message); }
        finally { setLoading(false); }
    }, [companyId]);

    useEffect(() => { fetchCompanies(); }, [fetchCompanies]);
    useEffect(() => { fetchWebhooks(); }, [fetchWebhooks]);

    const createWebhook = async () => {
        if (!form.url.trim() || !form.events.length) return;
        setCreating(true);
        try {
            await salesApiService.createWebhook(companyId, form);
            setForm({ url: '', events: ['order.confirmed'] });
            fetchWebhooks();
        } catch (e) { setError(e.message); }
        finally { setCreating(false); }
    };

    const toggleWebhook = async (id, active) => {
        try {
            await salesApiService.toggleWebhook(companyId, id, !active);
            fetchWebhooks();
        } catch (e) { setError(e.message); }
    };

    const deleteWebhook = async (id) => {
        if (!window.confirm('Remover este webhook?')) return;
        try {
            await salesApiService.deleteWebhook(companyId, id);
            fetchWebhooks();
        } catch (e) { setError(e.message); }
    };

    const toggleEvent = (ev) => setForm(f => ({
        ...f, events: f.events.includes(ev) ? f.events.filter(e => e !== ev) : [...f.events, ev],
    }));

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>

            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '1rem' }}>
                <div>
                    <h2 style={{ margin: 0, fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-main)' }}>
                        <Webhook size={20} style={{ marginRight: 8, verticalAlign: 'middle', color: 'var(--primary)' }} />
                        Webhooks
                    </h2>
                    <p style={{ margin: '4px 0 0', color: 'var(--text-muted)', fontSize: '0.875rem' }}>Notificações HTTP por empresa</p>
                </div>
                <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
                    {allCompanies.length > 1 && (
                        <select value={companyId} onChange={e => setCompanyId(e.target.value)} className="input-field" style={{ padding: '6px 10px', height: 36 }}>
                            {allCompanies.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                    )}
                    <button onClick={fetchWebhooks} disabled={loading} className="btn-outline hover-lift" style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <RefreshCw size={15} className={loading ? 'spin' : ''} />
                    </button>
                </div>
            </div>

            {error && <div style={{ padding: '0.75rem 1rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 8, border: '1px solid var(--danger)' }}>⚠ {error}</div>}

            {/* Formulário */}
            <div className="card" style={{ padding: '1.25rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                <div style={{ fontWeight: 600, color: 'var(--text-main)', marginBottom: 4 }}>Adicionar Webhook</div>
                <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap', alignItems: 'flex-end' }}>
                    <label style={{ flex: 1, minWidth: 220, display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8125rem', color: 'var(--text-muted)' }}>
                        URL destino
                        <input value={form.url} onChange={e => setForm(f => ({ ...f, url: e.target.value }))}
                            placeholder="https://minhapp.com/webhook"
                            className="input-field" style={{ padding: '6px 10px', height: 36 }} />
                    </label>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: '0.8125rem', color: 'var(--text-muted)' }}>
                        Eventos
                        <div style={{ display: 'flex', gap: 8, alignItems: 'center', height: 36 }}>
                            {EVENTS.map(ev => (
                                <label key={ev} style={{ display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer', fontSize: '0.8rem' }}>
                                    <input type="checkbox" checked={form.events.includes(ev)} onChange={() => toggleEvent(ev)} />
                                    {ev.split('.')[1]}
                                </label>
                            ))}
                        </div>
                    </div>
                    <button onClick={createWebhook} disabled={creating || !form.url.trim() || !form.events.length} className="btn-primary hover-lift"
                        style={{ display: 'flex', alignItems: 'center', gap: 6, height: 36, padding: '0 16px' }}>
                        <Plus size={15} /> {creating ? 'Criando...' : 'Adicionar'}
                    </button>
                </div>
            </div>

            {/* Lista */}
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ padding: '1rem 1.5rem', borderBottom: '1px solid var(--border)' }}>
                    <span style={{ fontWeight: 600 }}>Webhooks configurados ({webhooks.length})</span>
                </div>
                {webhooks.length === 0 ? (
                    <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>Nenhum webhook configurado.</div>
                ) : (
                    <div style={{ overflowX: 'auto' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem' }}>
                            <thead><tr style={{ background: 'var(--bg-body)' }}>
                                {['URL', 'Eventos', 'Status', 'Ações'].map(h => (
                                    <th key={h} style={{ padding: '10px 16px', textAlign: 'left', color: 'var(--text-muted)', fontWeight: 600, fontSize: '0.72rem', textTransform: 'uppercase' }}>{h}</th>
                                ))}
                            </tr></thead>
                            <tbody>
                                {webhooks.map((wh, i) => (
                                    <tr key={wh.id} style={{ borderTop: '1px solid var(--border)', background: i % 2 === 0 ? 'transparent' : 'var(--bg-body)' }}>
                                        <td style={{ padding: '12px 16px', fontFamily: 'monospace', fontSize: '0.8rem', wordBreak: 'break-all', maxWidth: 300 }}>{wh.url}</td>
                                        <td style={{ padding: '12px 16px' }}>
                                            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                                                {(wh.events || []).map(ev => (
                                                    <span key={ev} style={{ padding: '2px 6px', borderRadius: 4, background: 'var(--primary-bg)', color: 'var(--primary)', fontSize: '0.72rem', fontWeight: 600 }}>{ev}</span>
                                                ))}
                                            </div>
                                        </td>
                                        <td style={{ padding: '12px 16px' }}>
                                            <span style={{ padding: '2px 8px', borderRadius: 9999, fontSize: '0.72rem', fontWeight: 600, background: wh.active ? 'var(--success-bg)' : 'var(--danger-bg)', color: wh.active ? 'var(--success)' : 'var(--danger)' }}>
                                                {wh.active ? '● Ativo' : '○ Inativo'}
                                            </span>
                                        </td>
                                        <td style={{ padding: '12px 16px' }}>
                                            <div style={{ display: 'flex', gap: '0.5rem' }}>
                                                <button onClick={() => toggleWebhook(wh.id, wh.active)} className="btn-outline" style={{ padding: '4px 10px', display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem' }}>
                                                    {wh.active ? <ToggleRight size={14} /> : <ToggleLeft size={14} />} {wh.active ? 'Desativar' : 'Ativar'}
                                                </button>
                                                <button onClick={() => deleteWebhook(wh.id)} className="btn-outline" style={{ padding: '4px 10px', display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem', color: 'var(--danger)', borderColor: 'var(--danger)' }}>
                                                    <Trash2 size={14} /> Remover
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}
