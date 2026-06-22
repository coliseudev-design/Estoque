'use strict';
/**
 * admin-stats.js — Endpoints de métricas e configuração para o painel Identity.
 *
 * Consumido por salesApiService.js no frontend do Identity Admin.
 * Requer o header: X-Api-Key com a ADMIN_API_KEY do Middleware.
 *
 * @module routes/admin/stats
 * @route GET /api/admin/stats   — Métricas globais (pedidos, catálogo, uptime)
 * @route GET /api/admin/config  — Configuração efetiva do servidor
 * @route GET /api/admin/logs    — Últimas N requisições (buffer circular)
 */

const express  = require('express');
const { pgQuery } = require('../../db/postgres');
const store    = require('../../services/dataStore');
const config   = require('../../config/env');
const logger   = require('../../config/logger');

const router = express.Router();

function requireAdminApiKey(req, res, next) {
    // Lê a chave em runtime (não no startup) para aceitar rotações sem restart
    // e para garantir que a env var foi injetada antes da primeira requisição
    const expected = (process.env.ADMIN_API_KEY || '').trim();
    const received = (
        req.headers['x-api-key'] ||
        req.headers['admin-api-key'] ||
        req.headers['api-key'] ||
        ''
    ).trim();

    if (!expected) {
        // Se ADMIN_API_KEY não está configurada, bloqueia com mensagem clara
        logger.error('[Admin/Stats] ADMIN_API_KEY não configurada no ambiente');
        return res.status(503).json({ error: 'Admin API não configurada. Defina ADMIN_API_KEY no ambiente.' });
    }
    if (received !== expected) {
        logger.warn('[Admin/Stats] Tentativa com chave inválida', { ip: req.ip });
        return res.status(403).json({ error: 'Forbidden: Admin API Key inválida.' });
    }
    next();
}

// ── Buffer circular de logs de requisições ─────────────────────────────────────

const REQUEST_LOG_MAX = 200;
const requestLogBuffer = [];

/**
 * Middleware para registrar requests no buffer circular.
 * Adicionar ao app.js: app.use(recordRequest).
 */
function recordRequest(req, res, next) {
    const start = Date.now();
    res.on('finish', () => {
        const entry = {
            timestamp:  new Date().toISOString(),
            method:     req.method,
            path:       req.path,
            statusCode: res.statusCode,
            elapsedMs:  Date.now() - start,
            companyId:  req.company?.id ?? null,
            ipAddress:  req.ip || req.headers['x-forwarded-for'] || null,
            isError:    res.statusCode >= 400,
        };
        if (requestLogBuffer.length >= REQUEST_LOG_MAX) requestLogBuffer.shift();
        requestLogBuffer.push(entry);
    });
    next();
}

// ── GET /api/admin/stats ───────────────────────────────────────────────────────

/**
 * Métricas globais: pedidos por status, contagem de catálogo, uptime.
 * Público — dados agregados sem informações sensíveis.
 * O painel Identity já requer autenticação na camada de sessão.
 * @route GET /api/admin/stats
 */
router.get('/stats', async (req, res) => {
    try {
        // Pedidos por status (PostgreSQL)
        let ordersStats = { total: 0, pending: 0, processing: 0, synced: 0, error: 0 };
        let companiesCount = 0;
        let lastSyncAt = null;

        try {
            const [ordersRes, companiesRes, lastSyncRes] = await Promise.all([
                pgQuery(`SELECT sync_status, COUNT(*) AS count FROM orders GROUP BY sync_status`),
                pgQuery(`SELECT COUNT(*) AS count FROM companies WHERE "Status" = 0`),
                pgQuery(`SELECT MAX(updated_at) AS last_sync FROM orders WHERE sync_status = 'synced'`),
            ]);

            for (const row of ordersRes.rows) {
                const s = row.sync_status;
                const n = Number(row.count);
                ordersStats.total += n;
                if (s === 'pending')    ordersStats.pending    += n;
                if (s === 'processing') ordersStats.processing += n;
                if (s === 'synced')     ordersStats.synced     += n;
                if (s === 'error')      ordersStats.error      += n;
            }
            companiesCount = Number(companiesRes.rows[0]?.count || 0);
            lastSyncAt = lastSyncRes.rows[0]?.last_sync ?? null;
        } catch (pgErr) {
            logger.warn('[Admin/Stats] PostgreSQL indisponível', { error: pgErr.message });
        }

        // Contagem de catálogo no dataStore — soma para todas as empresas
        let catalogProducts  = 0;
        let catalogCustomers = 0;
        try {
            const allCompanies = await pgQuery(`SELECT "Id" AS id FROM companies WHERE "Status" = 0 LIMIT 50`);
            for (const company of allCompanies.rows) {
                const prod = await store.get(company.id, 'products');
                const cust = await store.get(company.id, 'customers');
                catalogProducts  += prod.data.length;
                catalogCustomers += cust.data.length;
            }
        } catch (storeErr) {
            logger.warn('[Admin/Stats] Falha ao contabilizar catálogo no dataStore', { error: storeErr.message });
        }

        res.json({
            uptime:    Math.floor(process.uptime()),
            orders:    ordersStats,
            catalog:   { products: catalogProducts, customers: catalogCustomers },
            companies: companiesCount,
            lastSyncAt,
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        logger.error('[Admin/Stats] Erro ao buscar métricas', { error: err.message });
        res.status(500).json({ error: err.message });
    }
});

// ── GET /api/admin/config ─────────────────────────────────────────────────────

/**
 * Configuração efetiva do servidor (sanitizada — sem segredos).
 * @route GET /api/admin/config
 */
router.get('/config', (req, res) => {
    // Monta string de conexão sanitizada a partir das variáveis individuais usadas pelo docker-compose
    const pgHost = process.env.PG_HOST || '';
    const pgDb   = process.env.PG_DATABASE || '';
    const pgUser = process.env.PG_USER || '';
    const pgPort = process.env.PG_PORT || '5432';
    const dbInfo = pgHost
        ? `postgresql://${pgUser}@${pgHost}:${pgPort}/${pgDb}`
        : (process.env.DATABASE_URL || process.env.POSTGRES_URL || '').replace(/:[^@]+@/, ':*****@') || '(não configurado)';

    res.json({
        apiKeysCount:       (process.env.API_KEYS || process.env.API_KEY || '').split(',').filter(Boolean).length,
        jwtConfigured:      !!process.env.JWT_ACCESS_SECRET,
        connectionString:   dbInfo,
        syncMode:           config.syncMode || process.env.SYNC_MODE || 'async',
        nodeEnv:            process.env.NODE_ENV || 'production',
        cors:               config.security?.allowedOrigins || [],
        rateLimit: {
            syncPerMinute:       config.security?.rateLimitMax || 200,
            ordersPerMinute:     config.security?.rateLimitMax || 200,
            monitoringPerMinute: config.security?.rateLimitMax || 200,
        },
        timestamp: new Date().toISOString(),
    });
});

// ── GET /api/admin/logs ───────────────────────────────────────────────────────

/**
 * Últimas N requisições do buffer circular.
 * @route GET /api/admin/logs?count=50&errorsOnly=true
 */
router.get('/logs', requireAdminApiKey, (req, res) => {
    const count      = Math.min(200, Math.max(1, parseInt(req.query.count) || 50));
    const errorsOnly = req.query.errorsOnly === 'true';

    let logs = requestLogBuffer.slice(-count);
    if (errorsOnly) logs = logs.filter(l => l.isError);

    res.json(logs);
});

module.exports = { router, recordRequest };
