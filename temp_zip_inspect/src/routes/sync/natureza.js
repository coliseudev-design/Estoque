'use strict';
/**
 * Rotas de natureza de operação e condições de pagamento.
 *
 * @module routes/sync/natureza
 * @route POST /api/sync/natureza              — Worker push
 * @route GET  /api/sync/natureza              — App leitura
 * @route POST /api/sync/payment-conditions    — Worker push
 * @route GET  /api/sync/payment-conditions    — App leitura
 */

const express = require('express');
const { fbQuery, makePushHandler } = require('./helpers');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ── natureza ──────────────────────────────────────────────────────────────────

/** @route POST /api/sync/natureza */
router.post('/natureza', makePushHandler('natureza', 'naturezas'));

/**
 * Naturezas de operação habilitadas para mobile.
 * Store (Worker push) → fallback Firebird direto.
 * @route GET /api/sync/natureza
 */
router.get('/natureza', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'natureza');
        if (cached.data.length > 0) {
            return res.json({ natureza: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        let natureza = [];
        try {
            natureza = await fbQuery(req.company,
                `SELECT N.ID_NATUREZA AS id, TRIM(N.DESCRICAO) AS descricao, N.MOB_ORDEM AS mobOrdem
                 FROM NATUREZA_OPERACAO N WHERE N.MOB_ACESSO = 1 ORDER BY N.MOB_ORDEM, N.DESCRICAO`
            );
        } catch (dbErr) {
            logger.warn('[Sync/Natureza] Tabela NATUREZA_OPERACAO não encontrada — retornando vazio.', {
                hint: 'Verifique se a tabela existe no banco com: node scripts/list_mob_objects.js',
                error: dbErr.message,
            });
        }

        logger.info('[Sync/Natureza] Enviadas', { count: natureza.length, source: 'firebird' });
        res.json({ natureza, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) { next(err); }
});

// ── payment-conditions (FORMA_PGTO) ──────────────────────────────────────────

/** @route POST /api/sync/payment-conditions */
router.post('/payment-conditions', makePushHandler('paymentConditions', 'conditions'));

/**
 * Condições de pagamento (FORMA_PGTO) via store ou Firebird.
 * @route GET /api/sync/payment-conditions
 */
router.get('/payment-conditions', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'paymentConditions');
        if (cached.data.length > 0) {
            return res.json({ data: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        let conditions = [];
        try {
            conditions = await fbQuery(req.company,
                `SELECT DISTINCT
                        (F.ID_FORMA || '_' || FP.ID_ESPECIE) AS id,
                        TRIM(F.DESCRICAO) AS descricao,
                        FP.ID_ESPECIE AS especieId, F.PARCELAS AS parcelas,
                        F.DESCONTO_MAX AS descontoMax
                 FROM FORMA_PGTO F
                 INNER JOIN FORMA_PGTO_PERMISSAO FP ON FP.ID_FORMA = F.ID_FORMA
                 INNER JOIN ESPECIE_PGTO E ON E.ID_ESPECIE = FP.ID_ESPECIE
                 WHERE F.MOB_ACESSO = 1 AND E.MOB_ACESSO = 1
                 ORDER BY F.DESCRICAO`
            );
        } catch (dbErr) {
            logger.warn('[Sync/PaymentConditions] Tabela FORMA_PGTO não acessível — retornando vazio.', {
                hint: 'Verifique se FORMA_PGTO existe no banco com MOB_ACESSO.',
                error: dbErr.message,
            });
        }

        logger.info('[Sync/PaymentConditions] Condições enviadas', { count: conditions.length, source: 'firebird' });
        res.json({ data: conditions, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) { next(err); }
});

module.exports = router;
