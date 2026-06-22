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
const orderPersistence = require('../../services/orderPersistence');
const logger = require('../../config/logger');
const store = require('../../services/dataStore');

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
router.get('/orders/report', requireAdminKey, async (req, res) => {
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
router.get('/orders/kpi', requireAdminKey, async (req, res) => {
    const from = req.query.from || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0];
    const to   = req.query.to   || new Date().toISOString().split('T')[0];
    const { companyId, branchId, source = 'app' } = req.query;

    try {
        if (source === 'erp') {
            let targetCompanyId = companyId;
            if (!targetCompanyId) {
                const firstCompany = await pgQuery('SELECT "Id" AS id FROM companies LIMIT 1');
                if (firstCompany.rows.length > 0) {
                    targetCompanyId = firstCompany.rows[0].id;
                }
            }

            if (!targetCompanyId) {
                return res.json({
                    period: { from, to },
                    company: 'ERP — Sem empresas cadastradas',
                    summary: { totalOrders: 0, totalRevenue: 0, avgTicket: 0, syncedRevenue: 0 },
                    byStatus: [],
                    dailySales: [],
                    topCustomers: [],
                    topSellers: [],
                    branchSales: []
                });
            }

            // Fetch company branches
            const branchesRes = await pgQuery('SELECT "Id" AS id, "Name" AS name, "ErpEmpresaId" AS erp_empresa_id, "ErpDeptoPadrao" AS erp_depto_padrao FROM branches WHERE "CompanyId" = $1', [targetCompanyId]);
            const targetDeptoId = branchId ? branchesRes.rows.find(b => b.id === branchId)?.erp_depto_padrao : null;

            // Fetch cached values
            const [cachedSellers, cachedPerformance, cachedRankings] = await Promise.all([
                store.get(targetCompanyId, 'sellers'),
                store.get(targetCompanyId, 'performance'),
                store.get(targetCompanyId, 'sales-rankings')
            ]);

            const sellersMap = new Map(cachedSellers?.data?.map(s => [s.id, s.name]) || []);
            
            // Parse targeted month & year from "to" date (or default to current month/year)
            const targetDate = to ? new Date(to) : new Date();
            const targetMonth = targetDate.getMonth() + 1;
            const targetYear = targetDate.getFullYear();

            // 1. Filter performance for current month/year and optional branch filter
            const perfList = (cachedPerformance.data || []).filter(k => 
                k.month === targetMonth && 
                k.year === targetYear &&
                (!branchId || String(k.branchId) === String(branchId) || (targetDeptoId && String(k.deptoId) === String(targetDeptoId)))
            );

            let totalRevenue = 0;
            let totalOrders = 0;
            const branchSalesMap = new Map();
            
            // Initialize branch sales map with 0s
            for (const b of branchesRes.rows) {
                branchSalesMap.set(b.id, {
                    branchId: b.id,
                    branchName: b.name,
                    totalRevenue: 0,
                    orderCount: 0
                });
            }

            const sellerSalesMap = new Map();

            // Aggregate revenue and initialize sellerSalesMap from performance
            for (const k of perfList) {
                const val = Number(k.vendaMensal) || 0;
                totalRevenue += val;

                const sId = k.sellerId;
                const sName = sellersMap.get(sId) || `Vendedor ${sId}`;
                if (!sellerSalesMap.has(sId)) {
                    sellerSalesMap.set(sId, { name: sName, revenue: 0, orderCount: 0 });
                }
                const sEntry = sellerSalesMap.get(sId);
                sEntry.revenue += val;

                // Track branch totalRevenue
                const bId = k.branchId || null;
                if (bId && branchSalesMap.has(bId)) {
                    const bEntry = branchSalesMap.get(bId);
                    bEntry.totalRevenue += val;
                } else if (k.deptoId) {
                    const match = branchesRes.rows.find(b => b.erp_depto_padrao === k.deptoId);
                    if (match) {
                        const bEntry = branchSalesMap.get(match.id);
                        bEntry.totalRevenue += val;
                    }
                }
            }

            // 2. Filter rankings for current month/year and branch
            const rankList = (cachedRankings.data || []).filter(k =>
                (k.period || 'month') === 'month' &&
                k.month === targetMonth &&
                k.year === targetYear &&
                (!branchId || String(k.branchId) === String(branchId) || (targetDeptoId && String(k.deptoId) === String(targetDeptoId)))
            );

            const dailyMap = new Map();
            const customerMap = new Map();

            for (const r of rankList) {
                const sId = r.sellerId;
                const sName = sellersMap.get(sId) || `Vendedor ${sId}`;

                // Aggregate daily sales
                if (Array.isArray(r.revenueByDay)) {
                    for (const d of r.revenueByDay) {
                        let dateStr = '';
                        if (d.date) {
                            if (d.date.includes('T')) {
                                dateStr = d.date.split('T')[0];
                            } else if (d.date.includes('/')) {
                                const parts = d.date.split(' ')[0].split('/');
                                if (parts[0].length === 4) {
                                    dateStr = `${parts[0]}-${parts[1]}-${parts[2]}`;
                                } else {
                                    dateStr = `${parts[2]}-${parts[1]}-${parts[0]}`;
                                }
                            } else {
                                dateStr = d.date.split(' ')[0];
                            }
                        }
                        if (!dateStr) continue;

                        if (dateStr >= from && dateStr <= to) {
                            if (!dailyMap.has(dateStr)) {
                                dailyMap.set(dateStr, { orderCount: 0, revenue: 0 });
                            }
                            const entry = dailyMap.get(dateStr);
                            entry.orderCount += parseInt(d.numOrders) || 0;
                            entry.revenue += parseFloat(d.totalAmount) || 0;

                            totalOrders += parseInt(d.numOrders) || 0;

                            // Track seller orderCount
                            if (!sellerSalesMap.has(sId)) {
                                sellerSalesMap.set(sId, { name: sName, revenue: 0, orderCount: 0 });
                            }
                            const sEntry = sellerSalesMap.get(sId);
                            sEntry.orderCount += parseInt(d.numOrders) || 0;

                            // Track branch orderCount
                            const bId = r.branchId || null;
                            if (bId && branchSalesMap.has(bId)) {
                                const bEntry = branchSalesMap.get(bId);
                                bEntry.orderCount += parseInt(d.numOrders) || 0;
                            } else if (r.deptoId) {
                                const match = branchesRes.rows.find(b => b.erp_depto_padrao === r.deptoId);
                                if (match) {
                                    const bEntry = branchSalesMap.get(match.id);
                                    bEntry.orderCount += parseInt(d.numOrders) || 0;
                                }
                            }
                        }
                    }
                }

                // Aggregate customer sales
                if (Array.isArray(r.topClients)) {
                    for (const c of r.topClients) {
                        const cName = c.name;
                        if (!cName) continue;
                        if (!customerMap.has(cName)) {
                            customerMap.set(cName, { orderCount: 0, revenue: 0 });
                        }
                        const entry = customerMap.get(cName);
                        entry.orderCount += parseInt(c.numOrders) || 0;
                        entry.revenue += parseFloat(c.totalValue) || 0;
                    }
                }
            }

            // Format to arrays
            const dailySales = Array.from(dailyMap.entries())
                .map(([day, val]) => ({ day, orderCount: val.orderCount, revenue: val.revenue }))
                .sort((a, b) => a.day.localeCompare(b.day));

            const topCustomers = Array.from(customerMap.entries())
                .map(([name, val]) => ({ name, orderCount: val.orderCount, revenue: val.revenue }))
                .sort((a, b) => b.revenue - a.revenue)
                .slice(0, 5);

            const topSellers = Array.from(sellerSalesMap.values())
                .sort((a, b) => b.revenue - a.revenue)
                .slice(0, 5);

            const branchSales = Array.from(branchSalesMap.values());

            const avgTicket = totalOrders > 0 ? Number((totalRevenue / totalOrders).toFixed(2)) : 0;

            return res.json({
                period: { from, to },
                company: 'ERP — Relatório consolidado',
                summary: {
                    totalOrders,
                    totalRevenue,
                    avgTicket,
                    syncedRevenue: totalRevenue
                },
                byStatus: [
                    { status: 'synced', count: totalOrders }
                ],
                dailySales,
                topCustomers,
                topSellers,
                branchSales
            });
        }

        // --- APP Source ---
        let filterSql = ` WHERE DATE(created_at) BETWEEN $1 AND $2`;
        const params = [from, to];
        
        if (companyId) {
            params.push(companyId);
            filterSql += ` AND company_id = $${params.length}`;
        }
        if (branchId) {
            params.push(branchId);
            filterSql += ` AND branch_id = $${params.length}`;
        }

        const [totals, byStatus, byDay, topCustomers, topSellers, branchSales] = await Promise.all([
            pgQuery(
                `SELECT
                    COUNT(*)                                                                 AS total_orders,
                    COALESCE(SUM(total_amount), 0)                                           AS total_revenue,
                    COALESCE(AVG(total_amount), 0)                                           AS avg_ticket,
                    COALESCE(SUM(CASE WHEN sync_status = 'synced' THEN total_amount END), 0) AS synced_revenue
                 FROM orders` + filterSql,
                params
            ),
            pgQuery(
                `SELECT sync_status AS status, COUNT(*) AS count
                 FROM orders` + filterSql + ` GROUP BY sync_status`,
                params
            ),
            pgQuery(
                `SELECT
                    DATE(created_at)              AS day,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders` + filterSql + ` GROUP BY DATE(created_at) ORDER BY day ASC`,
                params
            ),
            pgQuery(
                `SELECT
                    customer_name                  AS name,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders` + filterSql + ` AND customer_name IS NOT NULL
                 GROUP BY customer_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                params
            ),
            pgQuery(
                `SELECT
                    seller_name                    AS name,
                    COUNT(*)                       AS order_count,
                    COALESCE(SUM(total_amount), 0) AS revenue
                 FROM orders` + filterSql + ` AND seller_name IS NOT NULL
                 GROUP BY seller_name
                 ORDER BY revenue DESC
                 LIMIT 5`,
                params
            ),
            pgQuery(
                `SELECT 
                    b."Id" AS branch_id,
                    b."Name" AS branch_name,
                    COUNT(o.id) AS order_count,
                    COALESCE(SUM(o.total_amount), 0) AS total_revenue
                 FROM branches b
                 LEFT JOIN orders o ON o.branch_id = b."Id" AND DATE(o.created_at) BETWEEN $1 AND $2
                 ` + (companyId ? `WHERE b."CompanyId" = $3` : '') + `
                 GROUP BY b."Id", b."Name"`,
                 companyId ? [from, to, companyId] : [from, to]
            )
        ]);

        const t = totals.rows[0];

        res.json({
            period: { from, to },
            company: 'APP — Relatório consolidado',
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
            branchSales:  branchSales.rows.map(r => ({
                branchId:     r.branch_id,
                branchName:   r.branch_name,
                orderCount:   Number(r.order_count),
                totalRevenue: Number(r.total_revenue),
            }))
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
router.get('/orders/events', requireAdminKey, async (req, res) => {
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

// ── GET /api/admin/orders/stuck ───────────────────────────────────────────────

/**
 * Retorna os pedidos travados na memória do SQLite (pending/error),
 * unidos aos do PostgreSQL que perderam o cache.
 */
router.get('/orders/stuck', requireAdminKey, async (req, res) => {
    const from = req.query.from;
    const to   = req.query.to || new Date().toISOString().split('T')[0];
    const isAllTime = from === 'all';
    
    // Default 30 days se não for 'all' e não vier data
    const effectiveFrom = isAllTime ? null : (from || new Date(Date.now() - 30 * 864e5).toISOString().split('T')[0]);

    try {
        const fromDate = isAllTime ? new Date(0) : new Date(effectiveFrom);
        const toDate   = new Date(`${to}T23:59:59.999Z`);
        
        let sqliteStuck = orderPersistence.getStuckOrders() || [];
        
        // Fetch all companies to map company names
        const { rows: companiesList } = await pgQuery('SELECT "Id" AS id, "Name" AS name FROM companies');
        const companyNameMap = new Map(companiesList.map(c => [c.id, c.name]));

        // Adiciona um campo de tempo decorrido (elapsedTime) aos pedidos do SQLite
        const now = Date.now();
        const sqliteEnriched = sqliteStuck.map(order => {
            const created = new Date(order.createdAt).getTime();
            const elapsedMs = now - created;
            const elapsedMinutes = Math.floor(elapsedMs / 60000);
            return {
                id: order.id,
                status: order.status,
                erpOrderId: order.erpOrderId,
                errorMessage: order.errorMessage,
                customerName: order.customerName,
                sellerName: order.sellerName,
                totalAmount: order.totalAmount,
                createdAt: order.createdAt,
                updatedAt: order.updatedAt,
                elapsedMinutes,
                companyName: companyNameMap.get(order.companyId) || 'Desconhecida'
            };
        }).filter(o => {
            const dt = new Date(o.createdAt);
            return dt >= fromDate && dt <= toDate;
        });

        // Consulta pedidos travados "esquecidos" no Postgres
        let pgOrdersQuery = `
            SELECT o.id, o.sync_status as status, o.erp_order_id, null as error_message, o.customer_name, o.seller_name, o.total_amount, o.updated_at, o.created_at, c."Name" as company_name
            FROM orders o
            LEFT JOIN companies c ON o.company_id = c."Id"
            WHERE o.sync_status IN ('pending', 'error')
        `;
        let pgOrdersParams = [];
        if (!isAllTime) {
            pgOrdersQuery += ` AND DATE(o.created_at) BETWEEN $1 AND $2 `;
            pgOrdersParams = [effectiveFrom, to];
        }
        pgOrdersQuery += ` ORDER BY o.created_at DESC `;

        const { rows: pgOrders } = await pgQuery(pgOrdersQuery, pgOrdersParams);

        // Unificar (SQLite tem prioridade se houver dupla)
        const orderMap = new Map();
        for (const pgOp of pgOrders) {
            const created = new Date(pgOp.created_at).getTime();
            const elapsedMs = now - created;
            const elapsedMinutes = Math.floor(elapsedMs / 60000);
            orderMap.set(pgOp.id, {
                id: pgOp.id,
                status: pgOp.status,
                erpOrderId: pgOp.erp_order_id,
                errorMessage: pgOp.error_message,
                customerName: pgOp.customer_name,
                sellerName: pgOp.seller_name,
                totalAmount: parseFloat(pgOp.total_amount || 0),
                createdAt: pgOp.created_at,
                updatedAt: pgOp.updated_at,
                elapsedMinutes,
                companyName: pgOp.company_name || 'Desconhecida'
            });
        }
        for (const sqOp of sqliteEnriched) {
            orderMap.set(sqOp.id, sqOp); // Sobrescreve com dado mais fresco do SQLite
        }
        
        const unifiedStuckOrders = Array.from(orderMap.values())
            .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

        // Consulta clientes travados no Postgres
        let pgCustomersQuery = `
            SELECT pc.id, pc.local_id, pc.payload, pc.sync_status, pc.error_message, pc.updated_at, pc.created_at, c."Name" as company_name 
            FROM pending_customers pc
            LEFT JOIN companies c ON pc.company_id = c."Id"
            WHERE pc.sync_status IN ('pending', 'error')
        `;
        let pgCustomersParams = [];
        if (!isAllTime) {
            pgCustomersQuery += ` AND DATE(pc.created_at) BETWEEN $1 AND $2 `;
            pgCustomersParams = [effectiveFrom, to];
        }
        pgCustomersQuery += ` ORDER BY pc.created_at DESC `;

        let customerRows = [];
        try {
            const { rows } = await pgQuery(pgCustomersQuery, pgCustomersParams);
            customerRows = rows;
        } catch (err) {
            logger.warn('[Admin/Stuck] Erro ao buscar clientes travados (tabela pode não existir).', { error: err.message });
        }

        // Enriquece os clientes da mesma forma
        const enrichedCustomers = customerRows.map(customer => {
            const created = new Date(customer.created_at).getTime();
            const elapsedMs = now - created;
            const elapsedMinutes = Math.floor(elapsedMs / 60000);
            return {
                id: customer.id,
                localId: customer.local_id,
                payload: customer.payload,
                status: customer.sync_status,
                errorMessage: customer.error_message,
                createdAt: customer.created_at,
                updatedAt: customer.updated_at,
                elapsedMinutes,
                companyName: customer.company_name || 'Desconhecida'
            };
        });

        res.json({ stuckOrders: unifiedStuckOrders, stuckCustomers: enrichedCustomers });
    } catch (err) {
        logger.error('[AdminOrders/stuck] Erro', { error: err.message });
        res.status(500).json({ error: err.message, code: 'STUCK_FETCH_ERROR' });
    }
});

// GET /api/admin/orders/companies/:companyId/branches
router.get('/orders/companies/:companyId/branches', requireAdminKey, async (req, res) => {
    try {
        const { rows } = await pgQuery('SELECT "Id" AS id, "Name" AS name, "ErpEmpresaId" AS erp_empresa_id, "ErpDeptoPadrao" AS erp_depto_padrao FROM branches WHERE "CompanyId" = $1 ORDER BY "Name" ASC', [req.params.companyId]);
        res.json({ branches: rows });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── POST /api/admin/orders/stuck/:id/retry ────────────────────────────────────
router.post('/orders/stuck/:id/retry', requireAdminKey, async (req, res) => {
    const { id } = req.params;
    try {
        orderPersistence.retryOrder(id);
        await pgQuery("UPDATE orders SET sync_status = 'pending', error_message = NULL WHERE id = $1", [id]);
        res.json({ success: true, message: 'Pedido liberado para reprocessamento' });
    } catch (err) {
        logger.error('[AdminOrders/retry] Erro', { id, error: err.message });
        res.status(500).json({ error: err.message, code: 'RETRY_ERROR' });
    }
});

// ── DELETE /api/admin/orders/stuck/:id ────────────────────────────────────────
router.delete('/orders/stuck/:id', requireAdminKey, async (req, res) => {
    const { id } = req.params;
    try {
        orderPersistence.deleteOrder(id);
        await pgQuery("UPDATE orders SET sync_status = 'synced', error_message = 'Descartado pelo administrador' WHERE id = $1", [id]);
        res.json({ success: true, message: 'Pedido removido da fila de pendências' });
    } catch (err) {
        logger.error('[AdminOrders/delete] Erro', { id, error: err.message });
        res.status(500).json({ error: err.message, code: 'DELETE_ERROR' });
    }
});

// ── POST /api/admin/customers/stuck/:localId/retry ────────────────────────────
router.post('/customers/stuck/:localId/retry', requireAdminKey, async (req, res) => {
    const { localId } = req.params;
    try {
        await pgQuery("UPDATE pending_customers SET sync_status = 'pending', error_message = NULL WHERE local_id = $1", [localId]);
        res.json({ success: true, message: 'Cliente liberado para reprocessamento' });
    } catch (err) {
        logger.error('[AdminCustomers/retry] Erro', { localId, error: err.message });
        res.status(500).json({ error: err.message, code: 'RETRY_ERROR' });
    }
});

// ── DELETE /api/admin/customers/stuck/:localId ────────────────────────────────
router.delete('/customers/stuck/:localId', requireAdminKey, async (req, res) => {
    const { localId } = req.params;
    try {
        await pgQuery("DELETE FROM pending_customers WHERE local_id = $1", [localId]);
        res.json({ success: true, message: 'Cliente excluído da fila de pendências' });
    } catch (err) {
        logger.error('[AdminCustomers/delete] Erro', { localId, error: err.message });
        res.status(500).json({ error: err.message, code: 'DELETE_ERROR' });
    }
});

module.exports = router;
