import React, { useState, useEffect, useCallback } from 'react';
import {
    Plus, Search, MoreVertical, Edit2, Smartphone, AlertCircle,
    X, CheckCircle, Copy, Key, Power, Building2, Mail, Hash, Trash2,
    GitBranch, Star
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { companyService } from '../../services/companyService';
import { requestService } from '../../services/requestService';
import '../../animations.css';

/* ─── Sub-modal para adicionar filial localmente ────────── */
function AddBranchSubModal({ onSave, onClose }) {
    const [form, setForm] = useState({
        name: '',
        cnpj: '',
        erpEmpresaId: '',
        erpDeptoPadrao: '',
        erpCentroPadrao: '',
        isDefault: false,
        associatedRequestId: undefined
    });
    const [error, setError] = useState('');

    const [requests, setRequests] = useState([]);
    const [selectedReqId, setSelectedReqId] = useState('');
    const [selectedRequest, setSelectedRequest] = useState(null);
    const [selectedCompanyIdx, setSelectedCompanyIdx] = useState('');

    useEffect(() => {
        const fetchRequests = async () => {
            try {
                const list = await requestService.listRequests();
                const links = JSON.parse(localStorage.getItem('coliseu_request_license_links') || '{}');
                // Trazer somente as requisições pendentes que ainda não têm nenhuma empresa/filial associada
                setRequests(list.filter(r => r.status === 'Pendente' && !links[r.id]));
            } catch (e) {
                console.error('Failed to load requests inside AddBranchSubModal', e);
            }
        };
        fetchRequests();
    }, []);

    const handleRequestChange = (reqId) => {
        setSelectedReqId(reqId);
        setSelectedCompanyIdx('');
        if (!reqId) {
            setSelectedRequest(null);
            setForm({
                name: '',
                cnpj: '',
                erpEmpresaId: '',
                erpDeptoPadrao: '',
                erpCentroPadrao: '',
                isDefault: false,
                associatedRequestId: undefined
            });
            return;
        }

        const req = requests.find(r => r.id === reqId);
        setSelectedRequest(req);

        if (req.clientCompanyType === 'Empresa Individual') {
            setForm(prev => ({
                ...prev,
                cnpj: req.clientCnpj || '',
                erpCentroPadrao: req.costCenterCode || '',
                erpDeptoPadrao: req.deptCode || '',
                name: `Matriz ${req.clientCnpj ? req.clientCnpj.substring(0, 10) : ''}`,
                associatedRequestId: req.id
            }));
        } else {
            // Se for MultiEmpresa, o usuário deve selecionar a filial no outro dropdown
            setForm(prev => ({
                ...prev,
                associatedRequestId: req.id,
                name: '',
                cnpj: '',
                erpCentroPadrao: '',
                erpDeptoPadrao: ''
            }));
        }
    };

    const handleCompanyIdxChange = (idx) => {
        setSelectedCompanyIdx(idx);
        if (idx === '') {
            setForm(prev => ({
                ...prev,
                cnpj: '',
                erpCentroPadrao: '',
                erpDeptoPadrao: '',
                name: ''
            }));
            return;
        }

        if (selectedRequest && selectedRequest.companies) {
            const comp = selectedRequest.companies[idx];
            setForm(prev => ({
                ...prev,
                cnpj: comp.cnpj || '',
                erpCentroPadrao: comp.costCenter || '',
                erpDeptoPadrao: comp.dept || '',
                name: `Filial ${comp.cnpj ? comp.cnpj.substring(0, 10) : ''}`
            }));
        }
    };

    const handleSubmit = (e) => {
        e.preventDefault();
        if (!form.name.trim()) {
            setError('O nome da filial é obrigatório.');
            return;
        }
        if (!form.erpEmpresaId) {
            setError('O ID da Empresa no ERP é obrigatório.');
            return;
        }
        onSave({
            name: form.name.trim(),
            cnpj: form.cnpj.trim() || undefined,
            erpEmpresaId: Number(form.erpEmpresaId),
            erpDeptoPadrao: Number(form.erpDeptoPadrao) || 0,
            erpCentroPadrao: Number(form.erpCentroPadrao) || 0,
            isDefault: form.isDefault,
            associatedRequestId: form.associatedRequestId
        });
    };

    return (
        <div style={{
            position: 'fixed', inset: 0, zIndex: 110,
            background: 'rgba(15, 23, 42, 0.65)',
            backdropFilter: 'blur(3px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '1rem',
        }}>
            <div className="card animate-scale-in" style={{ width: '100%', maxWidth: '420px', padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid var(--border)', paddingBottom: '0.5rem' }}>
                    <div style={{ fontWeight: 700, fontSize: '0.9375rem', color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <GitBranch size={16} color="var(--primary)" /> Nova Filial
                    </div>
                    <button type="button" onClick={onClose} style={{ border: 'none', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer' }}>
                        <X size={16} />
                    </button>
                </div>
                
                {error && (
                    <div style={{ padding: '0.625rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 'var(--radius-sm)', fontSize: '0.8rem' }}>
                        {error}
                    </div>
                )}

                {/* SELECT REQUISIÇÃO (Importar da Requisição) */}
                <div style={{ background: 'rgba(27,143,205,0.04)', padding: '0.75rem', borderRadius: '8px', border: '1px solid rgba(27,143,205,0.15)', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                    <label style={{ display: 'block', fontSize: '0.74rem', fontWeight: 700, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                        Importar de uma Requisição de Licença
                    </label>
                    <select
                        value={selectedReqId}
                        onChange={e => handleRequestChange(e.target.value)}
                        style={{
                            width: '100%', padding: '0.55rem 0.75rem', borderRadius: '6px',
                            border: '1.5px solid var(--border)', background: '#fff',
                            color: 'var(--text-main)', fontSize: '0.85rem', outline: 'none'
                        }}
                    >
                        <option value="">— Digitar Manualmente (Não Importar) —</option>
                        {requests.map(r => (
                            <option key={r.id} value={r.id}>
                                {r.partnerName} — {r.clientCompanyType} ({r.clientCnpj || `${r.companies?.length || 0} filiais`})
                            </option>
                        ))}
                    </select>

                    {/* Dropdown de filiais para MultiEmpresa */}
                    {selectedRequest && selectedRequest.clientCompanyType === 'MultiEmpresa' && (
                        <div style={{ marginTop: '0.25rem', display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
                            <label style={{ display: 'block', fontSize: '0.74rem', fontWeight: 600, color: 'var(--text-muted)' }}>
                                Selecione a Filial da Requisição *
                            </label>
                            <select
                                value={selectedCompanyIdx}
                                onChange={e => handleCompanyIdxChange(e.target.value)}
                                required={selectedRequest.clientCompanyType === 'MultiEmpresa'}
                                style={{
                                    width: '100%', padding: '0.55rem 0.75rem', borderRadius: '6px',
                                    border: '1.5px solid var(--border)', background: '#fff',
                                    color: 'var(--text-main)', fontSize: '0.85rem', outline: 'none'
                                }}
                            >
                                <option value="">— Escolha a Filial —</option>
                                {selectedRequest.companies?.map((c, idx) => (
                                    <option key={idx} value={idx}>
                                        CNPJ: {c.cnpj} (Depto: {c.dept}, Centro: {c.costCenter})
                                    </option>
                                ))}
                            </select>
                        </div>
                    )}
                </div>

                <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.25rem' }}>Nome da Filial *</label>
                    <input required autoFocus type="text" className="input-field" placeholder="Ex: Matriz" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
                </div>

                <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.25rem' }}>CNPJ</label>
                    <input type="text" className="input-field" placeholder="00.000.000/0001-00" value={form.cnpj} onChange={e => setForm({ ...form, cnpj: e.target.value })} />
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' }}>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.25rem' }}>ID Empresa ERP *</label>
                        <input required type="number" min={1} className="input-field" placeholder="1" value={form.erpEmpresaId} onChange={e => setForm({ ...form, erpEmpresaId: e.target.value })} />
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.25rem' }}>Depto ERP</label>
                        <input type="number" min={0} className="input-field" placeholder="Ex: 5" value={form.erpDeptoPadrao} onChange={e => setForm({ ...form, erpDeptoPadrao: e.target.value })} />
                    </div>
                </div>

                <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.25rem' }}>Centro de Custo ERP</label>
                    <input type="number" min={0} className="input-field" placeholder="Ex: 3" value={form.erpCentroPadrao} onChange={e => setForm({ ...form, erpCentroPadrao: e.target.value })} />
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', paddingTop: '0.25rem' }}>
                    <input type="checkbox" id="sub-branch-default" checked={form.isDefault} onChange={e => setForm({ ...form, isDefault: e.target.checked })} style={{ cursor: 'pointer' }} />
                    <label htmlFor="sub-branch-default" style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-main)', cursor: 'pointer' }}>Filial padrão</label>
                </div>

                <div style={{ display: 'flex', gap: '0.75rem', paddingTop: '0.5rem' }}>
                    <button type="button" onClick={onClose} className="btn btn-outline" style={{ flex: 1 }}>Cancelar</button>
                    <button type="button" onClick={handleSubmit} className="btn btn-primary" style={{ flex: 1 }}>Adicionar</button>
                </div>
            </div>
        </div>
    );
}

/* ─── Modal de criação unificada ────────────────────────── */
function CreateCompanyModal({ onClose, onCreated }) {
    const [form, setForm] = useState({ name: '', contactEmail: '', deviceLimit: 10 });
    const [branches, setBranches] = useState([]);
    const [showAddBranch, setShowAddBranch] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [result, setResult] = useState(null); // { company, apiKey, salesTenantCreated }
    const [copied, setCopied] = useState(false);

    const handleAddBranch = (newBranch) => {
        setBranches(prev => {
            let list = [...prev];
            if (list.length === 0) {
                newBranch.isDefault = true;
            } else if (newBranch.isDefault) {
                list = list.map(b => ({ ...b, isDefault: false }));
            }
            return [...list, newBranch];
        });
        setShowAddBranch(false);
    };

    const handleRemoveBranch = (indexToRemove) => {
        setBranches(prev => {
            let list = prev.filter((_, idx) => idx !== indexToRemove);
            if (prev[indexToRemove]?.isDefault && list.length > 0) {
                list[0] = { ...list[0], isDefault: true };
            }
            return list;
        });
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        if (!form.name.trim()) return;
        if (branches.length === 0) {
            setError('É obrigatório cadastrar pelo menos uma filial antes de salvar.');
            return;
        }
        setLoading(true);
        setError('');
        try {
            const data = await companyService.createCompany({
                name: form.name.trim(),
                contactEmail: form.contactEmail.trim() || undefined,
                deviceLimit: Number(form.deviceLimit),
                branches: branches
            });
            setResult(data);
            onCreated?.();

            // Se houver filiais associadas a requisições, vamos associar seus IDs reais do backend
            const companyId = data.company?.id;
            const companyName = data.company?.name;
            const branchesWithRequests = branches.filter(b => b.associatedRequestId);
            if (companyId && branchesWithRequests.length > 0) {
                try {
                    // Buscar as filiais criadas para pegar seus IDs reais
                    const apiBranches = await companyService.getBranches(companyId);
                    const links = JSON.parse(localStorage.getItem('coliseu_request_license_links') || '{}');

                    for (const localBranch of branchesWithRequests) {
                        // Achar a filial correspondente no backend por erpEmpresaId ou nome ou CNPJ
                        const apiBranch = apiBranches.find(ab => 
                            ab.erpEmpresaId === localBranch.erpEmpresaId || 
                            ab.name === localBranch.name ||
                            (localBranch.cnpj && ab.cnpj === localBranch.cnpj)
                        );

                        if (apiBranch) {
                            links[localBranch.associatedRequestId] = {
                                companyId: companyId,
                                companyName: companyName || 'Empresa Principal',
                                branchId: apiBranch.id,
                                branchName: apiBranch.name
                            };
                            
                            // Atualizar o status da requisição
                            await requestService.updateStatus(localBranch.associatedRequestId, 'Aprovada');
                        }
                    }
                    localStorage.setItem('coliseu_request_license_links', JSON.stringify(links));
                } catch (linkErr) {
                    console.error('Failed to link request during company creation', linkErr);
                }
            }
        } catch (err) {
            setError(err.response?.data?.error || err.message || 'Erro ao criar empresa.');
        } finally {
            setLoading(false);
        }
    };

    const copyKey = () => {
        navigator.clipboard.writeText(result?.apiKey || '');
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
    };

    return (
        <div style={{
            position: 'fixed', inset: 0, zIndex: 100,
            background: 'rgba(15, 23, 42, 0.45)',
            backdropFilter: 'blur(4px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '1rem',
        }}>

            {showAddBranch && (
                <AddBranchSubModal
                    onSave={handleAddBranch}
                    onClose={() => setShowAddBranch(false)}
                />
            )}

            <div className="card animate-scale-in" style={{ width: '100%', maxWidth: '480px', padding: 0, overflow: 'hidden' }}>

                {/* Header */}
                <div style={{ padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <div style={{ width: 34, height: 34, borderRadius: 9, background: 'linear-gradient(135deg, var(--primary), var(--primary-light))', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <Building2 size={17} color="white" />
                        </div>
                        <div>
                            <div style={{ fontWeight: 700, fontSize: '0.9375rem', color: 'var(--text-main)' }}>Nova Empresa</div>
                            <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Cria conta no Identity + tenant no Sales</div>
                        </div>
                    </div>
                    {!result && (
                        <button onClick={onClose} style={{ width: 30, height: 30, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', background: 'var(--bg-body)', border: '1px solid var(--border)' }}>
                            <X size={14} />
                        </button>
                    )}
                </div>

                {/* Resultado da criação */}
                {result ? (
                    <div style={{ padding: '1.5rem' }}>
                        {/* Sucesso Identity */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem', padding: '0.875rem', background: 'var(--success-bg)', borderRadius: 'var(--radius-md)', border: '1px solid rgba(16,185,129,0.2)' }}>
                            <CheckCircle size={20} color="var(--success)" />
                            <div>
                                <div style={{ fontWeight: 600, color: 'var(--success-text)' }}>"{result.company?.name}" criada com sucesso!</div>
                                <div style={{ fontSize: '0.75rem', color: 'var(--success-text)', opacity: 0.8 }}>
                                    Identity ID: {result.company?.id?.split('-')[0]}…
                                </div>
                            </div>
                        </div>

                        {/* Status Sales API */}
                        <div style={{
                            display: 'flex', alignItems: 'center', gap: '0.625rem', marginBottom: '1rem',
                            padding: '0.75rem', borderRadius: 'var(--radius-md)',
                            background: result.salesTenantCreated ? 'var(--success-bg)' : 'var(--warning-bg)',
                            border: `1px solid ${result.salesTenantCreated ? 'rgba(16,185,129,0.2)' : 'rgba(245,158,11,0.2)'}`,
                        }}>
                            {result.salesTenantCreated
                                ? <CheckCircle size={16} color="var(--success)" />
                                : <AlertCircle size={16} color="var(--warning)" />
                            }
                            <span style={{ fontSize: '0.8125rem', fontWeight: 500, color: result.salesTenantCreated ? 'var(--success-text)' : 'var(--warning-text)' }}>
                                {result.salesTenantCreated
                                    ? 'Tenant na Sales API provisionado automaticamente'
                                    : 'Sales API offline — tenant será criado quando ela subir'
                                }
                            </span>
                        </div>

                        {/* API Key */}
                        {result.apiKey && (
                            <div style={{ marginBottom: '1.25rem' }}>
                                <div style={{ fontSize: '0.8125rem', fontWeight: 600, color: 'var(--warning-text)', marginBottom: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
                                    <Key size={13} color="var(--warning)" />
                                    API Key — copie agora, não será exibida novamente
                                </div>
                                <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                                    <code style={{
                                        flex: 1, padding: '0.625rem 0.75rem', background: 'var(--bg-body)',
                                        border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
                                        fontSize: '0.75rem', wordBreak: 'break-all', color: 'var(--text-main)',
                                        fontFamily: 'monospace',
                                    }}>
                                        {result.apiKey}
                                    </code>
                                    <button onClick={copyKey} className="btn btn-primary btn-sm" style={{ flexShrink: 0, gap: '0.375rem' }}>
                                        {copied ? <CheckCircle size={14} /> : <Copy size={14} />}
                                        {copied ? 'Copiado!' : 'Copiar'}
                                    </button>
                                </div>
                            </div>
                        )}

                        <button onClick={onClose} className="btn btn-outline w-full">
                            Fechar
                        </button>
                    </div>
                ) : (
                    /* Formulário */
                    <form onSubmit={handleSubmit} style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                        {error && (
                            <div style={{ padding: '0.75rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 'var(--radius-sm)', fontSize: '0.875rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                <AlertCircle size={15} /> {error}
                            </div>
                        )}

                        {/* Nome */}
                        <div>
                            <label style={{ display: 'block', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.375rem' }}>
                                <Building2 size={13} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                                Nome da Empresa *
                            </label>
                            <input
                                required autoFocus
                                type="text"
                                placeholder="Ex: Piveta Comércio Ltda"
                                className="input-field"
                                value={form.name}
                                onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                            />
                        </div>

                        {/* Email */}
                        <div>
                            <label style={{ display: 'block', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.375rem' }}>
                                <Mail size={13} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                                E-mail de Contato
                            </label>
                            <input
                                type="email"
                                placeholder="contato@empresa.com.br"
                                className="input-field"
                                value={form.contactEmail}
                                onChange={e => setForm(f => ({ ...f, contactEmail: e.target.value }))}
                            />
                        </div>

                        {/* Limite de dispositivos */}
                        <div>
                            <label style={{ display: 'block', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)', marginBottom: '0.375rem' }}>
                                <Hash size={13} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                                Limite de Dispositivos
                            </label>
                            <input
                                type="number" min={1} max={999}
                                className="input-field"
                                value={form.deviceLimit}
                                onChange={e => setForm(f => ({ ...f, deviceLimit: e.target.value }))}
                            />
                        </div>

                        {/* Seção de Filiais */}
                        <div>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                                <label style={{ display: 'block', fontSize: '0.8125rem', fontWeight: 600, color: 'var(--text-sub)', margin: 0 }}>
                                    <GitBranch size={13} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                                    Filiais da Empresa *
                                </label>
                                <button
                                    type="button"
                                    onClick={() => setShowAddBranch(true)}
                                    className="btn btn-outline btn-sm"
                                    style={{ padding: '0.25rem 0.5rem', fontSize: '0.75rem', height: 'auto', display: 'flex', alignItems: 'center', gap: '3px' }}
                                >
                                    <Plus size={12} /> Adicionar Filial
                                </button>
                            </div>

                            {branches.length === 0 ? (
                                <div style={{ padding: '0.75rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 'var(--radius-sm)', fontSize: '0.8rem', display: 'flex', gap: '0.5rem', marginBottom: '0.5rem' }}>
                                    <AlertCircle size={14} style={{ flexShrink: 0, marginTop: 1 }} />
                                    <span>É obrigatório cadastrar pelo menos uma filial.</span>
                                </div>
                            ) : (
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', maxHeight: '130px', overflowY: 'auto', padding: '2px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                                    {branches.map((b, idx) => (
                                        <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.4rem 0.6rem', background: 'var(--bg-body)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)' }}>
                                            <div style={{ minWidth: 0, flex: 1 }}>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', flexWrap: 'wrap' }}>
                                                    <span style={{ fontWeight: 600, fontSize: '0.8rem', color: 'var(--text-main)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.name}</span>
                                                    {b.isDefault && (
                                                        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '2px', background: 'rgba(245,158,11,0.12)', color: '#92400e', borderRadius: '10px', padding: '1px 6px', fontSize: '0.65rem', fontWeight: 700 }}>
                                                            <Star size={8} color="#f59e0b" /> Padrão
                                                        </span>
                                                    )}
                                                </div>
                                                <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginTop: '2px' }}>
                                                    Empresa ERP: {b.erpEmpresaId} | Depto: {b.erpDeptoPadrao} | Centro: {b.erpCentroPadrao}
                                                </div>
                                            </div>
                                            <button
                                                type="button"
                                                onClick={() => handleRemoveBranch(idx)}
                                                style={{ border: 'none', background: 'transparent', color: 'var(--danger)', cursor: 'pointer', padding: '4px', display: 'flex', alignItems: 'center' }}
                                                title="Remover filial"
                                            >
                                                <Trash2 size={12} />
                                            </button>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>

                        {/* Info box */}
                        <div style={{ padding: '0.75rem', background: 'var(--info-bg)', borderRadius: 'var(--radius-sm)', fontSize: '0.8rem', color: 'var(--info-text)', display: 'flex', gap: '0.5rem' }}>
                            <Power size={14} style={{ flexShrink: 0, marginTop: 1 }} />
                            <span>Ao criar, a empresa será provisionada na Identity API <strong>e</strong> registrada como tenant na Sales API automaticamente.</span>
                        </div>

                        <div style={{ display: 'flex', gap: '0.75rem', paddingTop: '0.25rem' }}>
                            <button type="button" onClick={onClose} className="btn btn-outline" style={{ flex: 1 }}>
                                Cancelar
                            </button>
                            <button type="submit" disabled={loading || !form.name.trim() || branches.length === 0} className="btn btn-primary" style={{ flex: 1 }}>
                                {loading ? 'Criando...' : '+ Criar Empresa'}
                            </button>
                        </div>
                    </form>
                )}
            </div>
        </div>
    );
}

/* ─── Skeleton row ───────────────────────────────────────── */
function SkeletonRow() {
    return (
        <tr>
            {[...Array(5)].map((_, i) => (
                <td key={i} style={{ padding: '1rem 1.25rem' }}>
                    <div className="skeleton" style={{ height: 14, width: i === 0 ? '70%' : i === 2 ? '50%' : '60%', borderRadius: 4 }} />
                </td>
            ))}
        </tr>
    );
}

/* ─── Modal confirmação de exclusão ─────────────────────── */
function DeleteCompanyModal({ company, onClose, onDeleted }) {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');

    const handleDelete = async () => {
        setLoading(true);
        setError('');
        try {
            await companyService.deleteCompany(company.id);
            onDeleted?.();
            onClose();
        } catch (err) {
            setError(err.response?.data?.error || err.message || 'Erro ao excluir empresa.');
            setLoading(false);
        }
    };

    return (
        <div style={{
            position: 'fixed', inset: 0, zIndex: 100,
            background: 'rgba(15, 23, 42, 0.55)',
            backdropFilter: 'blur(4px)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '1rem',
        }}>
            <div className="card animate-scale-in" style={{ width: '100%', maxWidth: '420px', padding: 0, overflow: 'hidden' }}>
                {/* Header */}
                <div style={{ padding: '1.25rem 1.5rem', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <div style={{ width: 34, height: 34, borderRadius: 9, background: 'rgba(239,68,68,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <Trash2 size={17} color="var(--danger)" />
                        </div>
                        <div style={{ fontWeight: 700, fontSize: '0.9375rem', color: 'var(--text-main)' }}>Excluir Empresa</div>
                    </div>
                    <button onClick={onClose} disabled={loading} style={{ width: 30, height: 30, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', background: 'var(--bg-body)', border: '1px solid var(--border)' }}>
                        <X size={14} />
                    </button>
                </div>

                {/* Body */}
                <div style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                    <div style={{ padding: '0.875rem', background: 'var(--danger-bg)', borderRadius: 'var(--radius-md)', border: '1px solid rgba(239,68,68,0.2)', display: 'flex', gap: '0.625rem' }}>
                        <AlertCircle size={18} color="var(--danger)" style={{ flexShrink: 0, marginTop: 1 }} />
                        <div>
                            <div style={{ fontWeight: 600, color: 'var(--danger)', marginBottom: '0.25rem' }}>Ação irreversível!</div>
                            <div style={{ fontSize: '0.8125rem', color: 'var(--danger)', opacity: 0.85 }}>
                                A empresa <strong>{company.name}</strong> e todos os seus dados serão excluídos permanentemente.
                            </div>
                        </div>
                    </div>

                    {error && (
                        <div style={{ padding: '0.75rem', background: 'var(--danger-bg)', color: 'var(--danger)', borderRadius: 'var(--radius-sm)', fontSize: '0.875rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <AlertCircle size={15} /> {error}
                        </div>
                    )}

                    <div style={{ display: 'flex', gap: '0.75rem' }}>
                        <button onClick={onClose} disabled={loading} className="btn btn-outline" style={{ flex: 1 }}>Cancelar</button>
                        <button onClick={handleDelete} disabled={loading} className="btn" style={{ flex: 1, background: 'var(--danger)', color: 'white', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.375rem' }}>
                            {loading ? 'Excluindo...' : <><Trash2 size={14} /> Confirmar Exclusão</>}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    );
}

/* ─── CompanyList principal ──────────────────────────────── */
export default function CompanyList() {
    const navigate = useNavigate();
    const [companies, setCompanies] = useState([]);
    const [isLoading, setIsLoading] = useState(true);
    const [errorMsg, setErrorMsg] = useState('');
    const [search, setSearch] = useState('');
    const [openDropdownId, setOpenDropdownId] = useState(null);
    const [showModal, setShowModal] = useState(false);
    const [deleteTarget, setDeleteTarget] = useState(null); // empresa a excluir

    const loadCompanies = useCallback(async () => {
        try {
            setIsLoading(true);
            setErrorMsg('');
            const data = await companyService.getCompanies(1, 20, search);
            setCompanies(data.items || []);
        } catch (err) {
            console.error('Failed to load companies', err);
            setErrorMsg('Não foi possível carregar as empresas.');
        } finally {
            setIsLoading(false);
        }
    }, [search]);

    useEffect(() => { loadCompanies(); }, [loadCompanies]);

    return (
        <div className="animate-fade-in" onClick={() => setOpenDropdownId(null)}>

            {showModal && (
                <CreateCompanyModal
                    onClose={() => setShowModal(false)}
                    onCreated={loadCompanies}
                />
            )}

            {deleteTarget && (
                <DeleteCompanyModal
                    company={deleteTarget}
                    onClose={() => setDeleteTarget(null)}
                    onDeleted={loadCompanies}
                />
            )}

            {/* Page Header */}
            <div className="page-header">
                <div className="page-header-info">
                    <h1>Empresas Registradas</h1>
                    <p className="page-subtext">Gerencie instâncias, licenças, dispositivos e acesso ao ecossistema.</p>
                </div>
                <button className="btn btn-primary" onClick={() => setShowModal(true)}>
                    <Plus size={16} /> Nova Empresa
                </button>
            </div>

            {/* Main Table Card */}
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>

                {/* Toolbar */}
                <div style={{ padding: '1rem 1.25rem', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '0.75rem', background: 'var(--bg-body)' }}>
                    <div style={{ position: 'relative', flex: '1', maxWidth: '320px' }}>
                        <Search size={16} color="var(--text-hint)" style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '10px', pointerEvents: 'none' }} />
                        <input
                            type="text"
                            placeholder="Procurar por nome, email..."
                            className="input-field"
                            style={{ paddingLeft: '34px', height: '38px', fontSize: '0.875rem' }}
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                        />
                    </div>
                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                        <button className="btn btn-outline btn-sm">Filtros</button>
                        <button className="btn btn-outline btn-sm">Exportar</button>
                    </div>
                </div>

                {/* Table */}
                <div style={{ overflowX: 'auto', minHeight: '300px' }}>
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>CÓD / NOME</th>
                                <th>E-MAIL</th>
                                <th style={{ textAlign: 'center' }}>DISPOSITIVOS</th>
                                <th>STATUS</th>
                                <th style={{ textAlign: 'right' }}>AÇÕES</th>
                            </tr>
                        </thead>
                        <tbody>
                            {isLoading ? (
                                [...Array(4)].map((_, i) => <SkeletonRow key={i} />)
                            ) : errorMsg ? (
                                <tr>
                                    <td colSpan="5" style={{ padding: '3rem', textAlign: 'center', color: 'var(--danger)' }}>
                                        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.625rem' }}>
                                            <AlertCircle size={28} />
                                            <p style={{ fontWeight: 500 }}>{errorMsg}</p>
                                            <button className="btn btn-outline btn-sm" onClick={loadCompanies}>Tentar novamente</button>
                                        </div>
                                    </td>
                                </tr>
                            ) : companies.length === 0 ? (
                                <tr>
                                    <td colSpan="5" style={{ padding: '3.5rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                                        <Building2 size={36} style={{ margin: '0 auto 0.75rem', opacity: 0.25 }} />
                                        <p style={{ fontWeight: 500, marginBottom: '0.75rem' }}>Nenhuma empresa cadastrada</p>
                                        <button className="btn btn-primary btn-sm" onClick={() => setShowModal(true)}>
                                            <Plus size={14} /> Criar primeira empresa
                                        </button>
                                    </td>
                                </tr>
                            ) : companies.map(company => (
                                <tr key={company.id}>
                                    <td>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                                            <div style={{
                                                width: 34, height: 34, borderRadius: 9, flexShrink: 0,
                                                background: 'linear-gradient(135deg, var(--primary), var(--primary-light))',
                                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                color: 'white', fontWeight: 700, fontSize: '0.875rem',
                                            }}>
                                                {company.name?.charAt(0).toUpperCase()}
                                            </div>
                                            <div>
                                                <div style={{ fontWeight: 600, color: 'var(--text-main)', fontSize: '0.9rem' }}>{company.name}</div>
                                                <div style={{ fontSize: '0.7rem', color: 'var(--text-hint)', fontFamily: 'monospace' }}>
                                                    {company.id?.split('-')[0]}…
                                                </div>
                                            </div>
                                        </div>
                                    </td>
                                    <td style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>
                                        {company.email || company.contactEmail || <span style={{ color: 'var(--text-hint)' }}>—</span>}
                                    </td>
                                    <td style={{ textAlign: 'center' }}>
                                        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '5px', background: 'var(--bg-body)', padding: '3px 10px', borderRadius: 'var(--radius-full)', fontSize: '0.8125rem', fontWeight: 600, border: '1px solid var(--border)' }}>
                                            <Smartphone size={12} color="var(--text-muted)" />
                                            <span style={{ color: company.activeDevices >= company.deviceLimit ? 'var(--danger)' : 'var(--text-main)' }}>
                                                {company.activeDevices ?? 0}
                                            </span>
                                            <span style={{ color: 'var(--text-hint)' }}>/ {company.deviceLimit ?? 10}</span>
                                        </div>
                                    </td>
                                    <td>
                                        <span className={`badge ${company.status === 'Active' ? 'badge-active' :
                                                company.status === 'Suspended' ? 'badge-suspended' :
                                                    'badge-inactive'
                                            }`}>
                                            {company.status === 'Active' ? 'Ativa' :
                                                company.status === 'Inactive' ? 'Inativa' : 'Suspensa'}
                                        </span>
                                    </td>
                                    <td style={{ textAlign: 'right' }}>
                                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.375rem' }}>
                                            <button
                                                onClick={(e) => { e.stopPropagation(); navigate(`/dashboard/companies/${company.id}`); }}
                                                className="btn btn-outline btn-sm"
                                                title="Gerenciar empresa"
                                            >
                                                <Edit2 size={13} /> Gerenciar
                                            </button>

                                            {/* Dropdown */}
                                            <div style={{ position: 'relative' }}>
                                                <button
                                                    onClick={(e) => { e.stopPropagation(); setOpenDropdownId(d => d === company.id ? null : company.id); }}
                                                    className="btn btn-outline btn-sm"
                                                    style={{ padding: '0.375rem 0.5rem' }}
                                                >
                                                    <MoreVertical size={14} />
                                                </button>

                                                {openDropdownId === company.id && (
                                                    <div className="animate-slide-down" style={{
                                                        position: 'absolute', right: 0, top: '38px',
                                                        background: 'var(--bg-card)', boxShadow: 'var(--shadow-md)',
                                                        borderRadius: 'var(--radius-md)', border: '1px solid var(--border)',
                                                        zIndex: 50, minWidth: '185px', overflow: 'hidden',
                                                    }}>
                                                        <button className="dropdown-item" onClick={(e) => { e.stopPropagation(); setOpenDropdownId(null); }}>
                                                            <Key size={13} /> Rotacionar API Key
                                                        </button>
                                                        <button className="dropdown-item" onClick={(e) => { e.stopPropagation(); setOpenDropdownId(null); }}>
                                                            <Power size={13} /> {company.status === 'Active' ? 'Suspender' : 'Ativar'}
                                                        </button>
                                                        <div style={{ height: 1, background: 'var(--border)' }} />
                                                        <button className="dropdown-item danger" onClick={(e) => { e.stopPropagation(); setOpenDropdownId(null); setDeleteTarget(company); }}>
                                                            <Trash2 size={13} /> Excluir Empresa
                                                        </button>
                                                    </div>
                                                )}
                                            </div>
                                        </div>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>

                {/* Footer / Pagination */}
                <div style={{ padding: '0.875rem 1.25rem', borderTop: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '0.8125rem', background: 'var(--bg-body)' }}>
                    <span>{isLoading ? '—' : `${companies.length} empresa${companies.length !== 1 ? 's' : ''} encontrada${companies.length !== 1 ? 's' : ''}`}</span>
                    <div style={{ display: 'flex', gap: '0.25rem' }}>
                        <button className="btn btn-outline btn-sm">Anterior</button>
                        <button className="btn btn-primary btn-sm">1</button>
                        <button className="btn btn-outline btn-sm">Próximo</button>
                    </div>
                </div>
            </div>
        </div>
    );
}
