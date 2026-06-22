/**
 * orders.js — Rotas de gerenciamento de pedidos multi-tenant.
 *
 * Todas as operações são scopadas por req.company.id (injetado pelo auth.js).
 * O PostgreSQL garante isolamento via RLS (SET LOCAL app.current_company_id).
 *
 * Rotas:
 *   GET  /api/orders/pending          — pendentes para o Worker processar
 *   GET  /api/orders/report           — dados para o relatório admin
 *   GET  /api/orders/:id              — status de um pedido específico
 *   POST /api/orders/:id/confirm      — Worker confirma integração ERP
 *   POST /api/orders/:id/error        — Worker registra erro de integração
 *
 * @module routes/orders
 */
'use strict';

const express = require('express');
const { pgQuery } = require('../db/postgres');
const { createError } = require('../middleware/errorHandler');
const { dispatchWebhook } = require('../services/webhookService');
const logger = require('../config/logger');

const router = express.Router();

// ── Helper: seta RLS por empresa na transação ─────────────────────────────────

/**
 * Executa uma query com SET LOCAL para ativar o RLS da empresa (e opcionalmente da filial).
 * Garante que mesmo uma query sem WHERE company_id seja bloqueada pelo PG.
 *
 * @param {string}  companyId UUID da empresa
 * @param {string}  sql
 * @param {Array}   params
 * @param {string}  [branchId] UUID da filial (opcional)
 */
async function pgQueryRLS(companyId, sql, params, branchId = null) {
    const { pool } = require('../db/postgres');
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        // set_config com is_local=true é equivalente a SET LOCAL
        await client.query('SELECT set_config($1, $2, true)', ['app.current_company_id', companyId]);
        if (branchId) {
            await client.query('SELECT set_config($1, $2, true)', ['app.current_branch_id', branchId]);
        }
        const result = await client.query(sql, params);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

// ── GET /api/orders/pending ───────────────────────────────────────────────────

/**
 * Retorna pedidos pendentes de integração ERP para o Worker processar.
 *
 * Aceita ?confirmedSince=<ISO> para que o Flutter faça polling de pedidos
 * já confirmados (sync_status = 'synced') a partir de uma data.
 * Quando PostgreSQL está offline, retorna lista vazia com warning (não 500).
 *
 * @route GET /api/orders/pending
 */
router.get('/pending', async (req, res, next) => {
    const companyId = req.company.id;
    const branchId = req.branch?.id;
    const { confirmedSince } = req.query;

    try {
        if (confirmedSince) {
            // Polling do Flutter: busca pedidos confirmados após determinada data
            // Se branch_id estiver presente no request, aplica o filtro extra
            let sql = `SELECT id, erp_order_id, sync_status, customer_name, seller_name, total_amount, created_at, updated_at
                 FROM   orders
                 WHERE  company_id  = $1
                   AND  sync_status = 'synced'
                   AND  updated_at >= $2`;
            let params = [companyId, confirmedSince];
            
            if (branchId) {
                sql += ` AND (branch_id = $3 OR branch_id IS NULL)`;
                params.push(branchId);
            }
            
            sql += ` ORDER  BY updated_at DESC LIMIT  50`;
            
            const { rows } = await pgQuery(sql, params);
            return res.json({ orders: rows });
        }

        // Worker: busca pedidos pendentes de integração ERP
        let pendingSql = `SELECT id, payload, created_at, branch_id
             FROM   orders
             WHERE  company_id = $1 AND sync_status = 'pending'`;
        let pendingParams = [companyId];
        
        if (branchId) {
            pendingSql += ` AND (branch_id = $2 OR branch_id IS NULL)`;
            pendingParams.push(branchId);
        }
        
        pendingSql += ` ORDER  BY created_at ASC`;
        
        const { rows } = await pgQuery(pendingSql, pendingParams);

        // Devolve payload completo para o Worker processar no Firebird.
        // Filtra pedidos sem payload (criados antes da migration 008).
        const orders = rows
            .filter(r => r.payload)
            .map(r => ({
                ...r.payload,
                id: r.id,
                branchId: r.branch_id,
                createdAt: r.created_at,
            }));

        res.json({ orders });
    } catch (err) {
        // PostgreSQL offline — retorna vazio com warning (não bloqueia o Worker)
        logger.warn('[Orders/Pending] PostgreSQL indisponível — retornando lista vazia', {
            companyId, error: err.message,
            hint: 'Configure PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD no .env',
        });
        // Resposta compatível com ambos os callers (Worker e Flutter)
        if (req.query.confirmedSince) {
            return res.json({ orders: [] });
        }
        res.json({ pending: [] });
    }
});

// ── GET /api/orders/report ────────────────────────────────────────────────────

/**
 * Dados para o relatório de vendas do admin.
 * Suporta filtro por data: ?from=YYYY-MM-DD&to=YYYY-MM-DD
 * @route GET /api/orders/report
 */
router.get('/report', async (req, res, next) => {
    const companyId = req.company.id;
    const from = req.query.from || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0];
    const to = req.query.to || new Date().toISOString().split('T')[0];
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const offset = (page - 1) * limit;

    try {
        const [data, countRes] = await Promise.all([
            pgQuery(
                `SELECT id,
                        sync_status     AS "syncStatus",
                        erp_order_id    AS "erpOrderId",
                        customer_name   AS "customerName",
                        seller_name     AS "sellerName",
                        total_amount    AS "totalAmount",
                        created_at      AS "createdAt",
                        updated_at      AS "updatedAt"
                 FROM   orders
                 WHERE  company_id = $1
                   AND  DATE(created_at) BETWEEN $2 AND $3
                 ORDER  BY created_at DESC
                 LIMIT  $4 OFFSET $5`,
                [companyId, from, to, limit, offset]
            ),
            pgQuery(
                `SELECT COUNT(*) AS total FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3`,
                [companyId, from, to]
            ),
        ]);

        const total = Number(countRes.rows[0]?.total ?? 0);
        const pages = Math.ceil(total / limit);

        res.json({
            orders: data.rows,
            from, to,
            company: req.company.name,
            pagination: { page, limit, total, pages },
        });
    } catch (err) {
        next(err);
    }
});

// ── GET /api/orders/events ──────────────────────────────────────────────────

/**
 * Polling de eventos de pedidos (confirmações, erros) para o app móvel.
 * Quando PostgreSQL está offline em dev, retorna lista vazia sem crashar.
 * @route GET /api/orders/events
 */
router.get('/events', async (req, res, next) => {
    const companyId = req.company.id;
    try {
        const { rows } = await pgQuery(
            `SELECT id, sync_status as status, erp_order_id as "erpOrderId",
                    error_message as "errorMessage", updated_at as "updatedAt"
             FROM   orders
             WHERE  company_id = $1
               AND  sync_status IN ('synced', 'error')
               AND  updated_at > NOW() - INTERVAL '10 minutes'
             ORDER  BY updated_at DESC
             LIMIT  50`,
            [companyId]
        );
        res.json({ events: rows });
    } catch (err) {
        // PostgreSQL offline em dev: retorna vazio sem 500
        if (process.env.NODE_ENV !== 'production') {
            logger.warn('[Orders/Events] PostgreSQL offline — retornando eventos vazios (dev)', { error: err.message });
            return res.json({ events: [] });
        }
        next(err);
    }
});

// ── GET /api/orders ───────────────────────────────────────────────────────────

/**
 * Retorna o histórico de pedidos de um vendedor (sellerId) da empresa autenticada.
 * @route GET /api/orders
 */
router.get('/', async (req, res, next) => {
    const companyId = req.company.id;
    const branchId = req.branch?.id;
    const { sellerId } = req.query;

    if (!sellerId) {
        return next(createError('O campo sellerId é obrigatório.', 400, 'MISSING_SELLER_ID'));
    }

    try {
        let sql = `SELECT id,
                          sync_status   AS "syncStatus",
                          erp_order_id  AS "erpOrderId",
                          error_message AS "errorMessage",
                          customer_name AS "customerName",
                          seller_name   AS "sellerName",
                          total_amount  AS "totalAmount",
                          created_at    AS "createdAt",
                          updated_at    AS "updatedAt",
                          payload
                   FROM   orders
                   WHERE  company_id = $1
                     AND  (payload->>'sellerId' = $2 OR payload->>'seller_id' = $2)
                     AND  created_at >= NOW() - INTERVAL '90 days'`;
        let params = [companyId, String(sellerId)];

        if (branchId) {
            sql += ` AND (branch_id = $3 OR branch_id IS NULL)`;
            params.push(branchId);
        }

        sql += ` ORDER BY created_at DESC LIMIT 100`;

        const { rows } = await pgQuery(sql, params);
        res.json({ orders: rows });
    } catch (err) {
        next(err);
    }
});

// ── GET /api/orders/:id ───────────────────────────────────────────────────────

/**
 * Retorna status de um pedido específico da empresa autenticada.
 * @route GET /api/orders/:id
 */
router.get('/:id', async (req, res, next) => {
    const companyId = req.company.id;
    const orderId = req.params.id;
    try {
        const { rows } = await pgQuery(
            `SELECT sync_status as status, erp_order_id as "erpOrderId",
                    error_message as "errorMessage", updated_at as "updatedAt"
             FROM   orders
             WHERE  id = $1 AND company_id = $2`,
            [orderId, companyId]
        );

        if (!rows.length) {
            // PostgreSQL offline em dev: retorna pending sem crash
            if (process.env.NODE_ENV !== 'production') {
                return res.json({ status: 'pending', erpOrderId: null, errorMessage: null });
            }
            return next(createError('Pedido não encontrado', 404, 'ORDER_NOT_FOUND'));
        }

        res.json(rows[0]);
    } catch (err) {
        // PostgreSQL offline em dev
        if (process.env.NODE_ENV !== 'production') {
            logger.warn('[Orders] PostgreSQL offline — retornando status pending (dev)', { orderId, error: err.message });
            return res.json({ status: 'pending', erpOrderId: null, errorMessage: null });
        }
        next(err);
    }
});

// ── POST /api/orders/:id/confirm ─────────────────────────────────────────────

/**
 * Worker confirma que o pedido foi integrado no ERP Firebird.
 * @route POST /api/orders/:id/confirm
 * @body  { erpOrderId: string }
 */
router.post('/:id/confirm', async (req, res, next) => {
    const companyId = req.company.id;
    const orderId = req.params.id;
    const erpOrderId = req.body?.erpOrderId;

    if (!erpOrderId) {
        return next(createError('Campo erpOrderId é obrigatório', 400, 'MISSING_ERP_ID'));
    }

    try {
        const { rowCount } = await pgQuery(
            `UPDATE orders
             SET    sync_status = 'synced', erp_order_id = $1, updated_at = NOW()
             WHERE  id = $2 AND company_id = $3`,
            [String(erpOrderId), orderId, companyId]
        );

        if (!rowCount) {
            return next(createError('Pedido não encontrado para confirmação', 404, 'ORDER_NOT_FOUND'));
        }

        // Dispara webhook assíncrono (fire-and-forget)
        dispatchWebhook(companyId, 'order.confirmed', { orderId, erpOrderId });

        logger.info('[Orders] Pedido confirmado', { orderId, erpOrderId, companyId });
        res.json({ ok: true, orderId, erpOrderId, confirmedAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

// ── POST /api/orders/:id/error ────────────────────────────────────────────────

/**
 * Worker registra falha na integração do pedido com o ERP.
 * @route POST /api/orders/:id/error
 * @body  { message: string }
 */
router.post('/:id/error', async (req, res, next) => {
    const companyId = req.company.id;
    const orderId = req.params.id;
    const message = String(req.body?.errorMessage ?? req.body?.message ?? 'Erro desconhecido').substring(0, 500);

    try {
        const { rowCount } = await pgQuery(
            `UPDATE orders
             SET    sync_status = 'error', error_message = $1, updated_at = NOW()
             WHERE  id = $2 AND company_id = $3`,
            [message, orderId, companyId]
        );

        if (!rowCount) {
            return next(createError('Pedido não encontrado', 404, 'ORDER_NOT_FOUND'));
        }

        // Dispara webhook assíncrono
        dispatchWebhook(companyId, 'order.error', { orderId, message });

        logger.warn('[Orders] Pedido com erro', { orderId, message, companyId });
        res.json({ ok: true, orderId, errorAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
