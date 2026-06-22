/**
 * dataStore.js â€” Store multi-tenant via Redis com cache warming (P2-D).
 *
 * Cache warming: ao startup ou quando Redis retorna vazio, o middleware
 * pode re-popular os dados de outras fontes (atualmente Redis-only;
 * em versÃµes futuras poderia ler de um backup PG se necessÃ¡rio).
 *
 * API pÃºblica:
 *   upsert(companyId, entity, data)      â€” Worker faz push de dados
 *   get(companyId, entity)               â€” App lÃª dados cacheados
 *   getSyncedAt(companyId, entity)       â€” Timestamp da Ãºltima sync
 *   getStatus(companyId)                 â€” Status do cache por empresa
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
    'company-data'
]);

const BRANCH_SCOPED_ENTITIES = new Set([
    'products', 'financials', 'performance', 'sales-rankings'
]);

/**
 * Armazena (ou atualiza) dados de uma entidade para uma empresa.
 * Chamado pelo Worker via POST /api/sync/*.
 *
 * @param {string} companyId UUID da empresa
 * @param {string} entity    Nome da entidade
 * @param {Array}  data      Array de objetos a armazenar
 * @param {string} [branchId] Opcional: UUID da filial
 * @returns {Promise<{count: number, syncedAt: string}>}
 */
async function upsert(companyId, entity, data, branchId = null) {
    if (!VALID_ENTITIES.has(entity)) {
        throw new TypeError(`dataStore.upsert: entidade invÃ¡lida "${entity}"`);
    }
    if (!Array.isArray(data)) {
        throw new TypeError(`dataStore.upsert: data deve ser Array (recebido ${typeof data})`);
    }
    
    // Se a entidade Ã© isolada por filial, certifique-se de usar o branchId.
    const resolvedBranchId = BRANCH_SCOPED_ENTITIES.has(entity) ? branchId : null;

    const now = new Date().toISOString();
    await redisSet(companyId, entity, data, 86400, resolvedBranchId);
    logger.info(`[DataStore] ${entity} atualizado`, { companyId, branchId: resolvedBranchId, count: data.length });
    return { count: data.length, syncedAt: now };
}

/**
 * Recupera dados cacheados de uma entidade para uma empresa.
 *
 * @param {string} companyId
 * @param {string} entity
 * @param {string} [branchId] Opcional: UUID da filial
 * @returns {Promise<{data: Array, syncedAt: string|null, source: 'redis'|'empty'}>}
 */
async function get(companyId, entity, branchId = null) {
    const { redisPing } = require('../db/redis');
    const isUp = await redisPing();

    if (!isUp) {
        logger.warn('[DataStore] Redis offline. Pulando cache devolvendo Vazio.');
        return { data: [], syncedAt: null, source: 'empty' };
    }

    const resolvedBranchId = BRANCH_SCOPED_ENTITIES.has(entity) ? branchId : null;

    let data = await redisGet(companyId, entity, resolvedBranchId);
    let syncedAt = data ? await redisSyncedAt(companyId, entity, resolvedBranchId) : null;

    // Fallback para cache global (branchId = null) ou qualquer filial se a consulta da filial estiver vazia
    if ((!data || data.length === 0) && resolvedBranchId !== null) {
        logger.info(`[DataStore] Cache para entidade branch-scoped "${entity}" na filial "${resolvedBranchId}" vazio. Buscando fallback global (null)...`, { companyId });
        const globalData = await redisGet(companyId, entity, null);
        if (globalData && globalData.length > 0) {
            data = globalData;
            syncedAt = await redisSyncedAt(companyId, entity, null);
            logger.info(`[DataStore] Fallback global encontrado para a entidade "${entity}" com ${data.length} itens.`, { companyId });
        } else {
            // Fallback: busca em qualquer outra filial desta empresa e combina os dados (evita 0 produtos/títulos por incompatibilidade de filial)
            try {
                const pattern = `company:${companyId}:branch:*:${entity}`;
                const keys = await redisClient.keys(pattern);
                if (keys && keys.length > 0) {
                    logger.info(`[DataStore] Fallback: Encontradas ${keys.length} filiais com cache para a entidade "${entity}". Combinando os dados...`, { companyId });
                    
                    let mergedData = [];
                    let maxTtl = 0;
                    
                    for (const key of keys) {
                        const raw = await redisClient.get(key);
                        if (raw) {
                            try {
                                const parsed = JSON.parse(raw);
                                if (Array.isArray(parsed)) {
                                    mergedData.push(...parsed);
                                }
                            } catch (_) {}
                        }
                        const ttl = await redisClient.ttl(key);
                        if (ttl > maxTtl) {
                            maxTtl = ttl;
                        }
                    }
                    
                    if (mergedData.length > 0) {
                        const seen = new Set();
                        data = mergedData.filter(item => {
                            const uniqueKey = item.id || item.code || JSON.stringify(item);
                            if (seen.has(uniqueKey)) return false;
                            seen.add(uniqueKey);
                            return true;
                        });
                        
                        if (maxTtl >= 0) {
                            const savedAt = new Date(Date.now() + (maxTtl - 86_400) * 1000);
                            syncedAt = savedAt.toISOString();
                        }
                        logger.info(`[DataStore] Fallback combinado concluído com sucesso: ${data.length} itens únicos encontrados para "${entity}"`, { companyId });
                    }
                }
            } catch (scanErr) {
                logger.warn('[DataStore] Erro ao buscar chaves de filiais alternativas', { error: scanErr.message });
            }
        }
    }

    if (data && data.length > 0) {
        return { data, syncedAt, source: 'redis' };
    }
    return { data: [], syncedAt: null, source: 'empty' };
}

/**
 * Cache warming (P2-D): re-populate Redis para uma empresa a partir
 * de uma lista de entidades+dados fornecida externamente.
 *
 * Uso: chamado pelo Worker ao reconectar (apÃ³s restart do middleware)
 * via POST /api/sync/* para cada entidade. O warming Ã© automÃ¡tico
 * pois o upsert() jÃ¡ persiste no Redis com TTL 24h.
 *
 * Esta funÃ§Ã£o permite forÃ§ar um warming de forma programÃ¡tica
 * (ex: ao detectar Redis recÃ©m-conectado apÃ³s restart).
 *
 * @param {string}  companyId
 * @param {object}  snapshot â€” { products: [], sellers: [], ... }
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
    logger.info('[DataStore] Cache warming concluÃ­do', { companyId, warmed });
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

