'use strict';

const express = require('express');
const router = express.Router();
const quoteService = require('../services/quote.service');
const upload = require('../config/upload');

/**
 * POST /api/quotes
 * Cria um novo orçamento no status DRAFT
 */
router.post('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const deviceId = req.device.id;
        const branchId = req.branch?.id;
        
        const result = await quoteService.createDraft(tenantId, deviceId, req.body, branchId);
        res.status(201).json(result);
    } catch (err) {
        if (err.status === 409) {
            return res.status(409).json({ code: err.code, message: err.message });
        }
        next(err);
    }
});

/**
 * POST /api/quotes/:id/photos
 * Faz o upload de múltiplas fotos (max 10) e atrela ao respectivo Orçamento.
 */
router.post('/:id/photos', upload.array('files[]', 10), async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const quoteId = req.params.id;
        const files = req.files;

        if (!files || files.length === 0) {
            return res.status(400).json({ error: 'Nenhuma foto enviada.', code: 'BAD_REQUEST' });
        }

        const photoUrls = files.map(file => `/uploads/${file.filename}`);
        
        await quoteService.addQuotePhotos(tenantId, quoteId, photoUrls);
        
        res.status(201).json({ message: 'Fotos enviadas com sucesso', uploadedCount: files.length });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/quotes/history
 * Lista o histórico recente (últimas 50) de vistorias processadas por este aparelho.
 */
router.get('/history', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const deviceId = req.device.id;
        const data = await quoteService.getDeviceHistory(tenantId, deviceId);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/quotes/approved
 * Busca Fila de orçamentos autorizados a subir para o ERP pelo Worker
 */
router.get('/approved', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const branchId = req.branch?.id;
        const data = await quoteService.getApprovedQuotes(tenantId, branchId);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/quotes/vehicle/:plate
 * Lista orçamentos recentes de uma placa
 */
router.get('/vehicle/:plate', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const plate = req.params.plate;

        const data = await quoteService.getQuotesByPlate(tenantId, plate);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

/**
 * PATCH /api/quotes/:id/status
 * Altera status do orçamento (ex: DRAFT -> APPROVED)
 */
router.patch('/:id/status', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const quoteId = req.params.id;
        const { status } = req.body;

        if (!status) {
            return res.status(400).json({ error: 'Status é obrigatório' });
        }

        const data = await quoteService.updateStatus(tenantId, quoteId, status);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
