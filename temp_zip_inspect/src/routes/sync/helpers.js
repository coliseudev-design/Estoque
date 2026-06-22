'use strict';
/**
 * Utilitários compartilhados entre os módulos de sync.
 *
 * @module routes/sync/helpers
 */

const fbManager = require('../../services/firebird.manager');
const logger    = require('../../config/logger');
const store     = require('../../services/dataStore');
const { createError } = require('../../middleware/errorHandler');

// ── Firebird ──────────────────────────────────────────────────────────────────

/**
 * Executa uma query SELECT no Firebird da empresa.
 * Retorna [] se fb_host não configurado ou se falhou (non-fatal para rotas de leitura).
 *
 * @param {object} company   req.company (shape: { id, name, fb_host, ... })
 * @param {string} sql
 * @param {Array}  [params]
 * @returns {Promise<Array>}
 */
async function fbQuery(company, sql, params = []) {
    if (!company.fb_host) return [];
    try {
        return await fbManager.queryFor(company, sql, params);
    } catch (err) {
        logger.warn('[Sync] Firebird direto indisponível', { companyId: company.id, error: err.message });
        return [];
    }
}

/**
 * Executa um DML/SP no Firebird da empresa.
 * Lança erro se Firebird não configurado (fatal para rotas de escrita).
 *
 * @param {object} company
 * @param {string} sql
 * @param {Array}  [params]
 * @returns {Promise<any>}
 */
async function fbExec(company, sql, params = []) {
    if (!company.fb_host) throw new Error('Firebird não configurado para esta empresa');
    return fbManager.executeFor(company, sql, params);
}

// ── Handlers genéricos ────────────────────────────────────────────────────────

/**
 * Cria um handler POST que recebe push de dados do Worker e armazena no dataStore.
 *
 * @param {string} entity    Chave do dataStore (ex: 'sellers')
 * @param {string} arrayKey  Chave do body (ex: 'sellers')
 * @returns {import('express').RequestHandler}
 */
function makePushHandler(entity, arrayKey) {
    return async function (req, res, next) {
        try {
            const companyId = req.company.id;
            const data = req.body[arrayKey];
            if (!Array.isArray(data)) {
                return next(createError(`Campo "${arrayKey}" deve ser um array.`, 400, 'INVALID_PAYLOAD'));
            }
            await store.upsert(companyId, entity, data);
            logger.info(`[Sync/${entity}] ${data.length} itens recebidos`, { companyId });
            res.json({ received: data.length, entity, syncedAt: new Date().toISOString() });
        } catch (err) {
            next(err);
        }
    };
}

// ── Validação ─────────────────────────────────────────────────────────────────

/**
 * Converte valor para inteiro seguro para interpolação em FIRST/SKIP do Firebird.
 * Defesa contra SQL injection: garante valor estritamente numérico.
 *
 * @param {*}      val
 * @param {number} fallback
 * @param {number} [min=0]
 * @param {number} [max=10000]
 * @returns {number}
 */
function safeInt(val, fallback, min = 0, max = 10000) {
    const n = parseInt(val, 10);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(min, Math.min(max, n));
}

/**
 * Valida campos obrigatórios de um payload de pedido.
 *
 * @param {object} order
 * @returns {{ valid: boolean, reason?: string }}
 */
function validateOrder(order) {
    const required = ['id', 'customerId', 'sellerId', 'totalAmount', 'items', 'createdAt'];
    for (const field of required) {
        if (order[field] === undefined || order[field] === null) {
            return { valid: false, reason: `Campo obrigatório ausente: ${field}` };
        }
    }
    if (!Array.isArray(order.items) || order.items.length === 0) {
        return { valid: false, reason: 'items deve ser um array não vazio' };
    }
    if (typeof order.totalAmount !== 'number' || order.totalAmount < 0) {
        return { valid: false, reason: 'totalAmount inválido' };
    }
    const uuidRx = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidRx.test(order.id)) {
        return { valid: false, reason: 'id deve ser UUID v4' };
    }
    return { valid: true };
}

// ── Formatação de datas ───────────────────────────────────────────────────────

/** @param {Date|string} d */
function padDate(d) {
    const dt = d instanceof Date ? d : new Date(d);
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

/** @param {Date|string} d */
function padTime(d) {
    const dt = d instanceof Date ? d : new Date(d);
    return `${String(dt.getHours()).padStart(2, '0')}:${String(dt.getMinutes()).padStart(2, '0')}`;
}

module.exports = { fbQuery, fbExec, makePushHandler, safeInt, validateOrder, padDate, padTime };
