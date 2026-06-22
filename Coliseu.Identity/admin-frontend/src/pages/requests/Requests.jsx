import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    History, PlusCircle, Search, Trash2, Plus, AlertCircle, X,
    ShieldAlert, Sparkles, Building, Briefcase, FileText, Check,
    AlertTriangle, ClipboardCheck, User, Info, Building2, Eye,
    ExternalLink, CheckSquare, Shield, Layers, HelpCircle,
    KeyRound, Activity, Smartphone, Clock, Loader2, LayoutGrid, List, Copy
} from 'lucide-react';
import { requestService } from '../../services/requestService';
import { partnerService } from '../../services/partnerService';
import { companyService } from '../../services/companyService';
import { monitoringService } from '../../services/monitoringService';

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
    'coliseu-sales': { label: 'Coliseu Sales', icon: '🏪', color: '#2196f3' },
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

// ─── Componente Modal local ──────────────────────────────────────────────────
const Modal = ({ open, title, icon: Icon, children, onClose, width = '540px' }) => {
    if (!open) return null;
    return (
        <div onClick={onClose} style={{
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
                borderRadius: '20px', width, maxWidth: '95vw',
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
                    {Icon && (
                        <div style={{
                            width: 36, height: 36, borderRadius: '10px',
                            background: 'var(--gradient-primary)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            boxShadow: '0 4px 12px rgba(27,143,205,0.2)', flexShrink: 0,
                        }}>
                            <Icon size={18} color="#fff" />
                        </div>
                    )}
                    <h3 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 700, color: C.textMain, flex: 1 }}>
                        {title}
                    </h3>
                    <button onClick={onClose} style={{
                        width: 32, height: 32, background: 'rgba(0,0,0,0.04)',
                        border: `1px solid ${C.border}`, borderRadius: '8px',
                        cursor: 'pointer', color: C.textMuted,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        transition: 'all 0.15s',
                    }}>
                        <X size={16} />
                    </button>
                </div>
                <div style={{ padding: '1.5rem' }}>
                    {children}
                </div>
            </div>
        </div>
    );
};

// ─── FormField local ─────────────────────────────────────────────────────────
const FormField = ({ label, children, hint }) => (
    <div style={{ marginBottom: '1rem' }}>
        <label style={{
            display: 'block', fontSize: '0.78rem', fontWeight: 600,
            color: C.textSub, marginBottom: '0.4rem', letterSpacing: '0.01em'
        }}>{label}</label>
        {children}
        {hint && <p style={{ margin: '0.3rem 0 0', fontSize: '0.72rem', color: C.textHint, lineHeight: 1.4 }}>{hint}</p>}
    </div>
);

// ─── Input Style ─────────────────────────────────────────────────────────────
const inputStyle = {
    width: '100%', padding: '0.7rem 0.9rem', borderRadius: '10px',
    background: 'var(--bg-input, rgba(255,255,255,0.92))',
    border: `1px solid ${C.border}`,
    color: C.textMain, fontSize: '0.875rem',
    outline: 'none', transition: 'border-color 0.2s, box-shadow 0.2s',
    boxSizing: 'border-box',
};

// ─── Autocomplete / Select Único com busca ───────────────────────────────────
const AutocompleteSelect = ({ value, onChange, options, placeholder, onActionClick, actionLabel }) => {
    const [search, setSearch] = useState('');
    const [open, setOpen] = useState(false);
    const containerRef = useRef(null);

    useEffect(() => {
        const clickOutside = (e) => {
            if (containerRef.current && !containerRef.current.contains(e.target)) {
                setOpen(false);
            }
        };
        document.addEventListener('mousedown', clickOutside);
        return () => document.removeEventListener('mousedown', clickOutside);
    }, []);

    const selectedOption = options.find(o => o.value === value);
    const filtered = options.filter(o =>
        o.label.toLowerCase().includes(search.toLowerCase()) ||
        (o.cnpj && o.cnpj.replace(/\D/g, '').includes(search.replace(/\D/g, '')))
    );

    return (
        <div ref={containerRef} style={{ position: 'relative', width: '100%' }}>
            <div style={{ display: 'flex', gap: '0.5rem' }}>
                <div
                    onClick={() => setOpen(!open)}
                    style={{
                        ...inputStyle,
                        cursor: 'pointer',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        background: 'var(--bg-input, #fff)',
                    }}
                >
                    <span style={{ color: selectedOption ? C.textMain : C.textHint }}>
                        {selectedOption ? selectedOption.label : placeholder}
                    </span>
                    <span style={{ fontSize: '0.8rem', color: C.textMuted }}>▼</span>
                </div>
                {onActionClick && (
                    <button
                        type="button"
                        className="btn btn-outline"
                        onClick={onActionClick}
                        style={{ padding: '0 0.85rem', height: '42px', borderRadius: '10px' }}
                    >
                        {actionLabel}
                    </button>
                )}
            </div>

            {open && (
                <div style={{
                    position: 'absolute', top: 'calc(100% + 5px)', left: 0, right: 0,
                    zIndex: 200, background: C.surface, border: `1px solid ${C.border}`,
                    borderRadius: '12px', boxShadow: '0 10px 30px rgba(0,0,0,0.1)',
                    maxHeight: '220px', overflowY: 'auto', padding: '0.5rem'
                }}>
                    <div style={{ position: 'relative', marginBottom: '0.5rem' }}>
                        <Search size={13} color={C.textHint} style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '10px' }} />
                        <input
                            type="text"
                            placeholder="Buscar parceiro..."
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                            style={{
                                ...inputStyle,
                                paddingLeft: '32px',
                                paddingRight: '10px',
                                height: '34px',
                                fontSize: '0.8rem',
                                borderRadius: '8px'
                            }}
                            autoFocus
                        />
                    </div>
                    {filtered.length === 0 ? (
                        <div style={{ padding: '0.75rem', fontSize: '0.8rem', color: C.textMuted, textAlign: 'center' }}>
                            Nenhum parceiro comercial encontrado.
                        </div>
                    ) : filtered.map(opt => (
                        <div
                            key={opt.value}
                            onClick={() => {
                                onChange(opt.value);
                                setOpen(false);
                                setSearch('');
                            }}
                            style={{
                                padding: '0.5rem 0.75rem',
                                fontSize: '0.82rem',
                                borderRadius: '6px',
                                cursor: 'pointer',
                                background: opt.value === value ? C.primaryAlpha : 'transparent',
                                color: opt.value === value ? C.primary : C.textMain,
                                transition: 'all 0.15s'
                            }}
                            onMouseEnter={e => {
                                if (opt.value !== value) e.currentTarget.style.background = 'rgba(0,0,0,0.03)';
                            }}
                            onMouseLeave={e => {
                                if (opt.value !== value) e.currentTarget.style.background = 'transparent';
                            }}
                        >
                            <div style={{ fontWeight: 600 }}>{opt.label}</div>
                            {opt.cnpj && <div style={{ fontSize: '0.7rem', color: C.textMuted }}>CNPJ: {opt.cnpj}</div>}
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
};

// ─── Multi-Select Dropdown para Módulos ──────────────────────────────────────
const MultiSelectDropdown = ({ value, onChange, options, placeholder }) => {
    const [open, setOpen] = useState(false);
    const containerRef = useRef(null);

    useEffect(() => {
        const clickOutside = (e) => {
            if (containerRef.current && !containerRef.current.contains(e.target)) {
                setOpen(false);
            }
        };
        document.addEventListener('mousedown', clickOutside);
        return () => document.removeEventListener('mousedown', clickOutside);
    }, []);

    const toggle = (val) => {
        if (value.includes(val)) {
            onChange(value.filter(x => x !== val));
        } else {
            onChange([...value, val]);
        }
    };

    return (
        <div ref={containerRef} style={{ position: 'relative', width: '100%' }}>
            <div
                onClick={() => setOpen(!open)}
                style={{
                    ...inputStyle,
                    cursor: 'pointer',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    background: 'var(--bg-input, #fff)',
                }}
            >
                <span style={{
                    color: value.length > 0 ? C.textMain : C.textHint,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                    paddingRight: '10px'
                }}>
                    {value.length === 0
                        ? placeholder
                        : value.length === 1
                            ? options.find(o => o.value === value[0])?.label
                            : `${value.length} Módulos selecionados`}
                </span>
                <span style={{ fontSize: '0.8rem', color: C.textMuted }}>▼</span>
            </div>

            {open && (
                <div style={{
                    position: 'absolute', top: 'calc(100% + 5px)', left: 0, right: 0,
                    zIndex: 200, background: C.surface, border: `1px solid ${C.border}`,
                    borderRadius: '12px', boxShadow: '0 10px 30px rgba(0,0,0,0.1)',
                    maxHeight: '220px', overflowY: 'auto', padding: '0.5rem'
                }}>
                    {options.map(opt => {
                        const checked = value.includes(opt.value);
                        return (
                            <label
                                key={opt.value}
                                style={{
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '0.5rem',
                                    padding: '0.45rem 0.75rem',
                                    fontSize: '0.82rem',
                                    borderRadius: '6px',
                                    cursor: 'pointer',
                                    background: checked ? 'rgba(27,143,205,0.05)' : 'transparent',
                                    color: checked ? C.primary : C.textMain,
                                    transition: 'all 0.15s',
                                    marginBottom: '2px'
                                }}
                            >
                                <input
                                    type="checkbox"
                                    checked={checked}
                                    onChange={() => toggle(opt.value)}
                                    style={{ accentColor: C.primary }}
                                />
                                <span>{opt.label}</span>
                            </label>
                        );
                    })}
                </div>
            )}
        </div>
    );
};

// ─── COMPONENTE PRINCIPAL: REQUESTS ──────────────────────────────────────────
export default function Requests() {
    const [user, setUser] = useState({ name: 'Super Admin', email: 'admin@coliseu.com.br', role: 'SuperAdmin', permissions: ['*'] });
    const [tab, setTab] = useState('list'); // 'list' | 'new'
    const [viewMode, setViewMode] = useState(() => localStorage.getItem('coliseu_requests_view_mode') || 'cards');
    const [partners, setPartners] = useState([]);
    const [requests, setRequests] = useState([]);
    const [loading, setLoading] = useState(true);

    // Modais
    const [rejectionModal, setRejectionModal] = useState(null); // request being rejected
    const [requestLinks, setRequestLinks] = useState({});
    const [licenseModalData, setLicenseModalData] = useState(null); // { company, modules, devices, syncStats, loading }
    const [isLicenseModalOpen, setIsLicenseModalOpen] = useState(false);
    const [copiedKeyId, setCopiedKeyId] = useState(null);

    // Filtros listagem
    const [filterQuery, setFilterQuery] = useState('');
    const [filterPartner, setFilterPartner] = useState('');
    const [filterModules, setFilterModules] = useState([]);
    const [filterStatus, setFilterStatus] = useState('');

    // Formulário Nova Requisição
    const [reqPartner, setReqPartner] = useState('');
    const [reqCompanyName, setReqCompanyName] = useState('');
    const [reqStructureType, setReqStructureType] = useState('individual'); // 'individual' | 'multi'
    
    // Campos para Empresa Individual
    const [reqCnpj, setReqCnpj] = useState('');
    const [reqCostCenter, setReqCostCenter] = useState('');
    const [reqDept, setReqDept] = useState('');

    // Campos para MultiEmpresa (Várias Filiais)
    const [reqCompanies, setReqCompanies] = useState([
        { id: '1', cnpj: '', costCenter: '', dept: '' }
    ]);

    // Configurações Mobile
    const [reqPriceTableMode, setReqPriceTableMode] = useState('none'); // 'none' | 'customer' | 'region'
    const [reqAllowNegativeStock, setReqAllowNegativeStock] = useState(false);

    // Grid dinâmico de módulos
    const [reqModules, setReqModules] = useState([{ moduleSlug: 'coliseu-sales', quantity: 1 }]);

    const [savingRequest, setSavingRequest] = useState(false);

    // Visualizar motivo recusado expandido
    const [expandedRequest, setExpandedRequest] = useState(null);

    // Mapeamento de CNPJs para Nome da Empresa (para exibição no histórico)
    const [cnpjCompanyNameMap, setCnpjCompanyNameMap] = useState({});

    const getCompanyNameByCnpj = useCallback((cnpj) => {
        if (!cnpj) return '';
        const clean = cnpj.replace(/\D/g, '');
        return cnpjCompanyNameMap[clean] || '';
    }, [cnpjCompanyNameMap]);

    const getRequestCompanyName = useCallback((req) => {
        if (req.companyName) {
            return req.companyName;
        }
        const link = requestLinks[req.id];
        if (link && link.companyName) {
            return link.companyName;
        }
        if (req.clientCompanyType === 'MultiEmpresa') {
            if (req.companies && req.companies.length > 0) {
                for (const c of req.companies) {
                    const name = getCompanyNameByCnpj(c.cnpj);
                    if (name) return name;
                }
            }
        } else {
            return getCompanyNameByCnpj(req.clientCnpj);
        }
        return '';
    }, [requestLinks, getCompanyNameByCnpj]);

    // Carregar dados de usuário e localStorage
    const loadData = useCallback(async () => {
        setLoading(true);
        try {
            const storedUser = localStorage.getItem('adminUser');
            if (storedUser) {
                const parsed = JSON.parse(storedUser);
                const links = JSON.parse(localStorage.getItem('coliseu_user_partner_links') || '{}');
                const link = links[parsed.email.toLowerCase()];
                if (link && link.isPartner) {
                    parsed.isPartner = true;
                    parsed.partnerId = link.partnerId;
                    setReqPartner(link.partnerId);
                }
                setUser(parsed);
            }

            const [pList, rList, compData] = await Promise.all([
                partnerService.listPartners(),
                requestService.listRequests(),
                companyService.getCompanies(1, 1000, '')
            ]);
            setPartners(pList);
            setRequests(rList);

            const companiesList = compData?.items || [];
            setCompanies(companiesList);

            // Mapear requisições aprovadas para as empresas reais correspondentes
            const links = {};
            rList.forEach(req => {
                if (req.companyId) {
                    const comp = companiesList.find(c => c.id === req.companyId);
                    if (comp) {
                        links[req.id] = {
                            companyId: req.companyId,
                            companyName: comp.name,
                            isMulti: req.clientCompanyType === 'MultiEmpresa'
                        };
                    }
                }
            });
            setRequestLinks(links);
        } catch (err) {
            console.error(err);
        } finally {
            setLoading(false);
        }
    }, []);
    useEffect(() => {
        loadData();
    }, [loadData]);

    const canSee = (perm) => {
        if (user.role === 'SuperAdmin') return true;
        const perms = user.permissions || [];
        return perms.includes('*') || perms.includes(perm);
    };

    const handleOpenLicenseModal = async (requestId) => {
        const link = requestLinks[requestId];
        if (!link) return;

        setIsLicenseModalOpen(true);
        setLicenseModalData({ loading: true });

        try {
            const companyId = link.companyId;
            let company = null;
            let modules = [];

            try {
                company = await companyService.getCompanyById(companyId);
                modules = await companyService.listModules(companyId);
            } catch (e) {
                console.warn("Company not found in DB, using link fallback info", e);
                company = {
                    id: companyId,
                    name: link.companyName || 'Empresa (Não encontrada no BD)',
                    status: 'Inactive',
                    deviceLimit: 10,
                    contactEmail: '—'
                };
                
                const req = requests.find(r => r.id === requestId);
                if (req && req.modules) {
                    modules = req.modules.map(m => ({
                        id: 'fallback_' + m.moduleSlug,
                        moduleSlug: m.moduleSlug,
                        deviceLimit: m.quantity || 1,
                        isActive: true
                    }));
                }
            }
            
            let devices = [];
            try {
                const devsData = await companyService.getDevicesByCompany(companyId);
                devices = devsData.items || [];
            } catch (e) {
                console.error("Erro ao carregar dispositivos do modal de licença", e);
            }

            let syncStats = null;
            try {
                syncStats = await monitoringService.getCompanySummary(companyId);
            } catch (e) {
                console.error("Erro ao carregar syncStats do modal de licença", e);
            }

            setLicenseModalData({
                loading: false,
                company,
                modules,
                devices,
                syncStats
            });
        } catch (error) {
            console.error("Erro ao carregar licença", error);
            setLicenseModalData({
                loading: false,
                error: 'Falha ao carregar os dados detalhados da licença.'
            });
        }
    };

    const handleCopyKey = (keyText, id) => {
        if (!keyText) return;
        navigator.clipboard.writeText(keyText);
        setCopiedKeyId(id);
        setTimeout(() => setCopiedKeyId(null), 2500);
    };

    const handleDeleteRequest = async (id) => {
        if (requestLinks[id]) {
            alert('Não é possível excluir esta requisição pois ela possui uma licença ativa associada.');
            return;
        }
        if (!window.confirm('Deseja realmente excluir esta requisição? Esta ação não pode ser desfeita.')) return;
        try {
            await requestService.deleteRequest(id);
            // Também remover link de licença se existir
            const links = JSON.parse(localStorage.getItem('coliseu_request_license_links') || '{}');
            if (links[id]) {
                delete links[id];
                localStorage.setItem('coliseu_request_license_links', JSON.stringify(links));
            }
            await loadData();
        } catch (e) {
            alert('Erro ao excluir requisição: ' + (e.message || 'Erro desconhecido'));
        }
    };

    if (!canSee('requests.read')) {
        return (
            <div style={{
                textAlign: 'center', padding: '6rem 2rem', background: C.surface,
                borderRadius: '16px', border: `1px solid ${C.border}`, maxWidth: '620px', margin: '4rem auto'
            }}>
                <ShieldAlert size={48} color={C.danger} style={{ marginBottom: '1.25rem' }} />
                <h2 style={{ fontSize: '1.4rem', fontWeight: 700, color: C.textMain, marginBottom: '0.5rem' }}>Acesso Restrito</h2>
                <p style={{ color: C.textMuted, fontSize: '0.875rem', lineHeight: 1.5, margin: '0 auto 1.5rem', maxWidth: '380px' }}>
                    Seu grupo de acesso não possui a permissão necessária para visualizar ou gerenciar requisições de licenças.
                </p>
                <div style={{ fontSize: '0.75rem', color: C.textHint, fontFamily: 'monospace' }}>
                    Permissão Requerida: requests.read
                </div>
            </div>
        );
    }

    // Alteração de Status diretamente pela listagem (veja para trocar o status)
    const handleStatusChange = async (id, newStatus) => {
        if (!canSee('requests.approve')) {
            alert('Você não tem permissão para alterar o status das requisições.');
            return;
        }

        if (newStatus === 'Recusada') {
            // Abre o modal de justificativa
            const req = requests.find(r => r.id === id);
            setRejectionModal(req);
            return;
        }

        try {
            await requestService.updateStatus(id, newStatus);
            await loadData();
        } catch (e) {
            alert(e?.response?.data?.error || 'Erro ao alterar status.');
        }
    };

    const handleRejectSubmit = async (e) => {
        e.preventDefault();
        const reason = e.target.reason.value;
        if (!reason.trim()) return;

        try {
            await requestService.updateStatus(rejectionModal.id, 'Recusada', reason);
            setRejectionModal(null);
            await loadData();
        } catch (e) {
            alert(e?.response?.data?.error || 'Erro ao recusar requisição.');
        }
    };



    // Grid de filiais (MultiEmpresa)
    const addCompanyRow = () => {
        setReqCompanies([
            ...reqCompanies,
            { id: String(Date.now()), cnpj: '', costCenter: '', dept: '' }
        ]);
    };

    const removeCompanyRow = (id) => {
        if (reqCompanies.length === 1) return;
        setReqCompanies(reqCompanies.filter(c => c.id !== id));
    };

    const updateCompanyRow = (id, field, value) => {
        setReqCompanies(reqCompanies.map(c => {
            if (c.id === id) {
                return { ...c, [field]: field === 'cnpj' ? maskCnpj(value) : value };
            }
            return c;
        }));
    };

    // Grid Dinâmico de Módulos (Adicionar / Remover / Alterar)
    const addModuleRow = () => {
        const unused = Object.keys(MODULE_META).find(slug => !reqModules.some(m => m.moduleSlug === slug));
        if (!unused) return; // Todos já adicionados
        setReqModules([...reqModules, { moduleSlug: unused, quantity: 1 }]);
    };

    const removeModuleRow = (index) => {
        if (reqModules.length === 1) return;
        setReqModules(reqModules.filter((_, i) => i !== index));
    };

    const updateModuleRow = (index, field, value) => {
        const next = [...reqModules];
        next[index] = { ...next[index], [field]: value };
        setReqModules(next);
    };

    // Ação: Criar Nova Requisição (Submit)
    const handleCreateRequest = async (e) => {
        e.preventDefault();
        if (!reqPartner) {
            alert('Por favor, selecione um parceiro.');
            return;
        }

        // Validação condicional da estrutura de empresa
        let companiesPayload = null;
        let singleCnpj = null;
        let singleCostCenter = null;
        let singleDept = null;

        if (reqStructureType === 'individual') {
            if (!reqCnpj || reqCnpj.length < 18) {
                alert('CNPJ do cliente destinatário inválido.');
                return;
            }
            singleCnpj = reqCnpj;
            singleCostCenter = reqCostCenter;
            singleDept = reqDept;
        } else {
            // MultiEmpresa
            const invalid = reqCompanies.some(c => !c.cnpj || c.cnpj.length < 18);
            if (invalid) {
                alert('Preencha corretamente o CNPJ de todas as filiais.');
                return;
            }
            companiesPayload = reqCompanies.map(c => ({
                cnpj: c.cnpj,
                costCenter: c.costCenter,
                dept: c.dept
            }));
        }

        if (reqModules.length === 0) {
            alert('Adicione pelo menos um módulo na requisição.');
            return;
        }

        const partner = partners.find(p => p.id === reqPartner);
        const payload = {
            partnerId: reqPartner,
            partnerName: partner?.name || 'Parceiro Comercial',
            companyName: reqCompanyName,
            requestorEmail: user.email,
            clientCnpj: singleCnpj,
            clientCompanyType: reqStructureType === 'individual' ? 'Empresa Individual' : 'MultiEmpresa',
            costCenterCode: singleCostCenter,
            deptCode: singleDept,
            companies: companiesPayload,
            // Configurações Mobile salvadas na requisição
            priceTableMode: reqPriceTableMode,
            allowNegativeStock: reqAllowNegativeStock,
            modules: reqModules.map(m => ({
                moduleSlug: m.moduleSlug,
                quantity: Number(m.quantity)
            }))
        };

        setSavingRequest(true);
        try {
            await requestService.createRequest(payload);
            
            // Resetar formulário
            setReqPartner(user.isPartner ? user.partnerId : '');
            setReqCompanyName('');
            setReqCnpj('');
            setReqCostCenter('');
            setReqDept('');
            setReqCompanies([{ id: '1', cnpj: '', costCenter: '', dept: '' }]);
            setReqPriceTableMode('none');
            setReqAllowNegativeStock(false);
            setReqModules([{ moduleSlug: 'coliseu-sales', quantity: 1 }]);

            setTab('list');
            await loadData();
        } catch (err) {
            alert(err?.response?.data?.error || 'Erro ao criar requisição.');
        } finally {
            setSavingRequest(false);
        }
    };

    // Filtragem das Requisições
    const filteredRequests = requests.filter(req => {
        // Se for usuário parceiro, restringir apenas às suas requisições
        if (user.isPartner && req.partnerId !== user.partnerId) {
            return false;
        }

        // Pesquisa geral (CNPJ ou Razão Social)
        const query = filterQuery.toLowerCase();
        const matchQuery = !filterQuery ||
            req.partnerName.toLowerCase().includes(query) ||
            req.requestorEmail.toLowerCase().includes(query) ||
            (req.clientCnpj && req.clientCnpj.includes(filterQuery)) ||
            (req.companies && req.companies.some(c => c.cnpj.includes(filterQuery)));

        const matchPartner = !filterPartner || req.partnerId === filterPartner;
        const matchStatus = !filterStatus || req.status === filterStatus;
        const matchModules = filterModules.length === 0 ||
            req.modules.some(m => filterModules.includes(m.moduleSlug));

        return matchQuery && matchPartner && matchStatus && matchModules;
    });

    const renderModuleBadges = (reqModules) => {
        return (
            <div style={{ display: 'flex', gap: '0.3rem', flexWrap: 'wrap' }}>
                {reqModules.map(m => {
                    const meta = MODULE_META[m.moduleSlug] || { label: m.moduleSlug, icon: '📦', color: '#64748b' };
                    return (
                        <span
                            key={m.moduleSlug}
                            style={{
                                display: 'inline-flex',
                                alignItems: 'center',
                                gap: '3px',
                                padding: '2px 8px',
                                borderRadius: '6px',
                                fontSize: '0.74rem',
                                fontWeight: 700,
                                background: `${meta.color}14`,
                                color: meta.color,
                                border: `1px solid ${meta.color}25`
                            }}
                            title={meta.label}
                        >
                            <span>{meta.icon}</span>
                            <span>{meta.label}</span>
                            <span style={{ fontSize: '0.68rem', fontWeight: 800, marginLeft: '3px', paddingLeft: '4px', borderLeft: `1px solid ${meta.color}35` }}>
                                {m.quantity}
                            </span>
                        </span>
                    );
                })}
            </div>
        );
    };

    // Renderização do Badge de Status Interativo
    const renderInteractiveStatus = (req) => {
        let bg = C.warnAlpha;
        let color = C.warn;
        let border = 'rgba(245,158,11,0.2)';

        if (req.status === 'Aprovada') {
            bg = C.successAlpha;
            color = C.success;
            border = 'rgba(16,185,129,0.2)';
        } else if (req.status === 'Recusada') {
            bg = C.dangerAlpha;
            color = C.danger;
            border = 'rgba(239,68,68,0.2)';
        } else if (req.status === 'Em Processamento') {
            bg = C.infoAlpha;
            color = C.info;
            border = 'rgba(59,130,246,0.2)';
        }

        const selectStyle = {
            padding: '4px 18px 4px 8px',
            borderRadius: '20px',
            fontSize: '0.72rem',
            border: `1px solid ${border}`,
            background: bg,
            color: color,
            cursor: canSee('requests.approve') ? 'pointer' : 'default',
            outline: 'none',
            fontFamily: 'inherit',
            fontWeight: 800,
            letterSpacing: '0.02em',
            textTransform: 'uppercase',
            textAlign: 'center',
            display: 'inline-block',
            // Custom arrow styling
            appearance: 'none',
            backgroundImage: `url("data:image/svg+xml;utf8,<svg fill='${encodeURIComponent(color)}' height='10' viewBox='0 0 24 24' width='10' xmlns='http://www.w3.org/2000/svg'><path d='M7 10l5 5 5-5z'/></svg>")`,
            backgroundRepeat: 'no-repeat',
            backgroundPosition: 'right 6px center',
        };

        return (
            <div style={{ display: 'inline-flex', flexDirection: 'column', alignItems: 'flex-start' }}>
                <select
                    value={req.status}
                    onChange={(e) => handleStatusChange(req.id, e.target.value)}
                    disabled={!canSee('requests.approve')}
                    style={selectStyle}
                >
                    <option value="Pendente" style={{ background: '#fff', color: C.warn, fontWeight: 700 }}>🟡 Pendente</option>
                    <option value="Aprovada" style={{ background: '#fff', color: C.success, fontWeight: 700 }}>🟢 Aprovada</option>
                    <option value="Em Processamento" style={{ background: '#fff', color: C.info, fontWeight: 700 }}>🔵 Processando</option>
                    <option value="Recusada" style={{ background: '#fff', color: C.danger, fontWeight: 700 }}>🔴 Recusada</option>
                </select>
                {req.status === 'Recusada' && req.rejectReason && (
                    <span
                        onClick={() => setExpandedRequest(expandedRequest === req.id ? null : req.id)}
                        style={{
                            fontSize: '0.68rem',
                            color: C.danger,
                            textDecoration: 'underline',
                            cursor: 'pointer',
                            marginTop: '4px',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '2px',
                            fontWeight: 600
                        }}
                    >
                        <Info size={11} /> Ver motivo
                    </span>
                )}
            </div>
        );
    };

    // Textos informativos de Tabela de Preços
    const getPriceTableHint = () => {
        switch (reqPriceTableMode) {
            case 'customer':
                return 'Tabela vinculada ao Cliente: O app mobile consulta a tabela específica associada ao CNPJ do cliente final nas configurações do ERP.';
            case 'region':
                return 'Tabela por Região: O app mobile define a tabela de preço com base na região geográfica de atendimento do cliente.';
            case 'none':
            default:
                return 'Não usar: O app sempre exibe o preço base cadastrado no produto. Tabelas de preço adicionais são completamente ignoradas.';
        }
    };

    return (
        <div className="animate-fade-in" style={{ maxWidth: '1400px', width: '100%' }}>
            {/* ─── PAGE HEADER ────────────────────────────────────────────── */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '1.75rem', flexWrap: 'wrap', gap: '1rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
                    <div style={{
                        width: 48, height: 48, borderRadius: '14px',
                        background: 'var(--gradient-primary)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        boxShadow: '0 0 24px rgba(27,143,205,0.30)',
                    }}>
                        <FileText size={24} color="#fff" />
                    </div>
                    <div>
                        <h1 style={{ fontSize: '1.45rem', fontWeight: 800, color: C.textMain, margin: 0, letterSpacing: '-0.02em' }}>
                            Requisições de Módulos
                        </h1>
                        <p style={{ margin: 0, color: C.textMuted, fontSize: '0.82rem', marginTop: '0.1rem' }}>
                            Aprovação de licenças comerciais e vinculação de parceiros integradores
                        </p>
                    </div>
                </div>
            </div>

            {/* ─── TABS NAVEGAÇÃO ─────────────────────────────────────────── */}
            <div style={{
                display: 'flex', gap: '4px', marginBottom: '1.5rem',
                background: 'var(--bg)', borderRadius: '14px', padding: '5px',
                border: `1px solid ${C.border}`,
            }}>
                <button
                    onClick={() => setTab('list')}
                    style={{
                        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                        gap: '0.5rem', padding: '0.65rem 1rem', borderRadius: '10px',
                        fontSize: '0.875rem', fontWeight: tab === 'list' ? 700 : 500,
                        background: tab === 'list'
                            ? 'linear-gradient(135deg, rgba(27,143,205,0.15) 0%, rgba(59,192,240,0.08) 100%)'
                            : 'transparent',
                        color: tab === 'list' ? C.textMain : C.textMuted,
                        border: tab === 'list' ? '1px solid rgba(27,143,205,0.20)' : '1px solid transparent',
                        cursor: 'pointer', transition: 'all 0.2s',
                        boxShadow: tab === 'list' ? '0 2px 8px rgba(27,143,205,0.12)' : 'none',
                    }}
                >
                    <History size={16} style={{ color: tab === 'list' ? C.primary : 'inherit' }} />
                    Histórico de Requisições
                </button>

                {canSee('requests.create') && (
                    <button
                        onClick={() => setTab('new')}
                        style={{
                            flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                            gap: '0.5rem', padding: '0.65rem 1rem', borderRadius: '10px',
                            fontSize: '0.875rem', fontWeight: tab === 'new' ? 700 : 500,
                            background: tab === 'new'
                                ? 'linear-gradient(135deg, rgba(27,143,205,0.15) 0%, rgba(59,192,240,0.08) 100%)'
                                : 'transparent',
                            color: tab === 'new' ? C.textMain : C.textMuted,
                            border: tab === 'new' ? '1px solid rgba(27,143,205,0.20)' : '1px solid transparent',
                            cursor: 'pointer', transition: 'all 0.2s',
                            boxShadow: tab === 'new' ? '0 2px 8px rgba(27,143,205,0.12)' : 'none',
                        }}
                    >
                        <PlusCircle size={16} style={{ color: tab === 'new' ? C.primary : 'inherit' }} />
                        Nova Requisição
                    </button>
                )}
            </div>

            {/* ─── TAB CONTENT: LISTAGEM E HISTÓRICO ─────────────────────────── */}
            {tab === 'list' && (
                <>
                    {/* BARRA DE FILTROS E BOTÃO DE VISUALIZAÇÃO */}
                    <div style={{
                        display: 'flex',
                        flexDirection: 'column',
                        gap: '0.75rem',
                        marginBottom: '1rem',
                    }}>
                        <div style={{
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center',
                            flexWrap: 'wrap',
                            gap: '0.75rem'
                        }}>
                            {/* Toggle de Visualização */}
                            <div style={{
                                display: 'flex',
                                background: 'var(--bg)',
                                borderRadius: '10px',
                                padding: '3px',
                                border: `1px solid ${C.border}`,
                                width: 'fit-content'
                            }}>
                                <button
                                    type="button"
                                    onClick={() => {
                                        setViewMode('cards');
                                        localStorage.setItem('coliseu_requests_view_mode', 'cards');
                                    }}
                                    title="Visualizar em Cards"
                                    style={{
                                        display: 'flex', alignItems: 'center', gap: '4px',
                                        padding: '0.45rem 0.85rem', borderRadius: '8px',
                                        fontSize: '0.78rem', fontWeight: 700,
                                        background: viewMode === 'cards' ? C.surface : 'transparent',
                                        color: viewMode === 'cards' ? C.primary : C.textMuted,
                                        border: 'none', cursor: 'pointer', transition: 'all 0.15s',
                                        boxShadow: viewMode === 'cards' ? 'var(--shadow-sm)' : 'none'
                                    }}
                                >
                                    <LayoutGrid size={14} /> Cards
                                </button>
                                <button
                                    type="button"
                                    onClick={() => {
                                        setViewMode('table');
                                        localStorage.setItem('coliseu_requests_view_mode', 'table');
                                    }}
                                    title="Visualizar em Tabela"
                                    style={{
                                        display: 'flex', alignItems: 'center', gap: '4px',
                                        padding: '0.45rem 0.85rem', borderRadius: '8px',
                                        fontSize: '0.78rem', fontWeight: 700,
                                        background: viewMode === 'table' ? C.surface : 'transparent',
                                        color: viewMode === 'table' ? C.primary : C.textMuted,
                                        border: 'none', cursor: 'pointer', transition: 'all 0.15s',
                                        boxShadow: viewMode === 'table' ? 'var(--shadow-sm)' : 'none'
                                    }}
                                >
                                    <List size={14} /> Tabela
                                </button>
                            </div>
                        </div>

                        {/* FILTROS AVANÇADOS */}
                        <div style={{
                            background: C.surface,
                            border: `1px solid ${C.border}`,
                            borderRadius: '16px',
                            padding: '1rem',
                            display: 'grid',
                            gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                            gap: '0.75rem',
                            boxShadow: '0 2px 12px rgba(0,0,0,0.02)'
                        }}>
                            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
                                <label style={{ fontSize: '0.68rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Pesquisa Geral</label>
                                <div style={{ position: 'relative' }}>
                                    <Search size={13} color={C.textHint} style={{ position: 'absolute', top: '50%', transform: 'translateY(-50%)', left: '10px' }} />
                                    <input
                                        type="text"
                                        placeholder="Razão Social ou CNPJ..."
                                        value={filterQuery}
                                        onChange={e => setFilterQuery(e.target.value)}
                                        style={{ ...inputStyle, paddingLeft: '32px', height: '36px', fontSize: '0.8rem', borderRadius: '8px' }}
                                    />
                                </div>
                            </div>

                            {!user.isPartner && (
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
                                    <label style={{ fontSize: '0.68rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Filtrar por Parceiro</label>
                                    <select
                                        value={filterPartner}
                                        onChange={e => setFilterPartner(e.target.value)}
                                        style={{ ...inputStyle, cursor: 'pointer', height: '36px', fontSize: '0.8rem', borderRadius: '8px', padding: '0.4rem 0.60rem' }}
                                    >
                                        <option value="">— Todos os Parceiros —</option>
                                        {partners.map(p => (
                                            <option key={p.id} value={p.id}>{p.name}</option>
                                        ))}
                                    </select>
                                </div>
                            )}

                            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
                                <label style={{ fontSize: '0.68rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Filtrar por Módulo</label>
                                <MultiSelectDropdown
                                    value={filterModules}
                                    onChange={setFilterModules}
                                    placeholder="— Selecionar Módulos —"
                                    options={Object.entries(MODULE_META).map(([key, val]) => ({
                                        value: key,
                                        label: `${val.icon} ${val.label}`
                                    }))}
                                />
                            </div>

                            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
                                <label style={{ fontSize: '0.68rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Status da Requisição</label>
                                <select
                                    value={filterStatus}
                                    onChange={e => setFilterStatus(e.target.value)}
                                    style={{ ...inputStyle, cursor: 'pointer', height: '36px', fontSize: '0.8rem', borderRadius: '8px', padding: '0.4rem 0.60rem' }}
                                >
                                    <option value="">— Todos os Status —</option>
                                    <option value="Pendente">🟡 Pendente</option>
                                    <option value="Aprovada">🟢 Aprovada</option>
                                    <option value="Recusada">🔴 Recusada</option>
                                    <option value="Em Processamento">🔵 Em Processamento</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    <div style={viewMode === 'table' ? {
                        background: C.surface, border: `1px solid ${C.border}`,
                        borderRadius: '16px', overflow: 'hidden', boxShadow: '0 4px 16px rgba(0,0,0,0.02)'
                    } : {}}>
                        {loading ? (
                            <div style={{ textAlign: 'center', padding: '4rem', color: C.textMuted }}>
                                <div className="skeleton" style={{ width: '40px', height: '40px', margin: '0 auto 1rem', borderRadius: '50%' }} />
                                Carregando dados do histórico...
                            </div>
                        ) : filteredRequests.length === 0 ? (
                            <div style={{ textAlign: 'center', padding: '5rem 2rem', color: C.textMuted, background: C.surface, border: `1px solid ${C.border}`, borderRadius: '16px' }}>
                                <FileText size={36} color={C.textHint} style={{ marginBottom: '1rem' }} />
                                <h3 style={{ fontSize: '1rem', fontWeight: 700, color: C.textMain, marginBottom: '0.25rem' }}>Nenhuma requisição encontrada</h3>
                                <p style={{ fontSize: '0.82rem', margin: 0 }}>Tente ajustar os filtros avançados ou lance uma nova requisição.</p>
                            </div>
                        ) : viewMode === 'cards' ? (
                            <div style={{
                                display: 'grid',
                                gridTemplateColumns: 'repeat(auto-fill, minmax(340px, 1fr))',
                                gap: '1.25rem',
                                padding: '0.1rem'
                            }}>
                                {filteredRequests.map(req => {
                                    const isExpanded = expandedRequest === req.id;
                                    const isMulti = req.clientCompanyType === 'MultiEmpresa';
                                    
                                    const companyNameResolved = getRequestCompanyName(req) || 'Empresa Final';
                                    const companyInitials = companyNameResolved
                                        ? companyNameResolved.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
                                        : 'E';
                                    
                                    const formattedDate = new Date(req.createdAt).toLocaleDateString('pt-BR');
                                    const formattedTime = new Date(req.createdAt).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

                                    return (
                                        <div
                                            key={req.id}
                                            className="animate-fade-in"
                                            style={{
                                                background: C.surface,
                                                border: `1px solid ${C.border}`,
                                                borderRadius: '16px',
                                                padding: '1.25rem',
                                                boxShadow: '0 4px 12px rgba(0,0,0,0.02)',
                                                display: 'flex',
                                                flexDirection: 'column',
                                                gap: '1rem',
                                                position: 'relative',
                                                transition: 'transform 0.2s, box-shadow 0.2s',
                                            }}
                                        >
                                            {/* Header do Card (Empresa em cima, Parceiro embaixo, Status abaixo dele) */}
                                            <div style={{ display: 'flex', alignItems: 'flex-start', gap: '0.75rem', minWidth: 0 }}>
                                                <div style={{
                                                    width: 36, height: 36, borderRadius: '10px',
                                                    background: C.primaryAlpha, color: C.primary,
                                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                    fontWeight: 700, fontSize: '0.8rem', flexShrink: 0
                                                }}>
                                                    {companyInitials}
                                                </div>
                                                <div style={{ minWidth: 0, flex: 1, display: 'flex', flexDirection: 'column', gap: '2px' }}>
                                                    <div style={{ 
                                                        fontWeight: 800, 
                                                        color: C.textMain, 
                                                        fontSize: '0.95rem', 
                                                        lineHeight: 1.2,
                                                        whiteSpace: 'nowrap',
                                                        overflow: 'hidden',
                                                        textOverflow: 'ellipsis'
                                                    }} title={companyNameResolved}>
                                                        {companyNameResolved}
                                                    </div>
                                                    <div style={{ 
                                                        fontSize: '0.72rem', 
                                                        color: C.textMuted, 
                                                        marginTop: '3px', 
                                                        display: 'flex', 
                                                        flexDirection: 'column', 
                                                        gap: '2px',
                                                        minWidth: 0
                                                    }}>
                                                        <span style={{ 
                                                            fontWeight: 600, 
                                                            color: C.textSub,
                                                            whiteSpace: 'nowrap',
                                                            overflow: 'hidden',
                                                            textOverflow: 'ellipsis'
                                                        }} title={req.partnerName}>
                                                            🤝 Parceiro: {req.partnerName}
                                                        </span>
                                                        <span>{formattedDate} às {formattedTime}</span>
                                                        <div style={{ marginTop: '6px', width: 'fit-content' }}>
                                                            {renderInteractiveStatus(req)}
                                                        </div>
                                                    </div>
                                                </div>
                                            </div>

                                            <div style={{ height: '1px', background: C.border, margin: '0 -0.25rem' }} />

                                            {/* Email do Solicitante */}
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.74rem', color: C.textSub }}>
                                                <User size={13} color={C.textHint} />
                                                <span style={{ fontWeight: 600 }}>Solicitante:</span>
                                                <span title={req.requestorEmail} style={{ textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>
                                                    {req.requestorEmail}
                                                </span>
                                            </div>

                                            {/* Cliente Destinatário */}
                                            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
                                                <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                                    <span style={{ fontSize: '0.74rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                                                        Destinatário
                                                    </span>
                                                </div>
                                                {isMulti ? (
                                                    <div style={{
                                                        background: 'rgba(0,0,0,0.015)',
                                                        border: `1px solid ${C.border}`,
                                                        borderRadius: '10px',
                                                        padding: '0.6rem',
                                                        display: 'flex',
                                                        flexDirection: 'column',
                                                        gap: '0.4rem'
                                                    }}>
                                                        <span style={{
                                                            fontSize: '0.64rem', padding: '2px 8px', borderRadius: '6px',
                                                            background: 'rgba(124,77,255,0.08)', color: '#7c4dff', fontWeight: 800,
                                                            width: 'fit-content', textTransform: 'uppercase', letterSpacing: '0.02em'
                                                        }}>
                                                            🏢 MultiEmpresa ({req.companies?.length || 0})
                                                        </span>
                                                        <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', maxHeight: '100px', overflowY: 'auto' }}>
                                                            {req.companies?.map((c, i) => (
                                                                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.74rem', borderBottom: i < req.companies.length - 1 ? `1px dashed ${C.border}` : 'none', paddingBottom: '3px' }}>
                                                                    <span style={{ fontFamily: 'monospace', color: C.textSub, fontWeight: 600 }}>{c.cnpj}</span>
                                                                    <span style={{ fontSize: '0.68rem', color: C.textMuted, background: 'rgba(0,0,0,0.04)', padding: '1px 5px', borderRadius: '4px' }}>
                                                                        {c.costCenter || '—'} / {c.dept || '—'}
                                                                    </span>
                                                                </div>
                                                            ))}
                                                        </div>
                                                    </div>
                                                ) : (
                                                    <div style={{
                                                        background: 'rgba(0,0,0,0.015)',
                                                        border: `1px solid ${C.border}`,
                                                        borderRadius: '10px',
                                                        padding: '0.6rem',
                                                        display: 'flex',
                                                        justifyContent: 'space-between',
                                                        alignItems: 'center'
                                                    }}>
                                                        <div>
                                                            <div style={{ fontWeight: 600, color: C.textSub, fontSize: '0.78rem', fontFamily: 'monospace' }}>{req.clientCnpj}</div>
                                                            <span style={{
                                                                fontSize: '0.64rem', padding: '1px 6px', borderRadius: '4px',
                                                                background: 'rgba(37,99,235,0.08)', color: '#2563eb', fontWeight: 800,
                                                                textTransform: 'uppercase', display: 'inline-block', marginTop: '4px'
                                                            }}>
                                                                👤 Individual
                                                            </span>
                                                        </div>
                                                        {req.costCenterCode || req.deptCode ? (
                                                            <div style={{ textAlign: 'right' }}>
                                                                <div style={{ fontSize: '0.62rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', marginBottom: '2px' }}>C.Custo / Depto</div>
                                                                <span style={{ fontSize: '0.74rem', background: 'rgba(0,0,0,0.04)', color: C.textSub, padding: '2px 6px', borderRadius: '4px', fontFamily: 'monospace', fontWeight: 600 }}>
                                                                    {req.costCenterCode || '—'} / {req.deptCode || '—'}
                                                                </span>
                                                            </div>
                                                        ) : (
                                                            <span style={{ color: C.textHint, fontSize: '0.72rem', fontStyle: 'italic' }}>Sem Classif.</span>
                                                        )}
                                                    </div>
                                                )}
                                            </div>

                                            {/* Módulos e Configs */}
                                            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', flexGrow: 1 }}>
                                                <span style={{ fontSize: '0.74rem', fontWeight: 700, color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                                                    Módulos & Configurações
                                                </span>
                                                
                                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                                                    {renderModuleBadges(req.modules)}
                                                    
                                                    <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginTop: '2px' }}>
                                                        <span style={{ fontSize: '0.64rem', fontWeight: 700, padding: '2px 8px', borderRadius: '6px', background: 'rgba(124, 77, 255, 0.08)', color: '#7c4dff', border: '1px solid rgba(124, 77, 255, 0.15)' }}>
                                                            🏷️ Tabela: {req.priceTableMode === 'customer' ? 'Cliente' : req.priceTableMode === 'region' ? 'Região' : 'Base'}
                                                        </span>
                                                        <span style={{
                                                            fontSize: '0.64rem', fontWeight: 700, padding: '2px 8px', borderRadius: '6px',
                                                            background: req.allowNegativeStock ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)',
                                                            color: req.allowNegativeStock ? C.success : C.danger,
                                                            border: req.allowNegativeStock ? '1px solid rgba(16, 185, 129, 0.15)' : '1px solid rgba(239, 68, 68, 0.15)'
                                                        }}>
                                                            📦 Estoque: {req.allowNegativeStock ? 'Permitido' : 'Bloqueado'}
                                                        </span>
                                                    </div>
                                                </div>
                                            </div>

                                            {/* Detalhe expandido de Recusa dentro do card */}
                                            {isExpanded && req.status === 'Recusada' && req.rejectReason && (
                                                <div style={{
                                                    display: 'flex', alignItems: 'flex-start', gap: '0.5rem',
                                                    padding: '0.75rem', background: C.dangerAlpha,
                                                    borderRadius: '10px', border: `1px solid ${C.danger}20`,
                                                    marginTop: '0.25rem'
                                                }}>
                                                    <AlertTriangle size={14} color={C.danger} style={{ marginTop: '2px', flexShrink: 0 }} />
                                                    <div>
                                                        <strong style={{ fontSize: '0.74rem', color: C.danger, display: 'block', marginBottom: '2px' }}>Motivo da Recusa:</strong>
                                                        <span style={{ fontSize: '0.72rem', color: C.textMain, lineHeight: 1.4 }}>{req.rejectReason}</span>
                                                    </div>
                                                </div>
                                            )}

                                            <div style={{ height: '1px', background: C.border, margin: '0 -0.25rem' }} />

                                            {/* Ações do Card */}
                                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                                <div>
                                                    {requestLinks[req.id] ? (
                                                        <button
                                                            type="button"
                                                            onClick={() => handleOpenLicenseModal(req.id)}
                                                            className="btn btn-sm"
                                                            style={{
                                                                fontSize: '0.72rem',
                                                                padding: '0.35rem 0.75rem',
                                                                borderRadius: '8px',
                                                                background: 'rgba(16, 185, 129, 0.12)',
                                                                border: '1px solid rgba(16, 185, 129, 0.25)',
                                                                color: '#10b981',
                                                                fontWeight: 700,
                                                                display: 'flex',
                                                                alignItems: 'center',
                                                                gap: '4px',
                                                                cursor: 'pointer'
                                                            }}
                                                        >
                                                            <KeyRound size={13} color="#10b981" />
                                                            🤝 Licença
                                                        </button>
                                                    ) : (
                                                        <span style={{ fontSize: '0.72rem', color: C.textHint, fontStyle: 'italic' }}>Sem licença ativa</span>
                                                    )}
                                                </div>

                                                <div style={{ display: 'flex', gap: '0.4rem', alignItems: 'center' }}>
                                                    {canSee('requests.approve') ? (
                                                        <button
                                                            type="button"
                                                            onClick={async () => {
                                                                if (req.status === 'Aprovada') {
                                                                    const link = requestLinks[req.id];
                                                                    if (link && link.companyId) {
                                                                        await requestService.syncRequestModulesWithCompanyModules(link.companyId);
                                                                    }
                                                                    await loadData();
                                                                } else {
                                                                    await handleStatusChange(req.id, 'Aprovada');
                                                                }
                                                            }}
                                                            className="btn btn-sm btn-outline"
                                                            style={{ fontSize: '0.72rem', padding: '0.35rem 0.75rem', borderRadius: '8px', fontWeight: 600 }}
                                                        >
                                                            {req.status === 'Aprovada' ? 'Atualizar Licenças' : 'Liberar'}
                                                        </button>
                                                    ) : (
                                                        !requestLinks[req.id] && <span style={{ fontSize: '0.72rem', color: C.textHint, fontStyle: 'italic' }}>Sem alçada</span>
                                                    )}
                                                    
                                                    <button
                                                        type="button"
                                                        disabled={Boolean(requestLinks[req.id])}
                                                        onClick={() => handleDeleteRequest(req.id)}
                                                        title={requestLinks[req.id] ? "Não é possível excluir: Licença ativa associada" : "Eliminar Requisição"}
                                                        style={{
                                                            display: 'inline-flex',
                                                            alignItems: 'center',
                                                            justifyContent: 'center',
                                                            padding: '0.4rem',
                                                            borderRadius: '8px',
                                                            background: requestLinks[req.id] ? 'rgba(0, 0, 0, 0.03)' : 'rgba(239, 68, 68, 0.08)',
                                                            border: requestLinks[req.id] ? '1px solid rgba(0, 0, 0, 0.08)' : '1px solid rgba(239, 68, 68, 0.2)',
                                                            color: requestLinks[req.id] ? C.textHint : '#ef4444',
                                                            cursor: requestLinks[req.id] ? 'not-allowed' : 'pointer',
                                                            transition: 'all 0.15s',
                                                            opacity: requestLinks[req.id] ? 0.5 : 1
                                                        }}
                                                        onMouseEnter={e => {
                                                            if (!requestLinks[req.id]) e.currentTarget.style.background = 'rgba(239, 68, 68, 0.15)';
                                                        }}
                                                        onMouseLeave={e => {
                                                            if (!requestLinks[req.id]) e.currentTarget.style.background = 'rgba(239, 68, 68, 0.08)';
                                                        }}
                                                    >
                                                        <Trash2 size={14} />
                                                    </button>
                                                </div>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        ) : (
                            <div style={{ overflowX: 'auto' }}>
                                <table className="data-table">
                                    <thead>
                                        <tr>
                                            <th>Parceiro Integrador</th>
                                            <th>Cliente Destinatário</th>
                                            <th>Módulos & Configs</th>
                                            <th>C. Custo / Depto</th>
                                            <th>Status (Mudar)</th>
                                            <th style={{ textAlign: 'right' }}>Ações adicionais</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {filteredRequests.map(req => {
                                            const isExpanded = expandedRequest === req.id;
                                            const isMulti = req.clientCompanyType === 'MultiEmpresa';
                                            return (
                                                <React.Fragment key={req.id}>
                                                    <tr>
                                                        {/* Parceiro */}
                                                        <td>
                                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                                                <div style={{
                                                                    width: 30, height: 30, borderRadius: '50%',
                                                                    background: C.primaryAlpha, color: C.primary,
                                                                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                                    fontWeight: 700, fontSize: '0.72rem', flexShrink: 0
                                                                }}>
                                                                    {req.partnerName.split(' ').map(w => w[0]).slice(0,2).join('').toUpperCase()}
                                                                </div>
                                                                <div>
                                                                    <div style={{ fontWeight: 600, color: C.textMain, fontSize: '0.8rem' }}>{req.partnerName}</div>
                                                                    <div style={{ fontSize: '0.68rem', color: C.textMuted }}>Data: {new Date(req.createdAt).toLocaleDateString('pt-BR')} {new Date(req.createdAt).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</div>
                                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '3px', fontSize: '0.68rem', color: C.textMuted, marginTop: '2px' }}>
                                                                        <User size={10} color={C.textHint} />
                                                                        <span title={req.requestorEmail} style={{ textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap', maxWidth: '140px' }}>
                                                                            {req.requestorEmail}
                                                                        </span>
                                                                    </div>
                                                                </div>
                                                            </div>
                                                        </td>

                                                        {/* Cliente Destinatário */}
                                                        <td>
                                                            {isMulti ? (
                                                                <div>
                                                                    {getRequestCompanyName(req) && (
                                                                        <div style={{ fontWeight: 700, color: C.textMain, fontSize: '0.8rem', marginBottom: '2px' }}>
                                                                            {getRequestCompanyName(req)}
                                                                        </div>
                                                                    )}
                                                                    <span style={{
                                                                        fontSize: '0.64rem', padding: '1px 6px', borderRadius: '4px',
                                                                        background: 'rgba(124,77,255,0.08)', color: '#7c4dff', fontWeight: 800,
                                                                        display: 'inline-block', marginBottom: '4px', textTransform: 'uppercase'
                                                                    }}>
                                                                        🏢 MultiEmpresa ({req.companies?.length || 0})
                                                                    </span>
                                                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', maxHeight: '70px', overflowY: 'auto' }}>
                                                                        {req.companies?.map((c, i) => (
                                                                            <span key={i} style={{ fontSize: '0.76rem', fontFamily: 'monospace', color: C.textSub }}>
                                                                                • {c.cnpj}
                                                                            </span>
                                                                        ))}
                                                                    </div>
                                                                </div>
                                                            ) : (
                                                                <div>
                                                                    {getRequestCompanyName(req) && (
                                                                        <div style={{ fontWeight: 700, color: C.textMain, fontSize: '0.8rem', marginBottom: '2px' }}>
                                                                            {getRequestCompanyName(req)}
                                                                        </div>
                                                                    )}
                                                                    <div style={{ fontWeight: 600, color: C.textSub, fontSize: '0.78rem', fontFamily: 'monospace' }}>{req.clientCnpj}</div>
                                                                    <div style={{ display: 'inline-flex', marginTop: '2px' }}>
                                                                        <span style={{
                                                                            fontSize: '0.64rem', padding: '1px 6px', borderRadius: '4px',
                                                                            background: 'rgba(37,99,235,0.08)', color: '#2563eb', fontWeight: 800,
                                                                            textTransform: 'uppercase'
                                                                        }}>
                                                                            👤 Individual
                                                                        </span>
                                                                    </div>
                                                                </div>
                                                            )}
                                                        </td>

                                                        {/* Módulos e Configurações */}
                                                        <td>
                                                            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                                                                {renderModuleBadges(req.modules)}
                                                                
                                                                {/* Configs adicionadas */}
                                                                <div style={{ display: 'flex', gap: '4px', flexWrap: 'wrap', marginTop: '2px' }}>
                                                                    <span style={{ fontSize: '0.62rem', fontWeight: 700, padding: '1px 6px', borderRadius: '4px', background: 'rgba(124, 77, 255, 0.08)', color: '#7c4dff' }}>
                                                                        🏷️ Tabela: {req.priceTableMode === 'customer' ? 'Cliente' : req.priceTableMode === 'region' ? 'Região' : 'Base'}
                                                                    </span>
                                                                    <span style={{ fontSize: '0.62rem', fontWeight: 700, padding: '1px 6px', borderRadius: '4px', background: req.allowNegativeStock ? 'rgba(16, 185, 129, 0.08)' : 'rgba(239, 68, 68, 0.08)', color: req.allowNegativeStock ? C.success : C.danger }}>
                                                                        📦 Estoque: {req.allowNegativeStock ? 'Permitido' : 'Bloqueado'}
                                                                    </span>
                                                                </div>
                                                            </div>
                                                        </td>

                                                        {/* Centro Custo / Depto */}
                                                        <td>
                                                            {isMulti ? (
                                                                <div style={{ display: 'flex', flexDirection: 'column', gap: '2px', maxHeight: '70px', overflowY: 'auto' }}>
                                                                    {req.companies?.map((c, i) => (
                                                                        <span key={i} style={{ fontSize: '0.74rem', background: 'rgba(0,0,0,0.04)', color: C.textSub, padding: '1px 4px', borderRadius: '3px', fontFamily: 'monospace', fontWeight: 600 }}>
                                                                            {c.costCenter || '—'} / {c.dept || '—'}
                                                                        </span>
                                                                    ))}
                                                                </div>
                                                            ) : (
                                                                req.costCenterCode || req.deptCode ? (
                                                                    <span style={{ fontSize: '0.78rem', background: 'rgba(0,0,0,0.04)', color: C.textSub, padding: '2px 6px', borderRadius: '4px', fontFamily: 'monospace', fontWeight: 600 }}>
                                                                        {req.costCenterCode || '—'} / {req.deptCode || '—'}
                                                                    </span>
                                                                ) : (
                                                                    <span style={{ color: C.textHint, fontSize: '0.78rem' }}>Sem Classif.</span>
                                                                )
                                                            )}
                                                        </td>

                                                        {/* Status (Interativo) */}
                                                        <td>
                                                            {renderInteractiveStatus(req)}
                                                        </td>

                                                        {/* Ações */}
                                                        <td style={{ textAlign: 'right' }}>
                                                            <div style={{ display: 'inline-flex', gap: '0.4rem', justifyContent: 'flex-end', alignItems: 'center' }}>
                                                                 {requestLinks[req.id] && (
                                                                     <button
                                                                         type="button"
                                                                         onClick={() => handleOpenLicenseModal(req.id)}
                                                                         className="btn btn-sm"
                                                                         style={{
                                                                             fontSize: '0.7rem',
                                                                             padding: '0.3rem 0.6rem',
                                                                             borderRadius: '6px',
                                                                             background: 'rgba(16, 185, 129, 0.12)',
                                                                             border: '1px solid rgba(16, 185, 129, 0.25)',
                                                                             color: '#10b981',
                                                                             fontWeight: 700,
                                                                             display: 'flex',
                                                                             alignItems: 'center',
                                                                             gap: '4px',
                                                                             cursor: 'pointer'
                                                                         }}
                                                                     >
                                                                         <KeyRound size={12} color="#10b981" />
                                                                         🤝 Licença
                                                                     </button>
                                                                 )}
                                                                 {canSee('requests.approve') ? (
                                                                     <button
                                                                         type="button"
                                                                         onClick={async () => {
                                                                             if (req.status === 'Aprovada') {
                                                                                 const link = requestLinks[req.id];
                                                                                 if (link && link.companyId) {
                                                                                     await requestService.syncRequestModulesWithCompanyModules(link.companyId);
                                                                                 }
                                                                                 await loadData();
                                                                             } else {
                                                                                 await handleStatusChange(req.id, 'Aprovada');
                                                                             }
                                                                         }}
                                                                         className="btn btn-sm btn-outline"
                                                                         style={{ fontSize: '0.7rem', padding: '0.3rem 0.6rem', borderRadius: '6px' }}
                                                                     >
                                                                         {req.status === 'Aprovada' ? 'Atualizar Licenças' : 'Liberar'}
                                                                     </button>
                                                                 ) : (
                                                                     !requestLinks[req.id] && <span style={{ fontSize: '0.78rem', color: C.textHint, fontStyle: 'italic' }}>Sem alçada</span>
                                                                 )}
                                                                 <button
                                                                     type="button"
                                                                     disabled={Boolean(requestLinks[req.id])}
                                                                     onClick={() => handleDeleteRequest(req.id)}
                                                                     title={requestLinks[req.id] ? "Não é possível excluir: Licença ativa associada" : "Eliminar Requisição"}
                                                                     style={{
                                                                         display: 'inline-flex',
                                                                         alignItems: 'center',
                                                                         justifyContent: 'center',
                                                                         padding: '0.35rem',
                                                                         borderRadius: '6px',
                                                                         background: requestLinks[req.id] ? 'rgba(0, 0, 0, 0.03)' : 'rgba(239, 68, 68, 0.08)',
                                                                         border: requestLinks[req.id] ? '1px solid rgba(0, 0, 0, 0.08)' : '1px solid rgba(239, 68, 68, 0.2)',
                                                                         color: requestLinks[req.id] ? C.textHint : '#ef4444',
                                                                         cursor: requestLinks[req.id] ? 'not-allowed' : 'pointer',
                                                                         transition: 'all 0.15s',
                                                                         opacity: requestLinks[req.id] ? 0.5 : 1
                                                                     }}
                                                                     onMouseEnter={e => {
                                                                         if (!requestLinks[req.id]) e.currentTarget.style.background = 'rgba(239, 68, 68, 0.15)';
                                                                     }}
                                                                     onMouseLeave={e => {
                                                                         if (!requestLinks[req.id]) e.currentTarget.style.background = 'rgba(239, 68, 68, 0.08)';
                                                                     }}
                                                                 >
                                                                     <Trash2 size={13} />
                                                                 </button>
                                                             </div>
                                                        </td>
                                                    </tr>

                                                    {/* Detalhe expandido de Recusa */}
                                                    {isExpanded && (
                                                        <tr style={{ background: 'rgba(239, 68, 68, 0.02)' }}>
                                                            <td colSpan={7} style={{ padding: '0.75rem 1.25rem', borderBottom: `1px solid ${C.border}` }}>
                                                                <div style={{
                                                                    display: 'flex', alignItems: 'flex-start', gap: '0.5rem',
                                                                    padding: '0.75rem 1rem', background: C.dangerAlpha,
                                                                    borderRadius: '8px', border: `1px solid ${C.danger}20`,
                                                                }}>
                                                                    <AlertTriangle size={15} color={C.danger} style={{ marginTop: '2px', flexShrink: 0 }} />
                                                                    <div>
                                                                        <strong style={{ fontSize: '0.78rem', color: C.danger, display: 'block', marginBottom: '2px' }}>Motivo da Recusa:</strong>
                                                                        <span style={{ fontSize: '0.78rem', color: C.textMain, lineHeight: 1.4 }}>{req.rejectReason}</span>
                                                                    </div>
                                                                </div>
                                                            </td>
                                                        </tr>
                                                    )}
                                                </React.Fragment>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </div>
                </>
            )}

            {/* ─── TAB CONTENT: FORMULÁRIO DE LANÇAMENTO ──────────────────────── */}
            {tab === 'new' && (
                <form onSubmit={handleCreateRequest} style={{ display: 'flex', flexDirection: 'column', gap: '1.25rem' }}>
                    {/* Bloco 1: Identificação e Vínculo */}
                    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: '16px', padding: '1.5rem', boxShadow: '0 2px 8px rgba(0,0,0,0.01)' }}>
                        <h3 style={{ margin: '0 0 1.25rem', fontSize: '0.92rem', fontWeight: 800, textTransform: 'uppercase', color: C.primary, letterSpacing: '0.06em', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                            <Building size={16} /> Bloco 1: Identificação e Vínculo
                        </h3>
                        
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1.25rem', marginBottom: '1.25rem' }}>
                            <FormField label="Parceiro Comercial *">
                                {user.isPartner ? (
                                    <input
                                        type="text"
                                        className="input-field"
                                        style={{ ...inputStyle, background: 'rgba(0,0,0,0.03)', border: `1px solid ${C.border}`, pointerEvents: 'none' }}
                                        value={partners.find(p => p.id === user.partnerId)?.name || 'Carregando parceiro...'}
                                        readOnly
                                    />
                                ) : (
                                    <AutocompleteSelect
                                        value={reqPartner}
                                        onChange={setReqPartner}
                                        options={partners.map(p => ({ value: p.id, label: p.name, cnpj: p.cnpj }))}
                                        placeholder="— Selecione o Parceiro Integrador —"
                                    />
                                )}
                            </FormField>

                            <FormField label="Usuário Solicitante">
                                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', height: '42px', ...inputStyle, background: 'rgba(0,0,0,0.03)', border: `1px solid ${C.border}`, pointerEvents: 'none' }}>
                                    <User size={14} color={C.textMuted} />
                                    <span style={{ color: C.textSub, fontWeight: 500 }}>{user.name} ({user.email})</span>
                                </div>
                            </FormField>
                        </div>

                        {/* Nome da Empresa Cliente */}
                        <div style={{ marginBottom: '1.25rem' }}>
                            <FormField label="Nome fantasia / Razão Social do Cliente *">
                                <input
                                    type="text"
                                    placeholder="Ex: Auto Posto Estrela Ltda"
                                    value={reqCompanyName}
                                    onChange={e => setReqCompanyName(e.target.value)}
                                    style={inputStyle}
                                    required
                                />
                            </FormField>
                        </div>

                        {/* SELETOR DE ESTRUTURA (Individual vs MultiEmpresa) */}
                        <div style={{ marginBottom: '1.5rem', borderBottom: `1px solid ${C.border}`, paddingBottom: '1.25rem' }}>
                            <label style={{ display: 'block', fontSize: '0.78rem', fontWeight: 700, color: C.textSub, marginBottom: '0.6rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                                Estrutura da Empresa Final *
                            </label>
                            <div style={{ display: 'flex', gap: '1rem', maxWidth: '500px' }}>
                                <label
                                    style={{
                                        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                                        gap: '0.5rem', padding: '0.75rem', borderRadius: '12px',
                                        border: `1px solid ${reqStructureType === 'individual' ? C.primary : C.border}`,
                                        background: reqStructureType === 'individual' ? C.primaryAlpha : 'transparent',
                                        color: reqStructureType === 'individual' ? C.primary : C.textSub,
                                        fontSize: '0.875rem', fontWeight: 700, cursor: 'pointer',
                                        transition: 'all 0.15s'
                                    }}
                                >
                                    <input
                                        type="radio"
                                        name="structureType"
                                        checked={reqStructureType === 'individual'}
                                        onChange={() => setReqStructureType('individual')}
                                        style={{ accentColor: C.primary }}
                                    />
                                    Empresa Individual
                                </label>
                                <label
                                    style={{
                                        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                                        gap: '0.5rem', padding: '0.75rem', borderRadius: '12px',
                                        border: `1px solid ${reqStructureType === 'multi' ? C.primary : C.border}`,
                                        background: reqStructureType === 'multi' ? C.primaryAlpha : 'transparent',
                                        color: reqStructureType === 'multi' ? C.primary : C.textSub,
                                        fontSize: '0.875rem', fontWeight: 700, cursor: 'pointer',
                                        transition: 'all 0.15s'
                                    }}
                                >
                                    <input
                                        type="radio"
                                        name="structureType"
                                        checked={reqStructureType === 'multi'}
                                        onChange={() => setReqStructureType('multi')}
                                        style={{ accentColor: C.primary }}
                                    />
                                    MultiEmpresa (Filiais)
                                </label>
                            </div>
                        </div>

                        {/* FORMULÁRIO DINÂMICO CONFORME TIPO */}
                        {reqStructureType === 'individual' ? (
                            <div className="animate-fade-in" style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: '1rem' }}>
                                <FormField label="CNPJ da Empresa Destinatária *">
                                    <input
                                        type="text"
                                        placeholder="00.000.000/0000-00"
                                        value={reqCnpj}
                                        onChange={e => setReqCnpj(maskCnpj(e.target.value))}
                                        style={inputStyle}
                                        required
                                    />
                                </FormField>
                                <FormField label="Centro de Custo (Código)">
                                    <input
                                        type="text"
                                        placeholder="Ex: 101"
                                        value={reqCostCenter}
                                        onChange={e => setReqCostCenter(e.target.value)}
                                        style={inputStyle}
                                    />
                                </FormField>
                                <FormField label="Departamento (Código)">
                                    <input
                                        type="text"
                                        placeholder="Ex: 10"
                                        value={reqDept}
                                        onChange={e => setReqDept(e.target.value)}
                                        style={inputStyle}
                                    />
                                </FormField>
                            </div>
                        ) : (
                            <div className="animate-fade-in" style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                                    <span style={{ fontSize: '0.78rem', fontWeight: 700, color: C.textSub }}>
                                        Filiais Vinculadas ({reqCompanies.length})
                                    </span>
                                    <button
                                        type="button"
                                        className="btn btn-outline btn-sm"
                                        onClick={addCompanyRow}
                                        style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.74rem', padding: '4px 8px' }}
                                    >
                                        <Plus size={12} /> Adicionar Filial
                                    </button>
                                </div>

                                <div style={{ border: `1px solid ${C.border}`, borderRadius: '12px', overflow: 'hidden' }}>
                                    <div style={{
                                        display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 60px',
                                        background: 'rgba(27,143,205,0.03)', borderBottom: `1px solid ${C.border}`,
                                        padding: '0.5rem 1rem', fontSize: '0.7rem', fontWeight: 700,
                                        color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em'
                                    }}>
                                        <span>CNPJ da Filial *</span>
                                        <span>Centro de Custo</span>
                                        <span>Departamento</span>
                                        <span style={{ textAlign: 'right' }}>Ação</span>
                                    </div>
                                    
                                    <div style={{ display: 'flex', flexDirection: 'column' }}>
                                        {reqCompanies.map((cRow, index) => (
                                            <div
                                                key={cRow.id}
                                                style={{
                                                    display: 'grid', gridTemplateColumns: '2fr 1fr 1fr 60px',
                                                    padding: '0.6rem 1rem', alignItems: 'center',
                                                    borderBottom: index < reqCompanies.length - 1 ? `1px solid ${C.border}` : 'none',
                                                    background: '#fff'
                                                }}
                                            >
                                                <div style={{ paddingRight: '0.75rem' }}>
                                                    <input
                                                        type="text"
                                                        placeholder="00.000.000/0000-00"
                                                        value={cRow.cnpj}
                                                        onChange={e => updateCompanyRow(cRow.id, 'cnpj', e.target.value)}
                                                        style={{ ...inputStyle, padding: '0.4rem 0.6rem', height: '34px' }}
                                                        required
                                                    />
                                                </div>
                                                <div style={{ paddingRight: '0.75rem' }}>
                                                    <input
                                                        type="text"
                                                        placeholder="Cód"
                                                        value={cRow.costCenter}
                                                        onChange={e => updateCompanyRow(cRow.id, 'costCenter', e.target.value)}
                                                        style={{ ...inputStyle, padding: '0.4rem 0.6rem', height: '34px' }}
                                                    />
                                                </div>
                                                <div style={{ paddingRight: '0.75rem' }}>
                                                    <input
                                                        type="text"
                                                        placeholder="Cód"
                                                        value={cRow.dept}
                                                        onChange={e => updateCompanyRow(cRow.id, 'dept', e.target.value)}
                                                        style={{ ...inputStyle, padding: '0.4rem 0.6rem', height: '34px' }}
                                                    />
                                                </div>
                                                <div style={{ textAlign: 'right' }}>
                                                    <button
                                                        type="button"
                                                        disabled={reqCompanies.length === 1}
                                                        onClick={() => removeCompanyRow(cRow.id)}
                                                        style={{
                                                            width: 28, height: 28, borderRadius: '6px',
                                                            background: C.dangerAlpha, color: C.danger,
                                                            border: `1px solid ${C.danger}15`,
                                                            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                                                            cursor: reqCompanies.length === 1 ? 'not-allowed' : 'pointer',
                                                            opacity: reqCompanies.length === 1 ? 0.4 : 1
                                                        }}
                                                    >
                                                        <Trash2 size={12} />
                                                    </button>
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>

                    {/* Bloco 1.5: Configurações do App Mobile (Cards Premium) */}
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.25rem', flexWrap: 'wrap' }}>
                        
                        {/* Configuração de Tabela de Preços */}
                        <div style={{
                            background: C.surface,
                            borderRadius: '16px',
                            border: `1px solid ${C.border}`,
                            borderLeft: '4px solid #7C4DFF',
                            padding: '1.25rem 1.5rem',
                            boxShadow: '0 2px 10px rgba(0,0,0,0.03)',
                            display: 'flex',
                            flexDirection: 'column',
                            justifyContent: 'space-between'
                        }}>
                            <div>
                                <h3 style={{ fontSize: '0.92rem', fontWeight: 800, color: C.textMain, margin: '0 0 0.5rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                    <Layers size={16} color="#7C4DFF" />
                                    Configuração de Tabela de Preços
                                </h3>
                                <p style={{ fontSize: '0.78rem', color: C.textMuted, margin: '0 0 1rem' }}>
                                    Controla como o app mobile aplica as tabelas de preço ao criar pedidos.
                                </p>
                                <FormField label="Modo de Tabela de Preço">
                                    <select
                                        value={reqPriceTableMode}
                                        onChange={e => setReqPriceTableMode(e.target.value)}
                                        style={{ ...inputStyle, cursor: 'pointer', border: '1px solid rgba(124, 77, 255, 0.2)' }}
                                    >
                                        <option value="none">Não usar tabela (preço base)</option>
                                        <option value="customer">Usar tabela por Cliente</option>
                                        <option value="region">Usar tabela por Região</option>
                                    </select>
                                </FormField>
                            </div>
                            
                            <div style={{
                                padding: '0.75rem 1rem', background: 'rgba(124, 77, 255, 0.04)', borderRadius: '8px',
                                border: '1px dashed rgba(124, 77, 255, 0.3)', color: '#6d28d9', fontSize: '0.76rem',
                                display: 'flex', alignItems: 'flex-start', gap: '0.4rem', marginTop: '0.5rem'
                            }}>
                                <Info size={14} style={{ marginTop: '2px', flexShrink: 0 }} />
                                <span style={{ fontWeight: 500, lineHeight: 1.4 }}>{getPriceTableHint()}</span>
                            </div>
                        </div>

                        {/* Controle de Estoque */}
                        <div style={{
                            background: C.surface,
                            borderRadius: '16px',
                            border: `1px solid ${C.border}`,
                            borderLeft: '4px solid #F59E0B',
                            padding: '1.25rem 1.5rem',
                            boxShadow: '0 2px 10px rgba(0,0,0,0.03)',
                            display: 'flex',
                            flexDirection: 'column',
                            justifyContent: 'space-between'
                        }}>
                            <div>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                                    <h3 style={{ fontSize: '0.92rem', fontWeight: 800, color: C.textMain, margin: 0, display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                        <Briefcase size={16} color="#F59E0B" />
                                        Controle de Estoque
                                    </h3>
                                    
                                    {/* Custom Toggle Switch */}
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                        <span style={{ fontSize: '0.7rem', fontWeight: 800, color: reqAllowNegativeStock ? C.success : C.textMuted }}>
                                            {reqAllowNegativeStock ? 'PERMITIDO' : 'BLOQUEADO'}
                                        </span>
                                        <button
                                            type="button"
                                            onClick={() => setReqAllowNegativeStock(!reqAllowNegativeStock)}
                                            style={{
                                                width: '42px', height: '22px', borderRadius: '20px',
                                                background: reqAllowNegativeStock ? C.primary : '#ccc',
                                                position: 'relative', cursor: 'pointer', transition: 'all 0.2s',
                                                display: 'flex', alignItems: 'center', padding: '0 2px'
                                            }}
                                        >
                                            <div style={{
                                                width: '18px', height: '18px', borderRadius: '50%',
                                                background: '#fff', boxShadow: '0 2px 4px rgba(0,0,0,0.2)',
                                                transform: reqAllowNegativeStock ? 'translateX(20px)' : 'translateX(0)',
                                                transition: 'all 0.2s'
                                            }} />
                                        </button>
                                    </div>
                                </div>
                                <p style={{ fontSize: '0.78rem', color: C.textMuted, margin: '0 0 1rem' }}>
                                    Quando **ativado**, o app permite adicionar produtos com estoque zerado ou negativo ao pedido.
                                </p>
                            </div>
                            
                            <div style={{
                                padding: '0.75rem 1rem',
                                background: reqAllowNegativeStock ? 'rgba(16, 185, 129, 0.04)' : 'rgba(239, 68, 68, 0.04)',
                                borderRadius: '8px',
                                border: `1px dashed ${reqAllowNegativeStock ? 'rgba(16, 185, 129, 0.3)' : 'rgba(239, 68, 68, 0.3)'}`,
                                color: reqAllowNegativeStock ? '#047857' : '#b91c1c',
                                fontSize: '0.76rem',
                                display: 'flex', alignItems: 'flex-start', gap: '0.4rem', marginTop: '0.5rem'
                            }}>
                                <Info size={14} style={{ marginTop: '2px', flexShrink: 0 }} />
                                <span style={{ fontWeight: 500, lineHeight: 1.4 }}>
                                    {reqAllowNegativeStock
                                        ? 'Estoque Liberado: O app permite adicionar produtos zerados, mostrando um selo laranja "Sem Estoque", mantendo a venda aberta.'
                                        : 'Venda sem estoque bloqueada (padrão): Produtos zerados ou indisponíveis ficam desabilitados no aplicativo mobile.'
                                    }
                                </span>
                            </div>
                        </div>

                    </div>

                    {/* Bloco 3: Ativação de Módulos (Grid Dinâmico) */}
                    <div style={{ background: C.surface, border: `1px solid ${C.border}`, borderRadius: '16px', padding: '1.5rem', boxShadow: '0 2px 8px rgba(0,0,0,0.01)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem' }}>
                            <h3 style={{ margin: 0, fontSize: '0.92rem', fontWeight: 800, textTransform: 'uppercase', color: C.primary, letterSpacing: '0.06em', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                <Sparkles size={16} /> Bloco 2: Ativação de Módulos do Ecossistema
                            </h3>
                            <button
                                type="button"
                                className="btn btn-outline btn-sm"
                                onClick={addModuleRow}
                                disabled={reqModules.length >= Object.keys(MODULE_META).length}
                                style={{ display: 'flex', alignItems: 'center', gap: '0.3rem' }}
                            >
                                <Plus size={14} /> Adicionar Módulo
                            </button>
                        </div>

                        {/* Tabela Dinâmica de Módulos */}
                        <div style={{ border: `1px solid ${C.border}`, borderRadius: '12px', overflow: 'hidden' }}>
                            <div style={{
                                display: 'grid', gridTemplateColumns: '2fr 1.5fr 80px',
                                background: 'rgba(27,143,205,0.03)', borderBottom: `1px solid ${C.border}`,
                                padding: '0.65rem 1rem', fontSize: '0.72rem', fontWeight: 700,
                                color: C.textMuted, textTransform: 'uppercase', letterSpacing: '0.04em'
                            }}>
                                <span>Módulo</span>
                                <span>Quantidade de Usuários</span>
                                <span style={{ textAlign: 'right' }}>Ação</span>
                            </div>

                            <div style={{ display: 'flex', flexDirection: 'column' }}>
                                {reqModules.map((row, index) => {
                                    const options = Object.entries(MODULE_META).map(([key, val]) => ({
                                        slug: key,
                                        label: `${val.icon} ${val.label} — ${val.desc || ''}`
                                    }));

                                    return (
                                        <div
                                            key={index}
                                            style={{
                                                display: 'grid', gridTemplateColumns: '2fr 1.5fr 80px',
                                                padding: '0.75rem 1rem', alignItems: 'center',
                                                borderBottom: index < reqModules.length - 1 ? `1px solid ${C.border}` : 'none',
                                                background: '#fff'
                                            }}
                                        >
                                            <div style={{ paddingRight: '1rem' }}>
                                                <select
                                                    value={row.moduleSlug}
                                                    onChange={e => updateModuleRow(index, 'moduleSlug', e.target.value)}
                                                    style={{ ...inputStyle, padding: '0.5rem 0.75rem', height: '36px', cursor: 'pointer' }}
                                                >
                                                    {options.map(opt => (
                                                        <option key={opt.slug} value={opt.slug}>{opt.label}</option>
                                                    ))}
                                                </select>
                                            </div>

                                            <div style={{ paddingRight: '1rem' }}>
                                                <input
                                                    type="number"
                                                    min={1}
                                                    value={row.quantity}
                                                    onChange={e => updateModuleRow(index, 'quantity', e.target.value)}
                                                    style={{ ...inputStyle, padding: '0.5rem 0.75rem', height: '36px' }}
                                                    required
                                                />
                                            </div>

                                            <div style={{ textAlign: 'right' }}>
                                                <button
                                                    type="button"
                                                    disabled={reqModules.length === 1}
                                                    onClick={() => removeModuleRow(index)}
                                                    style={{
                                                        width: 32, height: 32, borderRadius: '8px',
                                                        background: C.dangerAlpha, color: C.danger,
                                                        border: `1px solid ${C.danger}15`,
                                                        display: 'inline-flex', alignItems: 'center', justifyItems: 'center',
                                                        cursor: reqModules.length === 1 ? 'not-allowed' : 'pointer',
                                                        opacity: reqModules.length === 1 ? 0.4 : 1,
                                                        transition: 'all 0.15s'
                                                    }}
                                                >
                                                    <Trash2 size={14} style={{ display: 'block', margin: 'auto' }} />
                                                </button>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>
                    </div>

                    {/* Botões do Formulário */}
                    <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '0.5rem' }}>
                        <button
                            type="button"
                            className="btn btn-outline"
                            onClick={() => setTab('list')}
                            style={{ padding: '0.65rem 1.5rem', borderRadius: '12px' }}
                        >
                            Cancelar
                        </button>
                        <button
                            type="submit"
                            disabled={savingRequest}
                            style={{
                                display: 'flex', alignItems: 'center', gap: '0.5rem',
                                padding: '0.65rem 1.75rem', borderRadius: '12px',
                                background: 'var(--gradient-primary)',
                                color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                                cursor: savingRequest ? 'not-allowed' : 'pointer', opacity: savingRequest ? 0.7 : 1,
                                boxShadow: '0 4px 16px rgba(27,143,205,0.35)', transition: 'all 0.2s',
                            }}
                        >
                            {savingRequest ? 'Enviando...' : <ClipboardCheck size={16} />}
                            {savingRequest ? 'Processando...' : 'Lançar Requisição'}
                        </button>
                    </div>
                </form>
            )}



            {/* ─── MODAL INTEGRADO: JUSTIFICATIVA DE RECUSA ──────────────────── */}
            <Modal
                open={!!rejectionModal}
                title="Recusar Requisição de Módulos"
                icon={AlertTriangle}
                onClose={() => setRejectionModal(null)}
                width="480px"
            >
                <form onSubmit={handleRejectSubmit}>
                    <p style={{ margin: '0 0 1rem', fontSize: '0.85rem', color: C.textSub, lineHeight: 1.5 }}>
                        Você está recusando a requisição do parceiro <strong>{rejectionModal?.partnerName}</strong>. Por favor, insira o motivo da rejeição.
                    </p>
                    <FormField label="Justificativa / Motivo da Recusa *">
                        <textarea
                            name="reason"
                            placeholder="Descreva o motivo pelo qual esta liberação foi recusada pela administração..."
                            style={{ ...inputStyle, minHeight: '100px', resize: 'vertical', fontFamily: 'inherit' }}
                            required
                        />
                    </FormField>

                    <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1rem' }}>
                        <button
                            type="button"
                            className="btn btn-outline"
                            onClick={() => setRejectionModal(null)}
                            style={{ padding: '0.65rem 1.25rem', borderRadius: '10px' }}
                        >
                            Cancelar
                        </button>
                        <button
                            type="submit"
                            style={{
                                display: 'flex', alignItems: 'center', gap: '0.5rem',
                                padding: '0.65rem 1.5rem', borderRadius: '10px',
                                background: C.danger,
                                color: '#fff', fontWeight: 700, fontSize: '0.875rem', border: 'none',
                                cursor: 'pointer', transition: 'all 0.2s',
                                boxShadow: '0 4px 14px rgba(239,68,68,0.25)',
                            }}
                        >
                            <X size={16} />
                            Confirmar Recusa
                        </button>
                    </div>
                </form>
            </Modal>

            {/* ─── MODAL: DETALHES DA LICENÇA ATIVA ─────────────────────────── */}
            <Modal
                open={isLicenseModalOpen}
                title="Detalhamento da Licença Ativa"
                icon={KeyRound}
                onClose={() => setIsLicenseModalOpen(false)}
                width="800px"
            >
                {!licenseModalData ? (
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '3rem 0', gap: '1rem' }}>
                        <span style={{ fontSize: '0.875rem', color: C.textMuted }}>Preparando carregamento...</span>
                    </div>
                ) : licenseModalData.loading ? (
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '3rem 0', gap: '1rem' }}>
                        <Loader2 size={32} className="animate-spin" style={{ color: C.primary }} />
                        <span style={{ fontSize: '0.875rem', color: C.textMuted }}>Carregando dados da licença em tempo real...</span>
                    </div>
                ) : licenseModalData.error ? (
                    <div style={{ padding: '1.25rem', background: C.dangerAlpha, border: `1px solid ${C.danger}30`, borderRadius: '12px', color: C.danger, fontSize: '0.875rem', textAlign: 'center' }}>
                        {licenseModalData.error}
                    </div>
                ) : (
                    <div>
                        {/* Bloco 1: Chave Principal e Identificadora da Empresa */}
                        {licenseModalData.company && (
                            <div style={{
                                background: 'var(--bg-body, #f8fafc)',
                                borderRadius: '12px',
                                border: '1px solid var(--border)',
                                borderLeft: '4px solid #f59e0b',
                                padding: '1.25rem',
                                marginBottom: '1.5rem',
                                display: 'flex',
                                flexDirection: 'column',
                                gap: '1rem'
                            }}>
                                {/* Campo 1: Chave Identificadora da Empresa */}
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
                                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                        <div>
                                            <h4 style={{ margin: 0, fontSize: '0.9rem', fontWeight: 700, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                                <Building size={16} color="#f59e0b" />
                                                Chave Identificadora da Empresa (UUID)
                                            </h4>
                                            <p style={{ margin: '0.2rem 0 0', fontSize: '0.76rem', color: 'var(--text-muted)' }}>
                                                Identificador único de cadastro desta empresa no ecossistema.
                                            </p>
                                        </div>
                                    </div>
                                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                                        <input
                                            readOnly
                                            value={licenseModalData.company.id || 'Nenhum ID retornado'}
                                            style={{
                                                flex: 1, fontFamily: 'monospace', fontWeight: 700,
                                                fontSize: '0.85rem', padding: '0.55rem 0.85rem',
                                                border: '1.5px solid var(--border)', borderRadius: '8px',
                                                background: 'var(--bg-card, #fff)', color: 'var(--text-main)'
                                            }}
                                        />
                                        <button
                                            type="button"
                                            onClick={() => handleCopyKey(licenseModalData.company.id, 'company_id')}
                                            style={{
                                                padding: '0.55rem 1rem', borderRadius: '8px',
                                                background: copiedKeyId === 'company_id' ? '#22c55e' : '#f59e0b',
                                                border: 'none', color: '#fff', cursor: 'pointer',
                                                display: 'flex', alignItems: 'center', gap: '0.35rem',
                                                fontWeight: 600, fontSize: '0.8rem', minWidth: '90px', justifyContent: 'center'
                                            }}
                                        >
                                            {copiedKeyId === 'company_id' ? <Check size={14} /> : <Copy size={14} />}
                                            {copiedKeyId === 'company_id' ? 'Copiado!' : 'Copiar'}
                                        </button>
                                    </div>
                                </div>

                                <div style={{ height: '1px', background: 'var(--border)', margin: '0.25rem 0' }} />

                                {/* Campo 2: API Key Principal */}
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
                                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                        <div>
                                            <h4 style={{ margin: 0, fontSize: '0.9rem', fontWeight: 700, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                                <KeyRound size={16} color="#f59e0b" />
                                                API Key Principal (Força de Vendas)
                                            </h4>
                                            <p style={{ margin: '0.2rem 0 0', fontSize: '0.76rem', color: 'var(--text-muted)' }}>
                                                Usada pelos dispositivos móveis para ativação inicial do aplicativo.
                                            </p>
                                        </div>
                                    </div>
                                    <div style={{ display: 'flex', gap: '0.5rem' }}>
                                        <input
                                            readOnly
                                            value={licenseModalData.company.companyKey || 'Chave oculta ou não gerada'}
                                            style={{
                                                flex: 1, fontFamily: 'monospace', fontWeight: 700,
                                                fontSize: '0.85rem', padding: '0.55rem 0.85rem',
                                                border: '1.5px solid #f59e0b', borderRadius: '8px',
                                                background: 'var(--bg-card, #fff)', color: 'var(--text-main)'
                                            }}
                                        />
                                        <button
                                            type="button"
                                            onClick={() => handleCopyKey(licenseModalData.company.companyKey, 'company_key')}
                                            style={{
                                                padding: '0.55rem 1rem', borderRadius: '8px',
                                                background: copiedKeyId === 'company_key' ? '#22c55e' : '#f59e0b',
                                                border: 'none', color: '#fff', cursor: 'pointer',
                                                display: 'flex', alignItems: 'center', gap: '0.35rem',
                                                fontWeight: 600, fontSize: '0.8rem', minWidth: '90px', justifyContent: 'center'
                                            }}
                                        >
                                            {copiedKeyId === 'company_key' ? <Check size={14} /> : <Copy size={14} />}
                                            {copiedKeyId === 'company_key' ? 'Copiado!' : 'Copiar'}
                                        </button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Bloco 2: Módulos do Ecossistema */}
                        <div style={{ marginBottom: '1.5rem' }}>
                            <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: C.textMain, marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                <Layers size={16} color={C.primary} /> Módulos Ativados & Chaves de API
                            </h4>
                            {!licenseModalData.modules || licenseModalData.modules.length === 0 ? (
                                <div style={{ padding: '1rem', border: '1px dashed var(--border)', borderRadius: '10px', color: C.textMuted, fontSize: '0.8rem', textAlign: 'center' }}>
                                    Nenhum módulo ativado para esta empresa.
                                </div>
                            ) : (
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                                    {licenseModalData.modules.map(mod => {
                                        const meta = MODULE_META[mod.moduleSlug] || { label: mod.moduleSlug, icon: '📦', color: '#607d8b' };
                                        return (
                                            <div key={mod.id} style={{
                                                border: '1px solid var(--border)',
                                                borderRadius: '12px',
                                                overflow: 'hidden',
                                                background: 'var(--bg-card, #fff)'
                                            }}>
                                                <div style={{
                                                    padding: '0.75rem 1rem',
                                                    background: `${meta.color}06`,
                                                    borderBottom: '1px solid var(--border)',
                                                    display: 'flex',
                                                    justifyContent: 'space-between',
                                                    alignItems: 'center'
                                                }}>
                                                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                                        <span style={{ fontSize: '1.1rem' }}>{meta.icon}</span>
                                                        <strong style={{ fontSize: '0.85rem', color: C.textMain }}>{meta.label}</strong>
                                                        <span style={{ fontSize: '0.65rem', padding: '1px 6px', borderRadius: '10px', background: mod.isActive ? 'rgba(16,185,129,0.1)' : 'rgba(0,0,0,0.05)', color: mod.isActive ? C.success : C.textMuted, fontWeight: 700 }}>
                                                            {mod.isActive ? 'ATIVO' : 'INATIVO'}
                                                        </span>
                                                    </div>
                                                    <span style={{ fontSize: '0.72rem', color: C.textMuted, fontWeight: 500 }}>
                                                        Dispositivos: {mod.deviceLimit}
                                                    </span>
                                                </div>
                                                <div style={{ padding: '0.75rem 1rem', display: 'flex', gap: '0.5rem' }}>
                                                    <input
                                                        readOnly
                                                        value={mod.apiKey || ''}
                                                        placeholder="Sem chave gerada"
                                                        style={{
                                                            flex: 1, fontFamily: 'monospace', fontWeight: 700,
                                                            fontSize: '0.82rem', padding: '0.45rem 0.75rem',
                                                            border: `1.5px solid ${meta.color}`, borderRadius: '6px',
                                                            background: 'var(--bg-body)', color: 'var(--text-main)'
                                                        }}
                                                    />
                                                    <button
                                                        type="button"
                                                        onClick={() => handleCopyKey(mod.apiKey, mod.id)}
                                                        style={{
                                                            padding: '0.45rem 0.85rem', borderRadius: '6px',
                                                            background: copiedKeyId === mod.id ? '#22c55e' : meta.color,
                                                            border: 'none', color: '#fff', cursor: 'pointer',
                                                            display: 'flex', alignItems: 'center', gap: '0.3rem',
                                                            fontWeight: 600, fontSize: '0.75rem'
                                                        }}
                                                    >
                                                        {copiedKeyId === mod.id ? <Check size={12} /> : <Copy size={12} />}
                                                        {copiedKeyId === mod.id ? 'Copiado!' : 'Copiar'}
                                                    </button>
                                                </div>
                                            </div>
                                        );
                                    })}
                                </div>
                            )}
                        </div>

                        {/* Bloco 3: Status de Sincronização */}
                        <div style={{ marginBottom: '1.5rem' }}>
                            <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: C.textMain, marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                <Activity size={16} color={C.primary} /> Status de Sincronização (Sales API)
                                {licenseModalData.syncStats && (
                                    <span style={{
                                        marginLeft: 'auto', display: 'inline-flex', alignItems: 'center', gap: '3px', fontSize: '0.7rem', fontWeight: 800, padding: '1px 8px', borderRadius: '12px',
                                        background: licenseModalData.syncStats.health === 'ok' ? 'rgba(34,197,94,0.12)' : 'rgba(234,179,8,0.12)',
                                        color: licenseModalData.syncStats.health === 'ok' ? '#22c55e' : '#eab308'
                                    }}>
                                        {licenseModalData.syncStats.health === 'ok' ? '● ONLINE' : '● ATENÇÃO'}
                                    </span>
                                )}
                            </h4>
                            {!licenseModalData.syncStats ? (
                                <div style={{ padding: '0.85rem', background: 'var(--bg-body)', borderRadius: '10px', border: '1px dashed var(--border)', fontSize: '0.8rem', color: C.textMuted, textAlign: 'center' }}>
                                    Dados de sync indisponíveis — Sales API offline ou não provisionado.
                                </div>
                            ) : (
                                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: '0.5rem' }}>
                                    {[
                                        { label: 'Pendentes', value: licenseModalData.syncStats.orders?.pending, color: '#eab308', bg: 'rgba(234,179,8,0.06)' },
                                        { label: 'Processando', value: licenseModalData.syncStats.orders?.processing, color: '#3b82f6', bg: 'rgba(59,130,246,0.06)' },
                                        { label: 'Sincronizados', value: licenseModalData.syncStats.orders?.synced, color: '#22c55e', bg: 'rgba(34,197,94,0.06)' },
                                        { label: 'Erros', value: licenseModalData.syncStats.orders?.error, color: '#ef4444', bg: 'rgba(239,68,68,0.06)' },
                                        { label: 'Produtos', value: licenseModalData.syncStats.catalog?.products, color: C.primary, bg: 'rgba(27,143,205,0.06)' },
                                        { label: 'Clientes', value: licenseModalData.syncStats.catalog?.customers, color: C.primary, bg: 'rgba(27,143,205,0.06)' },
                                    ].map(item => (
                                        <div key={item.label} style={{ background: item.bg, border: `1px solid ${item.color}18`, borderRadius: '8px', padding: '0.6rem 0.4rem', textAlign: 'center' }}>
                                            <div style={{ fontSize: '1.2rem', fontWeight: 800, color: item.color, lineHeight: 1.1 }}>{item.value ?? '—'}</div>
                                            <div style={{ fontSize: '0.68rem', color: C.textMuted, marginTop: '2px', fontWeight: 600 }}>{item.label}</div>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>

                        {/* Bloco 4: Dispositivos Móveis */}
                        <div style={{ marginBottom: '1rem' }}>
                            <h4 style={{ fontSize: '0.95rem', fontWeight: 700, color: C.textMain, marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                                <Smartphone size={16} color={C.primary} /> Dispositivos Liberados
                                {licenseModalData.devices && (
                                    <span style={{ marginLeft: 'auto', background: '#D1FAE5', color: '#065F46', padding: '1px 8px', borderRadius: '12px', fontSize: '0.7rem', fontWeight: 700 }}>
                                        {licenseModalData.devices.filter(d => d.status === 'Active' || d.status === 'active').length} ATIVOS
                                    </span>
                                )}
                            </h4>
                            <div style={{ border: '1px solid var(--border)', borderRadius: '12px', overflow: 'hidden' }}>
                                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '0.8rem' }}>
                                    <thead>
                                        <tr style={{ background: 'var(--bg-body)', borderBottom: '1px solid var(--border)', color: C.textSub }}>
                                            <th style={{ padding: '0.6rem 0.85rem', fontWeight: 700 }}>Chave / Identificador</th>
                                            <th style={{ padding: '0.6rem 0.85rem', fontWeight: 700 }}>Modelo / SO</th>
                                            <th style={{ padding: '0.6rem 0.85rem', fontWeight: 700 }}>Versão App</th>
                                            <th style={{ padding: '0.6rem 0.85rem', fontWeight: 700 }}>Acesso</th>
                                            <th style={{ padding: '0.6rem 0.85rem', fontWeight: 700, textAlign: 'center' }}>Status</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {!licenseModalData.devices || licenseModalData.devices.length === 0 ? (
                                            <tr>
                                                <td colSpan="5" style={{ padding: '1.5rem', textAlign: 'center', color: C.textMuted }}>
                                                    Nenhum dispositivo registrado.
                                                </td>
                                            </tr>
                                        ) : (
                                            licenseModalData.devices.map((d, idx) => (
                                                <tr key={d.id || idx} style={{ borderBottom: idx < licenseModalData.devices.length - 1 ? '1px solid var(--border)' : 'none' }}>
                                                    <td style={{ padding: '0.65rem 0.85rem' }}>
                                                        <div style={{ fontWeight: 700, fontFamily: 'monospace', color: C.primary }}>
                                                            {d.activationKey?.toUpperCase()}
                                                        </div>
                                                        <div style={{ fontSize: '0.68rem', color: C.textMuted, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '180px' }}>
                                                            {d.name || 'Sem nome associado'}
                                                        </div>
                                                    </td>
                                                    <td style={{ padding: '0.65rem 0.85rem' }}>
                                                        <div style={{ fontWeight: 500 }}>{d.model || 'N/A'}</div>
                                                        <div style={{ fontSize: '0.7rem', color: C.textMuted }}>{d.os || 'N/A'}</div>
                                                    </td>
                                                    <td style={{ padding: '0.65rem 0.85rem', color: C.textSub }}>
                                                        {d.appVersion || '—'}
                                                    </td>
                                                    <td style={{ padding: '0.65rem 0.85rem', fontSize: '0.72rem', color: C.textMuted }}>
                                                        {d.lastAccess ? new Date(d.lastAccess).toLocaleDateString('pt-BR') : 'Sem acesso'}
                                                    </td>
                                                    <td style={{ padding: '0.65rem 0.85rem', textAlign: 'center' }}>
                                                        <span style={{
                                                            fontSize: '0.68rem',
                                                            fontWeight: 800,
                                                            padding: '2px 8px',
                                                            borderRadius: '10px',
                                                            background: d.status === 'Active' || d.status === 'active' ? 'rgba(16,185,129,0.1)' : 'rgba(239,68,68,0.1)',
                                                            color: d.status === 'Active' || d.status === 'active' ? C.success : C.danger,
                                                            textTransform: 'uppercase'
                                                        }}>
                                                            {d.status === 'Active' || d.status === 'active' ? 'ATIVO' : d.status === 'Blocked' ? 'BLOQUEADO' : d.status === 'Revoked' ? 'REVOGADO' : d.status}
                                                        </span>
                                                    </td>
                                                </tr>
                                            ))
                                        )}
                                    </tbody>
                                </table>
                            </div>
                        </div>

                        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '1.5rem', paddingTop: '1rem', borderTop: '1px solid var(--border)' }}>
                            <button
                                type="button"
                                className="btn btn-primary"
                                onClick={() => setIsLicenseModalOpen(false)}
                                style={{ padding: '0.6rem 1.5rem', borderRadius: '10px' }}
                            >
                                Fechar Detalhes
                            </button>
                        </div>
                    </div>
                )}
            </Modal>
        </div>
    );
}
