/**
 * auth.js — Middleware de autenticação multi-tenant por API Key.
 *
 * Fluxo:
 *   1. Extrai o header `API-Key` da requisição
 *   2. Calcula SHA-256 da chave para evitar timing attacks e buscar no banco
 *   3. Consulta a tabela `companies` no PostgreSQL pelo hash da chave
 *   4. Injeta `req.company = { id, name }` para uso nas rotas
 *   5. Rejeita com 401 se não encontrada ou empresa inativa
 *
 * Segurança:
 *   - Hashes SHA-256: nunca comparamos texto puro no JS, apenas no PG
 *   - Cache em memória (Map) de 60s para evitar round-trip ao PG por request
 *   - Rotação de chave: basta inserir nova empresa com nova api_key no PG
 *
 * @module middleware/auth
 */
'use strict';

const { createHash } = require('crypto');
const jwt = require('jsonwebtoken');
const { pgQuerySafe } = require('../db/postgres');
const logger = require('../config/logger');
const config = require('../config/env');

// Cache local para evitar query ao PG em toda requisição (TTL: 60s)
const _cache = new Map();  // hash → { company, expiresAt }
const CACHE_TTL = 60_000;  // 60 segundos

// WARNING-1 fix: limpeza periódica para evitar memory leak em maps sem limite.
// Remove entradas expiradas a cada 60s — impede crescimento indefinido do cache.
setInterval(() => {
    for (const [k, v] of _cache) {
        if (Date.now() > v.expiresAt) _cache.delete(k);
    }
}, 60_000).unref(); // .unref() garante que o timer não impede o processo de encerrar

// BLOCKER-1 fix: armazena credenciais Firebird SEPARADAS de req.company
// para nunca expor fb_password em logs ou serialização de req.company.
// Uso: const fbCreds = getFirebirdCreds(req);
const _fbCredsMap = new WeakMap(); // req → fbCredentials

/**
 * Retorna as credenciais Firebird associadas a um request.
 * NUNCA incluídas em req.company para evitar vazamento em logs.
 * @param {import('express').Request} req
 * @returns {{ fb_host, fb_port, fb_database, fb_user, fb_password, fb_charset, fb_wire_crypt }|null}
 */
function getFirebirdCreds(req) {
    return _fbCredsMap.get(req) ?? null;
}

/**
 * Calcula SHA-256 de uma string e retorna em hex.
 *
 * IMPORTANTE: normaliza para UPPERCASE antes do hash
 * para manter compatibilidade com o CompanyKeyGenerator.cs da Identity API,
 * que faz: SHA256(key.Trim().ToUpperInvariant())
 *
 * @param {string} raw
 * @returns {string}
 */
function sha256hex(raw) {
    return createHash('sha256').update(raw.trim().toUpperCase(), 'utf8').digest('hex');
}

/**
 * Busca empresa pelo hash da API Key — com cache de 60s.
 *
 * @param {string} keyHash SHA-256 hex da API Key recebida
 * @returns {Promise<{id: string, name: string}|null>}
 */
async function findCompanyByKeyHash(keyHash) {
    const cached = _cache.get(keyHash);
    if (cached && Date.now() < cached.expiresAt) {
        // Retorna o mesmo shape que o caminho de DB: { company, fbCreds }
        return { company: cached.company, fbCreds: cached.fbCreds ?? null };
    }

    try {
        // A tabela `companies` é gerenciada pela Coliseu.Identity API (EF Core).
        // Colunas com aspas duplas são case-sensitive (PascalCase do EF).
        // CompanyKeyHash = SHA-256(rawKey.Trim().ToUpperInvariant())
        // Status: 0 = Ativa, 1 = Inativa.
        const { rows } = await pgQuerySafe(
            `SELECT
                "Id"          AS id,
                "Name"        AS name,
                "FirebirdHost"         AS fb_host,
                3050                   AS fb_port,
                "FirebirdDatabasePath" AS fb_database,
                "FirebirdUser"         AS fb_user,
                "FirebirdPasswordEncrypted" AS fb_password,
                'WIN1252'              AS fb_charset,
                TRUE                   AS fb_wire_crypt
             FROM companies
             WHERE "CompanyKeyHash" = $1 AND "Status" = 0
             LIMIT 1`,
            [keyHash],
            6_000  // timeout 6s
        );

        const company = rows[0] ?? null;
        // BLOCKER-1 fix: separar dados seguros (id, name) de credenciais sensíveis (fb_password)
        // req.company terá apenas { id, name } — nunca credenciais do Firebird.
        const safePart  = company ? { id: company.id, name: company.name } : null;
        const fbCreds   = company ? {
            fb_host:      company.fb_host,
            fb_port:      company.fb_port,
            fb_database:  company.fb_database,
            fb_user:      company.fb_user,
            fb_password:  company.fb_password, // somente aqui, nunca em req.company
            fb_charset:   company.fb_charset,
            fb_wire_crypt: company.fb_wire_crypt,
        } : null;
        _cache.set(keyHash, { company: safePart, fbCreds, expiresAt: Date.now() + CACHE_TTL });
        return { company: safePart, fbCreds };
    } catch (err) {
        logger.error('[Auth] Falha ao consultar empresa no PostgreSQL pelo hash', { error: err.message });
        return { company: null, fbCreds: null };
    }
}

/**
 * Busca empresa pelo ID (usado na validação do JWT).
 * Cache de 60s.
 *
 * @param {string} companyId ID da empresa
 * @returns {Promise<{id: string, name: string}|null>}
 */
async function findCompanyById(companyId) {
    const cacheKey = `id-${companyId}`;
    const cached = _cache.get(cacheKey);
    if (cached && Date.now() < cached.expiresAt) {
        return cached.company;
    }

    try {
        const { rows } = await pgQuerySafe(
            `SELECT
                "Id"          AS id,
                "Name"        AS name
             FROM companies
             WHERE "Id" = $1 AND "Status" = 0
             LIMIT 1`,
            [companyId],
            6_000
        );

        const company = rows[0] ?? null;
        _cache.set(cacheKey, { company, expiresAt: Date.now() + CACHE_TTL });
        return company;
    } catch (err) {
        logger.error('[Auth] Falha ao consultar empresa no PostgreSQL pelo ID', { error: err.message });
        return null;
    }
}

/**
 * Middleware multi-tenant: valida API-Key e injeta req.company.
 *
 * Uso nas rotas:
 *   const { id: companyId, name } = req.company;
 *
 * @param {import('express').Request}  req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
async function requireApiKey(req, res, next) {
    const raw = req.headers['api-key'];

    if (!raw) {
        logger.warn('[Auth] Requisição sem API-Key', { ip: req.ip, path: req.path });
        return res.status(401).json({ error: 'Não autorizado', code: 'MISSING_API_KEY' });
    }

    const hash = sha256hex(raw);
    let { company, fbCreds } = await findCompanyByKeyHash(hash);
    if (company) {
        _fbCredsMap.set(req, fbCreds); // associa credenciais ao request sem poluir req.company
    }

    // BLOCKER-2 fix: fallback de mock APENAS em non-production.
    // Separado do fallback async para não bypassar auth em produção com SYNC_MODE=async.
    if (!company && process.env.NODE_ENV !== 'production') {
        const envKey = process.env.API_KEY;
        if (envKey && raw === envKey) {
            company = { id: 'dev-company-00000001', name: 'Empresa Local (dev)' };
            logger.warn('[Auth] PostgreSQL offline — usando API_KEY do .env como fallback (dev only)', { path: req.path });
        }
    }

    // Fallback VPS async: APENAS em ambientes não-produção.
    // Permite o Worker sincronizar enquanto o PG está sendo configurado em dev/staging.
    if (!company && process.env.NODE_ENV !== 'production' &&
        (process.env.SYNC_MODE === 'async' || process.env.FB_MOCK === 'true')) {
        const envKey      = process.env.API_KEY;
        const isPlaceholder = !envKey || envKey === 'fallback-not-used-in-production';
        if (!isPlaceholder && raw === envKey) {
            const companyId = process.env.COMPANY_ID || 'vps-company-00000001';
            company = { id: companyId, name: 'Empresa VPS (fallback)' };
            logger.warn('[Auth] PostgreSQL offline — usando API_KEY do .env como fallback (async/mock)', {
                path: req.path, companyId,
                fix: 'Configure PG_PASSWORD correto no Coolify e registre a empresa no Identity.',
            });
        }
    }

    if (!company) {
        logger.warn('[Auth] API-Key inválida ou empresa inativa', {
            ip: req.ip, path: req.path, keyPrefix: raw.substring(0, 6) + '…',
        });
        return res.status(401).json({ error: 'Não autorizado', code: 'INVALID_API_KEY' });
    }

    req.company = company;   // { id, name }
    logger.debug('[Auth] Autenticado (API-Key)', { companyId: company.id, name: company.name, path: req.path });
    next();
}

/**
 * Middleware para validar JWT do Dispositivo (Mobile App).
 * 
 * 1. Extrai header Authorization: Bearer <token>
 * 2. Valida assinatura HMAC usando JWT_ACCESS_SECRET
 * 3. Extrai o "tenant" (companyId) do token
 * 4. Valida se a empresa está ativa no PostgreSQL
 * 5. Injeta req.company e req.device
 *
 * @param {import('express').Request}  req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
async function requireDeviceJwt(req, res, next) {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        logger.warn('[Auth] Requisição sem token JWT (Bearer)', { ip: req.ip, path: req.path });
        return res.status(401).json({ error: 'Não autorizado', code: 'MISSING_JWT' });
    }

    const token = authHeader.substring(7); // Remove 'Bearer '

    try {
        const secret = config.security.jwtAccessSecret;
        const decoded = jwt.verify(token, secret);

        // Coliseu.Identity injeta o company_id no claim 'tenantId'
        const companyId = decoded.tenantId || decoded.tenant;
        const deviceId = decoded.deviceId || decoded.device_id;

        if (!companyId) {
            logger.warn('[Auth] JWT inválido: sem claim tenant', { ip: req.ip, path: req.path });
            return res.status(401).json({ error: 'Não autorizado', code: 'INVALID_TOKEN_CLAIMS' });
        }

        const company = await findCompanyById(companyId);

        if (!company) {
            logger.warn('[Auth] Empresa inativa ou não encontrada após verificação do JWT', {
                ip: req.ip, path: req.path, companyId
            });
            return res.status(401).json({ error: 'Não autorizado', code: 'COMPANY_INACTIVE' });
        }


        req.company = company;
        req.device = { id: deviceId };

        logger.info('[Auth] Autenticado (Device JWT)', {
            companyId: company.id,
            deviceId: deviceId,
            path: req.path
        });
        next();
    } catch (err) {
        if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
            logger.warn('[Auth] JWT inválido ou expirado', {
                ip: req.ip,
                path: req.path,
                error: err.message
            });
            return res.status(401).json({ error: 'Sessão expirada. Faça login novamente.', code: 'INVALID_JWT' });
        }

        // Se for erro de banco (PostgreSQL offline, senha errada), retorna 500 e não 401
        logger.error('[Auth] Erro interno ao validar token', { error: err.message });
        return res.status(500).json({ error: 'Erro interno no servidor (Banco de Dados)', code: 'INTERNAL_DB_ERROR' });
    }
}

/**
 * Invalida o cache de autenticação de uma empresa (use após rotação de chave).
 * @param {string} keyHash
 */
function invalidateAuthCache(keyHash) {
    _cache.delete(keyHash);
}

// Modo MOCK (para testes sem PostgreSQL)
// Se FB_MOCK=true, injeta empresa de dev sem consultar o PG.
function requireApiKeyMock(req, res, next) {
    req.company = { id: 'aaaaaaaa-0000-0000-0000-000000000001', name: 'Empresa Demo A' };
    next();
}

/**
 * Middleware misto para rotas de Sincronização.
 * 
 * Se vier Header "Authorization: Bearer <token>", usa validação JWT (Mobile App).
 * Caso contrário, cai para o "api-key" clássico (Worker).
 * 
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
async function authenticateSyncRequest(req, res, next) {
    logger.info('[Auth] incoming sync request', {
        path: req.path,
        authHeaderPresent: !!req.headers.authorization,
        apiKeyPresent: !!req.headers['api-key']
    });

    if (req.headers.authorization && req.headers.authorization.startsWith('Bearer ')) {
        return requireDeviceJwt(req, res, next);
    }
    return requireApiKey(req, res, next);
}

// NOTA: FB_MOCK controla apenas conexões Firebird, NÃO a autenticação.
// A autenticação SEMPRE usa a tabela companies do coliseu_identity (Identity API).
// requireApiKeyMock é mantido apenas para testes unitários locais sem PG.
module.exports = {
    requireApiKey,
    requireDeviceJwt,
    authenticateSyncRequest,
    requireApiKeyMock,
    invalidateAuthCache,
    sha256hex,
    getFirebirdCreds,  // exportado para uso em rotas que precisam de credenciais Firebird
};
