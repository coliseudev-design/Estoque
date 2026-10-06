/**
 * Documentos e conferência — mesmos endpoints para app e dashboard.
 * O perfil do usuário decide o que aparece (operador = conferência cega).
 */
'use strict';

const express = require('express');
const { z } = require('zod');
const { route, parse } = require('../http');
const { requireUser, UUID_RE } = require('../auth/middleware');
const docs = require('../services/documents');

const router = express.Router();
const supervisor = requireUser('supervisor', 'admin');
const anyone = requireUser();

const STATUSES = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE', 'AGUARDANDO_APROVACAO', 'CONCLUIDO', 'CANCELADO'];
const idParam = (req) => parse(z.string().regex(UUID_RE, 'id inválido'), req.params.id);

router.get('/', anyone, route(async (req, res) => {
    const q = parse(z.object({
        status: z.string().optional().transform((s) => (s ? s.split(',').filter((x) => STATUSES.includes(x)) : [])),
        q: z.string().trim().max(80).optional(),
        from: z.string().datetime({ offset: true }).optional().or(z.string().date().optional()),
        to: z.string().datetime({ offset: true }).optional().or(z.string().date().optional()),
        days: z.coerce.number().int().min(1).max(365).optional(),
        mine: z.enum(['1', 'true']).optional().transform(Boolean),
        writeback: z.enum(['PENDENTE', 'GRAVADO', 'ERRO']).optional(),
        flow: z.enum(['entrada', 'saida']).optional(),
        attention: z.enum(['1', 'true']).optional().transform(Boolean),
        priority: z.enum(['1', 'true']).optional().transform(Boolean),
        limit: z.coerce.number().int().min(1).max(200).default(50),
        offset: z.coerce.number().int().min(0).default(0),
    }), req.query);
    res.json({ items: await docs.listDocuments(req.tenantId, req.user, q) });
}));

// Contagem por status (pílulas de filtro). Precisa vir antes de '/:id'.
router.get('/counts', anyone, route(async (req, res) => {
    const q = parse(z.object({
        flow: z.enum(['entrada', 'saida']).optional(),
        days: z.coerce.number().int().min(1).max(365).default(7),
    }), req.query);
    res.json(await docs.countDocuments(req.tenantId, q));
}));

// Leitor de código de barras: pedido, NF, chave do ERP ou chave de acesso da NF-e.
// Precisa vir antes de '/:id'.
router.get('/lookup', anyone, route(async (req, res) => {
    const { code } = parse(z.object({ code: z.string().trim().min(1).max(64) }), req.query);
    res.json(await docs.lookupDocuments(req.tenantId, req.user, code));
}));

router.get('/:id', anyone, route(async (req, res) => {
    res.json(await docs.getDocument(req.tenantId, req.user, idParam(req)));
}));

router.get('/:id/scans', supervisor, route(async (req, res) => {
    res.json({ items: await docs.listScans(req.tenantId, idParam(req)) });
}));

router.post('/:id/claim', anyone, route(async (req, res) => {
    const body = parse(z.object({ force: z.boolean().optional() }).default({}), req.body ?? {});
    res.json(await docs.claim(req.tenantId, req.user, req.deviceId, idParam(req), body));
}));

router.post('/:id/release', anyone, route(async (req, res) => {
    await docs.release(req.tenantId, req.user, idParam(req));
    res.status(204).end();
}));

const scanEvent = z.object({
    id: z.string().regex(UUID_RE),
    round: z.number().int().min(0),
    barcode: z.string().trim().min(1).max(64).optional(),
    productErpId: z.string().trim().min(1).max(40).optional(),
    qty: z.number().refine((n) => n !== 0 && Math.abs(n) <= 100_000, 'quantidade inválida'),
    origin: z.enum(['camera', 'coletor', 'teclado', 'manual', 'web']).default('manual'),
    scannedAt: z.string().datetime({ offset: true }),
}).refine((e) => e.barcode || e.productErpId, 'informe barcode ou productErpId');

router.post('/:id/scans', anyone, route(async (req, res) => {
    const body = parse(z.object({ events: z.array(scanEvent).min(1).max(500) }), req.body);
    res.json(await docs.addScans(req.tenantId, req.user, req.deviceId, idParam(req), body.events));
}));

router.post('/:id/scans/:eventId/void', anyone, route(async (req, res) => {
    const eventId = parse(z.string().regex(UUID_RE), req.params.eventId);
    await docs.voidScan(req.tenantId, req.user, idParam(req), eventId);
    res.status(204).end();
}));

router.post('/:id/finalize', anyone, route(async (req, res) => {
    res.json(await docs.finalize(req.tenantId, req.user, idParam(req)));
}));

router.post('/:id/approve', supervisor, route(async (req, res) => {
    const body = parse(z.object({ justification: z.string().max(1000).optional() }), req.body ?? {});
    res.json(await docs.approve(req.tenantId, req.user, idParam(req), body.justification));
}));

router.post('/:id/reopen', supervisor, route(async (req, res) => {
    const body = parse(z.object({ products: z.array(z.string()).max(1000).default([]) }), req.body ?? {});
    res.json(await docs.reopen(req.tenantId, req.user, idParam(req), body.products));
}));

router.post('/:id/reset', supervisor, route(async (req, res) => {
    await docs.reset(req.tenantId, req.user, idParam(req));
    res.status(204).end();
}));

router.patch('/:id', supervisor, route(async (req, res) => {
    const body = parse(z.object({ priority: z.number().int().min(-10).max(10) }), req.body);
    await docs.setPriority(req.tenantId, req.user, idParam(req), body.priority);
    res.status(204).end();
}));

module.exports = router;
