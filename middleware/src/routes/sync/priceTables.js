'use strict';
/**
 * Rotas de sincronização de tabelas de preço.
 *
 * @module routes/sync/priceTables
 * @route POST /api/sync/price-tables    — Worker push de cabeçalhos
 * @route GET  /api/sync/price-tables    — App leitura
 * @route POST /api/sync/product-prices  — Worker push de preços produto×tabela
 * @route GET  /api/sync/product-prices  — App leitura
 * @route GET  /api/sync/company-settings — App lê configurações da empresa (priceTableMode)
 */

const express = require('express');
const { makePushHandler } = require('./helpers');
const store   = require('../../services/dataStore');
const { pool } = require('../../db/postgres');

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
        // [FIX] Usa branchId do JWT para isolar tabelas de preço por filial
        const branchId = req.branch?.id || null;
        const cached = await store.get(companyId, 'priceTables', branchId);
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
        // [FIX] Usa branchId do JWT para isolar preços por filial
        const branchId = req.branch?.id || null;
        const cached = await store.get(companyId, 'productPrices', branchId);
        res.json({ prices: cached.data, syncedAt: cached.syncedAt, source: 'store' });
    } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /company-settings — App lê configurações comportamentais da empresa
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Retorna as configurações da empresa para o App Mobile.
 *
 * @field priceTableMode    "none" | "product" | "prompt" — modo de tabela de preços
 * @field allowNegativeStock boolean — permite venda com estoque zero/negativo
 *
 * @route GET /api/sync/company-settings
 */
router.get('/company-settings', async (req, res, next) => {
    try {
        const companyId = req.company.id;

        // Busca configurações diretamente do PostgreSQL.
        // Degradação segura se migration pendente — retorna defaults.
        let priceTableMode    = 'none';
        let allowNegativeStock = false;
        try {
            const { rows } = await pool.query(
                'SELECT "PriceTableMode", "AllowNegativeStock" FROM companies WHERE "Id" = $1 LIMIT 1',
                [companyId]
            );
            if (rows.length > 0) {
                if (rows[0].PriceTableMode)     priceTableMode     = rows[0].PriceTableMode;
                if (rows[0].AllowNegativeStock !== undefined) allowNegativeStock = !!rows[0].AllowNegativeStock;
            }
        } catch (_) {
            // Colunas podem não existir se migrations ainda não rodaram — degradação segura
        }

        res.json({
            priceTableMode,
            allowNegativeStock,
            companyId,
            syncedAt: new Date().toISOString(),
        });
    } catch (err) { next(err); }
});


module.exports = router;

