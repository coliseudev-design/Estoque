import React, { useState, useEffect } from 'react';
import {
    Handshake, Plus, Search, Building2, Layers, Mail, Phone,
    User, Edit2, Trash2, ShieldAlert, Check, X, Building
} from 'lucide-react';
import { partnerService } from '../../services/partnerService';
import { requestService } from '../../services/requestService';
import { companyService } from '../../services/companyService';

// ─── Design Tokens (Alinhados com o index.css) ───────────────────────────────
const C = {
    primary:       '#1B8FCD',
    primaryDark:   '#1578AD',
    primaryAlpha:  'rgba(27,143,205,0.10)',
    success:       '#10B981',
    successAlpha:  'rgba(16,185,129,0.08)',
    danger:        '#EF4444',
    dangerAlpha:   'rgba(239,68,68,0.08)',
    warn:          '#F59E0B',
    warnAlpha:     'rgba(245,158,11,0.08)',
    info:          '#3B82F6',
    infoAlpha:     'rgba(59,130,246,0.08)',
    surface:       'var(--surface, #ffffff)',
    bg:            'var(--bg, #f5f8fc)',
    border:        'var(--border, rgba(27,143,205,0.12))',
    textMain:      'var(--text-main, #2d3748)',
    textSub:       'var(--text-sub, #4a5568)',
    textMuted:     'var(--text-muted, #718096)',
    textHint:      'var(--text-hint, #a0aec0)',
};

const MODULE_META = {
    'coliseu-speed': { label: 'Coliseu Speed', icon: '🏪', color: '#2196f3' },
    'autocenter':    { label: 'Auto Center', icon: '🔧', color: '#ff9800' },
    'coliseu-dash':  { label: 'Coliseu Dash', icon: '📈', color: '#10b981' },
    'controle-garantias': { label: 'Controle de Garantias', icon: '🛡️', color: '#0a58ca' },
    'nexus':         { label: 'Nexus', icon: '🌐', color: '#0891b2' },
    'visicon':       { label: 'Visicon', icon: '👁️', color: '#8b5cf6' },
    'siscom':        { label: 'Siscom', icon: '💼', color: '#ec4899' },
};

// ─── Helpers Máscaras ────────────────────────────────────────────────────────
const maskCnpj = (value) => {
    return value
        .replace(/\D/g, '')
        .replace(/^(\d{2})(\d)/, '$1.$2')
        .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
        .replace(/\.(\d{3})(\d)/, '.$1/$2')
        .replace(/(\d{4})(\d)/, '$1-$2')
        .substring(0, 18);
};

const maskPhone = (value) => {
    return value
        .replace(/\D/g, '')
        .replace(/^(\d{2})(\d)/, '($1) $2')
        .replace(/(\d{5})(\d)/, '$1-$2')
        .substring(0, 15);
};

export default function Partners() {
    const [partners, setPartners] = useState([]);
    const [requests, setRequests] = useState([]);
    const [companies, setCompanies] = useState([]);
    const [branches, setBranches] = useState([]);
    const [companyModules, setCompanyModules] = useState({});
    const [branchPartnerAssoc, setBranchPartnerAssoc] = useState({});
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');

    // Modal state
    const [modalOpen, setModalOpen] = useState(false);
    const [editPartner, setEditPartner] = useState(null);

    // Form states
    const [formName, setFormName] = useState('');
    const [formCnpj, setFormCnpj] = useState('');
    const [formContactName, setFormContactName] = useState('');
    const [formEmail, setFormEmail] = useState('');
    const [formPhone, setFormPhone] = useState('');

    // Delete confirmation state
    const [deleteConfirmId, setDeleteConfirmId] = useState(null);

    const loadData = async () => {
        setLoading(true);
        try {
            const [pList, rList, compData] = await Promise.all([
                partnerService.listPartners(),
                requestService.listRequests(),
                companyService.getCompanies(1, 1000, '')
            ]);
            setPartners(pList);
            setRequests(rList);

            const companiesList = compData?.items || [];
            setCompanies(companiesList);

            const branchesPromises = companiesList.map(comp =>
                companyService.getBranches(comp.id)
                    .then(bList => ({ companyId: comp.id, branches: bList || [] }))
                    .catch(err => {
                        console.error(`Erro ao buscar filiais para ${comp.name}`, err);
                        return { companyId: comp.id, branches: [] };
                    })
            );

            const modulesPromises = companiesList.map(comp =>
                companyService.listModules(comp.id)
                    .then(mList => ({ companyId: comp.id, modules: mList || [] }))
                    .catch(err => {
                        console.error(`Erro ao buscar módulos para ${comp.name}`, err);
                        return { companyId: comp.id, modules: [] };
                    })
            );

            const [branchesRes, modulesRes] = await Promise.all([
                Promise.all(branchesPromises),
                Promise.all(modulesPromises)
            ]);

            const allBranches = [];
            branchesRes.forEach(({ companyId, branches: bList }) => {
                bList.forEach(b => {
                    allBranches.push({ ...b, companyId });
                });
            });
            setBranches(allBranches);

            const modulesMap = {};
            modulesRes.forEach(({ companyId, modules: mList }) => {
                modulesMap[companyId] = mList;
            });
            setCompanyModules(modulesMap);

            const coliseuPartner = pList.find(p => p.cnpj === '29.639.089/0001-12' || p.name.toLowerCase() === 'coliseu sistemas');
            const coliseuId = coliseuPartner ? coliseuPartner.id : 'p_coliseu';

            const assoc = JSON.parse(localStorage.getItem('coliseu_branch_partner_associations') || '{}');
            let updatedAssoc = { ...assoc };
            let hasChanges = false;

            allBranches.forEach(b => {
                if (!assoc[b.id]) {
                    updatedAssoc[b.id] = coliseuId;
                    hasChanges = true;
                }
            });

            if (hasChanges) {
                localStorage.setItem('coliseu_branch_partner_associations', JSON.stringify(updatedAssoc));
            }
            setBranchPartnerAssoc(updatedAssoc);
        } catch (err) {
            console.error('Erro ao buscar dados:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadData();
    }, []);

    // Abre o modal para cadastro de novo parceiro
    const handleOpenCreateModal = () => {
        setEditPartner(null);
        setFormName('');
        setFormCnpj('');
        setFormContactName('');
        setFormEmail('');
        setFormPhone('');
        setModalOpen(true);
    };

    // Abre o modal para edição de um parceiro existente
    const handleOpenEditModal = (partner) => {
        setEditPartner(partner);
        setFormName(partner.name);
        setFormCnpj(partner.cnpj);
        setFormContactName(partner.contactName);
        setFormEmail(partner.email);
        setFormPhone(partner.phone);
        setModalOpen(true);
    };

    // Envio do formulário (Criar / Editar)
    const handleSavePartner = async (e) => {
        e.preventDefault();
        if (!formName || !formCnpj || !formContactName || !formEmail || !formPhone) {
            alert('Por favor, preencha todos os campos obrigatórios.');
            return;
        }

        if (formCnpj.length < 18) {
            alert('Por favor, insira um CNPJ válido.');
            return;
        }

        const payload = {
            name: formName,
            cnpj: formCnpj,
            contactName: formContactName,
            email: formEmail,
            phone: formPhone
        };

        setSaving(true);
        try {
            if (editPartner) {
                await partnerService.updatePartner({ ...editPartner, ...payload });
            } else {
                await partnerService.createPartner(payload);
            }
            setModalOpen(false);
            await loadData();
        } catch (err) {
            alert(err?.response?.data?.error || 'Erro ao salvar parceiro.');
        } finally {
            setSaving(false);
        }
    };

    // Exclusão de parceiro
    const handleDeletePartner = async () => {
        if (!deleteConfirmId) return;
        try {
            await partnerService.deletePartner(deleteConfirmId);
            setDeleteConfirmId(null);
            await loadData();
        } catch (err) {
            alert(err?.response?.data?.error || 'Erro ao excluir parceiro.');
        }
    };

    // ─── Métricas e Estatísticas Globais ─────────────────────────────────────
    
    // Obter as empresas ativas (status === 'Active')
    const activeCompanyIds = new Set(companies.filter(c => c.status === 'Active').map(c => c.id));

    // Filiais de empresas ativas
    const activeBranches = branches.filter(b => activeCompanyIds.has(b.companyId));

    // Total de empresas ativas de todos os parceiros (contando filiais de empresas ativas)
    const totalActiveCompanies = activeBranches.length;

    // Total de licenças/módulos ativas de todos os parceiros
    const totalActiveModules = Object.entries(companyModules).reduce((acc, [compId, compMods]) => {
        if (!activeCompanyIds.has(compId)) return acc;
        const qty = compMods?.reduce((sum, m) => sum + (m.isActive ? (Number(m.deviceLimit) || 1) : 0), 0) || 0;
        return acc + qty;
    }, 0);

    // ─── Estatísticas por Parceiro ──────────────────────────────────────────
    const getPartnerStats = (partnerId) => {
        // Filiais ativas associadas a este parceiro
        const partnerBranches = activeBranches.filter(b => branchPartnerAssoc[b.id] === partnerId);
        const companiesCount = partnerBranches.length;

        // Obter empresas ativas únicas a partir destas filiais
        const uniqueCompanyIds = [...new Set(partnerBranches.map(b => b.companyId))];

        // Agrupamento de módulos ativos destas empresas
        const moduleGroups = {};
        uniqueCompanyIds.forEach(compId => {
            const compMods = companyModules[compId] || [];
            compMods.forEach(m => {
                if (m.isActive) {
                    const slug = m.moduleSlug;
                    const qty = Number(m.deviceLimit) || 1;
                    moduleGroups[slug] = (moduleGroups[slug] || 0) + qty;
                }
            });
        });

        // Total de módulos
        const totalModules = Object.values(moduleGroups).reduce((sum, val) => sum + val, 0);

        // Array formatado para exibição
        const activeModulesList = Object.entries(moduleGroups).map(([slug, qty]) => ({
            slug,
            qty,
            meta: MODULE_META[slug] || { label: slug, icon: '📦', color: '#64748b' }
        }));

        return {
            companiesCount,
            totalModules,
            activeModulesList
        };
    };

    // Filtro dos parceiros listados
    const filteredPartners = partners.filter(p => {
        const query = searchQuery.toLowerCase();
        return p.name.toLowerCase().includes(query) ||
               p.cnpj.replace(/\D/g, '').includes(searchQuery.replace(/\D/g, '')) ||
               p.contactName.toLowerCase().includes(query);
    });

    return (
        <div className="page-enter" style={{ display: 'flex', flexDirection: 'column', gap: '2rem' }}>
            {/* Header da Página */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
                <span style={{
                    fontSize: '0.74rem',
                    fontWeight: 700,
                    textTransform: 'uppercase',
                    letterSpacing: '0.08em',
                    color: C.primary,
                }}>
                    Parceiros Credenciados
                </span>
                <h1 style={{
                    margin: 0,
                    fontSize: '1.75rem',
                    fontWeight: 800,
                    color: C.textMain,
                    letterSpacing: '-0.02em',
                }}>
                    Gestão de Parceiros Comerciais
                </h1>
                <p style={{
                    margin: 0,
                    fontSize: '0.875rem',
                    color: C.textMuted,
                    maxWidth: '800px',
                }}>
                    Gerencie os parceiros credenciados, visualize as empresas ativas sob a gestão de cada um e acompanhe os módulos licenciados em tempo real.
                </p>
            </div>

            {/* Grid de KPIs do Dashboard Global */}
            <div style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
                gap: '1.25rem',
            }}>
                {/* KPI 1: Total de Parceiros */}
                <div className="card fade-slide-up anim-delay-1" style={{
                    background: C.surface,
                    borderRadius: '16px',
                    padding: '1.5rem',
                    border: `1px solid ${C.border}`,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '1.25rem',
                    boxShadow: 'var(--shadow-sm)',
                    position: 'relative',
                    overflow: 'hidden',
                }}>
                    <div style={{
                        position: 'absolute', top: 0, right: 0,
                        width: '80px', height: '80px',
                        background: 'radial-gradient(circle, rgba(27,143,205,0.06) 0%, transparent 70%)',
                        pointerEvents: 'none',
                    }} />
                    <div style={{
                        width: 48, height: 48, borderRadius: '12px',
                        background: 'rgba(27,143,205,0.08)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: C.primary, flexShrink: 0
                    }}>
                        <Handshake size={24} />
                    </div>
                    <div>
                        <span style={{ fontSize: '0.78rem', fontWeight: 600, color: C.textMuted }}>Total de Parceiros</span>
                        <h2 style={{ margin: '0.15rem 0 0', fontSize: '1.6rem', fontWeight: 800, color: C.textMain }}>{partners.length}</h2>
                        <span style={{ fontSize: '0.68rem', color: C.textHint }}>Cadastrados no sistema</span>
                    </div>
                </div>

                {/* KPI 2: Empresas Ativas */}
                <div className="card fade-slide-up anim-delay-2" style={{
                    background: C.surface,
                    borderRadius: '16px',
                    padding: '1.5rem',
                    border: `1px solid ${C.border}`,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '1.25rem',
                    boxShadow: 'var(--shadow-sm)',
                    position: 'relative',
                    overflow: 'hidden',
                }}>
                    <div style={{
                        position: 'absolute', top: 0, right: 0,
                        width: '80px', height: '80px',
                        background: 'radial-gradient(circle, rgba(16,185,129,0.06) 0%, transparent 70%)',
                        pointerEvents: 'none',
                    }} />
                    <div style={{
                        width: 48, height: 48, borderRadius: '12px',
                        background: 'rgba(16,185,129,0.08)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: C.success, flexShrink: 0
                    }}>
                        <Building2 size={24} />
                    </div>
                    <div>
                        <span style={{ fontSize: '0.78rem', fontWeight: 600, color: C.textMuted }}>Empresas Ativas</span>
                        <h2 style={{ margin: '0.15rem 0 0', fontSize: '1.6rem', fontWeight: 800, color: C.textMain }}>{totalActiveCompanies}</h2>
                        <span style={{ fontSize: '0.68rem', color: C.textHint }}>CNPJs com licenças ativas</span>
                    </div>
                </div>

                {/* KPI 3: Módulos Licenciados */}
                <div className="card fade-slide-up anim-delay-3" style={{
                    background: C.surface,
                    borderRadius: '16px',
                    padding: '1.5rem',
                    border: `1px solid ${C.border}`,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '1.25rem',
                    boxShadow: 'var(--shadow-sm)',
                    position: 'relative',
                    overflow: 'hidden',
                }}>
                    <div style={{
                        position: 'absolute', top: 0, right: 0,
                        width: '80px', height: '80px',
                        background: 'radial-gradient(circle, rgba(59,130,246,0.06) 0%, transparent 70%)',
                        pointerEvents: 'none',
                    }} />
                    <div style={{
                        width: 48, height: 48, borderRadius: '12px',
                        background: 'rgba(59,130,246,0.08)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: C.info, flexShrink: 0
                    }}>
                        <Layers size={24} />
                    </div>
                    <div>
                        <span style={{ fontSize: '0.78rem', fontWeight: 600, color: C.textMuted }}>Módulos Licenciados</span>
                        <h2 style={{ margin: '0.15rem 0 0', fontSize: '1.6rem', fontWeight: 800, color: C.textMain }}>{totalActiveModules}</h2>
                        <span style={{ fontSize: '0.68rem', color: C.textHint }}>Total de licenças ativas</span>
                    </div>
                </div>
            </div>

            {/* Barra de Ações (Filtros e Botão Novo) */}
            <div className="card" style={{
                background: C.surface,
                borderRadius: '16px',
                padding: '1rem 1.25rem',
                border: `1px solid ${C.border}`,
                display: 'flex',
                flexWrap: 'wrap',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: '1rem',
                boxShadow: 'var(--shadow-sm)',
            }}>
                {/* Busca */}
                <div style={{ position: 'relative', flex: 1, minWidth: '260px', maxWidth: '480px' }}>
                    <Search size={16} color={C.textMuted} style={{
                        position: 'absolute',
                        left: '14px',
                        top: '50%',
                        transform: 'translateY(-50%)',
                        pointerEvents: 'none'
                    }} />
                    <input
                        type="text"
                        placeholder="Buscar por parceiro ou CNPJ..."
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        className="input-field"
                        style={{
                            paddingLeft: '40px',
                            height: '42px',
                            borderRadius: '10px',
                            width: '100%',
                            boxSizing: 'border-box',
                            fontSize: '0.85rem'
                        }}
                    />
                    {searchQuery && (
                        <button
                            onClick={() => setSearchQuery('')}
                            style={{
                                position: 'absolute',
                                right: '12px',
                                top: '50%',
                                transform: 'translateY(-50%)',
                                background: 'transparent',
                                border: 'none',
                                cursor: 'pointer',
                                color: C.textHint,
                                padding: '2px'
                            }}
                        >
                            <X size={14} />
                        </button>
                    )}
                </div>

                {/* Botão Novo */}
                <button
                    onClick={handleOpenCreateModal}
                    className="btn btn-primary"
                    style={{
                        height: '42px',
                        borderRadius: '10px',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '0.5rem',
                        fontWeight: 600,
                        fontSize: '0.85rem',
                        padding: '0 1.25rem',
                        background: 'var(--gradient-primary)',
                        color: 'white',
                        border: 'none',
                        cursor: 'pointer',
                        boxShadow: '0 4px 12px rgba(27,143,205,0.2)',
                    }}
                >
                    <Plus size={16} /> Novo Parceiro
                </button>
            </div>

            {/* Grid dos Parceiros Cadastrados */}
            {loading ? (
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '4rem 0', gap: '1rem' }}>
                    <div className="animate-spin" style={{
                        width: '32px', height: '32px',
                        borderRadius: '50%',
                        border: `3px solid ${C.primaryAlpha}`,
                        borderTopColor: C.primary,
                    }} />
                    <span style={{ fontSize: '0.85rem', color: C.textMuted, fontWeight: 600 }}>Carregando parceiros...</span>
                </div>
            ) : filteredPartners.length === 0 ? (
                <div className="card" style={{
                    background: C.surface,
                    borderRadius: '16px',
                    padding: '4rem 2rem',
                    border: `1px solid ${C.border}`,
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    textAlign: 'center',
                    gap: '1rem',
                    boxShadow: 'var(--shadow-sm)',
                }}>
                    <div style={{
                        width: 56, height: 56, borderRadius: '50%',
                        background: 'rgba(27,143,205,0.06)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        color: C.primary, marginBottom: '0.5rem'
                    }}>
                        <Handshake size={28} />
                    </div>
                    <div>
                        <h3 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 700, color: C.textMain }}>
                            {searchQuery ? 'Nenhum parceiro corresponde à busca' : 'Nenhum parceiro comercial'}
                        </h3>
                        <p style={{ margin: '0.25rem 0 0', fontSize: '0.85rem', color: C.textMuted, maxWidth: '400px' }}>
                            {searchQuery ? 'Tente ajustar os termos da pesquisa ou limpe o filtro atual.' : 'Comece cadastrando um novo parceiro comercial credenciado para gerenciar suas licenças.'}
                        </p>
                    </div>
                    {!searchQuery && (
                        <button
                            onClick={handleOpenCreateModal}
                            className="btn btn-primary"
                            style={{
                                height: '38px',
                                borderRadius: '8px',
                                display: 'flex',
                                alignItems: 'center',
                                gap: '0.5rem',
                                fontSize: '0.85rem',
                                fontWeight: 600,
                                padding: '0 1rem',
                                cursor: 'pointer',
                                background: 'var(--gradient-primary)',
                                color: 'white',
                                border: 'none'
                            }}
                        >
                            <Plus size={15} /> Cadastrar Parceiro
                        </button>
                    )}
                </div>
            ) : (
                <div style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(340px, 1fr))',
                    gap: '1.25rem',
                }}>
                    {filteredPartners.map((partner, index) => {
                        const { companiesCount, totalModules, activeModulesList } = getPartnerStats(partner.id);
                        
                        return (
                            <div
                                key={partner.id}
                                className="card fade-slide-up"
                                style={{
                                    background: C.surface,
                                    borderRadius: '16px',
                                    border: `1px solid ${C.border}`,
                                    boxShadow: 'var(--shadow-sm)',
                                    display: 'flex',
                                    flexDirection: 'column',
                                    overflow: 'hidden',
                                    transition: 'transform 0.22s ease, box-shadow 0.22s ease',
                                    animationDelay: `${index * 0.05}s`
                                }}
                                onMouseEnter={(e) => {
                                    e.currentTarget.style.transform = 'translateY(-3px)';
                                    e.currentTarget.style.boxShadow = 'var(--shadow-md)';
                                }}
                                onMouseLeave={(e) => {
                                    e.currentTarget.style.transform = 'translateY(0)';
                                    e.currentTarget.style.boxShadow = 'var(--shadow-sm)';
                                }}
                            >
                                {/* Header do Card */}
                                <div style={{
                                    padding: '1.25rem 1.25rem 0.75rem',
                                    borderBottom: `1px solid var(--border-light, rgba(27,143,205,0.06))`,
                                    display: 'flex',
                                    justifyContent: 'space-between',
                                    alignItems: 'flex-start',
                                    gap: '0.75rem',
                                }}>
                                    <div style={{ overflow: 'hidden' }}>
                                        <h3 style={{
                                            margin: 0,
                                            fontSize: '0.98rem',
                                            fontWeight: 700,
                                            color: C.textMain,
                                            whiteSpace: 'nowrap',
                                            overflow: 'hidden',
                                            textOverflow: 'ellipsis'
                                        }} title={partner.name}>
                                            {partner.name}
                                        </h3>
                                        <span style={{
                                            fontSize: '0.72rem',
                                            color: C.textMuted,
                                            fontFamily: 'monospace',
                                            fontWeight: 600
                                        }}>
                                            CNPJ: {partner.cnpj}
                                        </span>
                                    </div>
                                    
                                    {/* Ações Rápidas */}
                                    <div style={{ display: 'flex', gap: '0.35rem', flexShrink: 0 }}>
                                        <button
                                            onClick={() => handleOpenEditModal(partner)}
                                            style={{
                                                width: 28, height: 28, borderRadius: '6px',
                                                background: 'transparent', border: `1px solid ${C.border}`,
                                                color: C.textMuted, cursor: 'pointer',
                                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                transition: 'all 0.15s'
                                            }}
                                            onMouseEnter={(e) => {
                                                e.currentTarget.style.color = C.primary;
                                                e.currentTarget.style.borderColor = C.primary;
                                                e.currentTarget.style.background = 'rgba(27,143,205,0.05)';
                                            }}
                                            onMouseLeave={(e) => {
                                                e.currentTarget.style.color = C.textMuted;
                                                e.currentTarget.style.borderColor = C.border;
                                                e.currentTarget.style.background = 'transparent';
                                            }}
                                            title="Editar parceiro"
                                        >
                                            <Edit2 size={13} />
                                        </button>
                                        <button
                                            onClick={() => setDeleteConfirmId(partner.id)}
                                            style={{
                                                width: 28, height: 28, borderRadius: '6px',
                                                background: 'transparent', border: `1px solid ${C.border}`,
                                                color: C.textMuted, cursor: 'pointer',
                                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                transition: 'all 0.15s'
                                            }}
                                            onMouseEnter={(e) => {
                                                e.currentTarget.style.color = C.danger;
                                                e.currentTarget.style.borderColor = C.danger;
                                                e.currentTarget.style.background = 'rgba(239,68,68,0.05)';
                                            }}
                                            onMouseLeave={(e) => {
                                                e.currentTarget.style.color = C.textMuted;
                                                e.currentTarget.style.borderColor = C.border;
                                                e.currentTarget.style.background = 'transparent';
                                            }}
                                            title="Excluir parceiro"
                                        >
                                            <Trash2 size={13} />
                                        </button>
                                    </div>
                                </div>

                                {/* Conteúdo do Card */}
                                <div style={{
                                    padding: '1rem 1.25rem',
                                    display: 'flex',
                                    flexDirection: 'column',
                                    gap: '0.6rem',
                                    flex: 1
                                }}>
                                    {/* Contatos */}
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', fontSize: '0.78rem' }}>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: C.textSub }}>
                                            <User size={13} color={C.textHint} style={{ flexShrink: 0 }} />
                                            <span style={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                                {partner.contactName}
                                            </span>
                                        </div>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: C.textSub }}>
                                            <Mail size={13} color={C.textHint} style={{ flexShrink: 0 }} />
                                            <a href={`mailto:${partner.email}`} style={{ color: 'inherit', textDecoration: 'none', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                                {partner.email}
                                            </a>
                                        </div>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', color: C.textSub }}>
                                            <Phone size={13} color={C.textHint} style={{ flexShrink: 0 }} />
                                            <span>{partner.phone}</span>
                                        </div>
                                    </div>

                                    {/* Divisor */}
                                    <div style={{ borderTop: `1px solid var(--border-light, rgba(27,143,205,0.06))`, margin: '0.4rem 0' }} />

                                    {/* Métricas do Parceiro */}
                                    <div style={{
                                        display: 'grid',
                                        gridTemplateColumns: '1fr 1fr',
                                        gap: '0.75rem',
                                        marginBottom: '0.4rem'
                                    }}>
                                        <div style={{
                                            background: 'rgba(27,143,205,0.04)',
                                            border: `1px solid rgba(27,143,205,0.08)`,
                                            borderRadius: '10px',
                                            padding: '0.5rem 0.75rem',
                                            display: 'flex',
                                            flexDirection: 'column',
                                        }}>
                                            <span style={{ fontSize: '0.65rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase' }}>Empresas</span>
                                            <span style={{ fontSize: '1.1rem', fontWeight: 800, color: C.primary }}>{companiesCount}</span>
                                        </div>
                                        <div style={{
                                            background: 'rgba(16,185,129,0.03)',
                                            border: `1px solid rgba(16,185,129,0.07)`,
                                            borderRadius: '10px',
                                            padding: '0.5rem 0.75rem',
                                            display: 'flex',
                                            flexDirection: 'column',
                                        }}>
                                            <span style={{ fontSize: '0.65rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase' }}>Licenças Ativas</span>
                                            <span style={{ fontSize: '1.1rem', fontWeight: 800, color: C.success }}>{totalModules}</span>
                                        </div>
                                    </div>

                                    {/* Listagem de Módulos */}
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
                                        <span style={{ fontSize: '0.68rem', fontWeight: 700, color: C.textHint, textTransform: 'uppercase', letterSpacing: '0.02em' }}>
                                            Resumo de Distribuição
                                        </span>
                                        
                                        {activeModulesList.length === 0 ? (
                                            <span style={{ fontSize: '0.74rem', color: C.textHint, fontStyle: 'italic', padding: '0.2rem 0' }}>
                                                Nenhuma licença ativa
                                            </span>
                                        ) : (
                                            <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                                                {activeModulesList.map(item => (
                                                    <span
                                                        key={item.slug}
                                                        style={{
                                                            display: 'inline-flex',
                                                            alignItems: 'center',
                                                            gap: '3px',
                                                            padding: '2px 8px',
                                                            borderRadius: '6px',
                                                            fontSize: '0.7rem',
                                                            fontWeight: 700,
                                                            background: `${item.meta.color}10`,
                                                            color: item.meta.color,
                                                            border: `1px solid ${item.meta.color}20`
                                                        }}
                                                        title={item.meta.label}
                                                    >
                                                        <span>{item.meta.icon}</span>
                                                        <span>{item.meta.label}</span>
                                                        <span style={{
                                                            fontSize: '0.66rem',
                                                            fontWeight: 800,
                                                            marginLeft: '3px',
                                                            paddingLeft: '4px',
                                                            borderLeft: `1px solid ${item.meta.color}25`
                                                        }}>
                                                            {item.qty}
                                                        </span>
                                                    </span>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}

            {/* Modal de Criar / Editar Parceiro */}
            {modalOpen && (
                <div onClick={() => setModalOpen(false)} style={{
                    position: 'fixed', inset: 0,
                    background: 'rgba(15, 23, 42, 0.4)',
                    backdropFilter: 'blur(8px)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    zIndex: 1000, animation: 'fadeIn 0.18s ease',
                    padding: '1rem',
                }}>
                    <div onClick={e => e.stopPropagation()} style={{
                        background: C.surface,
                        border: `1px solid ${C.border}`,
                        borderRadius: '20px', width: '500px', maxWidth: '95vw',
                        maxHeight: '90vh', overflowY: 'auto',
                        boxShadow: '0 24px 80px rgba(15,23,42,0.18)',
                        animation: 'scaleIn 0.22s cubic-bezier(0.34, 1.56, 0.64, 1)',
                        color: C.textMain,
                    }}>
                        <div style={{
                            padding: '1.25rem 1.5rem 1rem',
                            borderBottom: `1px solid ${C.border}`,
                            display: 'flex', alignItems: 'center', gap: '0.75rem',
                        }}>
                            <div style={{
                                width: 36, height: 36, borderRadius: '10px',
                                background: 'var(--gradient-primary)',
                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                boxShadow: '0 4px 12px rgba(27,143,205,0.2)', flexShrink: 0,
                            }}>
                                <Handshake size={18} color="#fff" />
                            </div>
                            <h3 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 700, color: C.textMain, flex: 1 }}>
                                {editPartner ? 'Editar Parceiro Comercial' : 'Cadastrar Parceiro Comercial'}
                            </h3>
                            <button onClick={() => setModalOpen(false)} style={{
                                width: 32, height: 32, background: 'rgba(0,0,0,0.04)',
                                border: `1px solid ${C.border}`, borderRadius: '8px',
                                cursor: 'pointer', color: C.textMuted,
                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                transition: 'all 0.15s',
                            }}>
                                <X size={16} />
                            </button>
                        </div>
                        
                        <form onSubmit={handleSavePartner} style={{ padding: '1.5rem', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
                            {/* Razão Social */}
                            <div>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 600, color: C.textSub, marginBottom: '0.4rem' }}>
                                    Razão Social / Nome <span style={{ color: C.danger }}>*</span>
                                </label>
                                <input
                                    type="text"
                                    placeholder="Razão Social da Empresa Parceira"
                                    value={formName}
                                    onChange={(e) => setFormName(e.target.value)}
                                    className="input-field"
                                    style={{
                                        width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
                                        background: 'var(--bg-input, #fff)', border: `1px solid ${C.border}`,
                                        color: C.textMain, fontSize: '0.875rem', outline: 'none', boxSizing: 'border-box'
                                    }}
                                    required
                                />
                            </div>

                            {/* CNPJ */}
                            <div>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 600, color: C.textSub, marginBottom: '0.4rem' }}>
                                    CNPJ do Parceiro <span style={{ color: C.danger }}>*</span>
                                </label>
                                <input
                                    type="text"
                                    placeholder="00.000.000/0000-00"
                                    value={formCnpj}
                                    onChange={(e) => setFormCnpj(maskCnpj(e.target.value))}
                                    className="input-field"
                                    style={{
                                        width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
                                        background: 'var(--bg-input, #fff)', border: `1px solid ${C.border}`,
                                        color: C.textMain, fontSize: '0.875rem', outline: 'none', boxSizing: 'border-box',
                                        fontFamily: 'monospace'
                                    }}
                                    maxLength={18}
                                    required
                                />
                            </div>

                            {/* Nome do Contato */}
                            <div>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 600, color: C.textSub, marginBottom: '0.4rem' }}>
                                    Nome de Contato / Responsável <span style={{ color: C.danger }}>*</span>
                                </label>
                                <input
                                    type="text"
                                    placeholder="Nome do contato principal"
                                    value={formContactName}
                                    onChange={(e) => setFormContactName(e.target.value)}
                                    className="input-field"
                                    style={{
                                        width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
                                        background: 'var(--bg-input, #fff)', border: `1px solid ${C.border}`,
                                        color: C.textMain, fontSize: '0.875rem', outline: 'none', boxSizing: 'border-box'
                                    }}
                                    required
                                />
                            </div>

                            {/* E-mail */}
                            <div>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 600, color: C.textSub, marginBottom: '0.4rem' }}>
                                    E-mail de Contato <span style={{ color: C.danger }}>*</span>
                                </label>
                                <input
                                    type="email"
                                    placeholder="parceiro@exemplo.com.br"
                                    value={formEmail}
                                    onChange={(e) => setFormEmail(e.target.value)}
                                    className="input-field"
                                    style={{
                                        width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
                                        background: 'var(--bg-input, #fff)', border: `1px solid ${C.border}`,
                                        color: C.textMain, fontSize: '0.875rem', outline: 'none', boxSizing: 'border-box'
                                    }}
                                    required
                                />
                            </div>

                            {/* Telefone */}
                            <div>
                                <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 600, color: C.textSub, marginBottom: '0.4rem' }}>
                                    Telefone / WhatsApp <span style={{ color: C.danger }}>*</span>
                                </label>
                                <input
                                    type="text"
                                    placeholder="(00) 00000-0000"
                                    value={formPhone}
                                    onChange={(e) => setFormPhone(maskPhone(e.target.value))}
                                    className="input-field"
                                    style={{
                                        width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
                                        background: 'var(--bg-input, #fff)', border: `1px solid ${C.border}`,
                                        color: C.textMain, fontSize: '0.875rem', outline: 'none', boxSizing: 'border-box'
                                    }}
                                    maxLength={15}
                                    required
                                />
                            </div>

                            {/* Botões do Modal */}
                            <div style={{
                                display: 'flex',
                                gap: '0.75rem',
                                justifyContent: 'flex-end',
                                marginTop: '1rem',
                                borderTop: `1px solid ${C.border}`,
                                paddingTop: '1.25rem'
                            }}>
                                <button
                                    type="button"
                                    onClick={() => setModalOpen(false)}
                                    className="btn btn-outline"
                                    style={{
                                        height: '38px', borderRadius: '8px', cursor: 'pointer',
                                        padding: '0 1rem', fontSize: '0.85rem', fontWeight: 600,
                                        border: `1px solid ${C.border}`, background: 'transparent',
                                        color: C.textSub
                                    }}
                                >
                                    Cancelar
                                </button>
                                <button
                                    type="submit"
                                    disabled={saving}
                                    className="btn btn-primary"
                                    style={{
                                        height: '38px', borderRadius: '8px', cursor: 'pointer',
                                        padding: '0 1.25rem', fontSize: '0.85rem', fontWeight: 600,
                                        border: 'none', background: 'var(--gradient-primary)',
                                        color: 'white', display: 'flex', alignItems: 'center', gap: '0.5rem'
                                    }}
                                >
                                    {saving && (
                                        <div className="animate-spin" style={{
                                            width: '12px', height: '12px',
                                            borderRadius: '50%',
                                            border: '2px solid white',
                                            borderTopColor: 'transparent',
                                        }} />
                                    )}
                                    {editPartner ? 'Salvar Alterações' : 'Salvar Parceiro'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* Modal de Confirmação de Exclusão */}
            {deleteConfirmId && (
                <div onClick={() => setDeleteConfirmId(null)} style={{
                    position: 'fixed', inset: 0,
                    background: 'rgba(15, 23, 42, 0.4)',
                    backdropFilter: 'blur(8px)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    zIndex: 1010, animation: 'fadeIn 0.15s ease',
                    padding: '1rem',
                }}>
                    <div onClick={e => e.stopPropagation()} style={{
                        background: C.surface,
                        border: `1px solid ${C.border}`,
                        borderRadius: '16px', width: '400px', maxWidth: '95vw',
                        boxShadow: '0 20px 60px rgba(15,23,42,0.18)',
                        animation: 'scaleIn 0.18s cubic-bezier(0.34, 1.56, 0.64, 1)',
                        color: C.textMain,
                        padding: '1.5rem',
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        textAlign: 'center',
                        gap: '1rem'
                    }}>
                        <div style={{
                            width: 48, height: 48, borderRadius: '50%',
                            background: C.dangerAlpha,
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            color: C.danger,
                        }}>
                            <ShieldAlert size={24} />
                        </div>
                        <div>
                            <h3 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 700, color: C.textMain }}>Excluir Parceiro Comercial?</h3>
                            <p style={{ margin: '0.35rem 0 0', fontSize: '0.82rem', color: C.textMuted, lineHeight: 1.4 }}>
                                Tem certeza de que deseja remover este parceiro? As requisições de licença vinculadas a ele continuarão registradas no histórico, mas não exibirão mais o parceiro.
                            </p>
                        </div>
                        <div style={{ display: 'flex', gap: '0.75rem', width: '100%', marginTop: '0.5rem' }}>
                            <button
                                onClick={() => setDeleteConfirmId(null)}
                                style={{
                                    flex: 1, height: '36px', borderRadius: '8px',
                                    border: `1px solid ${C.border}`, background: 'transparent',
                                    color: C.textSub, cursor: 'pointer', fontWeight: 600, fontSize: '0.82rem'
                                }}
                            >
                                Cancelar
                            </button>
                            <button
                                onClick={handleDeletePartner}
                                style={{
                                    flex: 1, height: '36px', borderRadius: '8px',
                                    border: 'none', background: C.danger,
                                    color: 'white', cursor: 'pointer', fontWeight: 600, fontSize: '0.82rem',
                                    boxShadow: '0 2px 8px rgba(239,68,68,0.15)'
                                }}
                            >
                                Sim, Excluir
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
