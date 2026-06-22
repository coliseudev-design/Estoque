'use strict';
/**
 * Rota para gerenciar os dados da empresa (Firebird EMPRESA -> VPS).
 *
 * @module routes/sync/company
 * @route POST /api/sync/company-data
 * @route GET  /api/sync/company-data
 */

const express = require('express');
const { createError } = require('../../middleware/errorHandler');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

/** @route POST /api/sync/company-data */
router.post('/company-data', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const data = req.body.company;
        if (!data || !Array.isArray(data)) {
            return next(createError('Campo "company" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }
        await store.upsert(companyId, 'company-data', data);
        logger.info(`[Sync/Company] Dados da empresa atualizados pelo Worker`, { companyId });
        res.json({ received: data.length, entity: 'company-data', syncedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

/** @route GET /api/sync/company-data */
router.get('/company-data', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'company-data');
        if (cached && cached.data && cached.data.length > 0) {
            return res.json({ data: cached.data[0], source: 'dataStore' });
        }
        logger.info('[Sync/Company] Sem dados da empresa no store', { companyId });
        res.json({ data: null, source: 'empty' });
    } catch (err) {
        logger.error('[Sync/Company] Erro', { error: err.message });
        next(err);
    }
});

module.exports = router;
