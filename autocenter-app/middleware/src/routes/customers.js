'use strict';

const express = require('express');
const router  = express.Router();
const customerService = require('../services/customer.service');

/**
 * POST /internal/customers/sync
 * Recebe lote de clientes do Worker (sincronização Firebird → middleware).
 * Autenticado via X-Internal-Key (requireInternalAuth no app.js).
 *
 * Body: Array<CustomerDto>
 *   { erpId, name, fantasyName, cpfCnpj, phone, phone2, email, city, address, active }
 */
router.post('/sync', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente no token interno.' });
        }

        const customers = req.body;
        if (!Array.isArray(customers) || customers.length === 0) {
            return res.status(400).json({ error: 'Body deve ser um array não vazio de clientes.' });
        }

        const result = await customerService.upsertBatch(tenantId, customers);

        res.status(200).json({
            synced: result.synced,
            skipped: result.skipped,
            message: `${result.synced} cliente(s) sincronizado(s) com sucesso.`,
        });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /internal/customers
 * Lista todos os clientes de um tenant (para o app fazer download inicial).
 * Autenticado via X-Internal-Key OU JWT de dispositivo (reutilizable por ambos).
 *
 * Query params:
 *   ?search=texto   — busca por nome, CPF/CNPJ ou telefone
 *   ?limit=100      — limite de resultados (padrão 500)
 */
router.get('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const search = req.query.search?.trim() || '';
        const defaultLimitVal = search ? 500 : 1000000;
        const limit  = parseInt(req.query.limit || defaultLimitVal, 10);

        const customers = await customerService.findAll(tenantId, { search, limit });

        res.status(200).json(customers);
    } catch (err) {
        next(err);
    }
});

/**
 * POST /api/customers/new
 * Recebe novos clientes criados offline no mobile e salva em `pending_customers`.
 */
router.post('/new', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente no token.' });
        }

        const data = req.body;
        if (!data.name || (!data.localId && !data.local_id)) {
            return res.status(400).json({ error: 'Os campos "name" e "localId" são obrigatórios.' });
        }

        const result = await customerService.createPending(tenantId, data);
        res.status(201).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /api/customers/sync
 * Retorna lista paginada de clientes ERP para download do cliente.
 */
router.get('/sync', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const page = Math.max(parseInt(req.query.page || '1', 10), 1);
        const limit = Math.min(Math.max(parseInt(req.query.limit || '100', 10), 1), 500);
        const offset = (page - 1) * limit;
        const search = req.query.search?.trim() || '';

        const result = await customerService.findPaginated(tenantId, { search, limit, offset });

        res.status(200).json({
            page,
            limit,
            total: result.total,
            totalPages: Math.ceil(result.total / limit),
            customers: result.rows
        });
    } catch (err) {
        next(err);
    }
});

/**
 * GET /internal/customers/pending
 * Retorna os clientes pendentes de integração.
 */
router.get('/pending', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }
        const pending = await customerService.getPendingCustomers(tenantId);
        res.status(200).json(pending);
    } catch (err) {
        next(err);
    }
});

/**
 * POST /internal/customers/confirm/:pendingId
 * Confirma a integração do cliente informando o erpId definitivo.
 */
router.post('/confirm/:pendingId', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        const pendingId = req.params.pendingId;
        const { erpCustomerId } = req.body;

        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }
        if (!erpCustomerId) {
            return res.status(400).json({ error: 'erpCustomerId é obrigatório.' });
        }

        const result = await customerService.confirmCustomer(tenantId, pendingId, parseInt(erpCustomerId, 10));
        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * POST /internal/customers/error/:pendingId
 * Registra falha na integração do cliente.
 */
router.post('/error/:pendingId', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        const pendingId = req.params.pendingId;
        const { message } = req.body;

        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const result = await customerService.errorCustomer(tenantId, pendingId, message || 'Erro desconhecido');
        res.status(200).json(result);
    } catch (err) {
        next(err);
    }
});

/**
 * GET /internal/customers/:erpId
 * Busca cliente específico por ID do ERP.
 */
router.get('/:erpId', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        const erpId    = parseInt(req.params.erpId, 10);

        if (isNaN(erpId)) {
            return res.status(400).json({ error: 'erpId inválido.' });
        }

        const customer = await customerService.findByErpId(tenantId, erpId);

        if (!customer) {
            return res.status(404).json({ error: 'Cliente não encontrado.', code: 'NOT_FOUND' });
        }

        res.status(200).json(customer);
    } catch (err) {
        next(err);
    }
});

/**
 * POST /internal/customers
 * Cadastra um novo cliente individualmente.
 */
router.post('/', async (req, res, next) => {
    try {
        const tenantId = req.tenant?.id;
        if (!tenantId) {
            return res.status(400).json({ error: 'tenantId ausente.' });
        }

        const customer = await customerService.createCustomer(tenantId, req.body);
        res.status(201).json(customer);
    } catch (err) {
        next(err);
    }
});

module.exports = router;
