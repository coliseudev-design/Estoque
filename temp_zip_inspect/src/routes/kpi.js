/**
 * kpi.js — KPI endpoint agregado via PostgreSQL (P2-B).
 *
 * GET /api/orders/kpi?from=YYYY-MM-DD&to=YYYY-MM-DD
 *
 * Retorna:
 *   - Total vendido (R$)
 *   - Nº de pedidos por status
 *   - Ticket médio
 *   - Vendas por dia (últimos 30 dias)
 *   - Top 5 clientes
 *   - Top 5 vendedores
 *
 * Todas as queries são scopadas por company_id (regra multi-tenant).
 *
 * @module routes/kpi
 */
'use strict';

const express = require('express');
const { pgQuery } = require('../db/postgres');
const router = express.Router();

router.get('/', async (req, res, next) => {
    const companyId = req.company.id;
    const from = req.query.from || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0];
    const to = req.query.to || new Date().toISOString().split('T')[0];

    try {
        // Executa todas as queries paralelamente para menor latência
        const [totals, byStatus, byDay, topCustomers, topSellers] = await Promise.all([
            // Totals: sum, count, avg
            pgQuery(
                `SELECT
                    COUNT(*)                                    AS total_orders,
                    COALESCE(SUM(total_amount), 0)             AS total_revenue,
                    COALESCE(AVG(total_amount), 0)             AS avg_ticket,
                    COALESCE(SUM(CASE WHEN sync_status = 'synced' THEN total_amount END), 0) AS synced_revenue
                 FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3`,
                [companyId, from, to]
            ),

            // Contagem por status
            pgQuery(
                `SELECT sync_status AS status, COUNT(*) AS count
                 FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3
                 GROUP BY sync_status`,
                [companyId, from, to]
            ),

            // Vendas por dia (para gráfico)
            pgQuery(
                `SELECT
                    DATE(created_at)          AS day,
                    COUNT(*)                  AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3
                 GROUP BY DATE(created_at)
                 ORDER BY day ASC`,
                [companyId, from, to]
            ),

            // Top 5 clientes por receita
            pgQuery(
                `SELECT
                    customer_name              AS name,
                    COUNT(*)                  AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3
                   AND customer_name IS NOT NULL
                 GROUP BY customer_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                [companyId, from, to]
            ),

            // Top 5 vendedores
            pgQuery(
                `SELECT
                    seller_name               AS name,
                    COUNT(*)                  AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders
                 WHERE company_id = $1 AND DATE(created_at) BETWEEN $2 AND $3
                   AND seller_name IS NOT NULL
                 GROUP BY seller_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                [companyId, from, to]
            ),
        ]);

        const t = totals.rows[0];

        res.json({
            period: { from, to },
            company: req.company.name,
            summary: {
                totalOrders: Number(t.total_orders),
                totalRevenue: Number(t.total_revenue),
                avgTicket: Number(Number(t.avg_ticket).toFixed(2)),
                syncedRevenue: Number(t.synced_revenue),
            },
            byStatus: byStatus.rows.map(r => ({ status: r.status, count: Number(r.count) })),
            dailySales: byDay.rows.map(r => ({
                day: r.day,
                orderCount: Number(r.order_count),
                revenue: Number(r.revenue),
            })),
            topCustomers: topCustomers.rows.map(r => ({
                name: r.name,
                orderCount: Number(r.order_count),
                revenue: Number(r.revenue),
            })),
            topSellers: topSellers.rows.map(r => ({
                name: r.name,
                orderCount: Number(r.order_count),
                revenue: Number(r.revenue),
            })),
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
