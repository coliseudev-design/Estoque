import { useState, useEffect, useCallback } from 'react';
import { Box, Package, Shield, Settings, Server, RefreshCw, KeyRound, Copy, Check, AlertTriangle, AlertCircle, Info, Trash2 } from 'lucide-react';
import { companyService } from '../services/companyService';
import { requestService } from '../services/requestService';

// ── Slugs conhecidos ─────────────────────────────────────────────────────────
const MODULE_META = {
  'coliseu-speed': {
    label: 'Coliseu Speed',
    icon: '🏪',
    desc: 'App de força de vendas (Flutter mobile)',
    color: '#2196f3',
  },
  'autocenter': {
    label: 'AutoCenter',
    icon: '🔧',
    desc: 'App de pré-atendimento de oficina (Flutter mobile)',
    color: '#ff9800',
  },
  'coliseu-dash': {
    label: 'Coliseu Dash',
    icon: '📈',
    desc: 'Dashboard de Vendas de Lojas e Vendedores',
    color: '#10b981',
  },
  'controle-garantias': {
    label: 'Controle de Garantias',
    icon: '🛡️',
    desc: 'Sistema Web de Gestão e Auditoria de Garantias',
    color: '#0a58ca',
  },
  'nexus': {
    label: 'Nexus',
    icon: '🌐',
    desc: 'Plataforma de Integração e APIs Nexus',
    color: '#0891b2',
  },
  'vision': {
    label: 'Vision',
    icon: '👁️',
    desc: 'Módulo de Inteligência de Dados e Visão Computacional',
    color: '#f43f5e',
  },
};

const ALL_SLUGS = Object.keys(MODULE_META);

// ── Componente principal ─────────────────────────────────────────────────────
export default function ModulesSection({ companyId, company, onRotateCompanyKey, isSuperAdmin = false }) {
  const [modules, setModules]           = useState([]);
  const [loading, setLoading]           = useState(true);
  const [error, setError]               = useState(null);
  const [showAddModal, setShowAddModal] = useState(false);
  const [configModal, setConfigModal]   = useState(null); // module being edited
  const [copiedKeyId, setCopiedKeyId]   = useState(null);

  const load = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await companyService.listModules(companyId);
      setModules(data);
      // Sincronizar requisições vinculadas com os novos módulos da empresa
      requestService.syncRequestModulesWithCompanyModules(companyId).catch(err => 
        console.error('Error syncing request modules on load', err)
      );
    } catch (e) {
      setError('Erro ao carregar módulos.');
    } finally {
      setLoading(false);
    }
  }, [companyId]);

  useEffect(() => { load(); }, [load]);

  // ── Ações ────────────────────────────────────────────────────────────────

  const handleAddModule = async (slug, deviceLimit, middlewareBaseUrl, versions) => {
    try {
      await companyService.addModule(companyId, {
        moduleSlug: slug,
        deviceLimit,
        middlewareBaseUrl: middlewareBaseUrl || undefined,
        versions: slug === 'coliseu-dash' ? versions : undefined,
      });
      await load();
    } catch (e) {
      alert(e?.response?.data?.error || 'Erro ao adicionar módulo.');
    }
    setShowAddModal(false);
  };

  const handleRotateKey = async (moduleId, moduleSlug) => {
    if (!window.confirm(`Rotacionar API Key do módulo "${moduleSlug}"? A chave anterior será invalidada imediatamente.`)) return;
    try {
      await companyService.rotateModuleKey(companyId, moduleId);
      await load(); // Reload to get the new decrypted key
    } catch (e) {
      alert(e?.response?.data?.error || 'Erro ao rotacionar chave.');
    }
  };

  const handleToggleActive = async (mod) => {
    try {
      await companyService.updateModule(companyId, mod.id, { isActive: !mod.isActive });
      await load();
    } catch (e) {
      alert(e?.response?.data?.error || 'Erro ao atualizar módulo.');
    }
  };

  const handleRemove = async (mod) => {
    if (!window.confirm(`Remover módulo "${MODULE_META[mod.moduleSlug]?.label || mod.moduleSlug}"? Esta ação é irreversível.`)) return;
    try {
      await companyService.removeModule(companyId, mod.id);
      await load();
    } catch (e) {
      alert(e?.response?.data?.error || 'Erro ao remover módulo.');
    }
  };

  const handleSaveConfig = async (mod, deviceLimit, middlewareBaseUrl, versions) => {
    try {
      await companyService.updateModule(companyId, mod.id, {
        deviceLimit: Number(deviceLimit),
        middlewareBaseUrl: middlewareBaseUrl || null,
        versions: mod.moduleSlug === 'coliseu-dash' ? versions : undefined,
      });
      setConfigModal(null);
      await load();
    } catch (e) {
      alert(e?.response?.data?.error || 'Erro ao salvar configuração.');
    }
  };

  const handleCopy = (keyText, id) => {
    if (!keyText) return;
    navigator.clipboard.writeText(keyText);
    setCopiedKeyId(id);
    setTimeout(() => setCopiedKeyId(null), 2500);
  };

  // ── Componentes de UI ─────────────────────────────────────────────────────

  const renderApiKeyBox = (title, keyText, onRotate, id, color = '#f59e0b', description = null) => {
    const isLegacy = !keyText;
    
    return (
      <div style={{
          background: 'var(--bg-card)',
          borderRadius: '12px',
          border: '1px solid var(--border)',
          borderLeft: `4px solid ${color}`,
          padding: '1.5rem',
          boxShadow: '0 2px 10px rgba(0,0,0,0.05)',
          marginBottom: '1rem'
      }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '1rem', marginBottom: '1.25rem' }}>
              <div>
                  <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                      <KeyRound size={18} color={color} />
                      {title}
                  </h3>
                  {description && (
                    <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', marginTop: '0.4rem', marginBottom: 0, maxWidth: '500px' }}>
                        {description}
                    </p>
                  )}
              </div>
              <button
                  onClick={onRotate}
                  style={{
                      display: 'flex', alignItems: 'center', gap: '0.5rem',
                      padding: '0.5rem 1rem', borderRadius: '8px',
                      background: color, color: '#fff', border: 'none',
                      fontWeight: 600, cursor: 'pointer',
                      whiteSpace: 'nowrap', flexShrink: 0,
                      transition: 'transform 0.1s'
                  }}
                  onMouseDown={e => e.currentTarget.style.transform = 'scale(0.97)'}
                  onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
              >
                  <RefreshCw size={15} />
                  Gerar Nova Chave
              </button>
          </div>

          {isLegacy ? (
              <div style={{
                  padding: '1rem', background: 'rgba(239,68,68,0.05)', borderRadius: '8px',
                  border: '1px dashed rgba(239,68,68,0.3)', color: '#b91c1c',
                  display: 'flex', alignItems: 'center', gap: '0.75rem', fontSize: '0.85rem'
              }}>
                  <AlertCircle size={18} />
                  <div>
                      <strong>Chave Oculta (Legado):</strong> Esta chave foi gerada antes da atualização de segurança e não pode ser exibida. 
                      Para visualizar a chave permanentemente, clique em <strong>Gerar Nova Chave</strong>.
                  </div>
              </div>
          ) : (
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <input
                      readOnly
                      value={keyText}
                      style={{
                          flex: 1, fontFamily: 'monospace', fontWeight: 700,
                          fontSize: '0.95rem', padding: '0.75rem 1rem',
                          border: `2px solid ${color}`, borderRadius: '8px',
                          background: 'var(--bg-body)', color: 'var(--text-main)'
                      }}
                  />
                  <button
                      onClick={() => handleCopy(keyText, id)}
                      title="Copiar Chave"
                      style={{
                          padding: '0.75rem 1.25rem', borderRadius: '8px',
                          background: copiedKeyId === id ? '#22c55e' : color,
                          border: 'none', color: '#fff', cursor: 'pointer',
                          display: 'flex', alignItems: 'center', gap: '0.35rem',
                          fontWeight: 600, transition: 'background 0.2s'
                      }}
                  >
                      {copiedKeyId === id ? <Check size={16} /> : <Copy size={16} />}
                      {copiedKeyId === id ? 'Copiado!' : 'Copiar'}
                  </button>
              </div>
          )}
      </div>
    );
  };

  const availableSlugs = ALL_SLUGS.filter(s => !modules.find(m => m.moduleSlug === s));

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div style={{ marginTop: '2.5rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <Package size={22} color="var(--primary)" />
            Ecossistema & APIs
          </h2>
          <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', marginTop: '0.4rem', marginBottom: 0 }}>
            Gerencie as Chaves de API permanentemente visíveis e ative novos módulos para esta empresa.
          </p>
        </div>
        {availableSlugs.length > 0 && (
          <div style={{ position: 'relative' }}>
            <button 
              className="btn btn-outline hover-lift" 
              onClick={() => setShowAddModal(!showAddModal)} 
              style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem' }}
            >
              <Package size={16} /> Adicionar Módulo
            </button>
            {showAddModal && (
              <div 
                className="scale-in"
                style={{
                  position: 'absolute',
                  top: 'calc(100% + 8px)',
                  right: 0,
                  zIndex: 100,
                  background: 'var(--bg-elevated)',
                  border: '1px solid var(--border-strong)',
                  borderRadius: '12px',
                  padding: '1.25rem',
                  boxShadow: '0 10px 30px rgba(0, 0, 0, 0.15)',
                  width: '320px',
                  textAlign: 'left',
                  backdropFilter: 'blur(20px)',
                  WebkitBackdropFilter: 'blur(20px)'
                }}
              >
                <AddModuleForm
                  availableSlugs={availableSlugs}
                  onAdd={handleAddModule}
                  onClose={() => setShowAddModal(false)}
                />
              </div>
            )}
          </div>
        )}
      </div>

      <div style={{ background: 'var(--bg-body)', borderRadius: '12px', padding: '1.5rem', border: '1px solid var(--border)' }}>
          {/* Core API Key (Sales / Worker) */}
          {company && renderApiKeyBox(
              "API Key: APP Sales ( Força de Vendas )",
              company.companyKey,
              onRotateCompanyKey,
              'core_key',
              '#f59e0b',
              "Usada no app móvel Força de Vendas e no Worker Configurator."
          )}

          {loading && <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)', fontSize: '0.85rem' }}><RefreshCw size={18} className="spin" style={{ display: 'block', margin: '0 auto 0.5rem' }} /> Carregando módulos...</div>}
          {error   && <div style={{ padding: '1rem', background: '#FCE8E8', color: '#DC2626', borderRadius: '8px', fontSize: '0.85rem' }}>{error}</div>}

          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem', marginTop: '1.5rem' }}>
            {modules.map(mod => {
              const meta = MODULE_META[mod.moduleSlug] || { label: mod.moduleSlug, icon: '📦', color: '#607d8b' };
              return (
                <div key={mod.id} style={{ 
                  border: '1px solid var(--border)', 
                  background: 'var(--bg-card)', 
                  borderRadius: '12px', 
                  overflow: 'hidden',
                  opacity: mod.isActive ? 1 : 0.65,
                  transition: 'opacity 0.2s',
                  boxShadow: '0 2px 10px rgba(0,0,0,0.03)'
                }}>
                  {/* Module Header */}
                  <div style={{ 
                      padding: '1.25rem 1.5rem', 
                      background: `${meta.color}08`, 
                      borderBottom: '1px solid var(--border)',
                      display: 'flex', justifyContent: 'space-between', alignItems: 'center' 
                  }}>
                    <div style={{ display: 'flex', gap: '1rem', alignItems: 'center' }}>
                      <div style={{ width: '40px', height: '40px', borderRadius: '10px', background: `${meta.color}15`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.25rem' }}>
                        {meta.icon}
                      </div>
                      <div>
                        <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--text-main)', margin: 0, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                          {meta.label}
                          <span style={{ fontSize: '0.65rem', padding: '2px 8px', borderRadius: '12px', background: mod.isActive ? 'var(--success-light)' : 'var(--border)', color: mod.isActive ? 'var(--success-dark)' : 'var(--text-muted)', fontWeight: 700, letterSpacing: '0.05em' }}>
                            {mod.isActive ? 'ATIVO' : 'INATIVO'}
                          </span>
                        </h4>
                        <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', margin: '0.2rem 0 0 0' }}>{meta.desc}</p>
                      </div>
                    </div>

                    <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
                      <button onClick={() => setConfigModal(mod)} className="btn-pill" style={{ background: 'var(--bg-body)', border: '1px solid var(--border)' }}>
                        <Settings size={14} /> Configurar
                      </button>
                      <label style={{ display: 'flex', alignItems: 'center', cursor: 'pointer', background: 'var(--bg-body)', padding: '0.4rem 0.6rem', borderRadius: '20px', border: '1px solid var(--border)' }}>
                        <span style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)', marginRight: '8px' }}>Ativo</span>
                        <input type="checkbox" checked={mod.isActive} onChange={() => handleToggleActive(mod)} style={{ cursor: 'pointer', accentColor: meta.color, width: '16px', height: '16px' }} />
                      </label>
                      <button onClick={() => handleRemove(mod)} title="Remover Módulo" style={{ background: 'rgba(239,68,68,0.1)', border: 'none', color: '#ef4444', width: '32px', height: '32px', borderRadius: '8px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
                          <Trash2 size={16} />
                      </button>
                    </div>
                  </div>

                  {/* Module Content */}
                  <div style={{ padding: '1.5rem' }}>
                      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '1rem', marginBottom: '1.5rem' }}>
                        <div style={{ padding: '1rem', background: 'var(--bg-body)', borderRadius: '8px', border: '1px solid var(--border)' }}>
                          <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem', display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <Shield size={12} /> Limite de Dispositivos
                          </div>
                          <div style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--text-main)' }}>{mod.deviceLimit}</div>
                        </div>

                        {mod.middlewareBaseUrl && (
                          <div style={{ padding: '1rem', background: 'var(--bg-body)', borderRadius: '8px', border: '1px solid var(--border)' }}>
                            <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem', display: 'flex', alignItems: 'center', gap: '4px' }}>
                              <Server size={12} /> Sync Base URL
                            </div>
                            <div style={{ fontSize: '0.85rem', color: 'var(--primary)', fontFamily: 'monospace', wordBreak: 'break-all', fontWeight: 600 }}>{mod.middlewareBaseUrl}</div>
                          </div>
                        )}

                        {mod.moduleSlug === 'coliseu-dash' && (
                          <div style={{ padding: '1rem', background: 'var(--bg-body)', borderRadius: '8px', border: '1px solid var(--border)' }}>
                            <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', textTransform: 'uppercase', fontWeight: 600, marginBottom: '0.25rem', display: 'flex', alignItems: 'center', gap: '4px' }}>
                              <Package size={12} /> Versões Habilitadas
                            </div>
                            <div style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--text-main)' }}>
                              {mod.versions && mod.versions.length > 0 ? mod.versions.join(', ') : 'Nenhuma versão'}
                            </div>
                          </div>
                        )}
                      </div>

                      {/* API Key Inline */}
                      <div style={{ margin: 0 }}>
                          {renderApiKeyBox(
                              `API Key: ${meta.label}`,
                              mod.apiKey,
                              () => handleRotateKey(mod.id, mod.moduleSlug),
                              mod.id,
                              meta.color
                          )}
                      </div>
                  </div>
                </div>
              );
            })}
          </div>
      </div>



      {/* Modal: Configurar Módulo */}
      {configModal && (
        <ConfigModuleModal
          mod={configModal}
          onSave={handleSaveConfig}
          onClose={() => setConfigModal(null)}
        />
      )}
    </div>
  );
}

// ── Sub-componente: Formulário Adicionar Módulo ──────────────────────────────────
function AddModuleForm({ availableSlugs, onAdd, onClose }) {
  const [slug, setSlug]          = useState(availableSlugs[0] || '');
  const [limit, setLimit]        = useState(5);
  const [url, setUrl]            = useState('');
  const [versions, setVersions]  = useState(['Dash 1.0']);
  const [submitting, setSubmitting] = useState(false);

  const handleVersionChange = (version) => {
    if (versions.includes(version)) {
      setVersions(versions.filter(v => v !== version));
    } else {
      setVersions([...versions, version]);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (slug === 'coliseu-dash' && versions.length === 0) {
      alert('Selecione pelo menos uma versão para o Coliseu Dash.');
      return;
    }
    setSubmitting(true);
    await onAdd(slug, Number(limit), url, slug === 'coliseu-dash' ? versions : undefined);
    setSubmitting(false);
  };

  return (
    <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '0.85rem' }}>
      <h4 style={{ margin: '0 0 0.25rem 0', fontSize: '0.95rem', fontWeight: 700, color: 'var(--text-main)', borderBottom: '1px solid var(--border)', paddingBottom: '0.5rem' }}>
        ➕ Adicionar Módulo
      </h4>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
        <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)' }}>Módulo</label>
        <select 
          value={slug} 
          onChange={e => {
            setSlug(e.target.value);
            if (e.target.value !== 'coliseu-dash') {
              setVersions(['Dash 1.0']);
            }
          }} 
          required
          className="input-field"
          style={{
            padding: '0.45rem 0.75rem',
            fontSize: '0.85rem',
            cursor: 'pointer'
          }}
        >
          {availableSlugs.map(s => (
            <option key={s} value={s}>
              {MODULE_META[s]?.icon} {MODULE_META[s]?.label || s}
            </option>
          ))}
        </select>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
        <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)' }}>Limite de Dispositivos</label>
        <input 
          type="number" 
          min={1} 
          max={999} 
          value={limit}
          onChange={e => setLimit(e.target.value)} 
          required 
          className="input-field"
          style={{
            padding: '0.45rem 0.75rem',
            fontSize: '0.85rem'
          }}
        />
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
        <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)' }}>URL do Middleware (opcional)</label>
        <input 
          type="url" 
          placeholder="https://autocenter.coliseusistemas.com.br"
          value={url} 
          onChange={e => setUrl(e.target.value)} 
          className="input-field"
          style={{
            padding: '0.45rem 0.75rem',
            fontSize: '0.85rem'
          }}
        />
      </div>

      {slug === 'coliseu-dash' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
          <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)' }}>Versões Disponibilizadas</label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem', background: 'var(--bg-body)', padding: '0.6rem', borderRadius: '8px', border: '1px solid var(--border)' }}>
            {['Dash 1.0', 'B.I 1.0', 'B.I IA.'].map(v => (
              <label key={v} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.8rem', cursor: 'pointer', color: 'var(--text-main)' }}>
                <input 
                  type="checkbox" 
                  checked={versions.includes(v)} 
                  onChange={() => handleVersionChange(v)} 
                  style={{ accentColor: '#10b981', cursor: 'pointer' }}
                />
                {v}
              </label>
            ))}
          </div>
        </div>
      )}

      <div style={{ display: 'flex', gap: '0.5rem', justifyContent: 'flex-end', marginTop: '0.25rem' }}>
        <button 
          type="button" 
          className="btn btn-outline" 
          onClick={onClose}
          style={{ padding: '0.4rem 0.75rem', fontSize: '0.8rem' }}
        >
          Cancelar
        </button>
        <button 
          type="submit" 
          className="btn btn-primary" 
          disabled={submitting}
          style={{ padding: '0.4rem 0.75rem', fontSize: '0.8rem' }}
        >
          {submitting ? 'Adicionando...' : 'Adicionar'}
        </button>
      </div>
    </form>
  );
}

// ── Sub-modal: Configurar Módulo ─────────────────────────────────────────────
function ConfigModuleModal({ mod, onSave, onClose }) {
  const meta = MODULE_META[mod.moduleSlug] || { label: mod.moduleSlug };
  const [limit, setLimit] = useState(mod.deviceLimit);
  const [url, setUrl]     = useState(mod.middlewareBaseUrl || '');
  const [versions, setVersions] = useState(mod.versions || ['Dash 1.0']);
  const [saving, setSaving] = useState(false);

  const handleVersionChange = (version) => {
    if (versions.includes(version)) {
      setVersions(versions.filter(v => v !== version));
    } else {
      setVersions([...versions, version]);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (mod.moduleSlug === 'coliseu-dash' && versions.length === 0) {
      alert('Selecione pelo menos uma versão para o Coliseu Dash.');
      return;
    }
    setSaving(true);
    await onSave(mod, limit, url, mod.moduleSlug === 'coliseu-dash' ? versions : undefined);
    setSaving(false);
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={e => e.stopPropagation()}>
        <h4 className="modal-title">⚙️ Configurar — {meta.label}</h4>
        <form onSubmit={handleSubmit} className="modal-form">
          <label>
            Limite de Dispositivos
            <input type="number" min={1} max={999} value={limit}
              onChange={e => setLimit(e.target.value)} required />
          </label>
          <label>
            URL do Middleware
            <input type="url" placeholder="https://autocenter.coliseusistemas.com.br"
              value={url} onChange={e => setUrl(e.target.value)} />
          </label>

          {mod.moduleSlug === 'coliseu-dash' && (
            <label style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', marginTop: '0.5rem' }}>
              Versões Disponibilizadas
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem', background: 'var(--bg-body)', padding: '0.6rem', borderRadius: '8px', border: '1px solid var(--border)', width: '100%', boxSizing: 'border-box' }}>
                {['Dash 1.0', 'B.I 1.0', 'B.I IA.'].map(v => (
                  <label key={v} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.8rem', cursor: 'pointer', color: 'var(--text-main)', fontWeight: 'normal' }}>
                    <input 
                      type="checkbox" 
                      checked={versions.includes(v)} 
                      onChange={() => handleVersionChange(v)} 
                      style={{ accentColor: '#10b981', cursor: 'pointer' }}
                    />
                    {v}
                  </label>
                ))}
              </div>
            </label>
          )}

          <div className="modal-actions">
            <button type="button" className="btn btn-outline" onClick={onClose}>Cancelar</button>
            <button type="submit" className="btn btn-primary" disabled={saving}>
              {saving ? 'Salvando...' : 'Salvar'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
