/**
 * health.js — Health check completo: Firebird + PostgreSQL + Redis (P1-C).
 *
 * GET /health    — Público, retorna status de todos os serviços
 * GET /health/introspect — Privado (API-Key), diagnóstico de schema Firebird
 * GET /health/debug-mob  — Privado, diagnóstico de funcionários Firebird
 *
 * @module routes/health
 */
'use strict';

const express = require('express');
const { getPoolStatus, query } = require('../services/firebird.service');
const { requireApiKey } = require('../middleware/auth');
const { pgPing } = require('../db/postgres');
const { redisPing } = require('../db/redis');

const router = express.Router();

// ── GET /health ───────────────────────────────────────────────────────────────

router.get('/', async (req, res) => {
    const [pgOk, redisOk] = await Promise.all([pgPing(), redisPing()]);
    const fb = getPoolStatus();

    // Em modo async ou mock (VPS sem Firebird direto), o processo vivo = saudável.
    // PG e Redis são dependências opcionais: PG persiste logs de pedidos,
    // Redis armazena cache de sync. Sem eles o middleware ainda responde às rotas;
    // apenas não persiste dados até as conexões serem restauradas.
    //
    // Retornar 503 aqui блокeia o Traefik para TODOS os requests — comportamento
    // indesejado em modo VPS onde PG/Redis podem estar temporariamente indisponíveis.
    const isMock = process.env.FB_MOCK === 'true';
    const isAsync = process.env.SYNC_MODE === 'async';
    const firebirdOptional = isMock || isAsync;

    // Em modo VPS (firebirdOptional): sempre 200 — o processo está de pé.
    // Em modo direto (dev com Firebird): 503 se Firebird cair.
    const httpOk = firebirdOptional ? true : fb.connected;

    res.status(httpOk ? 200 : 503).json({
        status: httpOk ? 'ok' : 'degraded',
        uptime: Math.floor(process.uptime()),
        firebird: { ...fb, optional: firebirdOptional },
        postgres: { connected: pgOk, optional: firebirdOptional },
        redis: { connected: redisOk, optional: true },
        timestamp: new Date().toISOString(),
        version: process.env.npm_package_version || '1.0.0',
    });
});

// ── GET /health/introspect ────────────────────────────────────────────────────

router.get('/introspect', requireApiKey, async (req, res) => {
    const { table } = req.query;
    if (!table) return res.status(400).json({ error: 'table param required' });
    try {
        const cols = await query(
            `SELECT RF.RDB$FIELD_NAME FROM RDB$RELATION_FIELDS RF
             WHERE RF.RDB$RELATION_NAME = ? ORDER BY RF.RDB$FIELD_POSITION`,
            [table.toUpperCase()]
        );
        res.json({ table, columns: cols.map(r => r['RDB$FIELD_NAME'].trim()) });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ── GET /health/debug-mob ─────────────────────────────────────────────────────

router.get('/debug-mob', requireApiKey, async (req, res) => {
    try {
        const rows = await query(
            `SELECT FIRST 20 ID_FUNCIONARIO, NOME, MOB_ACESSO, MOB_SENHA, ID_MOBILE
             FROM FUNCIONARIOS ORDER BY ID_FUNCIONARIO DESC`
        );
        res.json(rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

module.exports = router;
