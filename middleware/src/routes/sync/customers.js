'use strict';
/**
 * Rotas de sync de clientes.
 *
 * @module routes/sync/customers
 * @route POST /api/sync/customers          — Worker push
 * @route POST /api/sync/new-customer       — Mobile cria cliente pendente
 * @route GET  /api/sync/pending-customers  — Worker busca pendentes
 * @route POST /api/sync/confirm-customer/:id
 * @route POST /api/sync/error-customer/:id
 * @route PATCH /api/sync/update-customer/:id
 * @route GET  /api/sync/customers          — App leitura
 */

const express = require('express');
const { fbQuery, makePushHandler, safeInt } = require('./helpers');
const { pgQuery } = require('../../db/postgres');
const { createError } = require('../../middleware/errorHandler');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ── Formatação de documentos para a SP MOB_CADASTRA_CLIENTE ──────────────────

function formatCpf(digits) {
    return digits.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4');
}
function formatCnpj(digits) {
    return digits.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
}
function formatCpfCnpj(raw) {
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 11) return formatCpf(d);
    if (d.length === 14) return formatCnpj(d);
    return raw;
}
function formatCep(raw) {
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 8) return `${d.slice(0, 5)}-${d.slice(5)}`;
    return raw;
}
function formatPhone(raw) {
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 11) return `(${d.slice(0, 2)})-${d.slice(2, 7)}-${d.slice(7)}`;
    if (d.length === 10) return `(${d.slice(0, 2)})-${d.slice(2, 6)}-${d.slice(6)}`;
    return raw;
}

// Export das funções de formatação para uso no worker se necessário
module.exports.formatPhone = formatPhone;
module.exports.formatCpfCnpj = formatCpfCnpj;

// ── POST /customers — Worker push ────────────────────────────────────────────

/** @route POST /api/sync/customers */
router.post('/customers', makePushHandler('customers', 'customers'));

// ── POST /new-customer — Mobile ──────────────────────────────────────────────

/**
 * Mobile cria novo cliente — salva no PostgreSQL como pendente.
 * O Worker processa e cadastra no Firebird via SP.
 * @route POST /api/sync/new-customer
 */
router.post('/new-customer', async (req, res, next) => {
    try {
        const b = req.body;
        if (!b.name || !b.name.trim()) {
            return res.status(400).json({ error: 'Campo "name" é obrigatório.' });
        }

        const companyId = req.company.id;
        const localId   = b.localId || null;

        const { rows } = await pgQuery(
            `INSERT INTO pending_customers (company_id, local_id, payload)
             VALUES ($1, $2, $3)
             RETURNING id`,
            [companyId, localId, JSON.stringify(b)]
        );

        const pendingId = rows[0].id;
        logger.info('[Sync/NewCustomer] Cliente salvo como pendente', {
            pendingId, localId, name: b.name, companyId,
        });
        res.status(201).json({ success: true, pendingId, status: 'pending' });
    } catch (err) {
        logger.error('[Sync/NewCustomer] Falha ao salvar cliente pendente', { error: err.message });
        next(err);
    }
});

// ── GET /resolve-local-customer — resolve local_ ID → ERP ID ─────────────────

/**
 * Busca o erp_customer_id confirmado para um cliente local.
 * Usado pelo Worker antes de inserir pedidos no Firebird.
 * @route GET /api/sync/resolve-local-customer?localId=local_xxx
 * @returns { found: bool, erpCustomerId: string|null }
 */
router.get('/resolve-local-customer', async (req, res, next) => {
    const companyId = req.company.id;
    const { localId } = req.query;

    if (!localId || !String(localId).startsWith('local_')) {
        return res.status(400).json({ found: false, error: 'localId inválido' });
    }

    try {
        const { rows } = await pgQuery(
            `SELECT erp_customer_id FROM pending_customers
             WHERE local_id = $1 AND company_id = $2 AND sync_status = 'synced'
             LIMIT 1`,
            [localId, companyId]
        );
        if (rows.length > 0 && rows[0].erp_customer_id) {
            logger.info('[Sync/ResolveCustomer] Resolvido', { localId, erpCustomerId: rows[0].erp_customer_id, companyId });
            return res.json({ found: true, erpCustomerId: rows[0].erp_customer_id });
        }
        logger.debug('[Sync/ResolveCustomer] Ainda pendente', { localId, companyId });
        return res.json({ found: false, erpCustomerId: null });
    } catch (err) {
        logger.error('[Sync/ResolveCustomer] Erro', { error: err.message });
        next(err);
    }
});

// ── GET /pending-customers — Worker busca ─────────────────────────────────────


/** @route GET /api/sync/pending-customers */
router.get('/pending-customers', async (req, res, next) => {
    const companyId = req.company.id;
    try {
        const { rows } = await pgQuery(
            `SELECT id, local_id, payload, created_at
             FROM   pending_customers
             WHERE  company_id = $1 AND sync_status = 'pending'
             ORDER  BY created_at ASC`,
            [companyId]
        );
        const customers = rows
            .filter(r => r.payload)
            .map(r => ({ ...r.payload, pendingId: r.id, localId: r.local_id, createdAt: r.created_at }));
        res.json({ customers });
    } catch (err) {
        logger.warn('[Sync/PendingCustomers] PostgreSQL indisponível', { companyId, error: err.message });
        res.json({ customers: [] });
    }
});

// ── POST /confirm-customer/:id — Worker confirma ──────────────────────────────

/** @route POST /api/sync/confirm-customer/:id */
router.post('/confirm-customer/:id', async (req, res, next) => {
    const companyId     = req.company.id;
    const pendingId     = req.params.id;
    const erpCustomerId = req.body?.erpCustomerId;

    if (!erpCustomerId) {
        return next(createError('Campo erpCustomerId é obrigatório', 400, 'MISSING_ERP_ID'));
    }

    try {
        const { rowCount } = await pgQuery(
            `UPDATE pending_customers
             SET    sync_status = 'synced', erp_customer_id = $1, updated_at = NOW()
             WHERE  id = $2 AND company_id = $3`,
            [String(erpCustomerId), pendingId, companyId]
        );
        if (!rowCount) {
            return next(createError('Cliente pendente não encontrado', 404, 'CUSTOMER_NOT_FOUND'));
        }
        logger.info('[Sync/ConfirmCustomer] Cliente confirmado no ERP', { pendingId, erpCustomerId, companyId });
        res.json({ ok: true, pendingId, erpCustomerId, confirmedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

// ── POST /error-customer/:id — Worker registra erro ───────────────────────────

/** @route POST /api/sync/error-customer/:id */
router.post('/error-customer/:id', async (req, res, next) => {
    const companyId = req.company.id;
    const pendingId = req.params.id;
    const message   = String(req.body?.errorMessage ?? 'Erro desconhecido').substring(0, 500);

    try {
        await pgQuery(
            `UPDATE pending_customers
             SET    sync_status = 'error', error_message = $1, updated_at = NOW()
             WHERE  id = $2 AND company_id = $3`,
            [message, pendingId, companyId]
        );
        logger.warn('[Sync/ErrorCustomer] Erro ao cadastrar cliente', { pendingId, message, companyId });
        res.json({ ok: true, pendingId, errorAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

// ── PATCH /update-customer/:id — Atualizar telefone/email ────────────────────

/**
 * Atualiza APENAS telefone e/ou e-mail de um cliente existente no ERP.
 * Por design: não permite alteração de dados cadastrais completos (segurança).
 * @route PATCH /api/sync/update-customer/:id
 */
router.patch('/update-customer/:id', async (req, res, next) => {
    try {
        const erpId = parseInt(req.params.id, 10);
        const { phone, email } = req.body;

        if (!erpId || isNaN(erpId)) {
            return res.status(400).json({ error: 'ID do cliente inválido.' });
        }
        if (!phone && !email) {
            return res.status(400).json({ error: 'Informe telefone e/ou e-mail para atualizar.' });
        }

        if (phone) {
            await fbQuery(req,
                `UPDATE CLIENTES_DADOS SET CELULAR = ?, FONE_RES = ? WHERE ID_CLIENTE = ?`,
                [formatPhone(phone), formatPhone(phone), erpId]
            );
        }
        if (email) {
            await fbQuery(req,
                `UPDATE CLIENTES SET EMAIL = ? WHERE ID_CLIENTE = ?`,
                [email.trim().toLowerCase(), erpId]
            );
        }

        logger.info('[Sync/UpdateContact] Contato atualizado', { erpId, phone: !!phone, email: !!email });
        res.json({ success: true });
    } catch (err) {
        logger.error('[Sync/UpdateContact] Falha ao atualizar contato', { error: err.message });
        next(err);
    }
});

// ── GET /customers — App leitura ─────────────────────────────────────────────

/**
 * Clientes via store ou Firebird direto.
 * Suporta paginação via ?page e ?limit.
 * @route GET /api/sync/customers?sellerId=<id>&page=1&limit=500
 */
router.get('/customers', async (req, res, next) => {
    try {
        const { sellerId, fresh } = req.query;
        const page  = Math.max(1, parseInt(req.query.page)  || 1);
        const limit = Math.min(1000, parseInt(req.query.limit) || 500);

        if (!fresh) {
            const companyId = req.company.id;
            // [FIX] Usa branchId do JWT para isolar clientes por filial
            const branchId = req.branch?.id || null;
            const cached = await store.get(companyId, 'customers', branchId);
            if (cached.data.length > 0) {
                let data = cached.data;
                if (sellerId) {
                    data = data.filter(c => {
                        const sId = String(c.sellerId || c.SELLERID || '');
                        return sId === String(sellerId) || !sId;
                    });
                }
                const total  = data.length;
                const start  = (page - 1) * limit;
                const paged  = data.slice(start, start + limit);
                const hasMore = start + limit < total;
                return res.json({ customers: paged, syncedAt: cached.syncedAt, page, hasMore, source: 'store' });
            }
        }

        // Fallback Firebird
        const filter      = `CL.CLASSIFICACAO IN (0, 2, 3, 4, 5, 6, 96, 97, 98, 99) AND CL.TIPO IN (1, 3, 4, 7, 8)`;
        const where       = sellerId ? `WHERE C.ID_VENDEDOR = ? AND ${filter}` : `WHERE ${filter}`;
        const params      = sellerId ? [sellerId] : [];
        const offset      = (page - 1) * limit;
        const safeLimit   = safeInt(limit, 500, 1, 1000);
        const safeOffset  = safeInt(offset, 0, 0, 100000);

        const customers = await fbQuery(
            req,
            `SELECT FIRST ${safeLimit} SKIP ${safeOffset}
               C.ID_CLIENTE AS id, C.NOME AS name, C.NOME_FANTASIA AS tradeName,
               C.CPF_CNPJ AS cnpj, C.FONE_RES AS phone, C.CELULAR AS mobile,
               C.EMAIL AS email, C.ENDERECO AS street, C.BAIRRO AS neighborhood,
               C.CEP AS zipCode, C.CIDADE AS city, C.UF AS state,
               C.ID_VENDEDOR AS sellerId, C.USUARIO AS sellerCode,
               COALESCE(C.LIMITE, 0) AS creditLimit, C.SITUACAO AS status
             FROM MOB_LISTACLIENTES C
             INNER JOIN CLIENTES CL ON CL.ID_CLIENTE = C.ID_CLIENTE
             ${where} ORDER BY C.NOME`,
            params
        );
        const hasMore = customers.length === limit;
        logger.info('[Sync/Customers] Clientes enviados', { count: customers.length, page, source: 'firebird' });
        res.json({ customers, syncedAt: new Date().toISOString(), page, hasMore, source: 'firebird' });
    } catch (err) { next(err); }
});

module.exports = router;
