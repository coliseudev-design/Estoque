/**
 * webhooks.js — CRUD de webhooks por empresa (N3).
 *
 * Rotas:
 *   GET    /api/admin/companies/:id/webhooks        — lista webhooks
 *   POST   /api/admin/companies/:id/webhooks        — cria webhook
 *   PATCH  /api/admin/companies/:id/webhooks/:whId  — ativa/desativa
 *   DELETE /api/admin/companies/:id/webhooks/:whId  — remove
 *
 * @module routes/admin/webhooks
 */
'use strict';

const crypto = require('crypto');
const express = require('express');
const { pgQuery } = require('../../db/postgres');
const { createError } = require('../../middleware/errorHandler');
const logger = require('../../config/logger');

const router = express.Router({ mergeParams: true });

const ADMIN_KEY = process.env.ADMIN_API_KEY || '';

function requireAdminKey(req, res, next) {
    const raw = req.headers['admin-api-key'] || req.headers['api-key'];
    if (!raw || raw !== ADMIN_KEY) return res.status(403).json({ error: 'Acesso negado', code: 'FORBIDDEN' });
    next();
}

// GET: listar webhooks de uma empresa
router.get('/', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    try {
        const { rows } = await pgQuery(
            `SELECT id, url, events, active, created_at FROM company_webhooks WHERE company_id = $1 ORDER BY created_at DESC`,
            [id]
        );
        res.json({ webhooks: rows });
    } catch (err) { next(err); }
});

// POST: criar webhook
router.post('/', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    const { url, events } = req.body;
    if (!url?.trim()) return next(createError('Campo url é obrigatório', 400, 'MISSING_URL'));
    if (!Array.isArray(events) || !events.length) return next(createError('Defina pelo menos um evento', 400, 'MISSING_EVENTS'));

    const secret = crypto.randomBytes(24).toString('hex');
    try {
        const { rows } = await pgQuery(
            `INSERT INTO company_webhooks (company_id, url, secret, events)
             VALUES ($1, $2, $3, $4)
             RETURNING id, url, events, active, created_at`,
            [id, url.trim(), secret, events]
        );
        logger.info('[Admin/Webhooks] Webhook criado', { companyId: id, url });
        res.status(201).json({ webhook: rows[0], secret });
    } catch (err) { next(err); }
});

// PATCH: ativar/desativar
router.patch('/:whId', requireAdminKey, async (req, res, next) => {
    const { id, whId } = req.params;
    const { active } = req.body;
    try {
        const { rows } = await pgQuery(
            `UPDATE company_webhooks SET active = $1 WHERE id = $2 AND company_id = $3 RETURNING id, active`,
            [!!active, whId, id]
        );
        if (!rows.length) return next(createError('Webhook não encontrado', 404, 'NOT_FOUND'));
        res.json({ webhook: rows[0] });
    } catch (err) { next(err); }
});

// DELETE: remover
router.delete('/:whId', requireAdminKey, async (req, res, next) => {
    const { id, whId } = req.params;
    try {
        const { rowCount } = await pgQuery(
            `DELETE FROM company_webhooks WHERE id = $1 AND company_id = $2`, [whId, id]
        );
        if (!rowCount) return next(createError('Webhook não encontrado', 404, 'NOT_FOUND'));
        res.json({ message: 'Webhook removido.' });
    } catch (err) { next(err); }
});

module.exports = router;
