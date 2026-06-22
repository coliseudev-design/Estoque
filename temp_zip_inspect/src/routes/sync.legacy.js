/**
 * Rotas de sincronização — schema real PIVETA.FDB.
 *
 * Fluxo duplo:
 *   Worker .NET faz POST  → armazena no dataStore (dados do Firebird)
 *   App Flutter  faz GET  → lê do dataStore (com fallback para Firebird direto)
 *
 *  ENDPOINT                 GET (app)    POST (worker)
 *  ─────────────────────────────────────────────────
 *  /catalog                 ✓            ✓
 *  /sellers                 ✓            ✓
 *  /customers               ✓            ✓
 *  /payment-species         ✓            ✓
 *  /natureza                ✓            ✓
 *  /financials              ✓            ✓
 *  /orders                  -            ✓ (processa no ERP)
 *
 * @module routes/sync
 */
'use strict';

const express = require('express');
const fbManager = require('../services/firebird.manager');
const { pgQuery } = require('../db/postgres');
const { createError } = require('../middleware/errorHandler');
const store = require('../services/dataStore');
const logger = require('../config/logger');
const config = require('../config/env');

const router = express.Router();


// ──────────────────────────────────────────────────────────────────────────────
// POST handler genérico — usado pelo Worker para fazer push de dados
// Valida payload e armazena no dataStore.
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Executa uma query Firebird para a empresa, retornando [] se não configurado.
 * Empresas que usam o Worker não precisam de Firebird direto — o store é populado
 * pelo Worker. Essa função garante que rotas de fallback nunca quebrem com 500.
 *
 * @param {object} company   req.company com credenciais
 * @param {string} sql
 * @param {Array}  [params]
 * @returns {Promise<Array>}  resultado ou [] se Firebird não configurado/falhou
 */
async function fbQuery(company, sql, params = []) {
    if (!company.fb_host) return [];
    try {
        return await fbManager.queryFor(company, sql, params);
    } catch (err) {
        logger.warn('[Sync] Firebird direto indisponível', { companyId: company.id, error: err.message });
        return [];
    }
}

async function fbExec(company, sql, params = []) {
    if (!company.fb_host) throw new Error('Firebird não configurado para esta empresa');
    return fbManager.executeFor(company, sql, params);
}

function makePushHandler(entity, arrayKey) {
    return async function (req, res, next) {
        try {
            const companyId = req.company.id;
            const data = req.body[arrayKey];
            if (!Array.isArray(data)) {
                return next(createError(
                    `Campo "${arrayKey}" deve ser um array.`, 400, 'INVALID_PAYLOAD'
                ));
            }
            await store.upsert(companyId, entity, data);
            logger.info(`[Sync/${entity}] ${data.length} itens recebidos`, { companyId });
            res.json({ received: data.length, entity, syncedAt: new Date().toISOString() });
        } catch (err) {
            next(err);
        }
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Converte valor para inteiro seguro para interpolação em cláusulas Firebird
 * FIRST/SKIP que não suportam parâmetros posicionais (?).
 * Defesa contra SQL injection: garante que o valor é estritamente numérico.
 *
 * @param {*} val    Valor a converter
 * @param {number} fallback  Valor padrão se conversão falhar
 * @param {number} [min=0]   Valor mínimo permitido
 * @param {number} [max=10000] Valor máximo permitido
 * @returns {number} Inteiro seguro para interpolação
 */
function safeInt(val, fallback, min = 0, max = 10000) {
    const n = parseInt(val, 10);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(min, Math.min(max, n));
}

function validateOrder(order) {
    const required = ['id', 'customerId', 'sellerId', 'totalAmount', 'items', 'createdAt'];
    for (const field of required) {
        if (order[field] === undefined || order[field] === null) {
            return { valid: false, reason: `Campo obrigatório ausente: ${field}` };
        }
    }
    if (!Array.isArray(order.items) || order.items.length === 0) {
        return { valid: false, reason: 'items deve ser um array não vazio' };
    }
    if (typeof order.totalAmount !== 'number' || order.totalAmount < 0) {
        return { valid: false, reason: 'totalAmount inválido' };
    }
    const uuidRx = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidRx.test(order.id)) {
        return { valid: false, reason: 'id deve ser UUID v4' };
    }
    return { valid: true };
}

function padDate(d) {
    const dt = d instanceof Date ? d : new Date(d);
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
}

function padTime(d) {
    const dt = d instanceof Date ? d : new Date(d);
    return `${String(dt.getHours()).padStart(2, '0')}:${String(dt.getMinutes()).padStart(2, '0')}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/sellers
// FUNCIONARIOS WHERE MOB_ACESSO = 1
// Cols: ID_FUNCIONARIO, NOME, EMAIL, MOB_SENHA, DESCONTO_MAX, ID_MOBILE
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/sellers   ← lê do dataStore (enviado pelo Worker)
// POST /api/sync/sellers  ← Worker faz push dos dados do Firebird
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Worker → push de vendedores (recebido via POST).
 * @route POST /api/sync/sellers
 */
router.post('/sellers', makePushHandler('sellers', 'sellers'));

/**
 * Vendedores para o app mobile.
 * Retorna dados do Worker (store). Fallback: query direta ao Firebird.
 *
 * @route GET /api/sync/sellers
 */
router.get('/sellers', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'sellers');
        if (cached.data.length > 0) {
            return res.json({ sellers: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback: Firebird direto — só quando fb_host está configurado.
        // Worker-mode: retorna [] e o app aguarda o Worker fazer POST /sellers.
        let sellers = [];
        try {
            sellers = await fbQuery(req.company,
                `SELECT F.ID_FUNCIONARIO AS id, F.ID_MOBILE AS mobileId, F.NOME AS name,
                        F.EMAIL AS email, F.MOB_SENHA AS passwordHash,
                        F.DESCONTO_MAX AS maxDiscount, F.COMISSAO AS commissionRate
                 FROM FUNCIONARIOS F WHERE F.MOB_ACESSO = 1 ORDER BY F.NOME`);

            if (!sellers.length && req.company.fb_host) {
                sellers = await fbQuery(req.company,
                    `SELECT FIRST 50 F.ID_FUNCIONARIO AS id, F.ID_MOBILE AS mobileId,
                            F.NOME AS name, F.EMAIL AS email, F.MOB_SENHA AS passwordHash,
                            F.DESCONTO_MAX AS maxDiscount, F.COMISSAO AS commissionRate
                     FROM FUNCIONARIOS F ORDER BY F.NOME`);
            }
        } catch (e) {
            logger.warn('[Sync/Sellers] Fallback Firebird falhou, retornando vazio', { error: e.message });
            sellers = [];
        }

        const source = (sellers.length > 0 && req.company.fb_host) ? 'firebird' : 'pending_worker';
        logger.info('[Sync/Sellers] Vendedores enviados', { count: sellers.length, source });
        res.json({ sellers, syncedAt: new Date().toISOString(), source });
    } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/catalog   ← lê do dataStore + fallback Firebird
// POST /api/sync/catalog  ← Worker faz push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de produtos. @route POST /api/sync/catalog */
router.post('/catalog', makePushHandler('products', 'products'));

/**
 * Catálogo de produtos via store (Worker push) ou Firebird direto.
 * Suporta paginação via ?page e ?limit quando in modo Firebird.
 *
 * @route GET /api/sync/catalog?since=<ISO>&page=1&limit=500
 */
router.get('/catalog', async (req, res, next) => {
    try {
        // Retorna do store se Worker já enviou dados
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'products');
        if (cached.data.length > 0) {
            // Aplica filtro delta e paginação no store
            const { since } = req.query;
            const page = Math.max(1, parseInt(req.query.page) || 1);
            const limit = Math.min(1000, parseInt(req.query.limit) || 500);
            let data = cached.data;
            if (since) {
                data = data.filter(p => !p.updatedAt || p.updatedAt >= since);
            }
            const total = data.length;
            const start = (page - 1) * limit;
            const paged = data.slice(start, start + limit);
            const hasMore = start + limit < total;
            return res.json({ products: paged, syncedAt: cached.syncedAt, page, hasMore, source: 'store' });
        }

        // Fallback: Firebird direto (modo dev local)
        const { since } = req.query;
        const page = Math.max(1, parseInt(req.query.page) || 1);
        const limit = Math.min(1000, parseInt(req.query.limit) || 500);
        const offset = (page - 1) * limit;
        const rowsFirst = offset + 1;
        const rowsLast = offset + limit;

        const base = `SELECT
               P.ID_PRODUTO        AS code,
               P.DESCRICAO         AS name,
               P.DESCRICAO_ABREV   AS nameShort,
               P.ESTOQUE           AS stock,
               P.UNIDADE           AS unit,
               P.MARCA             AS brand,
               P.REF               AS reference,
               P.CODIGO_BARRA      AS barCode,
               P.DESCONTO_MAX      AS maxDiscount,
               P.DATA_UP           AS updatedAt,
               PP.PRECO_TABELA     AS price,
               PP.PRECO_MINIMO     AS priceMin,
               PP.PRECO_CUSTO      AS priceCost
             FROM PRODUTOS P
             LEFT JOIN PRODUTO_PRECOS PP
               ON PP.ID_PRODUTO = P.ID_PRODUTO
              AND PP.ATIVO = 1`;

        const whereClause = since ? `WHERE P.DATA_UP > ?` : '';
        const params = since ? [since, rowsFirst, rowsLast] : [rowsFirst, rowsLast];

        // ATENÇÃO: no Firebird, ORDER BY deve vir ANTES de ROWS x TO y
        const sql = `${base} ${whereClause} ORDER BY P.DESCRICAO ROWS ? TO ?`;

        const products = await fbQuery(req.company, sql, params);
        const hasMore = products.length === limit;

        logger.info('[Sync/Catalog] Catálogo enviado', { count: products.length, page, since: since || 'full', hasMore, source: 'firebird' });
        res.json({ products, syncedAt: new Date().toISOString(), page, hasMore, source: 'firebird' });
    } catch (err) {
        next(err);
    }
});


// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/customers   ← store + fallback Firebird
// POST /api/sync/customers  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de clientes. @route POST /api/sync/customers */
router.post('/customers', makePushHandler('customers', 'customers'));

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/new-customer ← Mobile cria novo cliente no ERP via SP
// ─────────────────────────────────────────────────────────────────────────────

// Helpers de formatação para a stored procedure MOB_CADASTRA_CLIENTE
function formatCpf(digits) {
    // 705.032.149-01
    return digits.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4');
}
function formatCnpj(digits) {
    // 29.639.089/0001-12
    return digits.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5');
}
function formatCpfCnpj(raw) {
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 11) return formatCpf(d);
    if (d.length === 14) return formatCnpj(d);
    return raw; // já formatado ou inválido — devolve como veio
}
function formatCep(raw) {
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 8) return `${d.slice(0, 5)}-${d.slice(5)}`;
    return raw;
}
function formatPhone(raw) {
    // Formato ERP: (67)-99227-5455 (celular 11d) ou (67)-3421-8237 (fixo 10d)
    if (!raw) return null;
    const d = raw.replace(/\D/g, '');
    if (d.length === 11) return `(${d.slice(0, 2)})-${d.slice(2, 7)}-${d.slice(7)}`;
    if (d.length === 10) return `(${d.slice(0, 2)})-${d.slice(2, 6)}-${d.slice(6)}`;
    return raw;
}

router.post('/new-customer', async (req, res, next) => {
    try {
        const b = req.body;

        if (!b.name || !b.name.trim()) {
            return res.status(400).json({ error: 'Campo "name" é obrigatório.' });
        }

        const companyId = req.company.id;
        const localId = b.localId || null;

        // Salva no PostgreSQL como pendente — o Worker processará no Firebird
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

        // Retorna pendingId para o mobile rastrear
        res.status(201).json({ success: true, pendingId, status: 'pending' });
    } catch (err) {
        logger.error('[Sync/NewCustomer] Falha ao salvar cliente pendente', { error: err.message });
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/pending-customers ← Worker busca clientes para cadastrar no ERP
// ─────────────────────────────────────────────────────────────────────────────
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
            .map(r => ({
                ...r.payload,
                pendingId: r.id,
                localId: r.local_id,
                createdAt: r.created_at,
            }));

        res.json({ customers });
    } catch (err) {
        logger.warn('[Sync/PendingCustomers] PostgreSQL indisponível', {
            companyId, error: err.message,
        });
        res.json({ customers: [] });
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/confirm-customer/:id ← Worker confirma cadastro no ERP
// ─────────────────────────────────────────────────────────────────────────────
router.post('/confirm-customer/:id', async (req, res, next) => {
    const companyId = req.company.id;
    const pendingId = req.params.id;
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

        logger.info('[Sync/ConfirmCustomer] Cliente confirmado no ERP', {
            pendingId, erpCustomerId, companyId,
        });
        res.json({ ok: true, pendingId, erpCustomerId, confirmedAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/error-customer/:id ← Worker registra erro no cadastro
// ─────────────────────────────────────────────────────────────────────────────
router.post('/error-customer/:id', async (req, res, next) => {
    const companyId = req.company.id;
    const pendingId = req.params.id;
    const message = String(req.body?.errorMessage ?? 'Erro desconhecido').substring(0, 500);

    try {
        await pgQuery(
            `UPDATE pending_customers
             SET    sync_status = 'error', error_message = $1, updated_at = NOW()
             WHERE  id = $2 AND company_id = $3`,
            [message, pendingId, companyId]
        );

        logger.warn('[Sync/ErrorCustomer] Erro ao cadastrar cliente', { pendingId, message, companyId });
        res.json({ ok: true, pendingId, errorAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// PATCH /api/sync/update-customer/:id ← Atualização restrita: só telefone e e-mail
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Atualiza APENAS telefone e/ou e-mail de um cliente existente no ERP.
 * Escrita direta em CLIENTES_DADOS (celular/fone_res) e CLIENTES (email).
 * Não permite alteração de dados cadastrais completos — segurança por design.
 *
 * @route PATCH /api/sync/update-customer/:id
 * @body { phone?, email? }
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

        // Atualiza telefone em CLIENTES_DADOS (CELULAR e FONE_RES)
        if (phone) {
            await fbQuery(req.company,
                `UPDATE CLIENTES_DADOS SET CELULAR = ?, FONE_RES = ? WHERE ID_CLIENTE = ?`,
                [formatPhone(phone), formatPhone(phone), erpId]
            );
        }
        if (email) {
            await fbQuery(req.company,
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


/**
 * Clientes via store ou Firebird direto.
 * Suporta paginação via ?page e ?limit para evitar respostas gigantes.
 * @route GET /api/sync/customers?sellerId=<id>&page=1&limit=500
 */
router.get('/customers', async (req, res, next) => {
    try {
        const { sellerId, fresh } = req.query;
        const page = Math.max(1, parseInt(req.query.page) || 1);
        const limit = Math.min(1000, parseInt(req.query.limit) || 500);

        // Store primeiro (a menos que fresh=1 seja pedido)
        if (!fresh) {
            const companyId = req.company.id;
            const cached = await store.get(companyId, 'customers');
            if (cached.data.length > 0) {
                let data = cached.data;
                if (sellerId) {
                    data = data.filter(c => {
                        const sId = String(c.sellerId || c.SELLERID || '');
                        return sId === String(sellerId) || !sId;
                    });
                }
                // Paginação no store
                const total = data.length;
                const start = (page - 1) * limit;
                const paged = data.slice(start, start + limit);
                const hasMore = start + limit < total;
                return res.json({
                    customers: paged,
                    syncedAt: cached.syncedAt,
                    page,
                    hasMore,
                    source: 'store',
                });
            }
        }

        // Fallback Firebird
        const filter = `CL.CLASSIFICACAO IN (0, 2, 3, 4, 5, 6, 96, 97, 98, 99) AND CL.TIPO IN (1, 3, 4, 7, 8)`;
        const where = sellerId ? `WHERE C.ID_VENDEDOR = ? AND ${filter}` : `WHERE ${filter}`;
        const params = sellerId ? [sellerId] : [];
        const offset = (page - 1) * limit;
        // safeInt garante que FIRST/SKIP são inteiros — Firebird não aceita ?
        const safeLimit = safeInt(limit, 500, 1, 1000);
        const safeOffset = safeInt(offset, 0, 0, 100000);

        const customers = await fbQuery(
            req.company,
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
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/payment-species   ← store + fallback Firebird
// POST /api/sync/payment-species  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de formas de pagamento. @route POST /api/sync/payment-species */
router.post('/payment-species', makePushHandler('paymentSpecies', 'species'));

/**
 * Formas/espécies de pagamento do store ou Firebird.
 * @route GET /api/sync/payment-species
 */
router.get('/payment-species', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'paymentSpecies');
        if (cached.data.length > 0) {
            return res.json({ paymentMethods: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird
        // MOB_ACESSO = 1 (INTEGER) conforme mapeamento ERP real: SELECT * FROM ESPECIE_PGTO WHERE (MOB_ACESSO = 1)
        const species = await fbQuery(req.company,
            `SELECT E.ID_ESPECIE AS id, TRIM(E.DESCRICAO) AS name, E.TIPO AS type, E.DIAS AS days
             FROM ESPECIE_PGTO E WHERE E.MOB_ACESSO = 1 ORDER BY E.DESCRICAO`);

        logger.info('[Sync/PaymentSpecies] Espécies enviadas', { count: species.length, source: 'firebird' });
        res.json({ paymentMethods: species, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/financials   ← store + fallback Firebird
// POST /api/sync/financials  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de títulos financeiros. @route POST /api/sync/financials */
router.post('/financials', makePushHandler('financials', 'financials'));

/**
 * Posição financeira via store ou Firebird.
 * @route GET /api/sync/financials?customerId=<id>
 */
router.get('/financials', async (req, res, next) => {
    try {
        const { customerId } = req.query;

        const companyId = req.company.id;
        const cached = await store.get(companyId, 'financials');
        if (cached && cached.data.length > 0) {
            const data = customerId
                ? cached.data.filter(f => {
                    // Worker ToCamelCase pode enviar como 'customerid' (all lower),
                    // 'customerId' (camelCase), ou 'CUSTOMERID' (upper)
                    const fCid = f.customerId ?? f.customerid ?? f.CUSTOMERID ?? f.customer_id;
                    return fCid != null && String(fCid) === String(customerId);
                })
                : cached.data;
            return res.json({ financials: data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird
        const where = customerId ? 'WHERE L.ID_CLIENTE = ?' : '';
        const params = customerId ? [customerId] : [];
        const financials = await fbQuery(req.company,
            `SELECT FIRST 500
               L.ID_CONTA AS id, L.ID_CLIENTE AS customerId, L.N_DOC AS docNumber,
               L.VALOR AS amount, L.VALOR_JUROS AS interest, L.DATA_VENCIMENTO AS dueDate,
               L.ID_ESPECIE AS paymentSpeciesId, L.BAIXA AS isPaid,
               L.TIPO AS type, L.LBAIXA AS paymentDate
             FROM MOB_LISTACONTAS L ${where} ORDER BY L.DATA_VENCIMENTO`,
            params
        );

        // Normalizar: Firebird BAIXA é data (quando pago) ou null (em aberto)
        for (const f of financials) {
            f.isPaid = f.isPaid != null && f.isPaid !== '' && f.isPaid !== 0;
            if (f.customerId != null) f.customerId = String(f.customerId);
        }

        logger.info('[Sync/Financials] Títulos enviados', { count: financials.length, source: 'firebird' });
        res.json({ financials, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/orders
// MOB_CADASTRAR_PEDIDO (11 params) → ID_PEDIDO via SELECT FROM PEDIDOS
// MOB_CADASTRAR_PEDIDO_ITEM (7 params)
//
// Assinatura confirmada pelo app de referência integrado ao ERP:
//   USUARIO, CLIENTE,
//   CAST(DATA AS VARCHAR(10) CHARSET WIN1252),
//   CAST(HORA AS VARCHAR(10) CHARSET WIN1252),
//   CAST(SUBSTRING(OBSERVACAO,1,100) AS VARCHAR(136) CHARSET UTF8),
//   CAST(SUBSTRING(PRAZO_PEDIDO,1,100) AS VARCHAR(130) CHARSET UTF8),
//   PAGAMENTO, VALOR_DESCONTO, TOTAL_PEDIDO, 1, CONDICAO_PAGAMENTO
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Recebe pedidos do app, verifica idempotência e grava no ERP.
 *
 * @route POST /api/sync/orders
 * @body  {{ orders: OrderPayload[] }}
 */
router.post('/orders', async (req, res, next) => {
    try {
        const { orders } = req.body;
        if (!Array.isArray(orders)) {
            return next(createError('O campo "orders" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }

        const results = { accepted: 0, duplicates: 0, errors: [] };

        for (const order of orders) {
            // ── 1. Validação estrutural ──────────────────────────────────────
            const { valid, reason } = validateOrder(order);
            if (!valid) {
                results.errors.push({ id: order.id || 'desconhecido', reason });
                continue;
            }

            // ── 2. Idempotência e Verificação de Existência ──────────────────
            let alreadySynced = false;
            try {
                // Verifica no PostgreSQL se o pedido já existe e está sincronizado
                const pgRes = await pgQuery(
                    'SELECT sync_status FROM orders WHERE id = $1 AND company_id = $2',
                    [order.id, req.company.id]
                );
                if (pgRes.rows.length > 0 && pgRes.rows[0].sync_status === 'synced') {
                    alreadySynced = true;
                }
            } catch (pgErr) {
                logger.debug('[Sync/Orders] Erro consulta idempotência PG', { error: pgErr.message });
            }

            if (alreadySynced) {
                logger.debug('[Sync/Orders] Pedido já sincronizado detectado', { orderId: order.id });
                results.duplicates++;
                continue;
            }

            const mode = config.syncMode; // direct | async | fallback
            let integratedInErp = false;
            let erpIdValue = null;

            // ── 3. Tentativa de Gravação Direta (se mode for direct ou fallback) ─
            if (mode === 'direct' || mode === 'fallback') {
                try {
                    const now = order.createdAt ? new Date(order.createdAt) : new Date();
                    const obs = (order.notes || '').substring(0, 100);

                    // PRAZO_PEDIDO: ID composto da condição de pagamento (FORMA_PGTO.ID_FORMA || '_' || ID_ESPECIE)
                    // ex: "4_2" para FORMA 4 / ESPECIE 2 ("4X BOLETO").
                    // A SP usa esse ID composto para buscar o plano de parcelamento em FORMA_PGTO.
                    // Referência: SyncAtendenteOrdersJob passa order.PaymentConditionId diretamente.
                    const condStr = String(order.paymentConditionId || '0');
                    const prazo   = condStr.substring(0, 20);

                    // PAGAMENTO: ID inteiro da espécie de pagamento (ESPECIE_PGTO.ID_ESPECIE)
                    const pagamentoId = Number(order.paymentSpeciesId || 1);


                    // O app envia dois níveis de desconto:
                    // 1. Desconto nos itens (já reduz o subtotal do pedido no app)
                    // 2. Desconto do pedido (aplicado sobre o subtotal já com desconto dos itens)
                    //
                    // Para o ERP processar igual:
                    // - TOTAL_PEDIDO: Subtotal de todos os itens (considerando o desconto individual deles).
                    // - VALOR_DESCONTO do Pedido: O desconto extra do pedido (não inclui desconto de item).
                    
                    const items = order.items || [];
                    
                    // O SUBTOTAL BRUTO PARA O PEDIDO (soma do Total de cada item APÓS desconto de item)
                    // e a soma dos DESCONTOS DE ITEM.
                    let itemDiscountsTotal = 0;
                    const subtotalAposDescontoItem = items.reduce((s, it) => {
                        const itGross = Number(it.unitPrice) * Number(it.quantity);
                        const itDisc  = itGross * (Number(it.discount || 0) / 100);
                        itemDiscountsTotal += itDisc;
                        return s + (itGross - itDisc);
                    }, 0);

                    // O desconto do pedido retornado do app inclui o desconto dos itens!
                    // Precisamos extrair apenas a parte 'extra' do pedido para mandar no F1.
                    const totalAppDiscount = Number(order.discountValue || 0);
                    const extraOrderDiscount = Math.max(0, totalAppDiscount - itemDiscountsTotal);

                    // SP MOB_CADASTRAR_PEDIDO — 10 parâmetros (verificado no Firebird 2026-02-23):
                    //   USUARIO, CLIENTE, DATA, HORA, OBSERVACAO, PRAZO_PEDIDO,
                    //   TIPO_OPERACAO, PAGAMENTO, VALOR_DESCONTO, TOTAL_PEDIDO
                    // WARNING-4 fix: valida inteiros antes de chamar SP — previne NaN no Firebird
                    const sellerIdNum   = Number(order.sellerId);
                    const customerIdNum = Number(order.customerId);
                    if (!Number.isInteger(sellerIdNum) || sellerIdNum <= 0)
                        throw new Error(`sellerId inválido: '${order.sellerId}' no pedido ${order.id}`);
                    if (!Number.isInteger(customerIdNum) || customerIdNum <= 0)
                        throw new Error(`customerId inválido: '${order.customerId}' no pedido ${order.id}`);

                    await fbExec(
                        req.company,
                        'EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(?,?,?,?,?,?,?,?,?,?)',
                        [
                            sellerIdNum,                           // 1. USUARIO
                            customerIdNum,                         // 2. CLIENTE
                            padDate(now),                          // 3. DATA
                            padTime(now),                          // 4. HORA
                            obs,                                   // 5. OBSERVACAO
                            prazo,                                 // 6. PRAZO_PEDIDO (condição desc.)
                            String(order.naturezaId || ''),        // 7. TIPO_OPERACAO (natureza)
                            pagamentoId,                           // 8. PAGAMENTO (espécie ID)
                            extraOrderDiscount,                    // 9. VALOR_DESCONTO do Pedido
                            subtotalAposDescontoItem               // 10. TOTAL_PEDIDO
                        ]
                    );

                    // BLOCKER-2 fix: usa GEN_ID(PEDIDOS, 0) para ler o valor ATUAL do generator
                    // sem incrementar — é exatamente o ID que a SP usou no gen_id(PEDIDOS, 1).
                    // Eliminando a race condition com vendedores concorrentes.
                    const lastRows = await fbQuery(
                        req.company,
                        'SELECT GEN_ID(PEDIDOS, 0) AS ID_PEDIDO FROM RDB$DATABASE'
                    );
                    erpIdValue = lastRows[0]?.ID_PEDIDO ?? lastRows[0]?.id_pedido;
                    if (erpIdValue) {
                        for (const item of items) {
                            const qty       = Number(item.quantity);
                            const unitPx    = Number(item.unitPrice);
                            const itemGross = unitPx * qty;

                            // Desconto APENAS do item (valor absoluto em R$)
                            const itemDiscR = itemGross * (Number(item.discount || 0) / 100);

                            // VALOR_TOTAL do item: subtotal APÓS desconto
                            const itemTotal = itemGross - itemDiscR;

                            // SP MOB_CADASTRAR_PEDIDO_ITEM — 7 parâmetros:
                            //   ID_PEDIDO, PRODUTO, QUANTIDADE, OBSERVACAO,
                            //   VALOR_UNITARIO, VALOR_DESCONTO, VALOR_TOTAL
                            await fbExec(
                                req.company,
                                'EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO_ITEM(?,?,?,?,?,?,?)',
                                [erpIdValue, item.productCode, qty, item.notes || '', unitPx, itemDiscR, itemTotal]
                            );
                        }
                        integratedInErp = true;
                        logger.info('[Sync/Orders] Pedido criado no ERP (Direct)', { uuid: order.id, erpIdValue });

                        // 3. Corrigir parcelas em PEDIDOS_DOCS
                        //    A SP sempre insere 1 parcela com valor BRUTO (hardcoded).
                        //    Aqui: deletamos e reinserimos N parcelas corretas com valor LÍQUIDO.
                        const nParcelas    = Math.max(1, Number(order.paymentInstallments || 1));
                        const diasParc     = Math.max(1, Number(order.paymentDaysPerInstallment || 30));
                        const diasEntrada  = Number(order.paymentEntryDays || 0);
                        // BLOCKER-1 fix: totalLiquido = value the customer actually pays
                        // (subtotal after item discounts MINUS the order-level extra discount)
                        // This aligns with Worker's order.TotalAmount (grandTotal from CartNotifier).
                        const totalLiquido = subtotalAposDescontoItem - extraOrderDiscount;
                        // SUGGESTION-3 fix: última parcela absorve centavo residual
                        const valorBase   = parseFloat((totalLiquido / nParcelas).toFixed(2));
                        const valorUltima = parseFloat((totalLiquido - valorBase * (nParcelas - 1)).toFixed(2));

                        // SUGGESTION-2 fix: inclui uuid do pedido no log para correlação
                        logger.info('[Sync/Orders] Parcelamento', {
                            uuid: order.id,
                            parcelas: nParcelas, valorBase, valorUltima,
                            diasEntrada, diasParcelas: diasParc
                        });

                        await fbExec(req.company,
                            'DELETE FROM PEDIDOS_DOCS WHERE ID_PEDIDO = ?',
                            [erpIdValue]);

                        for (let p = 1; p <= nParcelas; p++) {
                            const diasTotal = diasEntrada + diasParc * p;
                            const vencDate  = new Date(now);
                            vencDate.setDate(vencDate.getDate() + diasTotal);
                            const venc = padDate(vencDate);
                            // Última parcela absorve o centavo residual (SUGGESTION-3)
                            const valorAtual = (p === nParcelas) ? valorUltima : valorBase;

                            await fbExec(req.company,
                                `INSERT INTO PEDIDOS_DOCS
                                    (ID_PEDIDO, PARCELA, N_DOC, ID_ESPECIE, DATA_VENCIMENTO, VALOR, ID_CHEQUE, TIPO_CARTAO)
                                VALUES (?, ?, ?, ?, ?, ?, 0, 2)`,
                                [erpIdValue, p, String(p), pagamentoId, venc, valorAtual]
                            );
                        }
                    }
                } catch (err) {
                    if (mode === 'direct') {
                        logger.error('[Sync/Orders] Falha direct (modo direct)', { error: err.message });
                        results.errors.push({ id: order.id, reason: err.message });
                        continue;
                    }
                    logger.warn('[Sync/Orders] Falha direct -> Fallback para Async', { error: err.message });
                }
            }

            // ── 4. Persistência no PostgreSQL (Delegada ou Sincronização de Status) ─
            try {
                const companyId = req.company.id;
                const status = integratedInErp ? 'synced' : 'pending';

                await pgQuery(
                    `INSERT INTO orders
                        (id, company_id, sync_status, erp_order_id, customer_name, seller_name, total_amount, payload, created_at)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
                     ON CONFLICT (id) DO UPDATE SET
                        sync_status = EXCLUDED.sync_status,
                        erp_order_id = COALESCE(EXCLUDED.erp_order_id, orders.erp_order_id),
                        payload = COALESCE(orders.payload, EXCLUDED.payload),
                        updated_at = NOW()`,
                    [
                        order.id,
                        companyId,
                        status,
                        erpIdValue ? String(erpIdValue) : null,
                        order.customerName ?? String(order.customerId),
                        order.sellerName ?? String(order.sellerId),
                        Number(order.totalAmount) || 0,
                        JSON.stringify(order),   // Bug2 fix: payload completo para o Worker
                    ]
                );

                results.accepted++;
                logger.info(`[Sync/Orders] Pedido registrado como ${status}`, {
                    uuid: order.id, companyId, erpId: erpIdValue
                });

            } catch (pgErr) {
                // Se falhou no PG mas já integrou no ERP (em modo direct/fallback), o usuário deve saber
                if (integratedInErp) {
                    results.accepted++; // ERP prevalece
                    logger.warn('[Sync/Orders] Integrado no ERP porém falha ao salvar no Log PG', { error: pgErr.message });
                } else {
                    logger.error('[Sync/Orders] Falha crítica: impossível enfileirar pedido', { error: pgErr.message });
                    results.errors.push({ id: order.id, reason: 'Erro interno ao enfileirar pedido (DB Offline)' });
                }
            }
        }

        res.json(results);
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/natureza   ← store + fallback Firebird
// POST /api/sync/natureza  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de naturezas de operação. @route POST /api/sync/natureza */
router.post('/natureza', makePushHandler('natureza', 'naturezas'));

/**
 * Naturezas de operação habilitadas para mobile.
 * Retorna do store (Worker push) com fallback para Firebird direto.
 * @route GET /api/sync/natureza
 */
router.get('/natureza', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'natureza');
        if (cached.data.length > 0) {
            return res.json({ natureza: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird direto
        let natureza = [];
        try {
            natureza = await fbQuery(
                req.company,
                `SELECT N.ID_NATUREZA AS id, TRIM(N.DESCRICAO) AS descricao, N.MOB_ORDEM AS mobOrdem
                 FROM NATUREZA_OPERACAO N WHERE N.MOB_ACESSO = 1 ORDER BY N.MOB_ORDEM, N.DESCRICAO`
            );
        } catch (dbErr) {
            logger.warn('[Sync/Natureza] Tabela NATUREZA_OPERACAO não encontrada — retornando vazio.', {
                hint: 'Verifique se a tabela existe no banco com: node scripts/list_mob_objects.js',
                error: dbErr.message,
            });
        }

        logger.info('[Sync/Natureza] Naturezas de operação enviadas', { count: natureza.length, source: 'firebird' });
        res.json({ natureza, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) {
        next(err);
    }
});


// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/payment-conditions  ← store + fallback Firebird (FORMA_PGTO)
// POST /api/sync/payment-conditions ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/** Worker → push de condições de pagamento. @route POST /api/sync/payment-conditions */
router.post('/payment-conditions', makePushHandler('paymentConditions', 'conditions'));

/**
 * Condições de pagamento (FORMA_PGTO) via store ou Firebird.
 * Retorna { data: [...], syncedAt, source }.
 *
 * @route GET /api/sync/payment-conditions
 */
router.get('/payment-conditions', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'paymentConditions');
        if (cached.data.length > 0) {
            return res.json({ data: cached.data, syncedAt: cached.syncedAt, source: 'store' });
        }

        // Fallback Firebird direto (modo desenvolvimento local)
        // Tabela CORRETA conforme mapeamento ERP: MOB_TABELAFORMASPAGTO
        // Sem filtro de acesso — todas as condições disponíveis são enviadas.
        // O campo EspecieId (ID_FORMA_PAGAMENTO) vincula condição ↔ espécie de pagamento.
        let conditions = [];
        try {
            // Updated to respect FORMA_PGTO_PERMISSAO, matching Worker logic
            conditions = await fbQuery(
                req.company,
                `SELECT DISTINCT 
                        (F.ID_FORMA || '_' || FP.ID_ESPECIE) AS id, 
                        TRIM(F.DESCRICAO) AS descricao,
                        FP.ID_ESPECIE AS especieId, F.PARCELAS AS parcelas,
                        F.DESCONTO_MAX AS descontoMax
                 FROM FORMA_PGTO F 
                 INNER JOIN FORMA_PGTO_PERMISSAO FP ON FP.ID_FORMA = F.ID_FORMA
                 INNER JOIN ESPECIE_PGTO E ON E.ID_ESPECIE = FP.ID_ESPECIE
                 WHERE F.MOB_ACESSO = 1 AND E.MOB_ACESSO = 1 
                 ORDER BY F.DESCRICAO`
            );
        } catch (dbErr) {
            logger.warn('[Sync/PaymentConditions] Tabela FORMA_PGTO não acessível — retornando vazio.', {
                hint: 'Verifique se a tabela FORMA_PGTO existe no banco com MOB_ACESSO e MOB_ORDEM.',
                error: dbErr.message,
            });
        }

        logger.info('[Sync/PaymentConditions] Condições enviadas', { count: conditions.length, source: 'firebird' });
        res.json({ data: conditions, syncedAt: new Date().toISOString(), source: 'firebird' });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/performance ← Worker envia KPIs do MINHASVENDAS
// ─────────────────────────────────────────────────────────────────────────────
router.post('/performance', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const data = req.body.performance;
        if (!Array.isArray(data)) {
            return next(createError(
                'Campo "performance" deve ser um array.', 400, 'INVALID_PAYLOAD'
            ));
        }
        await store.upsert(companyId, 'performance', data);
        logger.info(`[Sync/Performance] ${data.length} KPIs recebidos do Worker`, { companyId });
        res.json({ received: data.length, entity: 'performance', syncedAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/performance  ← Mobile busca KPIs do vendedor
// Lê do dataStore (populado pelo Worker). Fallback para Firebird direto se disponível.
// ─────────────────────────────────────────────────────────────────────────────
router.get('/performance', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year = parseInt(req.query.year) || now.getFullYear();

        // 1. Tenta ler do dataStore (dados do Worker — caminho principal)
        const cached = await store.get(companyId, 'performance');
        if (cached && cached.data.length > 0) {
            const sellerKpis = cached.data.find(
                k => String(k.sellerId) === String(sellerId)
                    && k.month === month
                    && k.year === year
            );
            if (sellerKpis) {
                logger.info('[Sync/Performance] KPIs retornados', {
                    sellerId, month, year,
                    vendaMensal: sellerKpis.vendaMensal,
                    metaMensal: sellerKpis.metaMensal,
                    source: 'dataStore',
                });
                return res.json({ data: sellerKpis, source: 'dataStore' });
            }
        }

        // 2. Fallback: Firebird direto (pode falhar se não acessível do Docker)
        const today = now.toISOString().split('T')[0];
        const firstDay = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay = new Date(year, month, 0).toISOString().split('T')[0];
        const empresaId = parseInt(req.query.empresaId) || 1;

        const [mainRows, rangeRows] = await Promise.all([
            fbQuery(req.company,
                'EXECUTE PROCEDURE MINHASVENDAS(?, ?, ?, ?)',
                [parseInt(sellerId), month, year, today]
            ),
            fbQuery(req.company,
                'EXECUTE PROCEDURE MINHASVENDASR(?, ?, ?, ?, ?)',
                [parseInt(sellerId), firstDay, lastDay, today, empresaId]
            ),
        ]);

        const main = mainRows[0] || {};
        const range = rangeRows[0] || {};

        const performance = {
            sellerId: parseInt(sellerId),
            month,
            year,
            syncedAt: now.toISOString(),
            vendaDiaria: parseFloat(main.VENDA_DIARIA) || 0,
            vendaMensal: parseFloat(main.VENDA_MENSAL) || 0,
            comissaoDiaria: parseFloat(main.COMISSAO_DIARIA) || 0,
            comissaoMensal: parseFloat(main.COMISSAO_MENSAL) || 0,
            metaDiaria: parseFloat(main.META_DIARIA) || 0,
            metaMensal: parseFloat(main.META_MENSAL) || 0,
            servicoMensal: parseFloat(main.SERVICO_MENSAL) || 0,
            comissaoSvMensal: parseFloat(main.COMISSAO_SV_MENSAL) || 0,
            totalDiario: parseFloat(range.TOTAL_DIARIO) || 0,
            totalMensal: parseFloat(range.TOTAL_MENSAL) || 0,
            comissaoDiariaR: parseFloat(range.COMISSAO_DIARIA) || 0,
            comissaoMensalR: parseFloat(range.COMISSAO_MENSAL) || 0,
        };

        const source = mainRows.length > 0 ? 'firebird' : 'empty';
        logger.info('[Sync/Performance] KPIs retornados', {
            sellerId, month, year,
            vendaMensal: performance.vendaMensal,
            metaMensal: performance.metaMensal,
            source,
        });

        if (source === 'empty') {
            return res.json({ data: null, source });
        }

        res.json({ data: performance, source });
    } catch (err) {
        logger.error('[Sync/Performance] Erro ao consultar procedures', { error: err.message });
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/sync/sales-rankings ← Worker envia rankings de vendas (L_VENDAS_*)
// ─────────────────────────────────────────────────────────────────────────────
router.post('/sales-rankings', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const data = req.body.rankings;
        if (!Array.isArray(data)) {
            return next(createError(
                'Campo "rankings" deve ser um array.', 400, 'INVALID_PAYLOAD'
            ));
        }
        await store.upsert(companyId, 'sales-rankings', data);
        logger.info(`[Sync/SalesRankings] ${data.length} vendedores recebidos do Worker`, { companyId });
        res.json({ received: data.length, entity: 'sales-rankings', syncedAt: new Date().toISOString() });
    } catch (err) {
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/sales-rankings ← Mobile busca rankings do vendedor
// Lê do dataStore (populado pelo Worker).
// ─────────────────────────────────────────────────────────────────────────────
router.get('/sales-rankings', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year = parseInt(req.query.year) || now.getFullYear();

        const cached = await store.get(companyId, 'sales-rankings');
        if (cached && cached.data && cached.data.length > 0) {
            const sellerRankings = cached.data.find(
                k => String(k.sellerId) === String(sellerId)
                    && k.month === month
                    && k.year === year
            );
            if (sellerRankings) {
                logger.info('[Sync/SalesRankings] Rankings retornados', {
                    sellerId, month, year,
                    topProducts: sellerRankings.topProducts?.length || 0,
                    topClients: sellerRankings.topClients?.length || 0,
                    byRegion: sellerRankings.byRegion?.length || 0,
                    source: 'dataStore',
                });
                return res.json({ data: sellerRankings, source: 'dataStore' });
            }
        }

        // Sem dados cacheados
        logger.info('[Sync/SalesRankings] Sem rankings para vendedor', { sellerId, month, year });
        res.json({ data: null, source: 'empty' });
    } catch (err) {
        logger.error('[Sync/SalesRankings] Erro', { error: err.message });
        next(err);
    }
});

// ═══════════════════════════════════════════════════════════════════════════
// GET /api/sync/company-logo — Logo da empresa (imagem PNG/JPG)
// ═══════════════════════════════════════════════════════════════════════════

router.get('/company-logo', async (req, res, next) => {
    try {
        const companyId = req.company?.id;
        if (!companyId) {
            return res.status(401).json({ error: 'Empresa não identificada.' });
        }

        // Busca logo_base64 diretamente da tabela companies (Identity PostgreSQL)
        const { rows } = await pgQuery(
            `SELECT "LogoBase64" AS logo_base64 FROM companies WHERE "Id" = $1 LIMIT 1`,
            [companyId]
        );

        if (!rows.length || !rows[0].logo_base64) {
            return res.status(404).json({ error: 'Nenhuma logo cadastrada.' });
        }

        let base64 = rows[0].logo_base64;
        let contentType = 'image/png';

        // Remove prefixo data:image/... se presente
        if (base64.startsWith('data:')) {
            const commaIdx = base64.indexOf(',');
            if (commaIdx > 0) {
                const header = base64.substring(0, commaIdx);
                if (header.includes('jpeg') || header.includes('jpg')) contentType = 'image/jpeg';
                base64 = base64.substring(commaIdx + 1);
            }
        }

        const buffer = Buffer.from(base64, 'base64');
        res.set('Content-Type', contentType);
        res.set('Content-Length', buffer.length);
        res.set('Cache-Control', 'public, max-age=3600'); // Cache 1h
        res.send(buffer);

        logger.info('[Sync/CompanyLogo] Logo servida', { companyId, bytes: buffer.length });
    } catch (err) {
        logger.error('[Sync/CompanyLogo] Erro', { error: err.message });
        next(err);
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/price-tables   ← store (Worker push)
// POST /api/sync/price-tables  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Worker → push de cabeçalhos das tabelas de preço.
 * @route POST /api/sync/price-tables
 */
router.post('/price-tables', makePushHandler('priceTables', 'tables'));

/**
 * Tabelas de preço do store.
 * @route GET /api/sync/price-tables
 */
router.get('/price-tables', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'priceTables');
        res.json({ tables: cached.data, syncedAt: cached.syncedAt, source: 'store' });
    } catch (err) { next(err); }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/sync/product-prices   ← store (Worker push via MOB_TABELAPRECO)
// POST /api/sync/product-prices  ← Worker push
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Worker → push de preços por produto × tabela (MOB_TABELAPRECO).
 * @route POST /api/sync/product-prices
 */
router.post('/product-prices', makePushHandler('productPrices', 'prices'));

/**
 * Preços produto × tabela via store.
 * Suporta filtro por ?priceTableId=<id>
 * @route GET /api/sync/product-prices
 */
router.get('/product-prices', async (req, res, next) => {
    try {
        const companyId  = req.company.id;
        const { priceTableId } = req.query;
        const cached = await store.get(companyId, 'productPrices');
        const data = priceTableId
            ? cached.data.filter(p => String(p.priceTableId ?? p.pricetableid ?? '') === String(priceTableId))
            : cached.data;
        res.json({ prices: data, syncedAt: cached.syncedAt, source: 'store' });
    } catch (err) { next(err); }
});

module.exports = router;

