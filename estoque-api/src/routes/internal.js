/**
 * Endpoints do Worker local (Windows Service junto ao Firebird).
 *
 * Autenticação idêntica à do Vision: X-Internal-Key (chave do módulo Estoque) +
 * X-Tenant-Id (Serial). Resposta no formato que o Worker já entende:
 * { aplicados, erros, detalhes[] }.
 */
'use strict';

const express = require('express');
const { z } = require('zod');
const { route, parse } = require('../http');
const { requireWorker, UUID_RE } = require('../auth/middleware');
const sync = require('../services/sync');

const router = express.Router();
router.use(requireWorker);

const qty = z.union([z.number(), z.string().regex(/^-?\d+(\.\d+)?$/)]).transform(Number);
const text = (max) => z.string().max(max).nullish().transform((s) => (s == null ? null : s.trim() || null));

const productSchema = z.object({
    erpId: z.union([z.string(), z.number()]).transform(String),
    sku: text(60),
    description: z.string().max(300).default(''),
    unit: text(10),
    brand: text(120),
    group: text(120),
    stock: qty.default(0),
    active: z.boolean().default(true),
    barcodes: z.array(z.object({
        barcode: z.string().trim().min(1).max(64),
        factor: qty.default(1),
    })).max(50).optional(),
});

router.post('/sync/products', route(async (req, res) => {
    const { rows } = parse(z.object({ rows: z.array(productSchema).max(5000) }), req.body);
    const r = await sync.upsertProducts(req.tenantId, rows);
    res.json({ ...r, erros: 0, detalhes: [] });
}));

router.post('/sync/stock', route(async (req, res) => {
    const { rows } = parse(z.object({
        rows: z.array(z.object({ erpId: z.union([z.string(), z.number()]).transform(String), stock: qty })).max(20000),
    }), req.body);
    const r = await sync.upsertStock(req.tenantId, rows);
    res.json({ ...r, erros: 0, detalhes: [] });
}));

const documentSchema = z.object({
    source: z.enum(['NFS', 'PED']),
    erpKey: z.union([z.string(), z.number()]).transform(String),
    number: text(30),
    series: text(10),
    movementType: z.number().int().nullish(),
    issuedAt: z.string().datetime({ offset: true }).nullish(),
    customerCode: text(30),
    customerName: text(200),
    sellerName: text(120),
    branchCode: z.number().int().nullish(),
    cancelled: z.boolean().default(false),
    items: z.array(z.object({
        seq: z.number().int().min(0).max(99_999),
        productErpId: z.union([z.string(), z.number()]).transform(String),
        description: z.string().max(300).default(''),
        unit: text(10),
        qty: qty.refine((n) => n >= 0, 'quantidade negativa'),
    })).max(5000),
});

router.post('/sync/documents', route(async (req, res) => {
    const { rows } = parse(z.object({ rows: z.array(documentSchema).max(500) }), req.body);
    // Último vence se o mesmo documento vier duplicado no lote.
    const unique = [...new Map(rows.map((d) => [`${d.source}|${d.erpKey}`, d])).values()];
    const r = await sync.upsertDocuments(req.tenantId, unique);
    res.json({ ...r, erros: 0, detalhes: [] });
}));

router.get('/writeback/pending', route(async (req, res) => {
    const { limit } = parse(z.object({ limit: z.coerce.number().int().min(1).max(200).default(50) }), req.query);
    res.json({ items: await sync.pendingWriteback(req.tenantId, limit) });
}));

router.post('/writeback/ack', route(async (req, res) => {
    const { results } = parse(z.object({
        results: z.array(z.object({
            documentId: z.string().regex(UUID_RE),
            ok: z.boolean(),
            error: z.string().max(2000).nullish(),
        })).max(500),
    }), req.body);
    res.json({ ...(await sync.ackWriteback(req.tenantId, results)), detalhes: [] });
}));

router.post('/heartbeat', route(async (req, res) => {
    const info = parse(z.object({
        version: z.string().max(30).optional(),
        machine: z.string().max(100).optional(),
        database: z.string().max(260).optional(),
        writebackEnabled: z.boolean().optional(),
        lastCycleSeconds: z.number().optional(),
    }).passthrough(), req.body ?? {});
    await sync.heartbeat(req.tenantId, info);
    res.json({ ok: true, serverTime: new Date().toISOString() });
}));

module.exports = router;
