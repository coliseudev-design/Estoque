'use strict';
/**
 * Rotas de sync de catálogo e vendedores.
 *
 * @module routes/sync/catalog
 * @route POST /api/sync/sellers   — Worker push
 * @route GET  /api/sync/sellers   — App leitura
 * @route POST /api/sync/catalog   — Worker push
 * @route GET  /api/sync/catalog   — App leitura (com paginação + delta)
 */

const express = require('express');
const { fbQuery, makePushHandler } = require('./helpers');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ─────────────────────────────────────────────────────────────────────────────
// POST /sellers  — Worker push de vendedores
// GET  /sellers  — App lê do dataStore ou Firebird direto
// ─────────────────────────────────────────────────────────────────────────────

/** @route POST /api/sync/sellers */
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
// POST /catalog  — Worker push de produtos
// GET  /catalog  — App lê do dataStore ou Firebird (com paginação + delta)
// ─────────────────────────────────────────────────────────────────────────────

/** @route POST /api/sync/catalog */
router.post('/catalog', makePushHandler('products', 'products'));

/**
 * Catálogo de produtos via store (Worker push) ou Firebird direto.
 * Suporta paginação via ?page e ?limit quando em modo Firebird.
 *
 * @route GET /api/sync/catalog?since=<ISO>&page=1&limit=500
 */
router.get('/catalog', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const cached = await store.get(companyId, 'products');
        if (cached.data.length > 0) {
            const { since } = req.query;
            const page  = Math.max(1, parseInt(req.query.page)  || 1);
            const limit = Math.min(1000, parseInt(req.query.limit) || 500);
            let data = cached.data;
            if (since) {
                data = data.filter(p => !p.updatedAt || p.updatedAt >= since);
            }
            const total  = data.length;
            const start  = (page - 1) * limit;
            const paged  = data.slice(start, start + limit);
            const hasMore = start + limit < total;
            return res.json({ products: paged, syncedAt: cached.syncedAt, page, hasMore, source: 'store' });
        }

        // Fallback: Firebird direto (modo dev local)
        const { since } = req.query;
        const page   = Math.max(1, parseInt(req.query.page)  || 1);
        const limit  = Math.min(1000, parseInt(req.query.limit) || 500);
        const offset = (page - 1) * limit;

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

        const rowsFirst = offset + 1;
        const rowsLast  = offset + limit;
        const whereClause = since ? `WHERE P.DATA_UP > ?` : '';
        const params = since ? [since, rowsFirst, rowsLast] : [rowsFirst, rowsLast];
        const sql = `${base} ${whereClause} ORDER BY P.DESCRICAO ROWS ? TO ?`;

        const products = await fbQuery(req.company, sql, params);
        const hasMore  = products.length === limit;

        logger.info('[Sync/Catalog] Catálogo enviado', { count: products.length, page, since: since || 'full', hasMore, source: 'firebird' });
        res.json({ products, syncedAt: new Date().toISOString(), page, hasMore, source: 'firebird' });
    } catch (err) {
        next(err);
    }
});

module.exports = router;
