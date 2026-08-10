'use strict';

const express = require('express');
const router = express.Router();
const serviceOrderService = require('../services/service-order.service');
const upload = require('../config/upload');
const logger = require('../config/logger');

/**
 * POST /api/service-orders
 * Cria uma nova Ordem de Serviço
 */
router.post('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const deviceId = req.device.id;

        logger.info('[ServiceOrdersRoute] Recebido POST /api/service-orders', { body: req.body });

        const result = await serviceOrderService.createServiceOrder(tenantId, deviceId, req.body);
        res.status(201).json(result);
    } catch (err) {
        logger.error('[ServiceOrdersRoute] Erro ao criar OS', { error: err.message, body: req.body });
        next(err);
    }
});

/**
 * GET /api/service-orders
 * Lista as ordens de serviço com paginação e filtros (placa/status)
 */
router.get('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { page, limit, status, plate } = req.query;

        const result = await serviceOrderService.listServiceOrders(tenantId, { page, limit, status, plate });
        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/service-orders/approved
 * Busca as OS aprovadas para o Worker sincronizar (X-Internal-Key ou JWT do dispositivo)
 */
router.get('/approved', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const data = await serviceOrderService.getApprovedServiceOrders(tenantId);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/service-orders/:id
 * Detalha uma Ordem de Serviço específica
 */
router.get('/:id', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const id = req.params.id;

        const result = await serviceOrderService.getServiceOrderDetail(tenantId, id);
        if (!result) {
            return res.status(404).json({ error: 'Ordem de Serviço não encontrada.', code: 'NOT_FOUND' });
        }

        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * PATCH /api/service-orders/:id/status
 * Atualiza o status de uma Ordem de Serviço
 */
router.patch('/:id/status', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const id = req.params.id;
        const { status } = req.body;

        if (!status) {
            return res.status(400).json({ error: 'Status é obrigatório' });
        }

        const result = await serviceOrderService.updateStatus(tenantId, id, status);
        if (!result) {
            return res.status(404).json({ error: 'Ordem de Serviço não encontrada.', code: 'NOT_FOUND' });
        }

        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * POST /api/service-orders/:id/photos
 * Faz o upload de múltiplas fotos (max 10) e anexa à Ordem de Serviço
 */
router.post('/:id/photos', upload.array('files[]', 10), async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const id = req.params.id;
        const files = req.files;

        if (!files || files.length === 0) {
            return res.status(400).json({ error: 'Nenhuma foto enviada.', code: 'BAD_REQUEST' });
        }

        const photoUrls = files.map(file => `/uploads/${file.filename}`);
        await serviceOrderService.addServiceOrderPhotos(tenantId, id, photoUrls);

        res.status(201).json({ message: 'Fotos enviadas com sucesso', uploadedCount: files.length });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
