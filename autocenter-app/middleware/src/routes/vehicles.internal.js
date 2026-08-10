'use strict';

const express = require('express');
const router = express.Router();
const vehicleService = require('../services/vehicle.service');

/**
 * POST /internal/vehicles/sync
 * Sincroniza em lote os veículos do ERP.
 */
router.post('/sync', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente no token.' });
        }

        const vehicles = req.body;
        if (!Array.isArray(vehicles)) {
            return res.status(400).json({ error: 'O corpo da requisição deve ser uma lista de veículos.' });
        }

        const result = await vehicleService.upsertBatch(tenantId, vehicles);
        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /internal/vehicles/:plate
 * Retorna os detalhes do veículo por placa (se não existir, consulta parceiro e cache).
 */
router.get('/:plate', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const plate = req.params.plate;
        const data = await vehicleService.fetchVehicleByPlate(plate, tenantId);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
