'use strict';
/**
 * Rotas de sincronização de tabelas de preço.
 *
 * @module routes/sync/priceTables
 * @route POST /api/sync/price-tables   — Worker push de cabeçalhos
 * @route GET  /api/sync/price-tables   — App leitura
 * @route POST /api/sync/product-prices — Worker push de preços produto×tabela
 * @route GET  /api/sync/product-prices — App leitura
 */

const express = require('express');
const { makePushHandler } = require('./helpers');
const store  = require('../../services/dataStore');

const router = express.Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /price-tables  — Worker push de cabeçalhos das tabelas
// GET  /price-tables  — App lê do dataStore
// ─────────────────────────────────────────────────────────────────────────────

/** @route POST /api/sync/price-tables */
router.post('/price-tables', makePushHandler('priceTables', 'tables'));

/**
 * Tabelas de preço do store.
 * @route GET /api/sync/price-tables
 */
router.get('/price-tables', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'priceTables');
        res.json({ tables: cached.data, syncedAt: cached.syncedAt, source: 'store' });
    } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /product-prices  — Worker push de preços produto×tabela
// GET  /product-prices  — App lê do dataStore
// ─────────────────────────────────────────────────────────────────────────────

/** @route POST /api/sync/product-prices */
router.post('/product-prices', makePushHandler('productPrices', 'prices'));

/**
 * Preços produto×tabela do store.
 * @route GET /api/sync/product-prices
 */
router.get('/product-prices', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'productPrices');
        res.json({ prices: cached.data, syncedAt: cached.syncedAt, source: 'store' });
    } catch (err) { next(err); }
});

module.exports = router;
