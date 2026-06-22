/**
 * dataStore.js — Store multi-tenant via Redis com cache warming (P2-D).
 *
 * Cache warming: ao startup ou quando Redis retorna vazio, o middleware
 * pode re-popular os dados de outras fontes (atualmente Redis-only;
 * em versões futuras poderia ler de um backup PG se necessário).
 *
 * API pública:
 *   upsert(companyId, entity, data)      — Worker faz push de dados
 *   get(companyId, entity)               — App lê dados cacheados
 *   getSyncedAt(companyId, entity)       — Timestamp da última sync
 *   getStatus(companyId)                 — Status do cache por empresa
 *
 * @module services/dataStore
 */
'use strict';

const { redisSet, redisGet, redisSyncedAt, client: redisClient } = require('../db/redis');
const logger = require('../config/logger');

const VALID_ENTITIES = new Set([
    'products', 'sellers', 'customers',
    'paymentSpecies', 'paymentConditions',
    'natureza', 'financials', 'performance',
    'sales-rankings', 'priceTables', 'productPrices',
]);

/**
 * Armazena (ou atualiza) dados de uma entidade para uma empresa.
 * Chamado pelo Worker via POST /api/sync/*.
 *
 * @param {string} companyId UUID da empresa
 * @param {string} entity    Nome da entidade
 * @param {Array}  data      Array de objetos a armazenar
 * @returns {Promise<{count: number, syncedAt: string}>}
 */
async function upsert(companyId, entity, data) {
    if (!VALID_ENTITIES.has(entity)) {
        throw new TypeError(`dataStore.upsert: entidade inválida "${entity}"`);
    }
    if (!Array.isArray(data)) {
        throw new TypeError(`dataStore.upsert: data deve ser Array (recebido ${typeof data})`);
    }

    const now = new Date().toISOString();
    await redisSet(companyId, entity, data);
    logger.info(`[DataStore] ${entity} atualizado`, { companyId, count: data.length });
    return { count: data.length, syncedAt: now };
}

/**
 * Recupera dados cacheados de uma entidade para uma empresa.
 *
 * @param {string} companyId
 * @param {string} entity
 * @returns {Promise<{data: Array, syncedAt: string|null, source: 'redis'|'empty'}>}
 */
async function get(companyId, entity) {
    const { redisPing } = require('../db/redis');
    const isUp = await redisPing();

    if (!isUp) {
        logger.warn('[DataStore] Redis offline. Pulando cache devolvendo Vazio.');
        return { data: [], syncedAt: null, source: 'empty' };
    }

    const data = await redisGet(companyId, entity);
    const syncedAt = data ? await redisSyncedAt(companyId, entity) : null;

    if (data && data.length > 0) {
        return { data, syncedAt, source: 'redis' };
    }
    return { data: [], syncedAt: null, source: 'empty' };
}

/**
 * Cache warming (P2-D): re-populate Redis para uma empresa a partir
 * de uma lista de entidades+dados fornecida externamente.
 *
 * Uso: chamado pelo Worker ao reconectar (após restart do middleware)
 * via POST /api/sync/* para cada entidade. O warming é automático
 * pois o upsert() já persiste no Redis com TTL 24h.
 *
 * Esta função permite forçar um warming de forma programática
 * (ex: ao detectar Redis recém-conectado após restart).
 *
 * @param {string}  companyId
 * @param {object}  snapshot — { products: [], sellers: [], ... }
 * @returns {Promise<{warmed: string[]}>}
 */
async function warmCache(companyId, snapshot) {
    const warmed = [];
    for (const [entity, data] of Object.entries(snapshot)) {
        if (!VALID_ENTITIES.has(entity)) continue;
        if (!Array.isArray(data) || data.length === 0) continue;
        await redisSet(companyId, entity, data);
        warmed.push(entity);
    }
    logger.info('[DataStore] Cache warming concluído', { companyId, warmed });
    return { warmed };
}

/**
 * Retorna status do cache para uma empresa (todas as entidades).
 *
 * @param {string} companyId
 * @returns {Promise<object>} { entity: { cached: bool, syncedAt } }
 */
async function getStatus(companyId) {
    const result = {};
    for (const entity of VALID_ENTITIES) {
        const syncedAt = await redisSyncedAt(companyId, entity);
        result[entity] = { cached: !!syncedAt, syncedAt };
    }
    return result;
}

module.exports = { upsert, get, warmCache, getStatus };
