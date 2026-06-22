'use strict';
/**
 * Rotas de sync financeiro.
 *
 * @module routes/sync/financials
 * @route POST /api/sync/payment-species    — Worker push
 * @route GET  /api/sync/payment-species    — App leitura
 * @route POST /api/sync/financials         — Worker push
 * @route GET  /api/sync/financials         — App leitura
 */

const express = require('express');
const { fbQuery, makePushHandler } = require('./helpers');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ── payment-species ───────────────────────────────────────────────────────────

/** @route POST /api/sync/payment-species */
router.post('/payment-species', makePushHandler('paymentSpecies', 'species'));

/**
 * Formas/espécies de pagamento do store ou Firebird.
 * @route GET /api/sync/payment-species
 */
router.get('/payment-species', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'paymentSpecies');
        if (cached.data.length > 0) {
            return res.json({ paymentMethods: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird
        const species = await fbQuery(req,
            `SELECT E.ID_ESPECIE AS id, TRIM(E.DESCRICAO) AS name, E.TIPO AS type, E.DIAS AS days
             FROM ESPECIE_PGTO E WHERE E.MOB_ACESSO = 1 ORDER BY E.DESCRICAO`);

        logger.info('[Sync/PaymentSpecies] Espécies enviadas', { count: species.length, source: 'firebird' });
        res.json({ paymentMethods: species, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) { next(err); }
});

// ── financials ────────────────────────────────────────────────────────────────

/** @route POST /api/sync/financials */
router.post('/financials', makePushHandler('financials', 'financials'));

/**
 * Posição financeira (titulos a receber) via store ou Firebird.
 * @route GET /api/sync/financials?customerId=<id>
 */
router.get('/financials', async (req, res, next) => {
    try {
        const { customerId } = req.query;
        const companyId = req.company.id;
        // [FIX] Usa branchId do JWT para isolar financeiros por filial
        const branchId = req.branch?.id || null;
        const cached = await store.get(companyId, 'financials', branchId);
        if (cached && cached.data.length > 0) {
            const data = customerId
                ? cached.data.filter(f => {
                    // Worker ToCamelCase pode enviar como 'customerid', 'customerId' ou 'CUSTOMERID'
                    const fCid = f.customerId ?? f.customerid ?? f.CUSTOMERID ?? f.customer_id;
                    return fCid != null && String(fCid) === String(customerId);
                })
                : cached.data;
            return res.json({ financials: data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird
        const where    = customerId ? 'WHERE L.ID_CLIENTE = ?' : '';
        const params   = customerId ? [customerId] : [];
        const financials = await fbQuery(req,
            `SELECT FIRST 500
               L.ID_CONTA AS id, L.ID_CLIENTE AS customerId, L.N_DOC AS docNumber,
               L.VALOR AS amount, L.VALOR_JUROS AS interest, L.DATA_VENCIMENTO AS dueDate,
               L.ID_ESPECIE AS paymentSpeciesId, L.BAIXA AS isPaid,
               L.TIPO AS type, L.LBAIXA AS paymentDate
             FROM MOB_LISTACONTAS L ${where} ORDER BY L.DATA_VENCIMENTO`,
            params
        );

        // Normalizar: BAIXA é data quando pago, null quando em aberto
        for (const f of financials) {
            f.isPaid = f.isPaid != null && f.isPaid !== '' && f.isPaid !== 0;
            if (f.customerId != null) f.customerId = String(f.customerId);
        }

        logger.info('[Sync/Financials] Títulos enviados', { count: financials.length, source: 'firebird' });
        res.json({ financials, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) { next(err); }
});

module.exports = router;
