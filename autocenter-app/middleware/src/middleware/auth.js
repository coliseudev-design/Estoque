'use strict';

const jwt = require('jsonwebtoken');
const config = require('../config/env');
const logger = require('../config/logger');

/**
 * Middleware para validar JWT do Dispositivo (Mobile App AutoCenter).
 * 
 * 1. Extrai header Authorization: Bearer <token>
 * 2. Valida assinatura HMAC usando JWT_DEVICE_KEY
 * 3. Valida se o claim module == 'autocenter' (Evita usar token do Sales no AutoCenter)
 * 4. Injeta req.tenant e req.device
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

    const token = authHeader.substring(7);

    try {
        const secret = config.security.jwtDeviceKey;
        const decoded = jwt.verify(token, secret);

        // Claims esperados do Coliseu.Identity
        const tenantId = decoded.tenantId || decoded.tenant;
        const deviceId = decoded.deviceId || decoded.device_id;
        const moduleSlug = decoded.module;

        if (!tenantId || !deviceId) {
            logger.warn('[Auth] JWT inválido: sem claim tenant ou device', { ip: req.ip, path: req.path });
            return res.status(401).json({ error: 'Token inválido', code: 'INVALID_TOKEN_CLAIMS' });
        }

        // Feature exclusiva multi-módulo (Fase 2): Garante que um token do Sales não abra o AutoCenter
        if (moduleSlug !== config.security.expectedModuleSlug) {
            logger.warn('[Auth] Módulo não autorizado para este token', { 
                ip: req.ip, 
                path: req.path, 
                tokenModule: moduleSlug, 
                expected: config.security.expectedModuleSlug 
            });
            return res.status(403).json({ error: 'Módulo de acesso incorreto', code: 'INVALID_MODULE' });
        }

        // No AutoCenter, injetamos `req.tenant` e `req.device` nas rotas
        req.tenant = { id: tenantId, name: decoded.companyName || 'Unknown Company' };
        req.device = { id: deviceId };

        const tokenBranchId = decoded.branchId;
        const headerBranchId = req.headers['x-branch-id'];
        const finalBranchId = headerBranchId || tokenBranchId;

        if (finalBranchId) {
            req.branch = { id: finalBranchId };
        }

        next();
    } catch (err) {
        if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
            logger.warn('[Auth] JWT inválido ou expirado', {
                ip: req.ip,
                path: req.path,
                error: err.message
            });
            return res.status(401).json({ error: 'Sessão expirada. Faça ativação novamente.', code: 'INVALID_JWT' });
        }

        logger.error('[Auth] Erro interno ao validar token', { error: err.message });
        return res.status(500).json({ error: 'Erro interno no servidor', code: 'INTERNAL_ERROR' });
    }
}

/**
 * Middleware para autenticar rotas internas usadas pelo Worker (.NET).
 * 
 * Valida o header X-Internal-Key contra a chave configurada no servidor.
 * Extrai o tenantId do header X-Tenant-Id (enviado pelo Worker).
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
// Cache em memória (TenantId -> { valid: boolean, expiresAt: number })
// Usado para evitar sobrecarregar o servidor de licenças nas chamadas frequentes do Worker.
const validationCache = new Map();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutos

/**
 * Middleware para autenticar rotas internas usadas pelo Worker (.NET).
 * 
 * Valida o header X-Internal-Key de forma dinâmica contra a API de Identidade.
 *
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
async function requireInternalAuth(req, res, next) {
    const internalKey = req.headers['x-internal-key'] || req.headers['x-internal-api-key'];
    const tenantId    = req.headers['x-tenant-id'];
    const branchId    = req.headers['x-branch-id'];

    if (branchId) {
        req.branch = { id: branchId };
    }

    if (!tenantId) {
        logger.warn('[InternalAuth] Header X-Tenant-Id ausente', { ip: req.ip, path: req.path });
        return res.status(400).json({ error: 'X-Tenant-Id é obrigatório para rotas internas.', code: 'MISSING_TENANT' });
    }

    if (!internalKey) {
        logger.warn('[InternalAuth] Chave interna ausente', { ip: req.ip, path: req.path });
        return res.status(401).json({ error: 'Não autorizado', code: 'INVALID_INTERNAL_KEY' });
    }

    const { identityApiUrl, identityInternalKey, expectedModuleSlug } = config.security;

    // Se as chaves do Identity não estiverem configuradas, rejeita a conexão.
    if (!identityApiUrl || !identityInternalKey) {
        logger.error('[InternalAuth] Configuração de validação do Identity ausente (IDENTITY_API_URL/IDENTITY_INTERNAL_KEY)');
        return res.status(500).json({ error: 'Serviço de validação de licenças não configurado.', code: 'CONFIG_ERROR' });
    }

    const cacheKey = `${tenantId}:${internalKey}`;
    const cached = validationCache.get(cacheKey);

    if (cached && cached.expiresAt > Date.now()) {
        if (!cached.valid) {
            logger.warn('[InternalAuth] Bloqueio pelo cache dinâmico', { ip: req.ip, tenantId, reason: cached.reason });
            return res.status(403).json({ error: cached.reason || 'Módulo bloqueado ou chave inválida', code: 'MODULE_BLOCKED' });
        }
        req.tenant = { id: tenantId };
        req.device = { id: 'worker' };
        return next();
    }

    try {
        const response = await fetch(`${identityApiUrl}/internal/companies/${tenantId}/modules/${expectedModuleSlug}/validate-key`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Internal-Api-Key': identityInternalKey
            },
            body: JSON.stringify({ apiKey: internalKey }),
            signal: AbortSignal.timeout(3000)
        });

        if (response.status === 200) {
            const data = await response.json();
            if (data.valid) {
                validationCache.set(cacheKey, { valid: true, expiresAt: Date.now() + CACHE_TTL_MS });
                req.tenant = { id: tenantId };
                req.device = { id: 'worker' };
                return next();
            }
        }

        if (response.status === 403) {
            const data = await response.json().catch(() => ({}));
            const reason = data.reason || data.Reason || data.error || data.Error || 'Módulo bloqueado (HTTP 403).';
            logger.warn(`[InternalAuth] Identity retornou 403 para tenant ${tenantId}:`, data);
            
            validationCache.set(cacheKey, { valid: false, reason, expiresAt: Date.now() + CACHE_TTL_MS });
            return res.status(403).json({ error: reason, code: 'MODULE_BLOCKED' });
        }

        throw new Error(`Identity API retornou status ${response.status}`);
        
    } catch (err) {
        logger.error('[InternalAuth] Erro ao validar no Identity API', { err: err.message, tenantId });
        return res.status(503).json({ error: 'Falha na comunicação com controle de licenças', code: 'IDENTITY_API_ERROR' });
    }
}

module.exports = {
    requireDeviceJwt,
    requireInternalAuth
};
