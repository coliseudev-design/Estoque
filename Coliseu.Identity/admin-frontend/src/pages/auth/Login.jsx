import React, { useState } from 'react';
import { Mail, Lock, ShieldCheck, ArrowRight, UserPlus, Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { authService } from '../../services/authService';

const encodeBase64 = (str) => {
    try {
        return btoa(encodeURIComponent(str));
    } catch {
        return '';
    }
};

const decodeBase64 = (str) => {
    try {
        return decodeURIComponent(atob(str));
    } catch {
        return '';
    }
};

export default function Login() {
    const [email, setEmail] = useState(() => localStorage.getItem('rememberedEmail') || '');
    const [password, setPassword] = useState(() => {
        const stored = localStorage.getItem('rememberedPassword');
        return stored ? decodeBase64(stored) : '';
    });
    const [rememberMe, setRememberMe] = useState(() => !!localStorage.getItem('rememberedEmail'));
    const [step, setStep] = useState(1); // 1 = Login, 2 = TOTP
    const [mfaCode, setMfaCode] = useState('');

    // API States
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [errorMsg, setErrorMsg] = useState('');
    // Guarda o e-mail do admin quando requiresTwoFactor = true
    const [pendingEmail, setPendingEmail] = useState('');

    const navigate = useNavigate();

    const handleLoginSubmit = async (e) => {
        e.preventDefault();
        if (!email || !password) return;

        setErrorMsg('');
        setIsSubmitting(true);

        if (rememberMe) {
            localStorage.setItem('rememberedEmail', email);
            localStorage.setItem('rememberedPassword', encodeBase64(password));
        } else {
            localStorage.removeItem('rememberedEmail');
            localStorage.removeItem('rememberedPassword');
        }

        try {
            const response = await authService.login(email, password);

            if (response?.requiresTwoFactor) {
                // Backend exige TOTP — avança para o passo 2 sem token ainda
                setPendingEmail(response.email || email);
                setMfaCode('');
                setStep(2);
            } else if (response?.accessToken) {
                // Login direto sem 2FA (token já salvo pelo authService)
                navigate('/dashboard/companies');
            } else {
                setErrorMsg('Resposta inesperada do servidor.');
            }
        } catch (error) {
            console.error('Login error:', error);
            setErrorMsg(
                error.response?.data?.error ??
                'Falha ao conectar ao servidor. Tente novamente.'
            );
        } finally {
            setIsSubmitting(false);
        }
    };

    const handle2FASubmit = async (e) => {
        e.preventDefault();
        if (mfaCode.length !== 6) return;

        setErrorMsg('');
        setIsSubmitting(true);

        try {
            // Chama o endpoint real de verificação TOTP
            const response = await authService.verify2fa(pendingEmail, mfaCode);

            if (response?.accessToken) {
                // Token já salvo pelo authService.verify2fa()
                navigate('/dashboard/companies');
            } else {
                setErrorMsg('Falha na verificação. Tente novamente.');
            }
        } catch (error) {
            console.error('2FA verify error:', error);
            setErrorMsg(
                error.response?.data?.error ??
                'Código inválido ou expirado. Tente novamente.'
            );
            setMfaCode('');
        } finally {
            setIsSubmitting(false);
        }
    };

    return (
        <div className="app-container" style={{ background: '#fff' }}>

            {/* Left Column: Form */}
            <div className="flex flex-col justify-center items-center" style={{ flex: '1', padding: '2rem', background: '#FFFFFF' }}>
                <div className="w-full animate-slide-up" style={{ maxWidth: '400px' }}>

                    <img src="/coliseu-logo.png" alt="Coliseu Sistemas" style={{ height: '96px', marginBottom: '2.5rem', objectFit: 'contain' }} />

                    <div style={{ marginBottom: '2rem' }}>
                        <h1 style={{ fontSize: '2.5rem', fontWeight: 800, color: 'var(--text-main)', letterSpacing: '-0.5px' }}>
                            {step === 1 ? 'Bem-vindo de volta.' : 'Proteção Global.'}
                        </h1>
                        <p className="text-muted" style={{ fontSize: '1rem', marginTop: '0.5rem' }}>
                            {step === 1
                                ? 'Entre para gerenciar o ecossistema Coliseu.'
                                : 'Insira o código de 6 dígitos gerado pelo seu Authenticator.'}
                        </p>
                    </div>

                    {step === 1 ? (
                        <form onSubmit={handleLoginSubmit} className="flex flex-col gap-4">
                            {errorMsg && (
                                <div style={{ padding: '0.75rem', background: 'var(--danger-light)', color: 'var(--danger)', borderRadius: 'var(--radius-md)', fontSize: '0.875rem', fontWeight: 500, border: '1px solid rgba(220, 53, 69, 0.2)' }}>
                                    {errorMsg}
                                </div>
                            )}

                            <div>
                                <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>E-mail de Acesso</label>
                                <div style={{ position: 'relative' }}>
                                    <Mail size={20} color="var(--text-muted)" style={{ position: 'absolute', top: '12px', left: '12px' }} />
                                    <input
                                        type="email"
                                        required
                                        className="input-field hover-lift"
                                        placeholder="email@coliseusistemas.com.br"
                                        style={{ paddingLeft: '40px' }}
                                        value={email}
                                        onChange={(e) => setEmail(e.target.value)}
                                        disabled={isSubmitting}
                                    />
                                </div>
                            </div>

                            <div>
                                <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Senha de Segurança</label>
                                <div style={{ position: 'relative' }}>
                                    <Lock size={20} color="var(--text-muted)" style={{ position: 'absolute', top: '12px', left: '12px' }} />
                                    <input
                                        type="password"
                                        required
                                        className="input-field hover-lift"
                                        placeholder="••••••••"
                                        style={{ paddingLeft: '40px' }}
                                        value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                        disabled={isSubmitting}
                                    />
                                </div>
                                <div className="flex justify-between items-center" style={{ marginTop: '0.75rem' }}>
                                    <label className="flex items-center gap-2 text-xs font-medium text-muted cursor-pointer select-none">
                                        <input
                                            type="checkbox"
                                            checked={rememberMe}
                                            onChange={(e) => setRememberMe(e.target.checked)}
                                            style={{ cursor: 'pointer' }}
                                        />
                                        Lembrar-me
                                    </label>
                                    <a href="#" className="text-xs font-medium" style={{ color: 'var(--primary)' }}>Esqueceu a senha?</a>
                                </div>
                            </div>

                            <button type="submit" disabled={isSubmitting} className="btn btn-primary hover-lift" style={{ marginTop: '1rem', padding: '1rem', fontSize: '1rem', display: 'flex', justifyContent: 'center', alignItems: 'center', gap: '8px' }}>
                                {isSubmitting ? (
                                    <>
                                        Validando... <Loader2 size={18} className="animate-spin" />
                                    </>
                                ) : (
                                    <>
                                        Avançar <ArrowRight size={18} />
                                    </>
                                )}
                            </button>

                            {/* Criar acesso link removed */}
                        </form>
                    ) : (
                        <form onSubmit={handle2FASubmit} className="flex flex-col gap-4 animate-fade-in">
                            <div>
                                <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Código 2FA</label>
                                <div style={{ position: 'relative' }}>
                                    <ShieldCheck size={20} color="var(--primary)" style={{ position: 'absolute', top: '12px', left: '12px' }} />
                                    <input
                                        type="text"
                                        required
                                        maxLength={6}
                                        className="input-field hover-lift"
                                        placeholder="000000"
                                        style={{ paddingLeft: '40px', fontSize: '1.5rem', letterSpacing: '8px', fontWeight: 'bold', textAlign: 'center' }}
                                        value={mfaCode}
                                        onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, ''))}
                                    />
                                </div>
                            </div>
                            <button type="submit" className="btn btn-primary hover-lift" style={{ marginTop: '1rem', padding: '1rem', fontSize: '1rem' }}>
                                Validar Identidade <ShieldCheck size={18} />
                            </button>
                            <div className="text-center" style={{ marginTop: '1rem' }}>
                                <button type="button" onClick={() => setStep(1)} className="text-xs font-medium text-muted hover-lift">
                                    Voltar ao Login
                                </button>
                            </div>
                        </form>
                    )}

                </div>
            </div>

            {/* Right Column: Hero / Branding (Light Variation) */}
            <div
                className="animate-slide-in-right"
                style={{
                    flex: '1',
                    background: 'var(--bg-body)',
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'center',
                    alignItems: 'center',
                    color: 'var(--text-main)',
                    padding: '4rem',
                    position: 'relative',
                    overflow: 'hidden',
                    borderLeft: '1px solid var(--border)'
                }}
            >
                {/* Subtle background circles for depth */}
                <div style={{ position: 'absolute', width: '500px', height: '500px', borderRadius: '50%', background: 'linear-gradient(135deg, rgba(0, 115, 180, 0.05), transparent)', top: '-10%', right: '-10%' }}></div>
                <div style={{ position: 'absolute', width: '300px', height: '300px', borderRadius: '50%', background: 'linear-gradient(135deg, transparent, rgba(36, 151, 212, 0.05))', bottom: '10%', left: '-10%' }}></div>

                <div style={{ zIndex: 1, textAlign: 'center', maxWidth: '500px' }}>
                    <div style={{ display: 'inline-flex', alignItems: 'center', gap: '12px', marginBottom: '2rem' }}>
                        <div style={{ width: '48px', height: '48px', background: 'var(--primary)', borderRadius: '12px', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 4px 14px 0 rgba(0, 115, 180, 0.2)' }}>
                            <ShieldCheck size={28} color="white" />
                        </div>
                        <h2 style={{ fontSize: '2.5rem', fontWeight: 800, margin: 0, color: 'var(--text-main)', letterSpacing: '-1px' }}>
                            Coliseu Identity
                        </h2>
                    </div>

                    <h3 style={{ fontSize: '2rem', fontWeight: 300, lineHeight: 1.2, marginBottom: '1.5rem' }}>
                        Do controle central à segurança extrema. Sem fricção.
                    </h3>
                    <p style={{ fontSize: '1.125rem', color: 'var(--text-muted)', lineHeight: 1.6 }}>
                        Gerencie centenas de licenças, monitore o ecossistema Coliseu Speed e ative integrações em tempo real através do Identity Vault.
                    </p>

                    {/* Feature Cards */}
                    <div className="flex gap-4" style={{ marginTop: '3rem' }}>
                        <div className="hover-lift" style={{ padding: '1.25rem', borderRadius: 'var(--radius-md)', flex: 1, textAlign: 'left', background: 'white', border: '1px solid var(--border)', boxShadow: 'var(--shadow-sm)' }}>
                            <Lock size={24} color="var(--primary)" style={{ marginBottom: '12px' }} />
                            <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--text-main)' }}>Criptografia AES-256</div>
                            <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>No repouso</div>
                        </div>
                        <div className="hover-lift" style={{ padding: '1.25rem', borderRadius: 'var(--radius-md)', flex: 1, textAlign: 'left', background: 'white', border: '1px solid var(--border)', boxShadow: 'var(--shadow-sm)' }}>
                            <ShieldCheck size={24} color="var(--primary)" style={{ marginBottom: '12px' }} />
                            <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--text-main)' }}>Multi-Tenant Shield</div>
                            <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>By Design</div>
                        </div>
                    </div>
                </div>
            </div>

        </div>
    );
}
