/**
 * Tokens:
 *  - Token da API (emitido aqui): identifica o USUÁRIO (operador/supervisor/admin)
 *    tanto no app quanto no dashboard. Claims: tid, uid, role, dev.
 *  - JWT de dispositivo (emitido pelo Coliseu.Identity no /auth/device-login):
 *    prova que o aparelho está licenciado para o módulo Estoque. Só é aceito
 *    no login do operador pelo app.
 */
'use strict';

const jwt = require('jsonwebtoken');
const config = require('../config');

const ISSUER = 'coliseu-estoque';

function signUserToken({ tenantId, userId, role, deviceId }) {
    return jwt.sign(
        { tid: tenantId, uid: userId, role, dev: deviceId || null },
        config.security.apiJwtSecret,
        { expiresIn: config.security.apiJwtTtl, issuer: ISSUER },
    );
}

function verifyUserToken(token) {
    return jwt.verify(token, config.security.apiJwtSecret, { issuer: ISSUER });
}

/**
 * Valida o JWT de dispositivo do Identity e confere se foi emitido para o módulo Estoque.
 * @returns {{ tenantId: string, deviceId: string }}
 */
function verifyDeviceToken(token) {
    const claims = jwt.verify(token, config.security.identityJwtSecret);
    const tenantId = claims.tenantId || claims.tenant;
    const deviceId = claims.deviceId || claims.device_id;
    const module = claims.module || claims.moduleSlug || claims.module_slug;
    if (!tenantId || !deviceId) throw new Error('JWT de dispositivo sem tenant/dispositivo');
    if (module && module !== config.identity.moduleSlug) {
        throw new Error(`JWT emitido para o módulo '${module}', esperado '${config.identity.moduleSlug}'`);
    }
    return { tenantId, deviceId };
}

module.exports = { signUserToken, verifyUserToken, verifyDeviceToken };
