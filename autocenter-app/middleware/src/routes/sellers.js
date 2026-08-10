'use strict';

const express = require('express');
const router = express.Router();
const sellerService = require('../services/seller.service');
const { requireInternalAuth, requireDeviceJwt } = require('../middleware/auth');

/**
 * POST /internal/sellers/sync
 * Recebe lote de vendedores do Worker ERP.
 * Autenticado via X-Internal-Key.
 */
router.post('/sync', requireInternalAuth, async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente no token interno.' });
        }

        const sellers = req.body;
        if (!Array.isArray(sellers) && req.body.sellers) {
            // Se vier encapsulado em { sellers: [...] }
            return res.status(400).json({ error: 'Body deve ser um array não vazio de vendedores.' });
        }
        
        const list = Array.isArray(sellers) ? sellers : (req.body.sellers || []);
        if (list.length === 0) {
            return res.status(400).json({ error: 'Nenhum vendedor fornecido para sincronização.' });
        }

        const result = await sellerService.upsertBatch(tenantId, list);
        res.status(200).json({
            synced: result.synced,
            skipped: result.skipped,
            message: `${result.synced} vendedor(es) sincronizado(s) com sucesso.`,
        });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/sellers
 * Retorna lista de vendedores ativos para o mobile.
 * Autenticado via Device JWT (requireDeviceJwt é aplicado globalmente no app.js na rota /api, mas esta rota é montada sob /api/sellers).
 */
router.get('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id || req.query.tenantId;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const list = await sellerService.findAll(tenantId);
        res.status(200).json({ sellers: list });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
