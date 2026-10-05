/**
 * Catálogo espelhado do ERP: busca, leitura de código e delta para o cache offline do app.
 */
'use strict';

const express = require('express');
const { z } = require('zod');
const db = require('../db');
const { route, parse, notFound } = require('../http');
const { requireUser } = require('../auth/middleware');

const router = express.Router();
router.use(requireUser());

router.get('/products', route(async (req, res) => {
    const q = parse(z.object({
        q: z.string().trim().max(80).default(''),
        limit: z.coerce.number().int().min(1).max(100).default(30),
    }), req.query);
    const term = q.q;
    const { rows } = await db.query(
        `SELECT p.erp_id, p.sku, p.description, p.unit, p.brand, p.group_name, p.stock::text AS stock,
                (SELECT array_agg(b.barcode) FROM product_barcodes b
                  WHERE b.tenant_id = p.tenant_id AND b.erp_id = p.erp_id) AS barcodes
           FROM products p
          WHERE p.tenant_id = $1 AND p.active
            AND ($2 = '' OR p.erp_id = $2 OR p.sku = $2
                 OR lower(p.description) LIKE lower($2) || '%'
                 OR p.description ILIKE '%' || $2 || '%'
                 OR EXISTS (SELECT 1 FROM product_barcodes b WHERE b.tenant_id = p.tenant_id
                             AND b.erp_id = p.erp_id AND b.barcode = $2))
          ORDER BY (p.erp_id = $2 OR p.sku = $2) DESC, p.description
          LIMIT $3`,
        [req.tenantId, term, q.limit],
    );
    res.json({ items: rows.map(mapProduct) });
}));

router.get('/products/barcode/:code', route(async (req, res) => {
    const { rows } = await db.query(
        `SELECT p.erp_id, p.sku, p.description, p.unit, p.brand, p.group_name, p.stock::text AS stock,
                b.factor::text AS factor
           FROM product_barcodes b
           JOIN products p ON p.tenant_id = b.tenant_id AND p.erp_id = b.erp_id
          WHERE b.tenant_id = $1 AND b.barcode = $2`,
        [req.tenantId, req.params.code.trim()],
    );
    if (!rows[0]) throw notFound('Código não cadastrado no ERP');
    res.json({ ...mapProduct(rows[0]), factor: rows[0].factor });
}));

/**
 * Delta do catálogo para o app trabalhar offline.
 * Cursor composto (updated_at, chave) — estável mesmo com muitos registros no mesmo instante.
 */
router.get('/catalog/delta', route(async (req, res) => {
    const q = parse(z.object({
        entity: z.enum(['products', 'barcodes']),
        since: z.string().datetime({ offset: true }).optional(),
        after: z.string().max(80).optional(),
        limit: z.coerce.number().int().min(1).max(5000).default(2000),
    }), req.query);
    const since = q.since || '1970-01-01T00:00:00Z';
    const after = q.after || '';

    if (q.entity === 'products') {
        const { rows } = await db.query(
            `SELECT erp_id, sku, description, unit, active, updated_at
               FROM products
              WHERE tenant_id = $1 AND (updated_at, erp_id) > ($2::timestamptz, $3)
              ORDER BY updated_at, erp_id LIMIT $4`,
            [req.tenantId, since, after, q.limit],
        );
        const last = rows[rows.length - 1];
        return res.json({
            items: rows.map((r) => ({ erpId: r.erp_id, sku: r.sku, description: r.description, unit: r.unit, active: r.active })),
            next: last ? { since: last.updated_at.toISOString(), after: last.erp_id } : null,
            done: rows.length < q.limit,
        });
    }

    const { rows } = await db.query(
        `SELECT barcode, erp_id, factor::text AS factor, updated_at
           FROM product_barcodes
          WHERE tenant_id = $1 AND (updated_at, barcode) > ($2::timestamptz, $3)
          ORDER BY updated_at, barcode LIMIT $4`,
        [req.tenantId, since, after, q.limit],
    );
    const last = rows[rows.length - 1];
    res.json({
        items: rows.map((r) => ({ barcode: r.barcode, erpId: r.erp_id, factor: r.factor })),
        next: last ? { since: last.updated_at.toISOString(), after: last.barcode } : null,
        done: rows.length < q.limit,
    });
}));

function mapProduct(r) {
    return {
        erpId: r.erp_id, sku: r.sku, description: r.description, unit: r.unit,
        brand: r.brand, group: r.group_name, stock: r.stock, barcodes: r.barcodes || undefined,
    };
}

module.exports = router;
