/**
 * Validação da licença do módulo Estoque no Coliseu.Identity.
 *
 * Mesmo contrato usado pelo Vision: o Worker envia a chave do módulo (COL-XXXX-XXXX-XXXX)
 * e o tenant (Serial da empresa); a API confirma em
 *   POST /internal/companies/{tenant}/modules/{slug}/validate-key
 *
 * Cache: resultado positivo vale LICENSE_CACHE_TTL_SECONDS. Se o Identity estiver
 * fora do ar, a última validação positiva continua aceita por LICENSE_GRACE_HOURS —
 * uma instabilidade no painel não pode parar a expedição do cliente. Uma resposta
 * NEGATIVA do Identity (licença suspensa, chave errada) derruba o acesso na hora.
 */
'use strict';

const crypto = require('node:crypto');
const config = require('../config');
const log = require('../log');
const db = require('../db');

/** SHA-256(UPPER(TRIM(chave))) — idêntico ao CompanyKeyGenerator.HashKey do Identity. */
function hashKey(raw) {
    return crypto.createHash('sha256').update(String(raw).trim().toUpperCase(), 'utf8').digest('hex');
}

const cache = new Map(); // `${tenant}|${hash}` → { valid, reason, checkedAt }

async function callIdentity(path, init) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 6_000);
    try {
        const res = await fetch(`${config.identity.baseUrl}${path}`, {
            ...init,
            headers: {
                'Content-Type': 'application/json',
                'X-Internal-Api-Key': config.identity.internalApiKey,
                ...(init?.headers || {}),
            },
            signal: ctrl.signal,
        });
        const body = await res.json().catch(() => ({}));
        return { status: res.status, body };
    } finally {
        clearTimeout(timer);
    }
}

/**
 * @returns {Promise<{valid: boolean, reason?: string, companyName?: string, deviceLimit?: number}>}
 */
async function validateModuleKey(tenantId, rawKey) {
    const keyHash = hashKey(rawKey);
    const cacheKey = `${tenantId}|${keyHash}`;
    const now = Date.now();
    const hit = cache.get(cacheKey);
    if (hit && now - hit.checkedAt < config.identity.cacheTtlMs) return hit;

    const slug = encodeURIComponent(config.identity.moduleSlug);
    try {
        const { status, body } = await callIdentity(
            `/internal/companies/${tenantId}/modules/${slug}/validate-key`,
            { method: 'POST', body: JSON.stringify({ apiKey: String(rawKey).trim() }) },
        );

        if (status >= 500) throw new Error(`Identity respondeu ${status}`);

        let result;
        if (status === 200 && body.valid) {
            const info = await callIdentity(`/internal/companies/${tenantId}/modules/${slug}/info`, { method: 'GET' })
                .catch(() => ({ body: {} }));
            result = {
                valid: true,
                companyName: info.body?.nomeDaEmpresa,
                deviceLimit: info.body?.deviceLimit,
                checkedAt: now,
            };
            await rememberTenant(tenantId, keyHash, result.companyName);
        } else {
            result = { valid: false, reason: body.reason || body.error || `Licença recusada (${status})`, checkedAt: now };
            await db.query('UPDATE tenants SET license_valid = FALSE, license_checked_at = now() WHERE id = $1', [tenantId])
                .catch(() => {});
        }
        cache.set(cacheKey, result);
        return result;
    } catch (err) {
        // Identity indisponível: aplica o período de carência sobre a última validação positiva.
        const lastGood = hit?.valid ? hit : await lastPositiveFromDb(tenantId, keyHash);
        if (lastGood && now - lastGood.checkedAt < config.identity.graceMs) {
            log.warn('[Licença] Identity indisponível — usando validação anterior (carência)', {
                tenantId, error: err.message,
            });
            return { ...lastGood, grace: true };
        }
        log.error('[Licença] Identity indisponível e sem validação anterior', { tenantId, error: err.message });
        return { valid: false, reason: 'Servidor de licenças indisponível. Tente novamente em instantes.' };
    }
}

async function rememberTenant(tenantId, keyHash, name) {
    await db.query(
        `INSERT INTO tenants (id, name, key_hash, license_checked_at, license_valid)
         VALUES ($1, COALESCE($3, ''), $2, now(), TRUE)
         ON CONFLICT (id) DO UPDATE
            SET key_hash = EXCLUDED.key_hash,
                name = COALESCE(NULLIF($3, ''), tenants.name),
                license_checked_at = now(),
                license_valid = TRUE`,
        [tenantId, keyHash, name ?? null],
    );
}

async function lastPositiveFromDb(tenantId, keyHash) {
    const { rows } = await db.query(
        'SELECT name, license_checked_at FROM tenants WHERE id = $1 AND key_hash = $2 AND license_valid',
        [tenantId, keyHash],
    ).catch(() => ({ rows: [] }));
    if (!rows[0]?.license_checked_at) return null;
    return { valid: true, companyName: rows[0].name, checkedAt: new Date(rows[0].license_checked_at).getTime() };
}

/** Licença de um tenant já registrado (usada nos logins do app/dashboard). */
async function isTenantLicensed(tenantId) {
    const { rows } = await db.query('SELECT license_valid, license_checked_at FROM tenants WHERE id = $1', [tenantId]);
    return rows[0]?.license_valid === true;
}

module.exports = { hashKey, validateModuleKey, isTenantLicensed };
