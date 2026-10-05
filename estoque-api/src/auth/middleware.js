/**
 * Middlewares de autenticação.
 *
 *  requireWorker  — Worker local (Windows). Headers iguais aos do Vision:
 *                   X-Internal-Key: COL-XXXX-XXXX-XXXX  (chave do módulo Estoque)
 *                   X-Tenant-Id:    <Serial da empresa>
 *  requireUser    — app e dashboard. Authorization: Bearer <token da API>.
 */
'use strict';

const { validateModuleKey } = require('./license');
const { verifyUserToken } = require('./tokens');
const { unauthorized, forbidden } = require('../http');
const db = require('../db');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function requireWorker(req, res, next) {
    try {
        const key = req.get('X-Internal-Key');
        const tenantId = req.get('X-Tenant-Id');
        if (!key || !tenantId || !UUID_RE.test(tenantId)) {
            throw unauthorized('Informe X-Internal-Key e X-Tenant-Id', 'MISSING_LICENSE');
        }
        const lic = await validateModuleKey(tenantId, key);
        if (!lic.valid) throw forbidden(lic.reason || 'Licença inválida', 'LICENSE_DENIED');
        req.tenantId = tenantId.toLowerCase();
        next();
    } catch (err) {
        next(err);
    }
}

// Cache curto do estado do usuário: desativar um operador corta o acesso em até 30 s
// sem custar uma consulta por requisição de bipagem.
const userCache = new Map();
const USER_TTL = 30_000;

async function loadUser(userId) {
    const hit = userCache.get(userId);
    if (hit && Date.now() - hit.at < USER_TTL) return hit.user;
    const { rows } = await db.query(
        `SELECT u.id, u.tenant_id, u.name, u.login, u.role, u.active, t.license_valid
           FROM users u JOIN tenants t ON t.id = u.tenant_id
          WHERE u.id = $1`,
        [userId],
    );
    const user = rows[0] || null;
    userCache.set(userId, { user, at: Date.now() });
    return user;
}

function extractToken(req, allowQuery) {
    const header = req.get('Authorization');
    if (header?.startsWith('Bearer ')) return header.slice(7);
    // EventSource não envia headers: o stream SSE aceita o token na query.
    if (allowQuery && typeof req.query.access_token === 'string') return req.query.access_token;
    return null;
}

/**
 * @param {...('operador'|'supervisor'|'admin')} roles  vazio = qualquer papel
 */
function requireUser(...roles) {
    const allowQuery = roles.includes('__query');
    const allowed = roles.filter((r) => r !== '__query');
    return async (req, res, next) => {
        try {
            const token = extractToken(req, allowQuery);
            if (!token) throw unauthorized('Sessão não informada', 'MISSING_TOKEN');
            let claims;
            try {
                claims = verifyUserToken(token);
            } catch {
                throw unauthorized('Sessão expirada. Entre novamente.', 'INVALID_TOKEN');
            }
            const user = await loadUser(claims.uid);
            if (!user || !user.active || user.tenant_id !== claims.tid) {
                throw unauthorized('Usuário inativo ou removido', 'USER_INACTIVE');
            }
            if (!user.license_valid) throw forbidden('Licença do módulo Estoque suspensa', 'LICENSE_DENIED');
            if (allowed.length && !allowed.includes(user.role)) throw forbidden();

            req.tenantId = user.tenant_id;
            req.user = { id: user.id, name: user.name, login: user.login, role: user.role };
            req.deviceId = claims.dev || null;
            next();
        } catch (err) {
            next(err);
        }
    };
}

const invalidateUser = (userId) => userCache.delete(userId);

/** Supervisor e admin enxergam quantidades esperadas; operador faz conferência cega. */
const canSeeExpected = (user) => user.role === 'supervisor' || user.role === 'admin';

module.exports = { requireWorker, requireUser, invalidateUser, canSeeExpected, UUID_RE };
