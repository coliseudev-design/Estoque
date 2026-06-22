import React, { useState, useEffect } from 'react';
import { Settings as SettingsIcon, Server, Shield, Key, Copy, Check, ExternalLink, ShieldCheck, ShieldOff, Loader2, QrCode, AlertTriangle } from 'lucide-react';
import { authService } from '../../services/authService';

const InfoCard = ({ icon: Icon, title, children }) => (
    <div style={{
        background: 'var(--surface)', border: '1px solid var(--border)',
        borderRadius: '12px', padding: '1.5rem', marginBottom: '1.5rem',
    }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1.25rem' }}>
            <div style={{ width: 36, height: 36, borderRadius: '8px', background: 'rgba(27,143,205,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon size={18} style={{ color: 'var(--accent)' }} />
            </div>
            <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: 600, color: 'var(--text-main)' }}>{title}</h3>
        </div>
        {children}
    </div>
);

const ConfigRow = ({ label, value, monospace, copyable }) => {
    const [copied, setCopied] = useState(false);

    const handleCopy = () => {
        navigator.clipboard.writeText(value ?? '');
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
    };

    return (
        <div style={{ display: 'flex', alignItems: 'center', padding: '0.75rem 0', borderBottom: '1px solid var(--border)' }}>
            <span style={{ flex: '0 0 200px', color: 'var(--text-muted)', fontSize: '0.875rem' }}>{label}</span>
            <span style={{
                flex: 1, color: 'var(--text-main)', fontSize: '0.875rem',
                fontFamily: monospace ? 'monospace' : 'inherit',
                wordBreak: 'break-all',
            }}>
                {value ?? <em style={{ color: 'var(--text-muted)', fontStyle: 'italic' }}>Não configurado</em>}
            </span>
            {copyable && value && (
                <button onClick={handleCopy} title="Copiar" style={{
                    background: 'none', border: 'none', cursor: 'pointer',
                    color: copied ? '#22c55e' : 'var(--text-muted)', padding: '0.25rem', borderRadius: '4px', transition: 'color 0.2s',
                }}>
                    {copied ? <Check size={14} /> : <Copy size={14} />}
                </button>
            )}
        </div>
    );
};

const StatusBadge = ({ status }) => {
    const isOk = status === 'ok';
    return (
        <span style={{
            padding: '2px 8px', borderRadius: '12px', fontSize: '0.75rem', fontWeight: 600,
            background: isOk ? 'rgba(34,197,94,0.15)' : 'rgba(239,68,68,0.15)',
            color: isOk ? '#22c55e' : '#ef4444',
        }}>
            {isOk ? '● Online' : '● Offline'}
        </span>
    );
};

export default function Settings() {
    const config = {
        identityUrl: window.location.origin.replace(/:\d+/, ':5100'),
        salesApiUrl: window.location.origin.replace(/:\d+/, ':5000'),
        adminVersion: '1.0.0',
        jwtExpiry: '8 horas (device token)',
        adminJwtExpiry: '1 hora (admin token)',
    };

    // Extrai o e-mail do admin do token JWT armazenado no localStorage
    const getAdminEmail = () => {
        try {
            const token = localStorage.getItem('adminToken');
            if (!token) return null;
            const payload = JSON.parse(atob(token.split('.')[1]));
            return payload?.email ?? payload?.sub ?? null;
        } catch { return null; }
    };
    const adminEmail = getAdminEmail();

    return (
        <div className="animate-fade-in" style={{ padding: '2rem', maxWidth: '900px' }}>
            {/* Header */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '2rem' }}>
                <SettingsIcon size={28} style={{ color: 'var(--accent)' }} />
                <div>
                    <h1 style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-main)', margin: 0 }}>
                        Configurações Globais
                    </h1>
                    <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '0.875rem' }}>
                        Informações da plataforma Coliseu Sales Force
                    </p>
                </div>
            </div>

            {/* Endpoints do Sistema */}
            <InfoCard icon={Server} title="Endpoints do Sistema">
                <ConfigRow label="Identity API (Admin)" value={config.identityUrl} monospace copyable />
                <ConfigRow label="Sales API (Mobile/Worker)" value={config.salesApiUrl} monospace copyable />
                <ConfigRow label="Versão do Painel Admin" value={config.adminVersion} />
                <div style={{ marginTop: '1rem', display: 'flex', gap: '1rem' }}>
                    <a href={`${config.identityUrl}/swagger`} target="_blank" rel="noreferrer"
                        style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.875rem', color: 'var(--accent)', textDecoration: 'none' }}>
                        <ExternalLink size={14} /> Swagger Identity
                    </a>
                    <a href={`${config.salesApiUrl}/swagger`} target="_blank" rel="noreferrer"
                        style={{ display: 'flex', alignItems: 'center', gap: '0.4rem', fontSize: '0.875rem', color: 'var(--accent)', textDecoration: 'none' }}>
                        <ExternalLink size={14} /> Swagger Sales API
                    </a>
                </div>
            </InfoCard>

            {/* Segurança */}
            <InfoCard icon={Shield} title="Segurança e Autenticação">
                <ConfigRow label="Expiração JWT (Device)" value={config.jwtExpiry} />
                <ConfigRow label="Expiração JWT (Admin)" value={config.adminJwtExpiry} />
                <ConfigRow label="2FA (Admin)" value="TOTP (Google Authenticator)" />
                <ConfigRow label="Criptografia" value="AES-256-GCM (credenciais Firebird)" />
                <ConfigRow label="Hash de Credenciais" value="bcrypt custo 12 (senhas admin)" />
                <div style={{ marginTop: '1rem', padding: '0.75rem 1rem', background: 'rgba(234,179,8,0.08)', border: '1px solid rgba(234,179,8,0.2)', borderRadius: '8px', fontSize: '0.8rem', color: '#eab308' }}>
                    ⚠️ As configurações de segurança são definidas nas variáveis de ambiente do servidor.
                    Não é possível alterá-las por este painel.
                </div>
            </InfoCard>

            {/* 2FA Setup */}
            <TwoFactorCard email={adminEmail} />

            {/* Chave Interna do Worker */}
            <InfoCard icon={Key} title="Chave Interna (Worker ↔ Identity)">
                <div style={{ marginBottom: '1rem', fontSize: '0.875rem', color: 'var(--text-muted)', lineHeight: 1.5 }}>
                    Esta chave é configurada no <code style={{ background: 'var(--bg)', padding: '1px 4px', borderRadius: '3px' }}>appsettings.json</code> do
                    Worker Service (<code style={{ background: 'var(--bg)', padding: '1px 4px', borderRadius: '3px' }}>IdentityApi:InternalApiKey</code>).
                    O Worker a usa para buscar credenciais Firebird do Identity API.
                </div>
                <ConfigRow label="X-Internal-Api-Key" value="Configurado no servidor" monospace />
                <div style={{ marginTop: '1rem', padding: '0.75rem 1rem', background: 'rgba(59,130,246,0.08)', border: '1px solid rgba(59,130,246,0.2)', borderRadius: '8px', fontSize: '0.8rem', color: '#60a5fa' }}>
                    💡 Para gerar uma nova chave: use o comando <code>openssl rand -hex 32</code> no servidor e atualize o arquivo de configuração do Worker.
                </div>
            </InfoCard>

            {/* Status dos Serviços */}
            <InfoCard icon={Server} title="Status dos Serviços">
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
                    {[
                        { name: 'Identity API', url: `${config.identityUrl}/health` },
                        { name: 'Sales API', url: `${config.salesApiUrl}/health` },
                    ].map(svc => (
                        <ServiceCheck key={svc.name} name={svc.name} url={svc.url} />
                    ))}
                </div>
            </InfoCard>
        </div>
    );
}

function ServiceCheck({ name, url }) {
    const [status, setStatus] = useState('checking');

    React.useEffect(() => {
        fetch(url)
            .then(r => setStatus(r.ok ? 'ok' : 'error'))
            .catch(() => setStatus('error'));
    }, [url]);

    return (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0.75rem 1rem', background: 'var(--bg)', borderRadius: '8px', border: '1px solid var(--border)' }}>
            <span style={{ fontSize: '0.875rem', color: 'var(--text-main)', fontWeight: 500 }}>{name}</span>
            {status === 'checking'
                ? <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Verificando…</span>
                : <StatusBadge status={status} />
            }
        </div>
    );
}

// ─── Componente de gerenciamento de 2FA ──────────────────────────────────────
function TwoFactorCard({ email }) {
    // Fase: 'idle' | 'setup_qr' | 'enabled'
    const [phase, setPhase] = useState('idle');
    const [otpUri, setOtpUri] = useState('');
    const [code, setCode] = useState('');
    const [msg, setMsg] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState('');

    // Gera o QR Code using otpauth URI via Google Charts (sem npm extra)
    const qrUrl = otpUri
        ? `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(otpUri)}`
        : null;

    const handleRequestQr = async () => {
        if (!email) { setError('E-mail não encontrado na sessão. Faça login novamente.'); return; }
        setError(''); setIsLoading(true);
        try {
            const res = await authService.setup2fa(email, '');
            setOtpUri(res.otpAuthUri);
            setPhase('setup_qr');
        } catch (e) {
            setError(e.response?.data?.error ?? 'Erro ao gerar QR Code.');
        } finally { setIsLoading(false); }
    };

    const handleActivate = async (e) => {
        e.preventDefault();
        if (code.length !== 6) return;
        setError(''); setIsLoading(true);
        try {
            const res = await authService.setup2fa(email, code);
            if (res.isVerified) {
                setMsg('2FA ativado com sucesso! 🎉');
                setPhase('enabled');
                setCode('');
                setOtpUri('');
            } else {
                setError('Código inválido. Tente novamente.');
                setCode('');
            }
        } catch (e) {
            setError(e.response?.data?.error ?? 'Código inválido ou expirado.');
            setCode('');
        } finally { setIsLoading(false); }
    };

    const handleDisable = async () => {
        setError(''); setIsLoading(true);
        try {
            await authService.disable2fa();
            setMsg('2FA desativado.');
            setPhase('idle');
        } catch (e) {
            setError(e.response?.data?.error ?? 'Erro ao desativar 2FA.');
        } finally { setIsLoading(false); }
    };

    return (
        <InfoCard icon={ShieldCheck} title="Autenticação de 2 Fatores (TOTP)">

            {/* Mensagem de feedback */}
            {msg && (
                <div style={{ marginBottom: '1rem', padding: '0.75rem', background: 'rgba(34,197,94,0.1)', color: '#22c55e', borderRadius: '8px', fontSize: '0.875rem', border: '1px solid rgba(34,197,94,0.2)' }}>
                    ✅ {msg}
                </div>
            )}
            {error && (
                <div style={{ marginBottom: '1rem', padding: '0.75rem', background: 'rgba(239,68,68,0.1)', color: '#ef4444', borderRadius: '8px', fontSize: '0.875rem', border: '1px solid rgba(239,68,68,0.2)' }}>
                    <AlertTriangle size={14} style={{ display: 'inline', marginRight: '6px' }} /> {error}
                </div>
            )}

            {/* Estado: desativado */}
            {phase === 'idle' && (
                <div>
                    <p style={{ fontSize: '0.875rem', color: 'var(--text-muted)', marginBottom: '1rem', lineHeight: 1.5 }}>
                        O 2FA adiciona uma camada extra de segurança ao login com Google Authenticator ou Authy.
                        Após ativar, o login exigirá o código TOTP além da senha.
                    </p>
                    <button onClick={handleRequestQr} disabled={isLoading} className="btn btn-primary"
                        style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        {isLoading ? <Loader2 size={16} className="animate-spin" /> : <ShieldCheck size={16} />}
                        Ativar Autenticação de 2 Fatores
                    </button>
                </div>
            )}

            {/* Estado: exibindo QR Code para scan */}
            {phase === 'setup_qr' && (
                <div>
                    <p style={{ fontSize: '0.875rem', color: 'var(--text-muted)', marginBottom: '1.25rem', lineHeight: 1.5 }}>
                        <strong>Passo 1:</strong> Escaneie o QR Code abaixo com o Google Authenticator ou Authy.<br />
                        <strong>Passo 2:</strong> Digite o código de 6 dígitos gerado pelo app para confirmar.
                    </p>
                    <div style={{ display: 'flex', gap: '2rem', alignItems: 'flex-start', flexWrap: 'wrap' }}>
                        {qrUrl && (
                            <div style={{ border: '4px solid white', borderRadius: '12px', boxShadow: 'var(--shadow)', lineHeight: 0 }}>
                                <img src={qrUrl} alt="QR Code 2FA" width="200" height="200" style={{ borderRadius: '8px' }} />
                            </div>
                        )}
                        <form onSubmit={handleActivate} style={{ flex: 1, minWidth: '200px' }}>
                            <label style={{ display: 'block', fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-main)', marginBottom: '0.5rem' }}>
                                Código de verificação:
                            </label>
                            <input
                                type="text"
                                className="input-field"
                                inputMode="numeric"
                                maxLength={6}
                                placeholder="000000"
                                value={code}
                                onChange={e => setCode(e.target.value.replace(/\D/g, ''))}
                                style={{ fontSize: '1.5rem', letterSpacing: '0.5rem', fontWeight: 700, textAlign: 'center', marginBottom: '1rem' }}
                                autoFocus
                            />
                            <div style={{ display: 'flex', gap: '0.75rem' }}>
                                <button type="submit" disabled={isLoading || code.length !== 6} className="btn btn-primary"
                                    style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                    {isLoading ? <Loader2 size={16} className="animate-spin" /> : <ShieldCheck size={16} />}
                                    Confirmar e Ativar
                                </button>
                                <button type="button" onClick={() => { setPhase('idle'); setCode(''); setOtpUri(''); setError(''); }}
                                    className="btn btn-outline">
                                    Cancelar
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* Estado: ativado */}
            {phase === 'enabled' && (
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '1rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'rgba(34,197,94,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <ShieldCheck size={20} style={{ color: '#22c55e' }} />
                        </div>
                        <div>
                            <div style={{ fontWeight: 600, color: 'var(--text-main)' }}>2FA Ativado</div>
                            <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Login protegido por TOTP (Google Authenticator)</div>
                        </div>
                    </div>
                    <button onClick={handleDisable} disabled={isLoading} className="btn btn-outline"
                        style={{ color: '#ef4444', borderColor: '#ef4444', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        {isLoading ? <Loader2 size={16} className="animate-spin" /> : <ShieldOff size={16} />}
                        Desativar 2FA
                    </button>
                </div>
            )}
        </InfoCard>
    );
}

