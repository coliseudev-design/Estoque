import React, { useState } from 'react';
import { Mail, Lock, User, ArrowLeft, ArrowRight, ShieldCheck } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

export default function Register() {
    const [name, setName] = useState('');
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const navigate = useNavigate();

    const handleRegisterSubmit = (e) => {
        e.preventDefault();
        if (name && email && password) {
            navigate('/');
        }
    };

    return (
        <div className="app-container" style={{ background: '#fff' }}>

            {/* Left Column: Form */}
            <div className="flex flex-col justify-center items-center" style={{ flex: '1', padding: '2rem', background: '#FFFFFF' }}>
                <div className="w-full animate-slide-up" style={{ maxWidth: '400px' }}>

                    <button
                        type="button"
                        onClick={() => navigate('/')}
                        className="flex items-center gap-2 text-muted hover-lift"
                        style={{ marginBottom: '2rem', fontSize: '0.875rem', fontWeight: 500 }}
                    >
                        <ArrowLeft size={16} /> Voltar para o Login
                    </button>

                    <img src="/coliseu-logo.png" alt="Coliseu Sistemas" style={{ height: '96px', marginBottom: '2.5rem', objectFit: 'contain' }} />

                    <div style={{ marginBottom: '2rem' }}>
                        <h1 style={{ fontSize: '2.5rem', fontWeight: 800, color: 'var(--text-main)', letterSpacing: '-0.5px' }}>
                            Criar Acesso.
                        </h1>
                        <p className="text-muted" style={{ fontSize: '1rem', marginTop: '0.5rem' }}>
                            Junte-se aos administradores do Coliseu.
                        </p>
                    </div>

                    <form onSubmit={handleRegisterSubmit} className="flex flex-col gap-4">
                        <div>
                            <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Nome Completo</label>
                            <div style={{ position: 'relative' }}>
                                <User size={20} color="var(--text-muted)" style={{ position: 'absolute', top: '12px', left: '12px' }} />
                                <input
                                    type="text"
                                    required
                                    className="input-field hover-lift"
                                    placeholder="Seu nome"
                                    style={{ paddingLeft: '40px' }}
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                />
                            </div>
                        </div>

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
                                />
                            </div>
                        </div>

                        <div>
                            <label className="text-sm font-medium text-muted" style={{ display: 'block', marginBottom: '0.5rem' }}>Senha Forte</label>
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
                                />
                            </div>
                            <p className="text-xs text-muted" style={{ marginTop: '0.5rem' }}>
                                A senha deve conter no mínimo 8 caracteres, uma letra maiúscula e um número.
                            </p>
                        </div>

                        <button type="submit" className="btn btn-primary hover-lift" style={{ marginTop: '1rem', padding: '1rem', fontSize: '1rem' }}>
                            Cadastrar Administrador <ArrowRight size={18} />
                        </button>
                    </form>

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
                <div style={{ position: 'absolute', width: '600px', height: '600px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(0,115,180,0.08) 0%, rgba(0,0,0,0) 70%)', top: '50%', left: '50%', transform: 'translate(-50%, -50%)' }}></div>

                <div style={{ zIndex: 1, textAlign: 'center', maxWidth: '500px' }}>
                    <ShieldCheck size={48} color="var(--primary)" style={{ margin: '0 auto 1.5rem', opacity: 0.8 }} />
                    <h3 style={{ fontSize: '2rem', fontWeight: 300, lineHeight: 1.2, marginBottom: '1.5rem' }}>
                        Acesso Restrito de Alta Performance.
                    </h3>
                    <p style={{ fontSize: '1.125rem', color: 'var(--text-muted)', lineHeight: 1.6 }}>
                        Cadastros administrativos requerem validação e aprovação por Super Admins da Coliseu. Segurança em cada camada.
                    </p>
                </div>
            </div>

        </div>
    );
}
