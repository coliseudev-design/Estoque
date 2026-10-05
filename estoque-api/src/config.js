/**
 * Configuração tipada a partir de variáveis de ambiente.
 * Falha no startup se faltar algo obrigatório em produção.
 */
'use strict';

const path = require('node:path');

const env = process.env;
const isProduction = env.NODE_ENV === 'production';

function required(name, devFallback) {
    const value = env[name];
    if (value) return value;
    if (!isProduction && devFallback !== undefined) return devFallback;
    throw new Error(`[Config] Variável obrigatória ausente: ${name}`);
}

const int = (name, fallback) => {
    const n = parseInt(env[name], 10);
    return Number.isFinite(n) ? n : fallback;
};

module.exports = {
    isProduction,
    port: int('PORT', 3100),
    trustProxy: env.TRUST_PROXY !== 'false',

    pg: {
        connectionString: env.DATABASE_URL || undefined,
        host: env.PG_HOST || 'localhost',
        port: int('PG_PORT', 5432),
        database: env.PG_DATABASE || 'coliseu_estoque',
        user: env.PG_USER || 'postgres',
        password: env.PG_PASSWORD || '',
        ssl: env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
        max: int('PG_POOL_MAX', 20),
    },

    identity: {
        baseUrl: required('IDENTITY_BASE_URL', 'https://adminlicencas.coliseusistemas.com.br').replace(/\/+$/, ''),
        internalApiKey: required('IDENTITY_INTERNAL_API_KEY', ''),
        // Slug do módulo "Estoque Coliseu" no painel de licenças.
        moduleSlug: env.ESTOQUE_MODULE_SLUG || 'estoque',
        // Por quanto tempo uma validação de licença positiva fica em cache.
        cacheTtlMs: int('LICENSE_CACHE_TTL_SECONDS', 300) * 1000,
        // Se o Identity cair, aceita a última validação positiva por este período.
        // Evita parar a operação do armazém por instabilidade do painel.
        graceMs: int('LICENSE_GRACE_HOURS', 24) * 3_600_000,
    },

    security: {
        // Segredo dos tokens emitidos por esta API (operadores e dashboard).
        apiJwtSecret: required('ESTOQUE_JWT_SECRET', 'dev-estoque-secret-change-me'),
        apiJwtTtl: env.ESTOQUE_JWT_TTL || '12h',
        // Segredo compartilhado com o Coliseu.Identity — valida o JWT de dispositivo.
        identityJwtSecret: required('JWT_ACCESS_SECRET', 'dev-identity-secret'),
        allowedOrigins: (env.ALLOWED_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean),
    },

    dashboardDir: env.DASHBOARD_DIR || path.resolve(__dirname, '..', '..', 'dashboard'),
};
