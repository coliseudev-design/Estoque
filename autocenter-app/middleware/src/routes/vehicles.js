'use strict';

const express = require('express');
const router = express.Router();
const vehicleService = require('../services/vehicle.service');
const { externalApiLimit } = require('../middleware/rateLimiter');

/**
 * GET /api/vehicles/:plate
 * Consulta os dados do veículo, usando cache Redis ou APIBrasil.
 * Aplica um rate limit estrito (externalApiLimit) pois consultar a APIBrasil custa crédito.
 */
router.get('/:plate', externalApiLimit, async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const plate = req.params.plate;

        const data = await vehicleService.fetchVehicleByPlate(plate, tenantId);
        
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/vehicles/customer/:customerId
 * Retorna todos os veículos associados a um cliente específico.
 */
router.get('/customer/:customerId', async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const customerId = parseInt(req.params.customerId, 10);

        if (isNaN(customerId)) {
            return res.status(400).json({ error: 'ID do cliente inválido.', code: 'BAD_REQUEST' });
        }

        const data = await vehicleService.getVehiclesByCustomer(customerId, tenantId);
        res.status(200).json(data);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
