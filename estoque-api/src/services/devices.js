/**
 * Aparelhos do app pareados pelo painel (QR Code / código de uso único).
 *
 *   1. supervisor → createPairing()  código XXXX-XXXX, válido por PAIRING_MINUTES
 *   2. app        → pair(code)       troca o código por { deviceId, secret } (uma vez)
 *   3. operador   → authenticate()   X-Device-Key: <deviceId>:<secret> + usuário + PIN
 *
 * Só hashes ficam no banco: o código aparece apenas na tela do supervisor e o
 * segredo apenas no aparelho.
 */
'use strict';

const crypto = require('node:crypto');
const db = require('../db');
const { audit } = require('./audit');
const { notFound, conflict, unauthorized, badRequest } = require('../http');

const PAIRING_MINUTES = 10;
// Sem 0/O, 1/I/L: o código também é digitado no celular.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const sha256 = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');
const normalizeCode = (c) => String(c || '').toUpperCase().replace(/[^A-Z0-9]/g, '');

function newCode() {
    const bytes = crypto.randomBytes(8);
    const raw = [...bytes].map((b) => ALPHABET[b % ALPHABET.length]).join('');
    return `${raw.slice(0, 4)}-${raw.slice(4)}`;
}

async function createPairing(tenantId, user, name) {
    const code = newCode();
    const { rows: [p] } = await db.query(
        `INSERT INTO device_pairings (code_hash, tenant_id, name, created_by, expires_at)
         VALUES ($1, $2, $3, $4, now() + ($5 || ' minutes')::interval)
         RETURNING expires_at`,
        [sha256(normalizeCode(code)), tenantId, name || '', user.id, String(PAIRING_MINUTES)],
    );
    await audit(null, { tenantId, userId: user.id, action: 'device.pairing_created', details: { name } });
    return { code, expiresAt: p.expires_at, minutes: PAIRING_MINUTES };
}

/** App troca o código pela credencial do aparelho. Código vale uma vez. */
async function pair({ code, deviceUuid, model, os, appVersion }) {
    const hash = sha256(normalizeCode(code));
    const secret = crypto.randomBytes(32).toString('base64url');
    return db.tx(async (client) => {
        const { rows: [p] } = await client.query(
            `SELECT p.*, t.name AS company_name, t.license_valid
               FROM device_pairings p JOIN tenants t ON t.id = p.tenant_id
              WHERE p.code_hash = $1 FOR UPDATE OF p`,
            [hash],
        );
        if (!p) throw notFound('Código de pareamento inválido. Gere um novo no painel (Aparelhos).');
        if (p.used_at) throw conflict('Este código já foi usado. Gere um novo no painel.', 'PAIRING_USED');
        if (new Date(p.expires_at) < new Date()) throw conflict('Código expirado. Gere um novo no painel.', 'PAIRING_EXPIRED');
        if (!p.license_valid) throw conflict('Licença do módulo Estoque suspensa para esta empresa.', 'LICENSE_DENIED');

        const { rows: [d] } = await client.query(
            `INSERT INTO devices (tenant_id, name, device_uuid, model, os, app_version, secret_hash, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
            [p.tenant_id, p.name || model || 'Aparelho', deviceUuid || null, model || null, os || null, appVersion || null,
                sha256(secret), p.created_by],
        );
        await client.query('UPDATE device_pairings SET used_at = now(), device_id = $2 WHERE code_hash = $1', [hash, d.id]);
        await audit(client, { tenantId: p.tenant_id, userId: p.created_by, action: 'device.paired',
            details: { deviceId: d.id, model, os } });
        return { deviceId: d.id, deviceKey: `${d.id}:${secret}`, tenantId: p.tenant_id, companyName: p.company_name || '' };
    });
}

/** Valida o header X-Device-Key. Devolve o aparelho (com tenant) ou lança 401. */
async function authenticate(header) {
    const [id, secret] = String(header || '').split(':');
    if (!id || !secret || !/^[0-9a-f-]{36}$/i.test(id)) throw unauthorized('Aparelho não pareado', 'DEVICE_NOT_PAIRED');
    const { rows: [d] } = await db.query('SELECT id, tenant_id, secret_hash, revoked_at FROM devices WHERE id = $1', [id]);
    const ok = d && crypto.timingSafeEqual(Buffer.from(d.secret_hash), Buffer.from(sha256(secret)));
    if (!ok) throw unauthorized('Aparelho não reconhecido. Pareie de novo pelo painel.', 'DEVICE_NOT_PAIRED');
    if (d.revoked_at) throw unauthorized('Este aparelho foi desvinculado no painel. Pareie de novo.', 'DEVICE_REVOKED');
    return d;
}

async function touch(deviceId, userId, appVersion) {
    await db.query(
        'UPDATE devices SET last_seen_at = now(), last_user_id = COALESCE($2, last_user_id), app_version = COALESCE($3, app_version) WHERE id = $1',
        [deviceId, userId || null, appVersion || null],
    );
}

// Revogação vale também para sessões já abertas: o middleware consulta isto (cache curto).
const revokedCache = new Map();
async function isRevoked(deviceId) {
    // Id do Identity pode não ser UUID (ANDROID_ID): esses não são pareados aqui.
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(deviceId)) return false;
    const hit = revokedCache.get(deviceId);
    if (hit && Date.now() - hit.at < 30_000) return hit.revoked;
    const { rows } = await db.query('SELECT revoked_at FROM devices WHERE id = $1', [deviceId]);
    // Aparelho ativado pelo Identity não está nesta tabela: não é revogado aqui.
    const revoked = Boolean(rows[0]?.revoked_at);
    revokedCache.set(deviceId, { revoked, at: Date.now() });
    return revoked;
}

async function list(tenantId) {
    const { rows } = await db.query(
        `SELECT d.id, d.name, d.model, d.os, d.app_version, d.created_at, d.last_seen_at, d.revoked_at,
                u.name AS last_user_name, c.name AS created_by_name
           FROM devices d
           LEFT JOIN users u ON u.id = d.last_user_id
           LEFT JOIN users c ON c.id = d.created_by
          WHERE d.tenant_id = $1
          ORDER BY d.revoked_at IS NOT NULL, d.last_seen_at DESC NULLS LAST, d.created_at DESC`,
        [tenantId],
    );
    return rows;
}

async function revoke(tenantId, user, id) {
    const { rowCount } = await db.query(
        'UPDATE devices SET revoked_at = now(), revoked_by = $3 WHERE tenant_id = $1 AND id = $2 AND revoked_at IS NULL',
        [tenantId, id, user.id],
    );
    if (!rowCount) throw notFound('Aparelho não encontrado ou já desvinculado');
    revokedCache.delete(id);
    await audit(null, { tenantId, userId: user.id, action: 'device.revoked', details: { deviceId: id } });
}

async function rename(tenantId, user, id, name) {
    if (!name?.trim()) throw badRequest('Informe o nome');
    const { rowCount } = await db.query('UPDATE devices SET name = $3 WHERE tenant_id = $1 AND id = $2', [tenantId, id, name.trim()]);
    if (!rowCount) throw notFound('Aparelho não encontrado');
}

module.exports = { createPairing, pair, authenticate, touch, isRevoked, list, revoke, rename, normalizeCode, newCode, PAIRING_MINUTES };
