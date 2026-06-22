/**
 * metrics.js — Endpoint Prometheus (N4).
 *
 * GET /metrics — retorna métricas no formato texto do Prometheus.
 *
 * Métricas expostas:
 *   coliseu_uptime_seconds         — tempo de uptime do processo
 *   coliseu_heap_used_bytes        — heap JS usada
 *   coliseu_http_requests_total    — contador de requests por rota+status
 *   coliseu_orders_total{status}  — pedidos por status (lido do PG)
 *   coliseu_companies_active_total — empresas ativas
 *
 * @module routes/metrics
 */
'use strict';

const express = require('express');
const { pgQuery } = require('../db/postgres');

const router = express.Router();

// Contador de requisições HTTP (incrementado pelo middleware abaixo)
let requestCounters = {};

/**
 * Middleware para contar requests por método+rota+status.
 * Adicionar no app.js: app.use(countRequest)
 */
function countRequest(req, res, next) {
    res.on('finish', () => {
        const key = `${req.method}_${(req.route?.path || 'unknown').replace(/:/g, '')}_${res.statusCode}`;
        requestCounters[key] = (requestCounters[key] || 0) + 1;
    });
    next();
}

/**
 * Serializa métricas no formato texto Prometheus.
 * @param {Array<{name, help, type, samples: Array<{labels?, value}>}>} metrics
 */
function serialize(metrics) {
    return metrics.map(m => [
        `# HELP ${m.name} ${m.help}`,
        `# TYPE ${m.name} ${m.type}`,
        ...m.samples.map(s => {
            const lblStr = s.labels
                ? '{' + Object.entries(s.labels).map(([k, v]) => `${k}="${v}"`).join(',') + '}'
                : '';
            return `${m.name}${lblStr} ${s.value}`;
        }),
    ].join('\n')).join('\n\n');
}

router.get('/', async (req, res) => {
    const mem = process.memoryUsage();

    // Métricas estáticas do processo
    const metrics = [
        {
            name: 'coliseu_uptime_seconds',
            help: 'Uptime do processo Node.js em segundos',
            type: 'gauge',
            samples: [{ value: Math.floor(process.uptime()) }],
        },
        {
            name: 'coliseu_heap_used_bytes',
            help: 'Heap JavaScript usada em bytes',
            type: 'gauge',
            samples: [{ value: mem.heapUsed }],
        },
        {
            name: 'coliseu_heap_total_bytes',
            help: 'Heap JavaScript total alocada',
            type: 'gauge',
            samples: [{ value: mem.heapTotal }],
        },
        {
            name: 'coliseu_rss_bytes',
            help: 'Resident Set Size (memória total do processo)',
            type: 'gauge',
            samples: [{ value: mem.rss }],
        },
        {
            name: 'coliseu_http_requests_total',
            help: 'Total de requests HTTP por rota e status',
            type: 'counter',
            samples: Object.entries(requestCounters).map(([key, count]) => {
                const [method, route, status] = key.split('_');
                return { labels: { method, route: route || 'unknown', status: status || '0' }, value: count };
            }),
        },
    ];

    // Métricas dinâmicas do PostgreSQL
    try {
        const [orders, companies] = await Promise.all([
            pgQuery(`SELECT sync_status, COUNT(*) AS count FROM orders GROUP BY sync_status`),
            pgQuery(`SELECT COUNT(*) AS count FROM companies WHERE active = TRUE`),
        ]);

        metrics.push({
            name: 'coliseu_orders_total',
            help: 'Total de pedidos por status',
            type: 'gauge',
            samples: orders.rows.map(r => ({
                labels: { status: r.sync_status }, value: Number(r.count),
            })),
        });
        metrics.push({
            name: 'coliseu_companies_active_total',
            help: 'Total de empresas ativas',
            type: 'gauge',
            samples: [{ value: Number(companies.rows[0].count) }],
        });
    } catch (_) {
        // PG offline — apenas métricas do processo
    }

    res.set('Content-Type', 'text/plain; version=0.0.4');
    res.send(serialize(metrics));
});

module.exports = { router, countRequest };
