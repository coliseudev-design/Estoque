/**
 * Configuração e validação de variáveis de ambiente.
 * Falha no startup se qualquer variável obrigatória estiver ausente.
 */
'use strict';

// dotenv SÓ em dev local — em produção as variáveis vêm do Docker/Coolify.
// SEM ISSO, o .env embutido na imagem Docker sobrescreve as variáveis reais.
if (process.env.NODE_ENV !== 'production') {
  require('dotenv').config();
}

/**
 * Valida a presença e formato de variáveis de ambiente críticas.
 * @throws {Error} Se alguma variável obrigatória estiver ausente.
 */
function validateEnv() {
  const alwaysRequired = ['API_KEY'];
  const missing = alwaysRequired.filter((key) => !process.env[key]);

  // Variáveis do Firebird só são obrigatórias quando NÃO estamos em modo mock
  // ou async (VPS sem acesso direto ao Firebird).
  const firebirdRequired = ['FB_DATABASE', 'FB_USER', 'FB_PASSWORD'];
  const isMock = process.env.FB_MOCK === 'true';
  const isAsync = process.env.SYNC_MODE === 'async';

  if (!isMock && !isAsync) {
    const missingFb = firebirdRequired.filter((key) => !process.env[key]);
    missing.push(...missingFb);
  }

  if (missing.length > 0) {
    throw new Error(
      `[Config] Variáveis de ambiente obrigatórias ausentes: ${missing.join(', ')}. ` +
      'Copie .env.example para .env e preencha os valores.'
    );
  }

  if (process.env.API_KEY === 'CHANGE_THIS_TO_A_STRONG_RANDOM_KEY') {
    throw new Error(
      '[Config] API_KEY ainda está com o valor padrão. Gere uma chave segura antes de iniciar.'
    );
  }

  // JWT_ACCESS_SECRET deve ser configurado em produção.
  // O fallback hardcodado é aceitável apenas em desenvolvimento local.
  if (process.env.NODE_ENV === 'production' && !process.env.JWT_ACCESS_SECRET) {
    throw new Error(
      '[Config] JWT_ACCESS_SECRET é obrigatório em produção. ' +
      'Defina uma chave segura via variável de ambiente.'
    );
  }
}

validateEnv();

module.exports = {
  port: parseInt(process.env.PORT, 10) || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  isProduction: process.env.NODE_ENV === 'production',

  /**
   * Modo de sincronização de pedidos:
   * - direct:  Middleware tenta gravar diretamente no Firebird (default dev local)
   * - async:   Middleware apenas enfileira no PostgreSQL; Worker local processa (VPS)
   * - fallback: Tenta direct; se falhar ou estiver offline, faz async.
   */
  syncMode: process.env.SYNC_MODE || 'direct',

  firebird: {
    host: process.env.FB_HOST || 'localhost',
    port: parseInt(process.env.FB_PORT, 10) || 3050,
    database: process.env.FB_DATABASE,
    user: process.env.FB_USER,
    password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', // charset do ERP Coliseu
    lowercase_keys: false,
    role: null,
    pageSize: 4096,
    poolMin: parseInt(process.env.FB_POOL_MIN, 10) || 2,
    poolMax: parseInt(process.env.FB_POOL_MAX, 10) || 10,
    mock: process.env.FB_MOCK === 'true',
    wireCrypt: process.env.FB_WIRE_CRYPT !== 'false', // true por padrão; false só em dev local
  },

  security: {
    apiKey: process.env.API_KEY,
    jwtAccessSecret: process.env.JWT_ACCESS_SECRET || 'Coliseu2026!IdentitySuperSecretKeyOauth20',
    rateLimitWindowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 60_000,
    rateLimitMax: parseInt(process.env.RATE_LIMIT_MAX, 10) || 200,
    allowedOrigins: (process.env.ALLOWED_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean),
  },
};
