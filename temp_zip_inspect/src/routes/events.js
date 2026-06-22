/**
 * events.js — Endpoint de audit trail (GET /api/orders/events).
 *
 * Retorna histórico de mudanças de status dos pedidos da empresa autenticada.
 * Dados vêm da tabela `order_events` (criada em sql/003_improvements.sql).
 *
 * Query params:
 *   orderId  — filtrar por UUID de pedido específico (opcional)
 *   page     — página (default: 1)
 *   limit    — itens por página (default: 50, máx: 200)
 *
 * @module routes/events
 */
'use strict';

const express = require('express');
const { pgQuery } = require('../db/postgres');
const router = express.Router();

router.get('/', async (req, res, next) => {
    const companyId = req.company.id;
    const orderId = req.query.orderId || null;
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const offset = (page - 1) * limit;

    try {
        // Constrói cláusula WHERE dinamicamente
        const conditions = ['e.company_id = $1'];
        const params = [companyId];
        let pIdx = 2;

        if (orderId) {
            conditions.push(`e.order_id = $${pIdx++}`);
            params.push(orderId);
        }

        const whereClause = conditions.join(' AND ');

        const [data, countRes] = await Promise.all([
            pgQuery(
                `SELECT
                    e.id,
                    e.order_id,
                    e.event_type,
                    e.old_status,
                    e.new_status,
                    e.metadata,
                    e.created_at
                 FROM   order_events e
                 WHERE  ${whereClause}
                 ORDER  BY e.created_at DESC
                 LIMIT  $${pIdx} OFFSET $${pIdx + 1}`,
                [...params, limit, offset]
            ),
            pgQuery(
                `SELECT COUNT(*) AS total FROM order_events e WHERE ${whereClause}`,
                params
            ),
        ]);

        const total = Number(countRes.rows[0].total);
        const pages = Math.ceil(total / limit);

        res.json({
            events: data.rows,
            company: req.company.name,
            pagination: { page, limit, total, pages },
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
