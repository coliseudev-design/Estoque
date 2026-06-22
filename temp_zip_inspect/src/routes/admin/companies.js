/**
 * companies.js — API de gestão de empresas/tenants (P1-D).
 *
 * Rotas protegidas por API-Key de super-admin (ADMIN_API_KEY env var).
 * NUNCA expostas ao frontend sem autenticação de admin.
 *
 * Rotas:
 *   GET    /api/admin/companies         — Lista todas as empresas
 *   POST   /api/admin/companies         — Cria nova empresa + gera API Key
 *   PATCH  /api/admin/companies/:id     — Atualiza nome / ativa / desativa
 *   POST   /api/admin/companies/:id/rotate-key — Gera nova API Key
 *   DELETE /api/admin/companies/:id     — Desativa empresa (soft delete)
 *
 * Segurança:
 *   - API Key retornada apenas no POST de criação e rotação (nunca mais)
 *   - Hash SHA-256 armazenado; texto puro nunca persiste
 *   - Admin key separada da API-Key de empresa
 *
 * @module routes/admin/companies
 */
'use strict';

const crypto = require('crypto');
const express = require('express');
const { pgQuery } = require('../../db/postgres');
const { sha256hex } = require('../../middleware/auth');
const { createError } = require('../../middleware/errorHandler');
const logger = require('../../config/logger');

const router = express.Router();

// ── Middleware de super-admin ─────────────────────────────────────────────────

const ADMIN_KEY = process.env.ADMIN_API_KEY || '';

function requireAdminKey(req, res, next) {
    const raw = req.headers['admin-api-key'] || req.headers['api-key'];
    if (!raw || raw !== ADMIN_KEY) {
        return res.status(403).json({ error: 'Acesso negado', code: 'FORBIDDEN' });
    }
    next();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Gera uma API Key segura e retorna o par (rawKey, hash).
 * rawKey é mostrado UMA vez; hash é salvo no banco.
 *
 * @returns {{ rawKey: string, hash: string }}
 */
function generateApiKey() {
    const rawKey = `csk_${crypto.randomBytes(24).toString('hex')}`;  // csk_ = coliseu sales key
    const hash = sha256hex(rawKey);
    return { rawKey, hash };
}

// ── GET /api/admin/companies ──────────────────────────────────────────────────

router.get('/', requireAdminKey, async (req, res, next) => {
    try {
        const { rows } = await pgQuery(
            `SELECT id, name, active, created_at FROM companies ORDER BY created_at DESC`
        );
        res.json({ companies: rows });
    } catch (err) { next(err); }
});

// ── POST /api/admin/companies ─────────────────────────────────────────────────

/**
 * Cria uma nova empresa e retorna a API Key em texto puro (apenas uma vez).
 * @body { name: string }
 */
router.post('/', requireAdminKey, async (req, res, next) => {
    const { name } = req.body;
    if (!name?.trim()) {
        return next(createError('Campo name é obrigatório', 400, 'MISSING_NAME'));
    }

    try {
        const { rawKey, hash } = generateApiKey();

        const { rows } = await pgQuery(
            `INSERT INTO companies (name, api_key)
             VALUES ($1, $2)
             RETURNING id, name, active, created_at`,
            [name.trim(), hash]
        );

        const company = rows[0];
        logger.info('[Admin/Companies] Nova empresa criada', { id: company.id, name: company.name });

        res.status(201).json({
            company,
            apiKey: rawKey,   // Retornado apenas nesta resposta — salve com segurança!
            warning: 'Salve a API Key agora. Ela não poderá ser recuperada depois.',
        });
    } catch (err) { next(err); }
});

// ── PATCH /api/admin/companies/:id ────────────────────────────────────────────

/**
 * Atualiza nome ou status (ativo/inativo) de uma empresa.
 * @body { name?: string, active?: boolean }
 */
router.patch('/:id', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    const { name, active } = req.body;

    const updates = [];
    const params = [];
    let idx = 1;

    if (name !== undefined) { updates.push(`name = $${idx++}`); params.push(name.trim()); }
    if (active !== undefined) { updates.push(`active = $${idx++}`); params.push(!!active); }

    if (!updates.length) {
        return next(createError('Nenhum campo para atualizar', 400, 'NOTHING_TO_UPDATE'));
    }

    params.push(id);
    try {
        const { rows } = await pgQuery(
            `UPDATE companies SET ${updates.join(', ')} WHERE id = $${idx}
             RETURNING id, name, active, created_at`,
            params
        );
        if (!rows.length) return next(createError('Empresa não encontrada', 404, 'NOT_FOUND'));
        res.json({ company: rows[0] });
    } catch (err) { next(err); }
});

// ── POST /api/admin/companies/:id/rotate-key ─────────────────────────────────

/**
 * Gera uma nova API Key para a empresa.
 * A chave antiga é invalidada imediatamente.
 * Período de sobreposição (grace period): 0s — mudança instantânea.
 */
router.post('/:id/rotate-key', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    try {
        const { rawKey, hash } = generateApiKey();

        const { rows } = await pgQuery(
            `UPDATE companies SET api_key = $1 WHERE id = $2
             RETURNING id, name`,
            [hash, id]
        );

        if (!rows.length) return next(createError('Empresa não encontrada', 404, 'NOT_FOUND'));

        logger.info('[Admin/Companies] API Key rotacionada', { id, name: rows[0].name });
        res.json({
            message: 'Nova API Key gerada com sucesso.',
            apiKey: rawKey,
            warning: 'Salve a nova API Key agora. A chave antiga foi invalidada.',
        });
    } catch (err) { next(err); }
});

// ── DELETE /api/admin/companies/:id ──────────────────────────────────────────

router.delete('/:id', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    try {
        const { rows } = await pgQuery(
            `UPDATE companies SET active = FALSE WHERE id = $1 RETURNING id, name`,
            [id]
        );
        if (!rows.length) return next(createError('Empresa não encontrada', 404, 'NOT_FOUND'));
        logger.warn('[Admin/Companies] Empresa desativada', { id, name: rows[0].name });
        res.json({ message: `Empresa "${rows[0].name}" desativada.` });
    } catch (err) { next(err); }
});

// ── POST /api/admin/companies/by-external/:externalId/rotate-key ─────────────

/**
 * Sincroniza a API Key do middleware com a nova chave gerada pela Identity API.
 *
 * Chamado automaticamente pela Coliseu.Identity API após rotate-key.
 * Encontra a empresa pelo external_id (UUID da Identity) e atualiza api_key.
 *
 * @header Admin-Api-Key — chave de admin do middleware
 * @body   { rawKey: string } — nova chave em texto puro (Identity vai passar)
 */
router.post('/by-external/:externalId/rotate-key', requireAdminKey, async (req, res, next) => {
    const { externalId } = req.params;
    const { rawKey } = req.body;

    if (!rawKey?.trim()) {
        return next(createError('Campo rawKey é obrigatório', 400, 'MISSING_RAW_KEY'));
    }

    try {
        const hash = sha256hex(rawKey.trim());

        const { rows } = await pgQuery(
            `UPDATE companies SET api_key = $1
             WHERE external_id = $2
             RETURNING id, name, external_id`,
            [hash, externalId]
        );

        if (!rows.length) {
            return next(createError(
                `Empresa com external_id "${externalId}" não encontrada. ` +
                'Use POST /api/admin/companies/:id/link-external para vincular primeiro.',
                404, 'NOT_FOUND'
            ));
        }

        const { invalidateAuthCache } = require('../../middleware/auth');
        invalidateAuthCache(hash);

        logger.info('[Admin/Companies] API Key sincronizada via Identity API', {
            id: rows[0].id, name: rows[0].name, externalId
        });
        res.json({ ok: true, companyId: rows[0].id, name: rows[0].name });
    } catch (err) { next(err); }
});

// ── POST /api/admin/companies/:id/link-external ───────────────────────────────

/**
 * Vincula uma empresa do middleware ao UUID externo da Identity API.
 * Executar UMA VEZ para empresas criadas antes da coluna external_id existir.
 *
 * @body { externalId: string, rawKey?: string } 
 */
router.post('/:id/link-external', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    const { externalId, rawKey } = req.body;

    if (!externalId) {
        return next(createError('Campo externalId é obrigatório', 400, 'MISSING_EXTERNAL_ID'));
    }

    try {
        const updates = ['external_id = $1'];
        const params = [externalId];
        let idx = 2;

        // Opcionalmente também atualiza a api_key ao mesmo tempo
        if (rawKey?.trim()) {
            updates.push(`api_key = $${idx++}`);
            params.push(sha256hex(rawKey.trim()));
        }

        params.push(id);
        const { rows } = await pgQuery(
            `UPDATE companies SET ${updates.join(', ')}
             WHERE id = $${idx}
             RETURNING id, name, external_id`,
            params
        );

        if (!rows.length) return next(createError('Empresa não encontrada', 404, 'NOT_FOUND'));

        logger.info('[Admin/Companies] external_id vinculado', { id, externalId, updatedKey: !!rawKey });
        res.json({ ok: true, company: rows[0] });
    } catch (err) { next(err); }
});

// ── PUT /api/admin/companies/:id/firebird ─────────────────────────────────────

/**
 * Salva as credenciais Firebird de uma empresa (criptografando a senha).
 * @body { fb_host, fb_port?, fb_database, fb_user?, fb_password, fb_charset?, fb_wire_crypt? }
 */
router.put('/:id/firebird', requireAdminKey, async (req, res, next) => {
    const { id } = req.params;
    const { fb_host, fb_port, fb_database, fb_user, fb_password, fb_charset, fb_wire_crypt } = req.body;

    if (!fb_host || !fb_database) {
        return next(createError('fb_host e fb_database são obrigatórios', 400, 'MISSING_FIELDS'));
    }

    try {
        const { encrypt } = require('../../services/firebird.manager');
        const encryptedPassword = fb_password ? encrypt(fb_password) : null;

        const { rows } = await pgQuery(
            `UPDATE companies SET
                fb_host       = $1,
                fb_port       = $2,
                fb_database   = $3,
                fb_user       = $4,
                fb_password   = COALESCE($5, fb_password),
                fb_charset    = $6,
                fb_wire_crypt = $7
             WHERE id = $8
             RETURNING id, name, fb_host, fb_port, fb_database, fb_user, fb_charset, fb_wire_crypt`,
            [
                fb_host.trim(),
                fb_port || 3050,
                fb_database.trim(),
                (fb_user || 'SYSDBA').trim(),
                encryptedPassword,
                (fb_charset || 'WIN1252').trim(),
                !!fb_wire_crypt,
                id,
            ]
        );

        if (!rows.length) return next(createError('Empresa não encontrada', 404, 'NOT_FOUND'));

        logger.info('[Admin/Companies] Firebird configurado', { id, host: fb_host, database: fb_database });
        res.json({ message: 'Configuração Firebird salva com sucesso.', company: rows[0] });
    } catch (err) { next(err); }
});

// ── POST /api/admin/companies/:id/firebird/test ───────────────────────────────

/**
 * Testa a conexão Firebird de uma empresa sem salvar nada.
 * Útil para validar credenciais antes de confirmar.
 * @body { fb_host, fb_port?, fb_database, fb_user?, fb_password, fb_charset?, fb_wire_crypt? }
 */
router.post('/:id/firebird/test', requireAdminKey, async (req, res, next) => {
    const { fb_host, fb_port, fb_database, fb_user, fb_password, fb_charset, fb_wire_crypt } = req.body;

    if (!fb_host || !fb_database) {
        return next(createError('fb_host e fb_database são obrigatórios', 400, 'MISSING_FIELDS'));
    }

    try {
        const { testConnection } = require('../../services/firebird.manager');
        const result = await testConnection({
            fb_host,
            fb_port: fb_port || 3050,
            fb_database,
            fb_user: fb_user || 'SYSDBA',
            fb_password_plain: fb_password,
            fb_charset: fb_charset || 'WIN1252',
            fb_wire_crypt: !!fb_wire_crypt,
        });

        if (result.ok) {
            logger.info('[Admin/Companies] Teste Firebird OK', { id: req.params.id, host: fb_host });
            res.json({ ok: true, message: 'Conexão ao Firebird bem-sucedida!' });
        } else {
            res.status(400).json({ ok: false, error: result.error });
        }
    } catch (err) { next(err); }
});

module.exports = router;
