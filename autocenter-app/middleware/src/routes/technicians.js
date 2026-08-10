'use strict';

const express = require('express');
const router = express.Router();
const technicianService = require('../services/technician.service');

/**
 * POST /internal/technicians/sync
 * Recebe lote de técnicos do Worker ERP.
 * Autenticado via X-Internal-Key.
 */
router.post('/sync', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente no token interno.' });
        }

        const technicians = req.body;
        if (!Array.isArray(technicians) || technicians.length === 0) {
            return res.status(400).json({ error: 'Body deve ser um array não vazio de técnicos.' });
        }

        const result = await technicianService.upsertBatch(tenantId, technicians);
        res.status(200).json({
            synced: result.synced,
            skipped: result.skipped,
            message: `${result.synced} técnico(s) sincronizado(s) com sucesso.`,
        });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/technicians
 * Retorna lista de técnicos ativos para o mobile.
 */
router.get('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const list = await technicianService.findAll(tenantId);
        res.status(200).json(list);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
