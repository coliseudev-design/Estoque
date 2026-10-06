/**
 * Recebimento — importação de XML de NF-e de entrada e vínculo de produtos.
 * A conferência das notas importadas usa as rotas normais de /v1/documents.
 */
'use strict';

const express = require('express');
const { z } = require('zod');
const { route, parse } = require('../http');
const { requireUser, UUID_RE } = require('../auth/middleware');
const entries = require('../services/entries');

const router = express.Router();
const supervisor = requireUser('supervisor', 'admin');
const idParam = (req) => parse(z.string().regex(UUID_RE, 'id inválido'), req.params.id);

router.post('/import', supervisor, route(async (req, res) => {
    const body = parse(z.object({
        xml: z.string().min(1).max(5_000_000),
        expectedKey: z.string().trim().regex(/^[\d\s]{44,60}$/, 'chave de acesso inválida').optional(),
        force: z.boolean().optional(),
    }), req.body);
    res.status(201).json(await entries.importNfe(req.tenantId, req.user, body));
}));

router.post('/:id/items/:seq/link', supervisor, route(async (req, res) => {
    const seq = parse(z.coerce.number().int().min(0), req.params.seq);
    const { productErpId } = parse(z.object({ productErpId: z.string().trim().min(1).max(40) }), req.body);
    res.json(await entries.linkItem(req.tenantId, req.user, idParam(req), seq, productErpId));
}));

router.delete('/:id', supervisor, route(async (req, res) => {
    await entries.deleteEntry(req.tenantId, req.user, idParam(req));
    res.status(204).end();
}));

module.exports = router;
