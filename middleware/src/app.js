/**
 * app.js — Configuração do Express exportável para testes e para o servidor.
 *
 * Responsabilidades:
 * - Configurar middlewares de segurança (helmet, cors, rate limit)
 * - Registrar rotas (/health, /api/sync)
 * - Registrar errorHandler
 *
 * NÃO inicializa o pool Firebird nem chama app.listen().
 * Esta separação torna o app testável via supertest sem subir um servidor real.
 *
 * @module src/app
 */
'use strict';

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');

const config = require('./config/env');
const { authenticateSyncRequest } = require('./middleware/auth');
const { errorHandler } = require('./middleware/errorHandler');
const { defaultLimit, syncCatalogLimit, syncOrdersLimit } = require('./middleware/rateLimiter');

const healthRouter = require('./routes/health');
const syncRouter = require('./routes/sync');
const ordersRouter = require('./routes/orders');
const kpiRouter = require('./routes/kpi');
const companiesRouter = require('./routes/admin/companies');
const webhooksRouter = require('./routes/admin/webhooks');
const { router: metricsRouter, countRequest } = require('./routes/metrics');
const { router: adminStatsRouter, recordRequest } = require('./routes/admin/stats');
const eventsRouter = require('./routes/events');
const cacheWarmRouter = require('./routes/cacheWarm');
const adminOrdersRouter = require('./routes/admin/adminOrders');
const branchesRouter    = require('./routes/branches');



const app = express();

// Segurança: headers HTTP defensivos
app.use(helmet());

// CORS — apenas origens permitidas em produção
app.use(cors({
    origin: config.security.allowedOrigins.length > 0
        ? config.security.allowedOrigins
        : '*',
    methods: ['GET', 'POST', 'PATCH', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', 'API-Key', 'Admin-Api-Key', 'X-Api-Key', 'X-Company-Id'],
}));


// Parse de JSON — limite de 50mb para sync de catálogos grandes
app.use(express.json({ limit: '50mb' }));

// Rate limiting global — proteção contra abuso
app.use(rateLimit({
    windowMs: config.security.rateLimitWindowMs,
    max: config.security.rateLimitMax,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Muitas requisições. Tente novamente em instantes.', code: 'RATE_LIMITED' },
}));

// ─────────────────────────────────────────────────────────────────────────────
// Rotas
// ─────────────────────────────────────────────────────────────────────────────

// Instrumentação de métricas (N4) — antes de todas as rotas
app.use(countRequest);

// Buffer circular de logs para o painel Identity (admin/logs)
app.use(recordRequest);

// Métricas Prometheus
app.use('/metrics', metricsRouter);

// Health check — público (sem API Key), para monitoramento
app.use('/health', healthRouter);

// Admin — rotas de gestão de empresas (requerem ADMIN_API_KEY)
app.use('/api/admin/companies', companiesRouter);
app.use('/api/admin/companies/:id/webhooks', webhooksRouter);  // N3: CRUD webhooks
app.use('/api/admin', adminStatsRouter);  // /api/admin/stats, /api/admin/config, /api/admin/logs
app.use('/api/admin', adminOrdersRouter);  // relatório/kpi/events cross-company e ações de fila

// Rotas protegidas — requerem JWT de Dispositivo ou API Key do Worker
app.use('/api', authenticateSyncRequest);
app.use('/api', defaultLimit);           // Rate limit por empresa (P1-B)
app.use('/api/sync', syncCatalogLimit, syncRouter);
app.use('/api/sync/cache/warm', cacheWarmRouter);  // N2: cache warming endpoint
app.use('/api/orders', syncOrdersLimit, ordersRouter);
app.use('/api/orders', kpiRouter);
app.use('/api/orders', eventsRouter);              // audit trail endpoint
app.use('/api/branches', branchesRouter);          // FASE 3: listagem de filiais por tenant



// Rota não encontrada
app.use((req, res) => {
    res.status(404).json({ error: 'Rota não encontrada', code: 'NOT_FOUND' });
});

// Handler centralizado de erros (deve ser o último middleware)
app.use(errorHandler);

module.exports = app;
