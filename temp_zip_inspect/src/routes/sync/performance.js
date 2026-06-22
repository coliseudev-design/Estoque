'use strict';
/**
 * Rotas de performance, rankings de vendas e logo da empresa.
 *
 * @module routes/sync/performance
 * @route POST /api/sync/performance      — Worker push de KPIs
 * @route GET  /api/sync/performance      — App leitura (store → fallback Firebird)
 * @route POST /api/sync/sales-rankings   — Worker push de rankings
 * @route GET  /api/sync/sales-rankings   — App leitura (store only)
 * @route GET  /api/sync/company-logo     — Logo da empresa em bytes
 */

const express = require('express');
const { fbQuery } = require('./helpers');
const { pgQuery } = require('../../db/postgres');
const { createError } = require('../../middleware/errorHandler');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ── performance ───────────────────────────────────────────────────────────────

/** @route POST /api/sync/performance */
router.post('/performance', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const data = req.body.performance;
        if (!Array.isArray(data)) {
            return next(createError('Campo "performance" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }
        await store.upsert(companyId, 'performance', data);
        logger.info(`[Sync/Performance] ${data.length} KPIs recebidos do Worker`, { companyId });
        res.json({ received: data.length, entity: 'performance', syncedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

/**
 * KPIs de performance do vendedor.
 * Store primeiro (Worker push) → fallback Firebird (MINHASVENDAS + MINHASVENDASR).
 * @route GET /api/sync/performance?sellerId=<id>&month=<m>&year=<y>
 */
router.get('/performance', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now   = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year  = parseInt(req.query.year)  || now.getFullYear();

        // 1. Store (dados do Worker — caminho principal)
        const cached = await store.get(companyId, 'performance');
        if (cached && cached.data.length > 0) {
            const sellerKpis = cached.data.find(
                k => String(k.sellerId) === String(sellerId) && k.month === month && k.year === year
            );
            if (sellerKpis) {
                logger.info('[Sync/Performance] KPIs retornados', { sellerId, month, year, source: 'dataStore' });
                return res.json({ data: sellerKpis, source: 'dataStore' });
            }
        }

        // 2. Fallback: Firebird direto (pode falhar se não acessível do Docker)
        const today    = now.toISOString().split('T')[0];
        const firstDay = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay  = new Date(year, month, 0).toISOString().split('T')[0];
        const empresaId = parseInt(req.query.empresaId) || 1;

        const [mainRows, rangeRows] = await Promise.all([
            fbQuery(req.company, 'EXECUTE PROCEDURE MINHASVENDAS(?, ?, ?, ?)',
                [parseInt(sellerId), month, year, today]),
            fbQuery(req.company, 'EXECUTE PROCEDURE MINHASVENDASR(?, ?, ?, ?, ?)',
                [parseInt(sellerId), firstDay, lastDay, today, empresaId]),
        ]);

        const main  = mainRows[0]  || {};
        const range = rangeRows[0] || {};

        const performance = {
            sellerId: parseInt(sellerId), month, year,
            syncedAt:           now.toISOString(),
            vendaDiaria:        parseFloat(main.VENDA_DIARIA)     || 0,
            vendaMensal:        parseFloat(main.VENDA_MENSAL)     || 0,
            comissaoDiaria:     parseFloat(main.COMISSAO_DIARIA)  || 0,
            comissaoMensal:     parseFloat(main.COMISSAO_MENSAL)  || 0,
            metaDiaria:         parseFloat(main.META_DIARIA)      || 0,
            metaMensal:         parseFloat(main.META_MENSAL)      || 0,
            servicoMensal:      parseFloat(main.SERVICO_MENSAL)   || 0,
            comissaoSvMensal:   parseFloat(main.COMISSAO_SV_MENSAL)  || 0,
            totalDiario:        parseFloat(range.TOTAL_DIARIO)    || 0,
            totalMensal:        parseFloat(range.TOTAL_MENSAL)    || 0,
            comissaoDiariaR:    parseFloat(range.COMISSAO_DIARIA) || 0,
            comissaoMensalR:    parseFloat(range.COMISSAO_MENSAL) || 0,
        };

        const source = mainRows.length > 0 ? 'firebird' : 'empty';
        logger.info('[Sync/Performance] KPIs retornados', { sellerId, month, year, source });
        if (source === 'empty') return res.json({ data: null, source });
        res.json({ data: performance, source });
    } catch (err) {
        logger.error('[Sync/Performance] Erro', { error: err.message });
        next(err);
    }
});

// ── sales-rankings ────────────────────────────────────────────────────────────

/** @route POST /api/sync/sales-rankings */
router.post('/sales-rankings', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const data = req.body.rankings;
        if (!Array.isArray(data)) {
            return next(createError('Campo "rankings" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }
        await store.upsert(companyId, 'sales-rankings', data);
        logger.info(`[Sync/SalesRankings] ${data.length} vendedores recebidos do Worker`, { companyId });
        res.json({ received: data.length, entity: 'sales-rankings', syncedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

/**
 * Rankings de vendas do vendedor (store only — sem fallback Firebird).
 * @route GET /api/sync/sales-rankings?sellerId=<id>&month=<m>&year=<y>
 */
router.get('/sales-rankings', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now   = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year  = parseInt(req.query.year)  || now.getFullYear();

        const cached = await store.get(companyId, 'sales-rankings');
        if (cached && cached.data && cached.data.length > 0) {
            const sellerRankings = cached.data.find(
                k => String(k.sellerId) === String(sellerId) && k.month === month && k.year === year
            );
            if (sellerRankings) {
                logger.info('[Sync/SalesRankings] Rankings retornados', { sellerId, month, year, source: 'dataStore' });
                return res.json({ data: sellerRankings, source: 'dataStore' });
            }
        }

        logger.info('[Sync/SalesRankings] Sem rankings para vendedor', { sellerId, month, year });
        res.json({ data: null, source: 'empty' });
    } catch (err) {
        logger.error('[Sync/SalesRankings] Erro', { error: err.message });
        next(err);
    }
});

// ── company-logo ──────────────────────────────────────────────────────────────

/**
 * Serve a logo da empresa como imagem binária (PNG/JPEG).
 * Lê LogoBase64 da tabela companies no PostgreSQL Identity.
 * @route GET /api/sync/company-logo
 */
router.get('/company-logo', async (req, res, next) => {
    try {
        const companyId = req.company?.id;
        if (!companyId) {
            return res.status(401).json({ error: 'Empresa não identificada.' });
        }

        const { rows } = await pgQuery(
            `SELECT "LogoBase64" AS logo_base64 FROM companies WHERE "Id" = $1 LIMIT 1`,
            [companyId]
        );

        if (!rows.length || !rows[0].logo_base64) {
            return res.status(404).json({ error: 'Nenhuma logo cadastrada.' });
        }

        let base64 = rows[0].logo_base64;
        let contentType = 'image/png';

        if (base64.startsWith('data:')) {
            const commaIdx = base64.indexOf(',');
            if (commaIdx > 0) {
                const header = base64.substring(0, commaIdx);
                if (header.includes('jpeg') || header.includes('jpg')) contentType = 'image/jpeg';
                base64 = base64.substring(commaIdx + 1);
            }
        }

        const buffer = Buffer.from(base64, 'base64');
        res.set('Content-Type', contentType);
        res.set('Content-Length', buffer.length);
        res.set('Cache-Control', 'public, max-age=3600');
        res.send(buffer);

        logger.info('[Sync/CompanyLogo] Logo servida', { companyId, bytes: buffer.length });
    } catch (err) {
        logger.error('[Sync/CompanyLogo] Erro', { error: err.message });
        next(err);
    }
});

module.exports = router;
