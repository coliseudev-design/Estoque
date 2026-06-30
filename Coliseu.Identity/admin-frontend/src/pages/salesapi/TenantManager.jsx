import React, { useState, useEffect, useCallback } from 'react';
import { Building2, Plus, Key, Power, PowerOff, RefreshCw, Copy, CheckCircle, AlertCircle } from 'lucide-react';
import { salesApiService } from '../../services/salesApiService';

/**
 * TenantManager — Gestão de Empresas/Tenants (A1).
 *
 * Permite ao super-admin: listar, criar, ativar/desativar e rotacionar
 * a API Key de cada empresa sem acessar diretamente o banco de dados.
 */
export default function TenantManager() {
    const [companies, setCompanies] = useState([]);
    const [loading, setLoading] = useState(false);
    const [creating, setCreating] = useState(false);
    const [newName, setNewName] = useState('');
    const [flashKey, setFlashKey] = useState(null);  // { id, key }
    const [copied, setCopied] = useState(false);
    const [error, setError] = useState(null);


    const fetchCompanies = useCallback(async () => {
        setLoading(true); setError(null);
        try {
            const data = await salesApiService.getAdminCompanies();
            setCompanies(data.companies || []);
        } catch (e) { setError(e.message); }
        finally { setLoading(false); }
    }, []);

    useEffect(() => { fetchCompanies(); }, [fetchCompanies]);

    // ── Criar empresa ──────────────────────────────────────────────────────────
    const createCompany = async () => {
        if (!newName.trim()) return;
        setCreating(true);
        try {
            const data = await salesApiService.createAdminCompany(newName.trim());
            setFlashKey({ id: data.company.id, name: data.company.name, key: data.apiKey });
            setNewName('');
            fetchCompanies();
        } catch (e) { setError(e.message); }
        finally { setCreating(false); }
    };

    // ── Ativar/desativar ───────────────────────────────────────────────────────
    const toggleActive = async (id, currentActive) => {
        try {
            await salesApiService.toggleAdminCompany(id, !currentActive);
            fetchCompanies();
        } catch (e) { setError(e.message); }
    };

    // ── Rotacionar key ─────────────────────────────────────────────────────────
    const rotateKey = async (id, name) => {
        if (!window.confirm(`Rotacionar a API Key de "${name}"?\nA chave antiga será invalidada imediatamente.`)) return;
        try {
            const data = await salesApiService.rotateAdminKey(id);
            setFlashKey({ id, name, key: data.apiKey });
        } catch (e) { setError(e.message); }
    };

    const copyKey = () => {
        navigator.clipboard.writeText(flashKey?.key || '').then(() => {
            setCopied(true); setTimeout(() => setCopied(false), 2000);
        });
    };

    // ── Render ─────────────────────────────────────────────────────────────────
    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>

            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '1rem' }}>
                <div>
                    <h2 style={{ margin: 0, fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-main)' }}>
                        <Building2 size={20} style={{ marginRight: 8, verticalAlign: 'middle', color: 'var(--primary)' }} />
                        Gestão de Empresas
                    </h2>
                    <p style={{ margin: '4px 0 0', color: 'var(--text-muted)', fontSize: '0.875rem' }}>
                        Tenants do sistema multi-tenant Coliseu Speed
                    </p>
                </div>
                <button onClick={fetchCompanies} disabled={loading} className="btn-outline hover-lift"
                    style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <RefreshCw size={15} className={loading ? 'spin' : ''} /> Atualizar
                </button>
            </div>

            {/* Flash: nova API Key */}
            {flashKey && (
                <div className="card" style={{ padding: '1.25rem', border: '2px solid var(--warning)', background: 'var(--warning-bg)', borderRadius: 10 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8, fontWeight: 700, color: 'var(--warning)' }}>
                        <AlertCircle size={18} /> API Key de "{flashKey.name}" — guarde agora!
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <code style={{ flex: 1, padding: '8px 12px', background: 'var(--bg-card)', borderRadius: 6, fontSize: '0.875rem', wordBreak: 'break-all' }}>
                            {flashKey.key}
                        </code>
                        <button onClick={copyKey} className="btn-primary" style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: 6 }}>
                            {copied ? <CheckCircle size={15} /> : <Copy size={15} />}
                            {copied ? 'Copiado!' : 'Copiar'}
                        </button>
                        <button onClick={() => setFlashKey(null)} className="btn-outline" style={{ whiteSpace: 'nowrap' }}>
                            Fechar
                        </button>
                    </div>
                </div>
            )}

            {/* Criar empresa */}
            <div className="card" style={{ padding: '1.25rem', display: 'flex', gap: '0.75rem', flexWrap: 'wrap', alignItems: 'flex-end' }}>
                <div style={{ flex: 1, minWidth: 200 }}>
                    <label style={{ fontSize: '0.8125rem', color: 'var(--text-muted)', fontWeight: 600, display: 'block', marginBottom: 6 }}>Nova Empresa</label>
                    <input value={newName} onChange={e => setNewName(e.target.value)}
                        onKeyDown={e => e.key === 'Enter' && createCompany()}
                        placeholder="Nome da empresa..."
                        className="input-field" style={{ padding: '8px 12px', width: '100%', boxSizing: 'border-box' }} />
                </div>
                <button onClick={createCompany} disabled={creating || !newName.trim()} className="btn-primary hover-lift"
                    style={{ display: 'flex', alignItems: 'center', gap: 6, height: 38 }}>
                    <Plus size={15} /> {creating ? 'Criando...' : 'Criar Empresa'}
                </button>
            </div>

            {/* Erro */}
            {error && (
                <div style={{ padding: '0.75rem 1rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 8, border: '1px solid var(--danger)' }}>
                    ⚠ {error}
                </div>
            )}

            {/* Lista */}
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ padding: '1rem 1.5rem', borderBottom: '1px solid var(--border)' }}>
                    <span style={{ fontWeight: 600, color: 'var(--text-main)' }}>Empresas ({companies.length})</span>
                </div>
                {companies.length === 0 && !loading ? (
                    <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                        Nenhuma empresa cadastrada.
                    </div>
                ) : (
                    <div style={{ overflowX: 'auto' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.875rem' }}>
                            <thead>
                                <tr style={{ background: 'var(--bg-body)' }}>
                                    {['Nome', 'ID', 'Status', 'Criado em', 'Ações'].map(h => (
                                        <th key={h} style={{ padding: '10px 16px', textAlign: 'left', color: 'var(--text-muted)', fontWeight: 600, fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.5px' }}>{h}</th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody>
                                {companies.map((c, i) => (
                                    <tr key={c.id} style={{ borderTop: '1px solid var(--border)', background: i % 2 === 0 ? 'transparent' : 'var(--bg-body)' }}>
                                        <td style={{ padding: '12px 16px', fontWeight: 600, color: 'var(--text-main)' }}>{c.name}</td>
                                        <td style={{ padding: '12px 16px', fontFamily: 'monospace', fontSize: '0.75rem', color: 'var(--text-muted)' }}>{c.id}</td>
                                        <td style={{ padding: '12px 16px' }}>
                                            <span style={{
                                                display: 'inline-block', padding: '2px 8px', borderRadius: 9999, fontSize: '0.75rem', fontWeight: 600,
                                                background: c.active ? 'var(--success-bg)' : 'var(--danger-bg)',
                                                color: c.active ? 'var(--success)' : 'var(--danger)',
                                            }}>
                                                {c.active ? '● Ativa' : '○ Inativa'}
                                            </span>
                                        </td>
                                        <td style={{ padding: '12px 16px', color: 'var(--text-muted)' }}>{new Date(c.created_at).toLocaleDateString('pt-BR')}</td>
                                        <td style={{ padding: '12px 16px' }}>
                                            <div style={{ display: 'flex', gap: '0.5rem' }}>
                                                <button onClick={() => rotateKey(c.id, c.name)} title="Rotacionar API Key"
                                                    className="btn-outline" style={{ padding: '4px 10px', display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem' }}>
                                                    <Key size={13} /> Rotacionar Key
                                                </button>
                                                <button onClick={() => toggleActive(c.id, c.active)} title={c.active ? 'Desativar' : 'Ativar'}
                                                    className={c.active ? 'btn-outline' : 'btn-primary'} style={{ padding: '4px 10px', display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.8rem' }}>
                                                    {c.active ? <PowerOff size={13} /> : <Power size={13} />}
                                                    {c.active ? 'Desativar' : 'Ativar'}
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
