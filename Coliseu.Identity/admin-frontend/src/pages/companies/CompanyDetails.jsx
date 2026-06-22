import React, { useState, useEffect, useRef } from 'react';
import { ArrowLeft, Save, Trash2, Smartphone, ShieldCheck, CheckCircle2, Clock, Plus, Loader2, AlertCircle, Activity, AlertTriangle, BarChart2, RotateCcw, KeyRound, Copy, Check, ImagePlus, Upload, X, AlertOctagon } from 'lucide-react';
import { useNavigate, useParams } from 'react-router-dom';
import { companyService } from '../../services/companyService';
import { monitoringService } from '../../services/monitoringService';
import ModulesSection from '../../components/ModulesSection';
import BranchesSection from '../../components/BranchesSection';

export default function CompanyDetails() {
    const { id } = useParams();
    const navigate = useNavigate();

    const [company, setCompany] = useState(null);
    const [devices, setDevices] = useState([]);
    const [syncStats, setSyncStats] = useState(null);
    const [statsLoading, setStatsLoading] = useState(false);

    // UI States
    const [isLoading, setIsLoading] = useState(true);
    const [isSaving, setIsSaving] = useState(false);
    const [isAddingDevice, setIsAddingDevice] = useState(false);
    const [errorMsg, setErrorMsg] = useState('');
    const [showDeleteModal, setShowDeleteModal] = useState(false);
    const [isDeleting, setIsDeleting] = useState(false);
    const [deleteConfirmText, setDeleteConfirmText] = useState('');

    // API Key rotation
    const [isRotating, setIsRotating] = useState(false);

    // Logo
    const [logoPreview, setLogoPreview] = useState(null);
    const [uploadingLogo, setUploadingLogo] = useState(false);
    const logoInputRef = useRef(null);

    // Device Edit States
    const [editingDeviceId, setEditingDeviceId] = useState(null);
    const [tempDeviceName, setTempDeviceName] = useState('');
    const [savingDeviceId, setSavingDeviceId] = useState(null);

    useEffect(() => {
        if (id) {
            loadCompanyData();
        }
    }, [id]);

    const loadCompanyData = async () => {
        try {
            setIsLoading(true);
            setErrorMsg('');
            const compData = await companyService.getCompanyById(id);
            setCompany(compData);
            if (compData.hasLogo) {
                setLogoPreview(companyService.getLogoUrl(id) + '?t=' + Date.now());
            } else {
                setLogoPreview(null);
            }

            const devsData = await companyService.getDevicesByCompany(id);
            setDevices(devsData.items || []);
        } catch (error) {
            console.error('Failed to load details', error);
            setErrorMsg('Falha ao carregar dados da empresa e dispositivos.');
        } finally {
            setIsLoading(false);
        }

        // Carrega stats de sync em paralelo (não bloqueia a UI principal)
        loadSyncStats();
    };

    const loadSyncStats = async () => {
        setStatsLoading(true);
        try {
            const stats = await monitoringService.getCompanySummary(id);
            setSyncStats(stats);
        } catch (e) {
            // Não bloqueia a página se o Sales API não estiver disponível
            setSyncStats(null);
        } finally {
            setStatsLoading(false);
        }
    };

    const handleToggleDeviceStatus = async (device) => {
        // Toggle: Active → blocked, any other → active
        const newStatus = device.status === 'Active' ? 'blocked' : 'active';
        try {
            await companyService.updateDeviceStatus(device.id, newStatus);
            loadCompanyData();
        } catch (error) {
            alert('Falha ao alterar status do dispositivo.');
        }
    };

    const handleRevokeDevice = async (device) => {
        if (!window.confirm(`Revogar o dispositivo ${device.activationKey}? Isso libera o UUID para re-ativação em outro aparelho.`)) return;
        try {
            await companyService.updateDeviceStatus(device.id, 'revoked');
            loadCompanyData();
        } catch (error) {
            alert('Falha ao revogar dispositivo.');
        }
    };

    const handleUpdateDeviceName = async (deviceId) => {
        setSavingDeviceId(deviceId);
        try {
            await companyService.updateDeviceName(deviceId, tempDeviceName);
            setEditingDeviceId(null);
            loadCompanyData();
        } catch (error) {
            alert('Falha ao atualizar nome do dispositivo: ' + (error?.response?.data?.error || error.message));
        } finally {
            setSavingDeviceId(null);
        }
    };

    const handleSaveCompany = async () => {
        try {
            setIsSaving(true);
            await companyService.updateCompany(company.id, {
                name: company.name,
                contactEmail: company.contactEmail || company.email,
                deviceLimit: company.deviceLimit,
                status: company.status,
                priceTableMode: company.priceTableMode || 'none',
                allowNegativeStock: company.allowNegativeStock ?? false,
            });
            alert('Alterações salvas com sucesso!');
        } catch (error) {
            alert('Falha ao salvar alterações: ' + (error?.response?.data?.error || error.message));
        } finally {
            setIsSaving(false);
        }
    };

    const handleDeleteCompany = async () => {
        if (deleteConfirmText !== company.name) return;
        try {
            setIsDeleting(true);
            await companyService.deleteCompany(company.id);
            navigate('/dashboard/companies');
        } catch (error) {
            alert('Falha ao excluir empresa: ' + (error?.response?.data?.error || error.message));
            setIsDeleting(false);
            setShowDeleteModal(false);
        }
    };

    const handleAddDevice = async () => {
        // Generate a 10-character hex string for the Activation Key
        const newActivationKey = [...Array(10)].map(() => Math.floor(Math.random() * 16).toString(16)).join('');

        try {
            setIsAddingDevice(true);
            await companyService.createPendingDevice(company.id, newActivationKey);
            // Reload devices
            loadCompanyData();
        } catch (error) {
            console.error('Add device error', error);
            const data = error?.response?.data;
            const msg = data
                ? `${data.error || 'Erro desconhecido'}\n\n[Detalhe]: ${data.details || '-'}\n[Inner]: ${data.inner || '-'}`
                : 'Erro ao gerar novo dispositivo pendente.';
            alert(msg);
        } finally {
            setIsAddingDevice(false);
        }
    };

    /**
     * Re-gera a API Key da empresa via Identity API.
     * A chave anterior é IMEDIATAMENTE invalidada.
     * A nova chave é exibida uma única vez no modal.
     */
    const handleRotateApiKey = async () => {
        if (!window.confirm(
            'Atenção: Gerar uma nova API Key invalida a chave anterior imediatamente.\n\n' +
            'Você precisará atualizar a chave em TODOS os dispositivos e no Worker Configurator.\n\n' +
            'Continuar?'
        )) return;
        try {
            setIsRotating(true);
            const result = await companyService.rotateApiKey(company.id);
            setCompany(prev => ({ ...prev, companyKey: result.newCompanyKey }));
        } catch (error) {
            alert('Falha ao gerar nova chave: ' + (error?.response?.data?.error || error.message));
        } finally {
            setIsRotating(false);
        }
    };



    const handleLogoUpload = async (e) => {
        const file = e.target.files?.[0];
        if (!file) return;
        if (file.size > 512_000) {
            alert('A logo deve ter no máximo 500KB.');
            return;
        }
        if (!file.type.startsWith('image/')) {
            alert('Selecione um arquivo de imagem (PNG ou JPG).');
            return;
        }
        setUploadingLogo(true);
        try {
            const reader = new FileReader();
            const base64 = await new Promise((resolve, reject) => {
                reader.onload = () => resolve(reader.result);
                reader.onerror = reject;
                reader.readAsDataURL(file);
            });
            await companyService.uploadLogo(id, base64);
            setLogoPreview(base64);
            setCompany(prev => ({ ...prev, hasLogo: true }));
        } catch (err) {
            alert('Erro ao enviar logo: ' + (err?.response?.data?.error || err.message));
        } finally {
            setUploadingLogo(false);
            if (logoInputRef.current) logoInputRef.current.value = '';
        }
    };

    const handleDeleteLogo = async () => {
        if (!window.confirm('Remover a logo da empresa?')) return;
        setUploadingLogo(true);
        try {
            await companyService.deleteLogo(id);
            setLogoPreview(null);
            setCompany(prev => ({ ...prev, hasLogo: false }));
        } catch (err) {
            alert('Erro ao remover logo: ' + (err?.response?.data?.error || err.message));
        } finally {
            setUploadingLogo(false);
        }
    };

    if (isLoading || !company) {
        return (
            <div className="flex flex-col items-center justify-center h-full gap-4 text-muted pt-20">
                <Loader2 size={40} className="animate-spin text-primary" />
                <p>Carregando informações da empresa...</p>
            </div>
        );
    }

    if (errorMsg) {
        return (
            <div className="flex flex-col items-center justify-center h-full gap-4 text-danger pt-20">
                <AlertCircle size={40} />
                <p>{errorMsg}</p>
                <button onClick={() => navigate('/dashboard/companies')} className="btn btn-outline">
                    Voltar para Empresas
                </button>
            </div>
        );
    }

    return (
        <div className="animate-slide-up">

            {/* ── Modal: Confirmar Exclusão ── */}
            {showDeleteModal && (
                <div style={{
                    position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)',
                    zIndex: 9999, display: 'flex', alignItems: 'center', justifyContent: 'center',
                    padding: '1rem'
                }} onMouseDown={e => e.stopPropagation()}>
                    <div style={{
                        background: 'var(--bg-card)', borderRadius: '16px',
                        boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
                        padding: '2rem', maxWidth: '480px', width: '100%',
                        borderTop: '4px solid #ef4444'
                    }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1rem' }}>
                            <AlertOctagon size={28} color="#ef4444" />
                            <h3 style={{ margin: 0, color: '#ef4444', fontWeight: 800, fontSize: '1.1rem' }}>Excluir Empresa Permanentemente</h3>
                        </div>
                        <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', marginBottom: '1.25rem', lineHeight: 1.6 }}>
                            Esta ação é <strong style={{ color: '#ef4444' }}>irreversível</strong>. Todos os dispositivos e dados desta empresa serão excluídos.
                        </p>
                        <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', marginBottom: '0.4rem' }}>
                            Digite o nome da empresa para confirmar: <strong style={{ color: 'var(--text-main)' }}>{company.name}</strong>
                        </p>
                        <input
                            type="text"
                            value={deleteConfirmText}
                            onChange={e => setDeleteConfirmText(e.target.value)}
                            placeholder={company.name}
                            style={{
                                width: '100%', padding: '0.6rem 0.9rem', borderRadius: '8px',
                                border: '2px solid #ef4444', background: 'var(--bg-body)',
                                color: 'var(--text-main)', fontSize: '0.95rem', marginBottom: '1.25rem', boxSizing: 'border-box'
                            }}
                        />
                        <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end' }}>
                            <button
                                onClick={() => { setShowDeleteModal(false); setDeleteConfirmText(''); }}
                                style={{ padding: '0.65rem 1.25rem', borderRadius: '8px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text-muted)', cursor: 'pointer', fontWeight: 600 }}
                            >Cancelar</button>
                            <button
                                onClick={handleDeleteCompany}
                                disabled={deleteConfirmText !== company.name || isDeleting}
                                style={{
                                    padding: '0.65rem 1.5rem', borderRadius: '8px', border: 'none',
                                    background: deleteConfirmText === company.name ? '#ef4444' : '#fca5a5',
                                    color: '#fff', cursor: deleteConfirmText === company.name ? 'pointer' : 'not-allowed',
                                    fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.4rem'
                                }}
                            >
                                {isDeleting ? <Loader2 size={15} className="animate-spin" /> : <Trash2 size={15} />}
                                {isDeleting ? 'Excluindo...' : 'Excluir Definitivamente'}
                            </button>
                        </div>
                    </div>
                </div>
            )}



            <div className="flex items-center gap-4" style={{ marginBottom: '2rem' }}>
                <button onClick={() => navigate('/dashboard/companies')} className="btn btn-outline hover-lift" style={{ padding: '0.5rem', width: '40px', height: '40px' }}>
                    <ArrowLeft size={18} />
                </button>
                <div>
                    <h2 style={{ fontSize: '1.5rem', fontWeight: 700, margin: 0, color: 'var(--text-main)' }}>{company.name}</h2>
                    <p className="text-muted text-sm" style={{ marginTop: '0.25rem' }}>Gerencie as configurações e dispositivos desta instância.</p>
                </div>
                <div style={{ marginLeft: 'auto', display: 'flex', gap: '0.75rem' }}>
                    <button
                        className="btn btn-outline text-danger hover-lift"
                        style={{ color: 'var(--danger)', borderColor: 'var(--danger)', background: 'transparent' }}
                        onClick={() => { setDeleteConfirmText(''); setShowDeleteModal(true); }}
                    >
                        <Trash2 size={16} /> Excluir Empresa
                    </button>
                    <button className="btn btn-primary shadow-primary hover-lift" onClick={handleSaveCompany} disabled={isSaving}>
                        <Save size={16} /> {isSaving ? 'Salvando...' : 'Salvar Alterações'}
                    </button>
                </div>
            </div>

            {/* Details Form Card */}
            <div className="glass" style={{ background: 'var(--bg-card)', borderRadius: 'var(--radius-lg)', boxShadow: 'var(--shadow-sm)', padding: '2rem', marginBottom: '2rem' }}>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.5rem' }}>

                    <div>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Nome da Empresa</label>
                        <input type="text" className="input-field hover-lift" value={company.name || ''} onChange={(e) => setCompany({ ...company, name: e.target.value })} />
                    </div>

                    <div>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>E-mail de Contato</label>
                        <input type="email" className="input-field hover-lift"
                            value={company.contactEmail || company.email || ''}
                            onChange={(e) => setCompany({ ...company, contactEmail: e.target.value })}
                            placeholder="contato@empresa.com.br"
                            title="E-mail de contato da empresa" />
                    </div>

                    <div style={{ gridColumn: '1 / -1' }}>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Chave Identificadora da Empresa</label>
                        <div style={{ position: 'relative' }}>
                            <ShieldCheck size={18} color="var(--primary)" style={{ position: 'absolute', top: '12px', left: '12px' }} />
                            <input type="text" className="input-field" value={company.id} readOnly disabled style={{ paddingLeft: '38px', background: 'var(--bg-body)', opacity: 0.8 }} />
                        </div>
                    </div>

                    <div>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Limite de Dispositivos</label>
                        <input type="number" className="input-field hover-lift" value={company.deviceLimit || 0} onChange={(e) => setCompany({ ...company, deviceLimit: parseInt(e.target.value) || 0 })} />
                    </div>

                    <div>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Status da Empresa</label>
                        <select className="input-field hover-lift" value={company.status || 'Active'} onChange={(e) => setCompany({ ...company, status: e.target.value })}>
                            <option value="Active">Ativa</option>
                            <option value="Inactive">Inativa</option>
                            <option value="Suspended">Suspensa</option>
                        </select>
                    </div>

                </div>
            </div>

            {/* Logo da Empresa Card */}
            <div style={{
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                boxShadow: 'var(--shadow-sm)',
                padding: '1.5rem',
                marginBottom: '2rem',
                borderLeft: '4px solid #06b6d4'
            }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '1rem' }}>
                    <div>
                        <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <ImagePlus size={18} color="#06b6d4" />
                            Logo da Empresa
                        </h3>
                        <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.4rem', marginBottom: 0, maxWidth: '500px' }}>
                            A logo aparece no cabeçalho dos PDFs de pedido gerados pelo app mobile.
                            Formatos aceitos: <strong>PNG</strong> ou <strong>JPG</strong> (máx. 500KB).
                        </p>
                    </div>
                </div>
                <div style={{ marginTop: '1rem', display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' }}>
                    {logoPreview && (
                        <div style={{
                            border: '1px solid var(--border)', borderRadius: '8px',
                            padding: '0.5rem', background: 'var(--bg-body)',
                            maxWidth: '160px'
                        }}>
                            <img src={logoPreview} alt="Logo" style={{ maxHeight: '80px', maxWidth: '140px', objectFit: 'contain' }} />
                        </div>
                    )}
                    <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
                        <label style={{
                            display: 'flex', alignItems: 'center', gap: '0.4rem',
                            padding: '0.5rem 1rem', borderRadius: '8px',
                            background: 'transparent', border: '1px solid #06b6d4',
                            color: '#06b6d4', fontWeight: 600, fontSize: '0.85rem',
                            cursor: uploadingLogo ? 'not-allowed' : 'pointer',
                            opacity: uploadingLogo ? 0.6 : 1
                        }}>
                            {uploadingLogo ? <Loader2 size={15} className="animate-spin" /> : <Upload size={15} />}
                            {uploadingLogo ? 'Enviando...' : (company.hasLogo ? 'Trocar Logo' : 'Enviar Logo')}
                            <input
                                ref={logoInputRef}
                                type="file"
                                accept=".png,.jpg,.jpeg"
                                onChange={handleLogoUpload}
                                disabled={uploadingLogo}
                                style={{ display: 'none' }}
                            />
                        </label>
                        {company.hasLogo && (
                            <button
                                onClick={handleDeleteLogo}
                                disabled={uploadingLogo}
                                style={{
                                    display: 'flex', alignItems: 'center', gap: '0.4rem',
                                    padding: '0.5rem 1rem', borderRadius: '8px',
                                    background: 'transparent', border: '1px solid var(--danger)',
                                    color: 'var(--danger)', fontWeight: 600, fontSize: '0.85rem',
                                    cursor: uploadingLogo ? 'not-allowed' : 'pointer',
                                    opacity: uploadingLogo ? 0.6 : 1
                                }}
                            >
                                <X size={15} /> Remover
                            </button>
                        )}
                    </div>
                </div>
            </div>

            {/* Configurações de Tabela de Preço Card */}
            <div style={{
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                boxShadow: 'var(--shadow-sm)',
                padding: '1.5rem',
                marginBottom: '2rem',
                borderLeft: '4px solid #8b5cf6'
            }}>
                <div style={{ marginBottom: '1rem' }}>
                    <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        <BarChart2 size={18} color="#8b5cf6" />
                        Configuração de Tabela de Preços
                    </h3>
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.4rem', marginBottom: 0 }}>
                        Controla como o app mobile aplica as tabelas de preço ao criar pedidos.
                    </p>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', alignItems: 'start' }}>
                    <div>
                        <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>
                            Modo de Tabela de Preço
                        </label>
                        <select
                            id="price-table-mode"
                            className="input-field hover-lift"
                            value={company.priceTableMode || 'none'}
                            onChange={(e) => setCompany({ ...company, priceTableMode: e.target.value })}
                        >
                            <option value="none">Não usar tabela (preço base)</option>
                            <option value="product">Usar por Produto (tabela do cliente)</option>
                            <option value="prompt">Usar e solicitar tabela ao criar pedido</option>
                        </select>
                    </div>

                    <div style={{ padding: '0.9rem', background: 'rgba(139,92,246,0.06)', borderRadius: '10px', border: '1px solid rgba(139,92,246,0.2)' }}>
                        {(!company.priceTableMode || company.priceTableMode === 'none') && (
                            <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                                <strong style={{ color: '#8b5cf6' }}>Não usar:</strong> O app sempre exibe o preço base cadastrado no produto. Tabelas de preço são completamente ignoradas.
                            </p>
                        )}
                        {company.priceTableMode === 'product' && (
                            <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                                <strong style={{ color: '#8b5cf6' }}>Por Produto:</strong> Se o cliente tiver uma tabela de preço vinculada, o app aplica automaticamente os preços dessa tabela ao abrir o pedido.
                            </p>
                        )}
                        {company.priceTableMode === 'prompt' && (
                            <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                                <strong style={{ color: '#8b5cf6' }}>Solicitar tabela:</strong> Ao criar um pedido, o vendedor vê um dropdown para escolher a tabela de preço manualmente, independente do cliente selecionado.
                            </p>
                        )}
                    </div>
                </div>
            </div>

            {/* Controle de Estoque Card */}
            <div style={{
                background: 'var(--bg-card)',
                borderRadius: 'var(--radius-lg)',
                boxShadow: 'var(--shadow-sm)',
                padding: '1.5rem',
                marginBottom: '2rem',
                borderLeft: '4px solid #f97316'
            }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '1.5rem' }}>
                    <div style={{ flex: 1 }}>
                        <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                            <BarChart2 size={18} color="#f97316" />
                            Controle de Estoque
                        </h3>
                        <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.4rem', marginBottom: 0, maxWidth: '520px', lineHeight: 1.6 }}>
                            Quando <strong>ativado</strong>, o app permite adicionar produtos com estoque zerado ou negativo ao pedido.
                            O produto exibe um badge laranja <em>“Sem Estoque”</em> mas permanece interativo.
                            Por padrão, a venda sem estoque é <strong>bloqueada</strong>.
                        </p>
                    </div>

                    {/* Toggle switch */}
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.4rem', flexShrink: 0 }}>
                        <button
                            id="toggle-allow-negative-stock"
                            role="switch"
                            aria-checked={company.allowNegativeStock ?? false}
                            onClick={() => setCompany(prev => ({ ...prev, allowNegativeStock: !(prev.allowNegativeStock ?? false) }))}
                            style={{
                                width: '52px', height: '28px', borderRadius: '14px', border: 'none',
                                cursor: 'pointer', position: 'relative', transition: 'background 0.25s',
                                background: (company.allowNegativeStock ?? false) ? '#f97316' : 'var(--border)',
                                padding: 0,
                                outline: 'none',
                            }}
                        >
                            <span style={{
                                position: 'absolute', top: '4px',
                                left: (company.allowNegativeStock ?? false) ? '26px' : '4px',
                                width: '20px', height: '20px', borderRadius: '50%',
                                background: '#fff',
                                boxShadow: '0 1px 4px rgba(0,0,0,0.25)',
                                transition: 'left 0.2s',
                                display: 'block',
                            }} />
                        </button>
                        <span style={{
                            fontSize: '0.7rem', fontWeight: 700, letterSpacing: '0.04em',
                            color: (company.allowNegativeStock ?? false) ? '#f97316' : 'var(--text-muted)',
                        }}>
                            {(company.allowNegativeStock ?? false) ? 'LIBERADO' : 'BLOQUEADO'}
                        </span>
                    </div>
                </div>

                {/* Info box: estado atual */}
                <div style={{
                    marginTop: '1rem', padding: '0.7rem 1rem',
                    background: (company.allowNegativeStock ?? false)
                        ? 'rgba(249,115,22,0.07)'
                        : 'rgba(100,116,139,0.06)',
                    borderRadius: '8px',
                    border: `1px solid ${(company.allowNegativeStock ?? false) ? 'rgba(249,115,22,0.25)' : 'var(--border)'}`,
                    fontSize: '0.8rem',
                    color: (company.allowNegativeStock ?? false) ? '#9a3412' : 'var(--text-muted)',
                    display: 'flex', alignItems: 'flex-start', gap: '0.5rem',
                }}>
                    <AlertTriangle size={14} style={{ flexShrink: 0, marginTop: '2px' }} />
                    {(company.allowNegativeStock ?? false)
                        ? <span><strong>Venda sem estoque liberada.</strong> Pedidos serão aceitos mesmo com saldo zero ou negativo. Lembre-se de clicar em <em>Salvar Alterações</em> e sincronizar o app.</span>
                        : <span><strong>Venda sem estoque bloqueada</strong> (padrão). Produtos indisponíveis ficam desabilitados no app mobile.</span>
                    }
                </div>
            </div>

            {/* ── Filiais da Empresa (Multi-tenant ERP) ── */}
            <BranchesSection companyId={company.id} companyName={company.name} />

            {/* ── Módulos do Ecossistema (AutoCenter, Sales, etc.) ── */}
            <ModulesSection 
                companyId={company.id} 
                company={company}
                onRotateCompanyKey={handleRotateApiKey}
                isSuperAdmin={localStorage.getItem('adminRole') === 'SuperAdmin'} 
            />

            <div style={{ marginBottom: '2rem' }}>
                <h3 style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--text-main)', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <Activity size={18} color="var(--primary)" /> Status de Sincronização (Sales API)
                    {statsLoading && <Loader2 size={14} className="animate-spin" style={{ color: 'var(--text-muted)', marginLeft: 'auto' }} />}
                    {!statsLoading && syncStats && (
                        <span style={{
                            marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.75rem', fontWeight: 700, padding: '2px 10px', borderRadius: '20px',
                            background: syncStats.health === 'ok' ? 'rgba(34,197,94,0.12)' : 'rgba(234,179,8,0.12)',
                            color: syncStats.health === 'ok' ? '#22c55e' : '#eab308'
                        }}>
                            {syncStats.health === 'ok' ? <CheckCircle2 size={12} /> : <AlertTriangle size={12} />}
                            {syncStats.health === 'ok' ? 'Sincronizado' : 'Atenção'}
                        </span>
                    )}
                </h3>

                {!syncStats && !statsLoading && (
                    <div style={{ padding: '1rem', background: 'var(--bg-body)', borderRadius: '10px', border: '1px dashed var(--border)', fontSize: '0.875rem', color: 'var(--text-muted)', textAlign: 'center' }}>
                        Dados de sync indisponíveis — Sales API pode não estar rodando.
                    </div>
                )}

                {syncStats && (
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(130px, 1fr))', gap: '1rem' }}>
                        {[
                            { label: 'Pendentes', value: syncStats.orders?.pending, color: '#eab308', bg: 'rgba(234,179,8,0.08)' },
                            { label: 'Processando', value: syncStats.orders?.processing, color: '#3b82f6', bg: 'rgba(59,130,246,0.08)' },
                            { label: 'Sincronizados', value: syncStats.orders?.synced, color: '#22c55e', bg: 'rgba(34,197,94,0.08)' },
                            { label: 'Erros', value: syncStats.orders?.error, color: '#ef4444', bg: 'rgba(239,68,68,0.08)' },
                            { label: 'Produtos', value: syncStats.catalog?.products, color: 'var(--primary)', bg: 'rgba(99,102,241,0.08)' },
                            { label: 'Clientes', value: syncStats.catalog?.customers, color: 'var(--primary)', bg: 'rgba(99,102,241,0.08)' },
                        ].map(item => (
                            <div key={item.label} style={{ background: item.bg, border: `1px solid ${item.color}22`, borderRadius: '10px', padding: '1rem', textAlign: 'center' }}>
                                <div style={{ fontSize: '1.75rem', fontWeight: 800, color: item.color, lineHeight: 1 }}>{item.value ?? '—'}</div>
                                <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '4px', fontWeight: 500 }}>{item.label}</div>
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {/* Devices List Card */}
            <h3 style={{ fontSize: '1.25rem', fontWeight: 600, color: 'var(--text-main)', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Smartphone size={20} color="var(--primary)" /> Dispositivos Liberados
                <span className="badge badge-active" style={{ marginLeft: 'auto', background: '#D1FAE5', color: '#065F46' }}>
                    {devices.filter(d => d.status === 'Ativo').length} {company.limit > 0 ? `de ${company.limit}` : ''} ATIVOS
                </span>
            </h3>

            <div className="glass" style={{ background: 'var(--bg-card)', borderRadius: 'var(--radius-lg)', boxShadow: 'var(--shadow-sm)', overflow: 'hidden' }}>
                <div style={{ overflowX: 'auto' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
                        <thead>
                            <tr style={{ background: '#FCE8E8', color: '#B3261E', fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                                <th style={{ padding: '0.8rem 1.5rem', fontWeight: 700 }}>Chave de Ativação / CELULAR</th>
                                <th style={{ padding: '0.8rem 1.5rem', fontWeight: 700 }}>Dispositivo / SO</th>
                                <th style={{ padding: '0.8rem 1.5rem', fontWeight: 700 }}>Versão</th>
                                <th style={{ padding: '0.8rem 1.5rem', fontWeight: 700 }}>Registro & Acesso</th>
                                <th style={{ padding: '0.8rem 1.5rem', fontWeight: 700, textAlign: 'center' }}>Ações</th>
                            </tr>
                        </thead>
                        <tbody>
                            {devices.length === 0 ? (
                                <tr>
                                    <td colSpan="5" style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-muted)' }}>
                                        Nenhum dispositivo registrado. Gere uma chave para começar.
                                    </td>
                                </tr>
                            ) : (
                                devices.map((device, index) => (
                                    <tr key={device.id || index} style={{ borderBottom: '1px solid var(--border)' }} className="hover-lift">
                                        <td style={{ padding: '1rem 1.5rem' }}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.25rem' }}>
                                                <span style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)' }}>Chave:</span>
                                                <span style={{ fontFamily: 'monospace', fontSize: '1rem', fontWeight: 700, color: 'var(--primary)', background: '#FCE8E8', padding: '2px 8px', borderRadius: '4px', letterSpacing: '0.1em' }}>
                                                    {device.activationKey?.toUpperCase() || 'N/A'}
                                                </span>
                                            </div>
                                            <div style={{ fontFamily: 'monospace', fontSize: '0.7rem', color: 'var(--text-muted)' }}>UUID: {device.deviceUuid || 'Apenas chave pendente'}</div>
                                            
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginTop: '0.5rem' }}>
                                                {editingDeviceId === device.id ? (
                                                    <>
                                                        <input 
                                                            type="text" 
                                                            className="input-field" 
                                                            value={tempDeviceName} 
                                                            onChange={(e) => setTempDeviceName(e.target.value)}
                                                            placeholder="Ex: Celular Robert" 
                                                            style={{ padding: '0.4rem 0.75rem', fontSize: '0.875rem', background: 'var(--bg-body)', borderRadius: '6px', flex: 1 }}
                                                            autoFocus
                                                            onKeyDown={(e) => {
                                                                if (e.key === 'Enter') handleUpdateDeviceName(device.id);
                                                                if (e.key === 'Escape') setEditingDeviceId(null);
                                                            }}
                                                        />
                                                        <button 
                                                            onClick={() => handleUpdateDeviceName(device.id)}
                                                            disabled={savingDeviceId === device.id}
                                                            className="btn btn-outline"
                                                            style={{ padding: '0.4rem', minWidth: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                                                            title="Salvar"
                                                        >
                                                            {savingDeviceId === device.id ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} color="var(--success)" />}
                                                        </button>
                                                        <button 
                                                            onClick={() => setEditingDeviceId(null)}
                                                            disabled={savingDeviceId === device.id}
                                                            className="btn btn-outline"
                                                            style={{ padding: '0.4rem', minWidth: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                                                            title="Cancelar"
                                                        >
                                                            <X size={14} color="var(--danger)" />
                                                        </button>
                                                    </>
                                                ) : (
                                                    <>
                                                        <input 
                                                            type="text" 
                                                            className="input-field hover-lift" 
                                                            value={device.name || device.model || 'Aguardando Sinc. - Desconhecido'} 
                                                            placeholder="Nome / Modelo" 
                                                            style={{ padding: '0.4rem 0.75rem', fontSize: '0.875rem', background: 'var(--bg-body)', borderRadius: '6px', cursor: 'pointer', flex: 1 }} 
                                                            readOnly 
                                                            onClick={() => {
                                                                setEditingDeviceId(device.id);
                                                                setTempDeviceName(device.name || device.model || '');
                                                            }}
                                                        />
                                                        <button
                                                            onClick={() => {
                                                                setEditingDeviceId(device.id);
                                                                setTempDeviceName(device.name || device.model || '');
                                                            }}
                                                            style={{
                                                                background: 'transparent',
                                                                border: 'none',
                                                                color: 'var(--primary)',
                                                                cursor: 'pointer',
                                                                fontSize: '0.75rem',
                                                                textDecoration: 'underline',
                                                                padding: 0
                                                            }}
                                                        >
                                                            Editar
                                                        </button>
                                                    </>
                                                )}
                                            </div>
                                        </td>
                                        <td style={{ padding: '1rem 1.5rem', fontSize: '0.875rem' }}>
                                            <div style={{ fontWeight: 500, color: 'var(--text-main)' }}>{device.model || 'N/A'}</div>
                                            <div className="text-muted" style={{ fontSize: '0.75rem' }}>{device.os || 'N/A'}</div>
                                        </td>
                                        <td style={{ padding: '1rem 1.5rem', fontSize: '0.875rem', color: 'var(--text-muted)' }}>
                                            {device.appVersion || '-'}
                                        </td>
                                        <td style={{ padding: '1rem 1.5rem', fontSize: '0.75rem' }}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '4px', marginBottom: '4px', color: 'var(--success)' }}>
                                                <CheckCircle2 size={12} color="var(--success)" /> Ativação: {new Date(device.firstActivation).toLocaleDateString()}
                                            </div>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '4px', color: 'var(--text-muted)' }}>
                                                <Clock size={12} /> Último: {new Date(device.lastAccess).toLocaleDateString()}
                                            </div>
                                        </td>
                                        <td style={{ padding: '1rem 1.5rem', textAlign: 'center', display: 'flex', flexDirection: 'column', gap: '0.4rem', justifyContent: 'center', alignItems: 'center' }}>
                                            {device.status === 'Active' ? (
                                                <button onClick={() => handleToggleDeviceStatus(device)} className="btn-pill btn-pill-danger">
                                                    Bloquear
                                                </button>
                                            ) : device.status === 'Blocked' ? (
                                                <button onClick={() => handleToggleDeviceStatus(device)} className="btn-pill btn-pill-success">
                                                    Reativar
                                                </button>
                                            ) : null}
                                            {device.status !== 'Revoked' ? (
                                                <button onClick={() => handleRevokeDevice(device)} style={{ fontSize: '0.72rem', color: 'var(--text-muted)', background: 'transparent', border: 'none', cursor: 'pointer', textDecoration: 'underline', padding: 0 }}>
                                                    Revogar
                                                </button>
                                            ) : (
                                                <span style={{ fontSize: '0.72rem', color: 'var(--danger)', fontWeight: 600 }}>Revogado</span>
                                            )}
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
                {/* Add Device Button Footer */}
                <div style={{ padding: '1rem', borderTop: '1px solid var(--border)', display: 'flex', justifyContent: 'center' }}>
                    <button
                        onClick={handleAddDevice}
                        className="btn btn-outline hover-lift"
                        style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.5rem',
                            color: 'var(--primary)',
                            borderStyle: 'dashed',
                            width: '100%',
                            justifyContent: 'center',
                            padding: '0.75rem'
                        }}
                    >
                        <Plus size={18} /> Adicionar novo dispositivo
                    </button>
                </div>
            </div>




        </div>
    );
}
