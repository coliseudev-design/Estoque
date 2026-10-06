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
// Autenticação POR ROTA, não router.use(): este router fica montado em /v1 e um
// router.use() aqui interceptava TODA requisição /v1/* — inclusive /v1/stream, que
// autentica pelo token na query (EventSource não envia header) e caía em 401.
const auth = requireUser();

/**
 * Busca no catálogo.
 *   q        código, EAN ou palavras da descrição em qualquer ordem
 *   brand    marca exata          group  grupo exato
 *   inStock  1 = só saldo > 0
 */
router.get('/products', auth, route(async (req, res) => {
    const q = parse(z.object({
        q: z.string().trim().max(80).default(''),
        brand: z.string().trim().max(120).optional(),
        group: z.string().trim().max(120).optional(),
        inStock: z.enum(['1', 'true']).optional().transform(Boolean),
        limit: z.coerce.number().int().min(1).max(200).default(50),
        offset: z.coerce.number().int().min(0).default(0),
    }), req.query);

    const where = ['p.tenant_id = $1', 'p.active'];
    const params = [req.tenantId];
    const add = (sql, value) => { params.push(value); where.push(sql.replaceAll('?', `$${params.length}`)); };

    if (q.brand) add('p.brand = ?', q.brand);
    if (q.group) add('p.group_name = ?', q.group);
    if (q.inStock) where.push('p.stock > 0');

    let exactParam = null;
    if (q.q) {
        params.push(q.q);
        exactParam = `$${params.length}`;
        // Cada palavra precisa aparecer na descrição (ordem livre); ou bate código/EAN exato.
        const words = q.q.split(/\s+/).filter(Boolean).slice(0, 6);
        const wordConds = words.map((w) => { params.push(`%${w}%`); return `p.description ILIKE $${params.length}`; });
        where.push(`(p.erp_id = ${exactParam} OR p.sku = ${exactParam}
                     OR EXISTS (SELECT 1 FROM product_barcodes b WHERE b.tenant_id = p.tenant_id
                                 AND b.erp_id = p.erp_id AND b.barcode = ${exactParam})
                     OR (${wordConds.join(' AND ')}))`);
    }

    params.push(q.limit + 1, q.offset);
    const { rows } = await db.query(
        `SELECT p.erp_id, p.sku, p.description, p.unit, p.brand, p.group_name, p.stock::text AS stock,
                (SELECT array_agg(b.barcode) FROM product_barcodes b
                  WHERE b.tenant_id = p.tenant_id AND b.erp_id = p.erp_id) AS barcodes
           FROM products p
          WHERE ${where.join(' AND ')}
          ORDER BY ${exactParam ? `(p.erp_id = ${exactParam} OR p.sku = ${exactParam}) DESC,` : ''} p.description, p.erp_id
          LIMIT $${params.length - 1} OFFSET $${params.length}`,
        params,
    );
    const hasMore = rows.length > q.limit;
    res.json({ items: rows.slice(0, q.limit).map(mapProduct), hasMore });
}));

/** Marcas e grupos (com contagem) para os filtros — respeita "somente com estoque". */
router.get('/products/facets', auth, route(async (req, res) => {
    const { inStock } = parse(z.object({ inStock: z.enum(['1', 'true']).optional().transform(Boolean) }), req.query);
    const stockCond = inStock ? 'AND stock > 0' : '';
    const [brands, groups, totals] = await Promise.all([
        db.query(`SELECT brand AS name, count(*)::int AS n FROM products
                   WHERE tenant_id = $1 AND active AND brand IS NOT NULL ${stockCond}
                   GROUP BY brand ORDER BY brand`, [req.tenantId]),
        db.query(`SELECT group_name AS name, count(*)::int AS n FROM products
                   WHERE tenant_id = $1 AND active AND group_name IS NOT NULL ${stockCond}
                   GROUP BY group_name ORDER BY group_name`, [req.tenantId]),
        db.query(`SELECT count(*)::int AS total, count(*) FILTER (WHERE stock > 0)::int AS com_estoque
                    FROM products WHERE tenant_id = $1 AND active`, [req.tenantId]),
    ]);
    res.json({ brands: brands.rows, groups: groups.rows, ...totals.rows[0] });
}));

router.get('/products/barcode/:code', auth, route(async (req, res) => {
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
router.get('/catalog/delta', auth, route(async (req, res) => {
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
