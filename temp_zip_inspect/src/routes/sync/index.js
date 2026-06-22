'use strict';
/**
 * Router principal de sync — monta todos os sub-módulos em /api/sync/*.
 *
 * Refactoring: sync.js (1229 linhas) → 6 módulos com responsabilidade única.
 *
 * @module routes/sync/index
 *
 * Mapa de endpoints:
 *   catalog.js      → POST/GET /sellers, POST/GET /catalog
 *   customers.js    → POST/GET /customers, POST /new-customer,
 *                     GET /pending-customers, POST /confirm-customer/:id,
 *                     POST /error-customer/:id, PATCH /update-customer/:id
 *   financials.js   → POST/GET /payment-species, POST/GET /financials
 *   orders.js       → POST /orders
 *   natureza.js     → POST/GET /natureza, POST/GET /payment-conditions
 *   performance.js  → POST/GET /performance, POST/GET /sales-rankings,
 *                     GET /company-logo
 *   priceTables.js  → POST/GET /price-tables, POST/GET /product-prices
 */

const express    = require('express');
const catalog    = require('./catalog');
const customers  = require('./customers');
const financials = require('./financials');
const orders     = require('./orders');
const natureza   = require('./natureza');
const performance = require('./performance');
const priceTables = require('./priceTables');

const router = express.Router();

router.use(catalog);
router.use(customers);
router.use(financials);
router.use(orders);
router.use(natureza);
router.use(performance);
router.use(priceTables);

module.exports = router;

