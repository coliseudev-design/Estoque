/**
 * adminOrders.js — Rotas admin de relatório de pedidos (cross-company).
 *
 * Protegidas por ADMIN_API_KEY (header Admin-Api-Key), não pela API-Key de empresa.
 * Retorna dados agregados de todas as empresas para o painel Identity.
 *
 * Rotas:
 *   GET /api/admin/orders/report  — Relatório de vendas (todas as empresas)
 *   GET /api/admin/orders/kpi     — KPIs agregados no mesmo formato de /api/orders/kpi
 *   GET /api/admin/orders/events  — Audit trail no mesmo formato snake_case de /api/orders/events
 *
 * @module routes/admin/adminOrders
 */
'use strict';

const express = require('express');
const { pgQuery } = require('../../db/postgres');
const logger = require('../../config/logger');

const router = express.Router();

// ── Middleware de super-admin ─────────────────────────────────────────────────

const ADMIN_KEY = process.env.ADMIN_API_KEY || '';

function requireAdminKey(req, res, next) {
    const raw = req.headers['admin-api-key'] || req.headers['api-key'];
    if (!raw || raw !== ADMIN_KEY) {
        return res.status(403).json({ error: 'Acesso negado', code: 'FORBIDDEN' });
    }
    next();
}

// ── GET /api/admin/orders/report ──────────────────────────────────────────────

/**
 * Relatório de pedidos para o painel admin (todas as empresas).
 * Query params: from, to, page, limit
 */
router.get('/report', requireAdminKey, async (req, res) => {
    const from  = req.query.from  || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0];
    const to    = req.query.to    || new Date().toISOString().split('T')[0];
    const page  = Math.max(1, parseInt(req.query.page  || '1',  10));
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const offset = (page - 1) * limit;

    try {
        const [data, countRes] = await Promise.all([
            pgQuery(
                `SELECT
                    o.id,
                    o.sync_status   AS "syncStatus",
                    o.erp_order_id  AS "erpOrderId",
                    o.customer_name AS "customerName",
                    o.seller_name   AS "sellerName",
                    o.total_amount  AS "totalAmount",
                    o.created_at    AS "createdAt",
                    o.updated_at    AS "updatedAt"
                 FROM orders o
                 WHERE DATE(o.created_at) BETWEEN $1 AND $2
                 ORDER BY o.created_at DESC
                 LIMIT $3 OFFSET $4`,
                [from, to, limit, offset]
            ),
            pgQuery(
                `SELECT COUNT(*) AS total FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2`,
                [from, to]
            ),
        ]);

        const total = parseInt(countRes.rows[0]?.total || '0', 10);
        const orders = data.rows.map(r => ({
            id:           r.id,
            syncStatus:   r.syncStatus,
            erpOrderId:   r.erpOrderId,
            customerName: r.customerName,
            sellerName:   r.sellerName,
            totalAmount:  parseFloat(r.totalAmount || 0),
            createdAt:    r.createdAt,
            updatedAt:    r.updatedAt,
        }));

        res.json({ orders, pagination: { total, page, limit, totalPages: Math.ceil(total / limit) } });
    } catch (err) {
        logger.error('[AdminOrders/report] Erro', { error: err.message });
        res.status(500).json({ error: err.message, code: 'DB_ERROR' });
    }
});

// ── GET /api/admin/orders/kpi ─────────────────────────────────────────────────

/**
 * KPIs agregados — mesmo formato de /api/orders/kpi para compatibilidade com KpiDashboard.jsx.
 * Inclui: summary, byStatus, dailySales, topCustomers, topSellers.
 */
router.get('/kpi', requireAdminKey, async (req, res) => {
    const from = req.query.from || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0];
    const to   = req.query.to   || new Date().toISOString().split('T')[0];

    try {
        const [totals, byStatus, byDay, topCustomers, topSellers] = await Promise.all([
            pgQuery(
                `SELECT
                    COUNT(*)                                                                 AS total_orders,
                    COALESCE(SUM(total_amount), 0)                                           AS total_revenue,
                    COALESCE(AVG(total_amount), 0)                                           AS avg_ticket,
                    COALESCE(SUM(CASE WHEN sync_status = 'synced' THEN total_amount END), 0) AS synced_revenue
                 FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2`,
                [from, to]
            ),
            pgQuery(
                `SELECT sync_status AS status, COUNT(*) AS count
                 FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2
                 GROUP BY sync_status`,
                [from, to]
            ),
            pgQuery(
                `SELECT
                    DATE(created_at)              AS day,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2
                 GROUP BY DATE(created_at)
                 ORDER BY day ASC`,
                [from, to]
            ),
            pgQuery(
                `SELECT
                    customer_name                  AS name,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2 AND customer_name IS NOT NULL
                 GROUP BY customer_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                [from, to]
            ),
            pgQuery(
                `SELECT
                    seller_name                    AS name,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE DATE(created_at) BETWEEN $1 AND $2 AND seller_name IS NOT NULL
                 GROUP BY seller_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                [from, to]
            ),
        ]);

        const t = totals.rows[0];

        // Formato idêntico ao /api/orders/kpi para compatibilidade com KpiDashboard.jsx
        res.json({
            period: { from, to },
            company: 'Admin — Todas as Empresas',
            summary: {
                totalOrders:  Number(t.total_orders),
                totalRevenue: Number(t.total_revenue),
                avgTicket:    Number(Number(t.avg_ticket).toFixed(2)),
                syncedRevenue: Number(t.synced_revenue),
            },
            byStatus:     byStatus.rows.map(r => ({ status: r.status, count: Number(r.count) })),
            dailySales:   byDay.rows.map(r => ({
                day:        typeof r.day === 'string' ? r.day.substring(0, 10) : new Date(r.day).toISOString().substring(0, 10),
                orderCount: Number(r.order_count),
                revenue:    Number(r.revenue),
            })),
            topCustomers: topCustomers.rows.map(r => ({
                name:       r.name,
                orderCount: Number(r.order_count),
                revenue:    Number(r.revenue),
            })),
            topSellers:   topSellers.rows.map(r => ({
                name:       r.name,
                orderCount: Number(r.order_count),
                revenue:    Number(r.revenue),
            })),
        });
    } catch (err) {
        logger.error('[AdminOrders/kpi] Erro', { error: err.message });
        res.status(500).json({ error: err.message, code: 'DB_ERROR' });
    }
});

// ── GET /api/admin/orders/events ──────────────────────────────────────────────

/**
 * Audit trail de eventos — mesmo formato snake_case de /api/orders/events
 * para compatibilidade com AuditTrail.jsx (usa ev.created_at, ev.order_id, etc.)
 */
router.get('/events', requireAdminKey, async (req, res) => {
    const page    = Math.max(1, parseInt(req.query.page  || '1',  10));
    const limit   = Math.min(200, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const offset  = (page - 1) * limit;
    const orderId = req.query.orderId || null;

    const conditions = [];
    const filterParams = [];
    let pIdx = 1;

    if (orderId) {
        conditions.push(`order_id = $${pIdx++}`);
        filterParams.push(orderId);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    try {
        const [data, countRes] = await Promise.all([
            pgQuery(
                // snake_case: compatível com AuditTrail.jsx que lê ev.created_at, ev.order_id, etc.
                `SELECT
                    id,
                    order_id,
                    event_type,
                    old_status,
                    new_status,
                    metadata,
                    created_at
                 FROM order_events
                 ${whereClause}
                 ORDER BY created_at DESC
                 LIMIT $${pIdx} OFFSET $${pIdx + 1}`,
                [...filterParams, limit, offset]
            ),
            pgQuery(
                `SELECT COUNT(*) AS total FROM order_events ${whereClause}`,
                filterParams
            ),
        ]);

        const total = Number(countRes.rows[0]?.total || 0);
        const pages = Math.ceil(total / limit);

        res.json({
            events: data.rows,
            pagination: { page, limit, total, pages },
        });
    } catch (err) {
        logger.error('[AdminOrders/events] Erro', { error: err.message });
        res.status(500).json({ error: err.message, code: 'DB_ERROR' });
    }
});

module.exports = router;
