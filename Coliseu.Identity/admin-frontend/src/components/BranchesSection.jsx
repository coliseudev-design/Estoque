/**
 * BranchesSection.jsx — Gerenciamento de Filiais de uma Empresa.
 *
 * Permite criar, editar e excluir filiais com seus IDs de ERP (Empresa, Depto, Centro de Custo).
 * Integra com a Identity API via Admin API: /admin/companies/:id/branches
 *
 * @param {string} companyId - UUID da empresa
 */
import React, { useState, useEffect, useCallback } from 'react';
import {
    GitBranch, Plus, Pencil, Trash2, Loader2, CheckCircle2,
    AlertTriangle, X, Save, Building2, Star
} from 'lucide-react';
import { companyService } from '../services/companyService';
import { requestService } from '../services/requestService';
import { partnerService } from '../services/partnerService';

// ── Helpers ────────────────────────────────────────────────────────────────────

const EMPTY_BRANCH = {
    name: '',
    cnpj: '',
    erpEmpresaId: '',
    erpDeptoPadrao: '',
    erpCentroPadrao: '',
    isDefault: false,
};

// ── Sub-components: Modal ──────────────────────────────────────────────────────

function BranchModal({ branch, onSave, onClose, isSaving, error }) {
    const [form, setForm] = useState(branch ?? EMPTY_BRANCH);
    const isEdit = Boolean(branch?.id);

    // Requests states
    const [requests, setRequests] = useState([]);
    const [selectedReqId, setSelectedReqId] = useState('');
    const [selectedRequest, setSelectedRequest] = useState(null);
    const [selectedCompanyIdx, setSelectedCompanyIdx] = useState('');
    const [partners, setPartners] = useState([]);
    const [selectedPartnerId, setSelectedPartnerId] = useState('');

    useEffect(() => {
        const fetchRequests = async () => {
            try {
                const list = await requestService.listRequests();
                const links = JSON.parse(localStorage.getItem('coliseu_request_license_links') || '{}');
                // Trazer somente as requisições pendentes que ainda não têm nenhuma empresa/filial associada
                setRequests(list.filter(r => r.status === 'Pendente' && !links[r.id]));
            } catch (e) {
                console.error('Failed to load requests inside BranchModal', e);
            }
        };
        if (!isEdit) {
            fetchRequests();
        }
    }, [isEdit]);

    useEffect(() => {
        const fetchPartners = async () => {
            try {
                const list = await partnerService.listPartners();
                setPartners(list);
                
                if (branch && branch.id) {
                    const assoc = JSON.parse(localStorage.getItem('coliseu_branch_partner_associations') || '{}');
                    setSelectedPartnerId(assoc[branch.id] || '');
                }
            } catch (e) {
                console.error('Failed to load partners inside BranchModal', e);
            }
        };
        fetchPartners();
    }, [branch]);

    const handleChange = (field, value) =>
        setForm(prev => ({ ...prev, [field]: value }));

    const handleRequestChange = (reqId) => {
        setSelectedReqId(reqId);
        setSelectedCompanyIdx('');
        if (!reqId) {
            setSelectedRequest(null);
            setForm(branch ?? EMPTY_BRANCH);
            if (!isEdit) {
                setSelectedPartnerId('');
            }
            return;
        }

        const req = requests.find(r => r.id === reqId);
        setSelectedRequest(req);
        if (req && req.partnerId) {
            setSelectedPartnerId(req.partnerId);
        }

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
                associatedRequestId: req.id
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
        onSave({ ...form, associatedPartnerId: selectedPartnerId });
    };

    return (
        <div style={{
            position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)',
            zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center',
            padding: '1rem'
        }}>
            <div style={{
                background: 'var(--bg-card)', borderRadius: '16px',
                boxShadow: '0 20px 60px rgba(0,0,0,0.4)',
                padding: '2rem', maxWidth: '520px', width: '100%',
                borderTop: '4px solid #10b981'
            }}>
                {/* Header */}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.5rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
                        <GitBranch size={20} color="#10b981" />
                        <h3 style={{ margin: 0, fontWeight: 700, color: 'var(--text-main)', fontSize: '1.05rem' }}>
                            {isEdit ? 'Editar Filial' : 'Nova Filial'}
                        </h3>
                    </div>
                    <button onClick={onClose} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                        <X size={20} />
                    </button>
                </div>

                {error && (
                    <div style={{
                        padding: '0.6rem 0.9rem', borderRadius: '8px',
                        background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.3)',
                        color: '#ef4444', fontSize: '0.85rem', marginBottom: '1rem',
                        display: 'flex', alignItems: 'center', gap: '0.45rem'
                    }}>
                        <AlertTriangle size={14} /> {error}
                    </div>
                )}

                <form onSubmit={handleSubmit}>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>

                        {/* SELECT REQUISIÇÃO (Apenas na Criação) */}
                        {!isEdit && (
                            <div style={{ gridColumn: '1 / -1', background: 'rgba(27,143,205,0.04)', padding: '0.75rem', borderRadius: '10px', border: '1px solid rgba(27,143,205,0.15)', marginBottom: '0.5rem' }}>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 700, color: 'var(--primary)', marginBottom: '0.35rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
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
                                    <div style={{ marginTop: '0.75rem', animation: 'scaleIn 0.18s ease' }}>
                                        <label style={{ display: 'block', fontSize: '0.74rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.25rem' }}>
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
                        )}

                        <div style={{ gridColumn: '1 / -1' }}>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                Nome da Filial *
                            </label>
                            <input
                                id="branch-name"
                                required
                                type="text"
                                value={form.name}
                                onChange={e => handleChange('name', e.target.value)}
                                placeholder="Ex: Matriz, Filial Norte..."
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', boxSizing: 'border-box'
                                }}
                            />
                        </div>

                        <div style={{ gridColumn: '1 / -1' }}>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                CNPJ
                            </label>
                            <input
                                id="branch-cnpj"
                                type="text"
                                value={form.cnpj}
                                onChange={e => handleChange('cnpj', e.target.value)}
                                placeholder="00.000.000/0001-00"
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', boxSizing: 'border-box'
                                }}
                            />
                        </div>

                        <div style={{ gridColumn: '1 / -1' }}>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                Parceiro Comercial
                            </label>
                            <select
                                id="branch-partner"
                                value={selectedPartnerId}
                                onChange={e => setSelectedPartnerId(e.target.value)}
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', outline: 'none',
                                    boxSizing: 'border-box'
                                }}
                            >
                                <option value="">— Sem Parceiro Comercial —</option>
                                {partners.map(p => (
                                    <option key={p.id} value={p.id}>
                                        {p.name} ({p.cnpj})
                                    </option>
                                ))}
                            </select>
                        </div>

                        {/* Separator */}
                        <div style={{ gridColumn: '1 / -1', borderTop: '1px dashed var(--border)', paddingTop: '0.75rem' }}>
                            <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', margin: '0 0 0.75rem 0', fontWeight: 600 }}>
                                🔗 IDs do ERP Firebird (para isolamento de estoque e financeiro)
                            </p>
                        </div>

                        <div>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                ID Empresa (ERP) *
                            </label>
                            <input
                                id="branch-erp-empresa"
                                required
                                type="number"
                                min="1"
                                value={form.erpEmpresaId}
                                onChange={e => handleChange('erpEmpresaId', parseInt(e.target.value) || '')}
                                placeholder="1"
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', boxSizing: 'border-box'
                                }}
                            />
                            <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', margin: '0.25rem 0 0' }}>
                                CONFIG.ID_EMPRESA no Firebird
                            </p>
                        </div>

                        <div>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                Depto Padrão (ERP)
                            </label>
                            <input
                                id="branch-erp-depto"
                                type="number"
                                min="0"
                                value={form.erpDeptoPadrao}
                                onChange={e => handleChange('erpDeptoPadrao', parseInt(e.target.value) || '')}
                                placeholder="Ex: 5"
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', boxSizing: 'border-box'
                                }}
                            />
                            <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', margin: '0.25rem 0 0' }}>
                                PEDIDOS.ID_DEPTO (estoque por filial)
                            </p>
                        </div>

                        <div>
                            <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '0.35rem' }}>
                                Centro de Custo (ERP)
                            </label>
                            <input
                                id="branch-erp-centro"
                                type="number"
                                min="0"
                                value={form.erpCentroPadrao}
                                onChange={e => handleChange('erpCentroPadrao', parseInt(e.target.value) || '')}
                                placeholder="Ex: 3"
                                style={{
                                    width: '100%', padding: '0.6rem 0.85rem', borderRadius: '8px',
                                    border: '1.5px solid var(--border)', background: 'var(--bg-body)',
                                    color: 'var(--text-main)', fontSize: '0.9rem', boxSizing: 'border-box'
                                }}
                            />
                            <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', margin: '0.25rem 0 0' }}>
                                PEDIDOS.ID_PORTADOR (centro de custo)
                            </p>
                        </div>

                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', paddingTop: '0.5rem' }}>
                            <input
                                id="branch-is-default"
                                type="checkbox"
                                checked={form.isDefault}
                                onChange={e => handleChange('isDefault', e.target.checked)}
                                style={{ width: '16px', height: '16px', cursor: 'pointer' }}
                            />
                            <label htmlFor="branch-is-default" style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-main)', cursor: 'pointer' }}>
                                <Star size={13} color="#f59e0b" style={{ verticalAlign: 'middle', marginRight: '4px' }} />
                                Filial padrão (pré-selecionada no login)
                            </label>
                        </div>
                    </div>

                    {/* Actions */}
                    <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1.75rem', paddingTop: '1rem', borderTop: '1px solid var(--border)' }}>
                        <button
                            type="button"
                            onClick={onClose}
                            style={{
                                padding: '0.6rem 1.2rem', borderRadius: '8px',
                                border: '1px solid var(--border)', background: 'transparent',
                                color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 600
                            }}
                        >
                            Cancelar
                        </button>
                        <button
                            type="submit"
                            disabled={isSaving}
                            style={{
                                padding: '0.6rem 1.4rem', borderRadius: '8px',
                                background: '#10b981', border: 'none', color: '#fff',
                                fontWeight: 700, cursor: isSaving ? 'not-allowed' : 'pointer',
                                opacity: isSaving ? 0.7 : 1,
                                display: 'flex', alignItems: 'center', gap: '0.4rem'
                            }}
                        >
                            {isSaving ? <Loader2 size={15} className="animate-spin" /> : <Save size={15} />}
                            {isSaving ? 'Salvando...' : (isEdit ? 'Salvar Filial' : 'Criar Filial')}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    );
}

// ── Main Component ─────────────────────────────────────────────────────────────

export default function BranchesSection({ companyId, companyName }) {
    const [branches, setBranches]           = useState([]);
    const [isLoading, setIsLoading]         = useState(true);
    const [modalBranch, setModalBranch]     = useState(null);   // null = closed; EMPTY_BRANCH = new; obj = edit
    const [isSaving, setIsSaving]           = useState(false);
    const [modalError, setModalError]       = useState('');
    const [deletingId, setDeletingId]       = useState(null);
    const [successMsg, setSuccessMsg]       = useState('');

    const loadBranches = useCallback(async () => {
        setIsLoading(true);
        try {
            const data = await companyService.getBranches(companyId);
            setBranches(data || []);
        } catch (e) {
            console.error('[BranchesSection] Falha ao carregar filiais', e);
        } finally {
            setIsLoading(false);
        }
    }, [companyId]);

    useEffect(() => { loadBranches(); }, [loadBranches]);

    const flashSuccess = (msg) => {
        setSuccessMsg(msg);
        setTimeout(() => setSuccessMsg(''), 3000);
    };

    const handleSave = async (form) => {
        setIsSaving(true);
        setModalError('');
        try {
            let savedBranch;
            if (form.id) {
                savedBranch = await companyService.updateBranch(companyId, form.id, form);
                flashSuccess('Filial atualizada com sucesso!');
            } else {
                savedBranch = await companyService.createBranch(companyId, form);
                flashSuccess('Filial criada com sucesso!');
            }

            // Salvar a associação do parceiro comercial
            const targetBranchId = savedBranch?.id || form.id;
            if (targetBranchId) {
                const assoc = JSON.parse(localStorage.getItem('coliseu_branch_partner_associations') || '{}');
                if (form.associatedPartnerId) {
                    assoc[targetBranchId] = form.associatedPartnerId;
                } else {
                    delete assoc[targetBranchId];
                }
                localStorage.setItem('coliseu_branch_partner_associations', JSON.stringify(assoc));
            }

            // SE HOUVER REQUEST ASSOCIADO, SALVAR O LINK E MARCAR COMO APROVADA
            if (form.associatedRequestId) {
                const links = JSON.parse(localStorage.getItem('coliseu_request_license_links') || '{}');
                links[form.associatedRequestId] = {
                    companyId: companyId,
                    companyName: companyName || 'Empresa Principal',
                    branchId: savedBranch?.id || 'new_branch',
                    branchName: form.name
                };
                localStorage.setItem('coliseu_request_license_links', JSON.stringify(links));
                
                // Atualizar o status da requisição
                await requestService.updateStatus(form.associatedRequestId, 'Aprovada');
            }

            setModalBranch(null);
            await loadBranches();
        } catch (e) {
            setModalError(e?.response?.data?.error || e.message || 'Erro ao salvar filial.');
        } finally {
            setIsSaving(false);
        }
    };

    const handleDelete = async (branch) => {
        if (!window.confirm(`Excluir a filial "${branch.name}"? Esta ação não pode ser desfeita.`)) return;
        setDeletingId(branch.id);
        try {
            await companyService.deleteBranch(companyId, branch.id);
            flashSuccess('Filial excluída.');
            await loadBranches();
        } catch (e) {
            alert('Falha ao excluir: ' + (e?.response?.data?.error || e.message));
        } finally {
            setDeletingId(null);
        }
    };

    return (
        <>
            {modalBranch !== null && (
                <BranchModal
                    branch={modalBranch?.id ? modalBranch : null}
                    onSave={handleSave}
                    onClose={() => { setModalBranch(null); setModalError(''); }}
                    isSaving={isSaving}
                    error={modalError}
                />
            )}

            <div style={{
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                boxShadow: 'var(--shadow-sm)',
                padding: '1.5rem',
                marginBottom: '2rem',
                borderLeft: '4px solid #10b981'
            }}>
                {/* Header */}
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
                    <div>
                        <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <GitBranch size={18} color="#10b981" />
                            Filiais
                        </h3>
                        <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.3rem', marginBottom: 0 }}>
                            Cada filial mapeia para uma empresa no ERP Firebird. O Worker usa esses IDs para rotear pedidos.
                        </p>
                    </div>
                    <button
                        id="btn-add-branch"
                        onClick={() => setModalBranch(EMPTY_BRANCH)}
                        style={{
                            display: 'flex', alignItems: 'center', gap: '0.4rem',
                            padding: '0.5rem 1rem', borderRadius: '8px',
                            background: '#10b981', border: 'none', color: '#fff',
                            fontWeight: 700, fontSize: '0.85rem', cursor: 'pointer',
                            whiteSpace: 'nowrap', flexShrink: 0
                        }}
                    >
                        <Plus size={15} /> Nova Filial
                    </button>
                </div>

                {/* Success flash */}
                {successMsg && (
                    <div style={{
                        padding: '0.55rem 0.9rem', borderRadius: '8px', marginBottom: '1rem',
                        background: 'rgba(16,185,129,0.1)', border: '1px solid rgba(16,185,129,0.3)',
                        color: '#065f46', fontSize: '0.85rem', display: 'flex', alignItems: 'center', gap: '0.4rem'
                    }}>
                        <CheckCircle2 size={14} /> {successMsg}
                    </div>
                )}

                {/* Content */}
                {isLoading ? (
                    <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)', display: 'flex', justifyContent: 'center', gap: '0.5rem' }}>
                        <Loader2 size={18} className="animate-spin" /> Carregando filiais...
                    </div>
                ) : branches.length === 0 ? (
                    <div style={{
                        padding: '2rem', textAlign: 'center',
                        border: '1px dashed var(--border)', borderRadius: '10px',
                        color: 'var(--text-muted)', fontSize: '0.875rem'
                    }}>
                        <Building2 size={32} style={{ marginBottom: '0.5rem', opacity: 0.4 }} />
                        <p style={{ margin: 0 }}>Nenhuma filial cadastrada. Clique em <strong>Nova Filial</strong> para começar.</p>
                    </div>
                ) : (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.6rem' }}>
                        {branches.map(branch => (
                            <div
                                key={branch.id}
                                style={{
                                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                                    padding: '0.85rem 1rem', borderRadius: '10px',
                                    background: 'var(--bg-body)', border: '1px solid var(--border)',
                                    gap: '1rem', flexWrap: 'wrap'
                                }}
                            >
                                {/* Info */}
                                <div style={{ flex: 1, minWidth: 0 }}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
                                        <span style={{ fontWeight: 700, color: 'var(--text-main)', fontSize: '0.95rem', marginRight: '0.25rem' }}>
                                            {branch.name}
                                        </span>
                                        {branch.isDefault && (
                                            <span style={{
                                                display: 'inline-flex', alignItems: 'center', gap: '3px',
                                                background: 'rgba(245,158,11,0.12)', color: '#92400e',
                                                borderRadius: '20px', padding: '1px 8px',
                                                fontSize: '0.72rem', fontWeight: 700
                                            }}>
                                                <Star size={10} color="#f59e0b" /> Padrão
                                            </span>
                                        )}
                                        {branch.cnpj && (
                                            <span style={{
                                                fontSize: '0.72rem',
                                                fontFamily: 'monospace',
                                                background: 'rgba(27,143,205,0.06)',
                                                color: '#1b8fcd',
                                                border: '1px solid rgba(27,143,205,0.15)',
                                                padding: '1px 6px',
                                                borderRadius: '6px',
                                                fontWeight: 600
                                            }}>
                                                {branch.cnpj}
                                            </span>
                                        )}
                                        <span style={{
                                            fontSize: '0.72rem',
                                            fontWeight: 600,
                                            padding: '2px 8px',
                                            borderRadius: '6px',
                                            background: 'rgba(0,0,0,0.04)',
                                            color: 'var(--text-sub)',
                                            border: '1px solid var(--border)'
                                        }}>
                                            Empresa ERP: <strong style={{ color: 'var(--text-main)' }}>{branch.erpEmpresaId ?? '—'}</strong>
                                        </span>
                                        <span style={{
                                            fontSize: '0.72rem',
                                            fontWeight: 600,
                                            padding: '2px 8px',
                                            borderRadius: '6px',
                                            background: 'rgba(0,0,0,0.04)',
                                            color: 'var(--text-sub)',
                                            border: '1px solid var(--border)'
                                        }}>
                                            Depto: <strong style={{ color: 'var(--text-main)' }}>{branch.erpDeptoPadrao ?? '—'}</strong>
                                        </span>
                                        <span style={{
                                            fontSize: '0.72rem',
                                            fontWeight: 600,
                                            padding: '2px 8px',
                                            borderRadius: '6px',
                                            background: 'rgba(0,0,0,0.04)',
                                            color: 'var(--text-sub)',
                                            border: '1px solid var(--border)'
                                        }}>
                                            Centro: <strong style={{ color: 'var(--text-main)' }}>{branch.erpCentroPadrao ?? '—'}</strong>
                                        </span>
                                    </div>
                                </div>

                                {/* Actions */}
                                <div style={{ display: 'flex', gap: '0.4rem', flexShrink: 0 }}>
                                    <button
                                        onClick={() => { setModalBranch(branch); setModalError(''); }}
                                        title="Editar filial"
                                        style={{
                                            padding: '0.4rem 0.7rem', borderRadius: '7px',
                                            border: '1px solid var(--border)', background: 'transparent',
                                            color: 'var(--text-muted)', cursor: 'pointer',
                                            display: 'flex', alignItems: 'center', gap: '0.3rem',
                                            fontSize: '0.8rem', fontWeight: 600
                                        }}
                                    >
                                        <Pencil size={13} /> Editar
                                    </button>
                                    <button
                                        onClick={() => handleDelete(branch)}
                                        disabled={deletingId === branch.id}
                                        title="Excluir filial"
                                        style={{
                                            padding: '0.4rem 0.7rem', borderRadius: '7px',
                                            border: '1px solid rgba(239,68,68,0.4)',
                                            background: 'transparent', color: '#ef4444',
                                            cursor: deletingId === branch.id ? 'not-allowed' : 'pointer',
                                            display: 'flex', alignItems: 'center', gap: '0.3rem',
                                            fontSize: '0.8rem', fontWeight: 600,
                                            opacity: deletingId === branch.id ? 0.6 : 1
                                        }}
                                    >
                                        {deletingId === branch.id
                                            ? <Loader2 size={13} className="animate-spin" />
                                            : <Trash2 size={13} />}
                                        Excluir
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </>
    );
}
