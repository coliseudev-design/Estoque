/**
 * cacheWarm.js — Endpoint de cache warming (POST /api/sync/cache/warm).
 *
 * Permite que o Flutter ou o Worker façam re-push em massa de dados
 * quando detectam que o Redis está vazio (source: 'empty').
 *
 * Body:
 *   {
 *     products?:           [],
 *     sellers?:            [],
 *     customers?:          [],
 *     paymentSpecies?:     [],
 *     paymentConditions?:  [],
 *     natureza?:           [],
 *   }
 *
 * Resposta: { warmed: ['products', ...], skipped: ['sellers'] }
 *
 * @module routes/cacheWarm
 */
'use strict';

const express = require('express');
const store = require('../services/dataStore');
const logger = require('../config/logger');
const router = express.Router();

const ALLOWED_ENTITIES = [
    'products', 'sellers', 'customers',
    'paymentSpecies', 'paymentConditions', 'natureza',
];

router.post('/', async (req, res, next) => {
    const companyId = req.company.id;
    const body = req.body || {};

    try {
        const warmed = [];
        const skipped = [];

        for (const entity of ALLOWED_ENTITIES) {
            const data = body[entity];
            if (!Array.isArray(data) || data.length === 0) {
                skipped.push(entity);
                continue;
            }
            await store.upsert(companyId, entity, data);
            warmed.push(entity);
        }

        logger.info('[CacheWarm] Re-warm concluído', { companyId, warmed, skippedCount: skipped.length });

        res.json({
            ok: true,
            companyId,
            warmed,
            skipped,
            warmedAt: new Date().toISOString(),
        });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
