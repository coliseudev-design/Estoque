/**
 * Configurações da conferência por empresa (tenants.settings JSONB).
 */
'use strict';

const db = require('../db');

const DEFAULTS = Object.freeze({
    // Recontagens permitidas ao operador antes de exigir aprovação do supervisor.
    maxRecounts: 1,
    // Duração da reserva de um documento por um operador. Renovada a cada leitura.
    lockMinutes: 120,
    // Permite digitar a quantidade (ex.: 24) em vez de bipar unidade por unidade.
    allowManualQty: true,
    // Exige justificativa ao aprovar documento com divergência.
    requireJustification: true,
    // Mostra ao operador quais produtos compõem o documento (sem quantidades).
    // Desligado = conferência "às cegas" total: operador só bipa.
    showItemList: true,
    // Dias de documentos mantidos na fila (os mais antigos somem da lista padrão).
    queueDays: 7,
});

const cache = new Map();
const TTL = 30_000;

async function getSettings(tenantId) {
    const hit = cache.get(tenantId);
    if (hit && Date.now() - hit.at < TTL) return hit.value;
    const { rows } = await db.query('SELECT settings FROM tenants WHERE id = $1', [tenantId]);
    const value = { ...DEFAULTS, ...(rows[0]?.settings || {}) };
    cache.set(tenantId, { value, at: Date.now() });
    return value;
}

async function updateSettings(tenantId, patch) {
    const allowed = Object.fromEntries(Object.entries(patch).filter(([k]) => k in DEFAULTS));
    await db.query('UPDATE tenants SET settings = settings || $2::jsonb WHERE id = $1', [tenantId, JSON.stringify(allowed)]);
    cache.delete(tenantId);
    return getSettings(tenantId);
}

module.exports = { DEFAULTS, getSettings, updateSettings };
