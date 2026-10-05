/**
 * Express — rotas e middlewares. Exportado sem listen() para testes.
 *
 *   /internal/v1/*  Worker (licença do módulo)
 *   /v1/*           app e dashboard (token de usuário)
 *   /health         monitoramento
 *   /*              dashboard (SPA estática)
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const express = require('express');
const helmet = require('helmet');
const compression = require('compression');
const config = require('./config');
const log = require('./log');
const db = require('./db');
const { HttpError } = require('./http');

const app = express();
app.disable('x-powered-by');
if (config.trustProxy) app.set('trust proxy', 1);

app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
            fontSrc: ["'self'", 'https://fonts.gstatic.com'],
            imgSrc: ["'self'", 'data:'],
            connectSrc: ["'self'"],
        },
    },
}));

// O app nativo não precisa de CORS; só libera origens explícitas (ex.: dashboard em outro domínio).
if (config.security.allowedOrigins.length) {
    app.use((req, res, next) => {
        const origin = req.get('Origin');
        if (origin && config.security.allowedOrigins.includes(origin)) {
            res.set({
                'Access-Control-Allow-Origin': origin,
                'Access-Control-Allow-Headers': 'Authorization, Content-Type, X-Device-Token',
                'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE',
                Vary: 'Origin',
            });
            if (req.method === 'OPTIONS') return res.status(204).end();
        }
        next();
    });
}

// Compressão em tudo, exceto no stream SSE (comprimir bufferiza os eventos).
app.use(compression({ filter: (req, res) => !req.path.endsWith('/stream') && compression.filter(req, res) }));
app.use(express.json({ limit: '20mb' }));

app.get('/health', async (req, res) => {
    const pg = await db.query('SELECT 1').then(() => true, () => false);
    res.status(pg ? 200 : 503).json({ status: pg ? 'ok' : 'degraded', postgres: pg, time: new Date().toISOString() });
});

app.use('/internal/v1', require('./routes/internal'));
app.use('/v1/auth', require('./routes/auth'));
app.use('/v1/documents', require('./routes/documents'));
app.use('/v1', require('./routes/catalog'));
app.use('/v1', require('./routes/admin'));

app.use(['/v1', '/internal'], (req, res) => res.status(404).json({ error: 'Rota não encontrada', code: 'NOT_FOUND' }));

// Dashboard: arquivos estáticos + fallback do roteador por hash.
if (fs.existsSync(config.dashboardDir)) {
    app.use(express.static(config.dashboardDir, { index: 'index.html', maxAge: '1h' }));
    app.get('*', (req, res) => res.sendFile(path.join(config.dashboardDir, 'index.html')));
} else {
    log.warn('[App] pasta do dashboard não encontrada — servindo só a API', { dir: config.dashboardDir });
}

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
    if (err instanceof HttpError) {
        return res.status(err.status).json({ error: err.message, code: err.code, ...(err.extra || {}) });
    }
    if (err.type === 'entity.parse.failed') {
        return res.status(400).json({ error: 'JSON inválido', code: 'BAD_JSON' });
    }
    if (err.type === 'entity.too.large') {
        return res.status(413).json({ error: 'Lote grande demais', code: 'PAYLOAD_TOO_LARGE' });
    }
    log.error('[App] erro não tratado', { path: req.path, error: err.message, stack: err.stack });
    res.status(500).json({ error: 'Erro interno', code: 'INTERNAL' });
});

module.exports = app;
