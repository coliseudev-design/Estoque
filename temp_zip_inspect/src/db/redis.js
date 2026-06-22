/**
 * redis.js — Cliente Redis singleton para o dataStore multi-tenant.
 *
 * O Redis substitui o Map em memória do dataStore.js, garantindo:
 *   1. Dados sobrevivem a restarts do middleware (persistência RDB/AOF)
 *   2. Múltiplas instâncias do middleware compartilham o mesmo store
 *   3. Isolamento por empresa via namespace de chave: company:{id}:{entity}
 *
 * Variáveis de ambiente (em ordem de prioridade):
 *   REDIS_HOST     (string)  — IP ou hostname explícito do Redis
 *   REDIS_PORT     (number)  — porta (default: 6379)
 *   REDIS_PASSWORD (string)  — senha (opcional)
 *   REDIS_URL      (string)  — fallback quando REDIS_HOST não definido
 *
 * Por que REDIS_HOST tem prioridade?
 *   Gestores de deploy como Coolify auto-injetam REDIS_URL com o hostname
 *   interno do serviço vinculado. Em setups com múltiplos serviços Redis,
 *   esse hostname pode resolver para o Redis errado. As variáveis individuais
 *   permitem apontar diretamente para o Redis correto via IP ou hostname único.
 *
 * Modo gracioso: se Redis não estiver disponível, os métodos retornam
 * null/[] sem travar o servidor — fallback para Firebird direto nas rotas.
 *
 * @module db/redis
 */
'use strict';

const Redis = require('ioredis');
const logger = require('../config/logger');

/**
 * Resolve opções de conexão Redis com a seguinte prioridade:
 *
 * 1. Variáveis individuais: REDIS_HOST + REDIS_PORT + REDIS_PASSWORD
 *    (usadas quando REDIS_URL é auto-injetada pelo Coolify com hostname errado)
 * 2. REDIS_URL (fallback — pode ser sobrescrita por gestores de deploy)
 *
 * O password é passado sem username → ioredis usa AUTH legado sem username,
 * compatível com qualquer configuração Redis 6/7 (requirepass ou ACL).
 *
 * @returns {{ host: string, port: number, password?: string }}
 */
function resolveRedisOptions() {
    // Prioridade 1: variáveis individuais (Coolify não as sobrescreve)
    const envHost = process.env.REDIS_HOST;
    if (envHost) {
        const opts = {
            host: envHost,
            port: parseInt(process.env.REDIS_PORT || '6379', 10),
        };
        if (process.env.REDIS_PASSWORD) {
            opts.password = process.env.REDIS_PASSWORD;
        }
        // Diagnóstico mascarado (Rule-04: sem expor credenciais)
        const rPass = process.env.REDIS_PASSWORD || '';
        const maskedRPass = rPass.length > 0
            ? rPass.slice(0, 4) + '*'.repeat(Math.max(rPass.length - 4, 0)) + ` (${rPass.length} chars)`
            : '(empty!)';
        logger.info('[Redis] Usando REDIS_HOST/REDIS_PORT/REDIS_PASSWORD', {
            host: opts.host,
            port: opts.port,
            password: maskedRPass,
        });
        return opts;
    }

    // Prioridade 2: REDIS_URL (pode ser sobrescrita por gestores de deploy)
    const url = process.env.REDIS_URL || 'redis://localhost:6379';
    try {
        const parsed = new URL(url);
        const opts = {
            host: parsed.hostname || 'localhost',
            port: parseInt(parsed.port || '6379', 10),
        };
        // Não passa username → AUTH legado (sem username), compatível com --requirepass
        if (parsed.password) {
            opts.password = decodeURIComponent(parsed.password);
        }
        return opts;
    } catch (err) {
        logger.warn('[Redis] REDIS_URL inválida — usando localhost:6379 sem auth', { error: err.message });
        return { host: 'localhost', port: 6379 };
    }
}

const redisOpts = resolveRedisOptions();

const client = new Redis({
    ...redisOpts,
    maxRetriesPerRequest: 2,
    connectTimeout: 2_000,
    lazyConnect: false,
    retryStrategy(times) {
        if (times > 5) return null;          // Desiste após 5 tentativas
        return Math.min(times * 500, 3_000); // Backoff: 500ms, 1s, 1.5s…
    },
});

client.on('connect', () => logger.info('[Redis] Conectado', { host: redisOpts.host, port: redisOpts.port }));
client.on('reconnecting', () => logger.warn('[Redis] Reconectando...'));
client.on('error', (err) => logger.error('[Redis] Erro de conexão', { error: err.message }));


// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Monta a chave Redis para um dado de empresa.
 * Formato: `company:{companyId}:{entity}` (ex: company:abc123:products)
 *
 * @param {string} companyId
 * @param {string} entity    — 'products', 'customers', 'sellers', etc.
 * @returns {string}
 */
function key(companyId, entity) {
    return `company:${companyId}:${entity}`;
}

/**
 * Armazena um array de dados de uma empresa.
 * Serializa para JSON e define TTL de 24h (dados recarregados pelo Worker).
 *
 * @param {string}  companyId
 * @param {string}  entity
 * @param {Array}   data
 * @param {number}  [ttlSeconds]  — default: 86400 (24h)
 */
async function redisSet(companyId, entity, data, ttlSeconds = 86_400) {
    if (client.status !== 'ready') return false;
    try {
        await client.setex(key(companyId, entity), ttlSeconds, JSON.stringify(data));
        return true;
    } catch (err) {
        logger.warn('[Redis] Falha ao salvar', { entity, companyId, error: err.message });
        return false;
    }
}

/**
 * Recupera dados de uma empresa.
 *
 * @param {string} companyId
 * @param {string} entity
 * @returns {Promise<Array|null>} Array de dados ou null (não encontrado/erro)
 */
async function redisGet(companyId, entity) {
    if (client.status !== 'ready') return null;
    try {
        const raw = await client.get(key(companyId, entity));
        return raw ? JSON.parse(raw) : null;
    } catch (err) {
        logger.warn('[Redis] Falha ao ler', { entity, companyId, error: err.message });
        return null;
    }
}

/**
 * Retorna quando a entidade foi salva pela última vez (TTL → syncedAt estimado).
 *
 * @param {string} companyId
 * @param {string} entity
 * @returns {Promise<string|null>} ISO string ou null
 */
async function redisSyncedAt(companyId, entity) {
    if (client.status !== 'ready') return null;
    try {
        const ttl = await client.ttl(key(companyId, entity));
        if (ttl < 0) return null;
        const savedAt = new Date(Date.now() + (ttl - 86_400) * 1000);
        return savedAt.toISOString();
    } catch {
        return null;
    }
}

/**
 * Verifica se Redis está acessível (para health check).
 * @returns {Promise<boolean>}
 */
async function redisPing() {
    try {
        return (await client.ping()) === 'PONG';
    } catch {
        return false;
    }
}

module.exports = { client, redisSet, redisGet, redisSyncedAt, redisPing };
