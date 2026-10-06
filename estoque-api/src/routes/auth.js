/**
 * Autenticação de usuários.
 *
 *  Dashboard:  Serial da empresa + chave do módulo Estoque + login + senha.
 *              (a chave prova a licença; o navegador pode lembrá-la)
 *  App:        aparelho pareado pelo painel (X-Device-Key) + login + PIN; ou
 *              JWT de dispositivo do Coliseu.Identity (X-Device-Token) + login + PIN
 *              (ativação pela chave do painel de licenças).
 *
 * Os dois caminhos devolvem o MESMO tipo de token: daí em diante app e dashboard
 * usam exatamente os mesmos endpoints.
 */
'use strict';

const express = require('express');
const rateLimit = require('express-rate-limit');
const { z } = require('zod');
const db = require('../db');
const { route, parse, unauthorized, forbidden, conflict } = require('../http');
const { validateModuleKey, isTenantLicensed } = require('../auth/license');
const { hashSecret, verifySecret } = require('../auth/passwords');
const { signUserToken, verifyDeviceToken } = require('../auth/tokens');
const { requireUser, UUID_RE } = require('../auth/middleware');
const { getSettings } = require('../services/settings');
const { audit } = require('../services/audit');
const devices = require('../services/devices');

const router = express.Router();

// Força bruta em senha/PIN: 20 tentativas por IP a cada 10 minutos.
const loginLimit = rateLimit({
    windowMs: 10 * 60_000, max: 20, standardHeaders: true, legacyHeaders: false,
    message: { error: 'Muitas tentativas. Aguarde alguns minutos.', code: 'RATE_LIMITED' },
});

const tenantSchema = z.string().regex(UUID_RE, 'Serial inválido').transform((s) => s.toLowerCase());

async function session(user, deviceId) {
    await db.query('UPDATE users SET last_login_at = now() WHERE id = $1', [user.id]);
    const { rows } = await db.query('SELECT name FROM tenants WHERE id = $1', [user.tenant_id]);
    return {
        token: signUserToken({ tenantId: user.tenant_id, userId: user.id, role: user.role, deviceId }),
        user: { id: user.id, name: user.name, login: user.login, role: user.role },
        company: { id: user.tenant_id, name: rows[0]?.name || '' },
        settings: await getSettings(user.tenant_id),
    };
}

async function findUser(tenantId, login) {
    const { rows } = await db.query(
        'SELECT * FROM users WHERE tenant_id = $1 AND lower(login) = lower($2)',
        [tenantId, login.trim()],
    );
    return rows[0] || null;
}

// ── Primeiro acesso: cria o administrador da empresa ─────────────────────────
router.post('/setup', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        tenantId: tenantSchema,
        companyKey: z.string().min(8),
        name: z.string().trim().min(2).max(120),
        login: z.string().trim().min(2).max(60),
        password: z.string().min(8, 'Senha com no mínimo 8 caracteres').max(200),
    }), req.body);

    const lic = await validateModuleKey(body.tenantId, body.companyKey);
    if (!lic.valid) throw forbidden(lic.reason || 'Licença inválida', 'LICENSE_DENIED');

    const user = await db.tx(async (client) => {
        // Serializa setups concorrentes da mesma empresa.
        await client.query('SELECT 1 FROM tenants WHERE id = $1 FOR UPDATE', [body.tenantId]);
        const { rows: existing } = await client.query('SELECT 1 FROM users WHERE tenant_id = $1 LIMIT 1', [body.tenantId]);
        if (existing.length) throw conflict('Esta empresa já foi configurada. Entre com seu usuário.', 'ALREADY_SETUP');
        const { rows } = await client.query(
            `INSERT INTO users (tenant_id, login, name, role, password_hash)
             VALUES ($1, $2, $3, 'admin', $4) RETURNING *`,
            [body.tenantId, body.login, body.name, await hashSecret(body.password)],
        );
        await audit(client, { tenantId: body.tenantId, userId: rows[0].id, action: 'tenant.setup' });
        return rows[0];
    });
    res.status(201).json(await session(user, null));
}));

// ── Situação da empresa (tela de login decide entre "setup" e "entrar") ──────
router.post('/company', loginLimit, route(async (req, res) => {
    const body = parse(z.object({ tenantId: tenantSchema, companyKey: z.string().min(8) }), req.body);
    const lic = await validateModuleKey(body.tenantId, body.companyKey);
    if (!lic.valid) throw forbidden(lic.reason || 'Licença inválida', 'LICENSE_DENIED');
    const { rows } = await db.query(
        `SELECT t.name, t.worker_seen_at, EXISTS (SELECT 1 FROM users u WHERE u.tenant_id = t.id) AS has_users
           FROM tenants t WHERE t.id = $1`,
        [body.tenantId],
    );
    res.json({
        name: rows[0]?.name || lic.companyName || '',
        needsSetup: !rows[0]?.has_users,
        workerSeenAt: rows[0]?.worker_seen_at || null,
    });
}));

// ── Login do dashboard ───────────────────────────────────────────────────────
router.post('/login', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        tenantId: tenantSchema,
        companyKey: z.string().min(8),
        login: z.string().trim().min(1),
        password: z.string().min(1),
    }), req.body);

    const lic = await validateModuleKey(body.tenantId, body.companyKey);
    if (!lic.valid) throw forbidden(lic.reason || 'Licença inválida', 'LICENSE_DENIED');

    const user = await findUser(body.tenantId, body.login);
    if (!user || !user.active || !(await verifySecret(body.password, user.password_hash))) {
        throw unauthorized('Usuário ou senha inválidos', 'INVALID_CREDENTIALS');
    }
    res.json(await session(user, null));
}));

// ── Login do operador no app ─────────────────────────────────────────────────
router.post('/device-login', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        login: z.string().trim().min(1),
        pin: z.string().min(4).max(12),
    }), req.body);

    let device;
    try {
        device = verifyDeviceToken(req.get('X-Device-Token') || '');
    } catch (err) {
        throw unauthorized(`Dispositivo não autorizado: ${err.message}`, 'INVALID_DEVICE_TOKEN');
    }
    const tenantId = device.tenantId.toLowerCase();
    if (!(await isTenantLicensed(tenantId))) {
        throw conflict('Empresa ainda não configurada no Coliseu Estoque. Faça o primeiro acesso pelo painel web.', 'TENANT_NOT_SETUP');
    }

    const user = await findUser(tenantId, body.login);
    if (!user || !user.active || !(await verifySecret(body.pin, user.pin_hash))) {
        throw unauthorized('Usuário ou PIN inválidos', 'INVALID_CREDENTIALS');
    }
    res.json(await session(user, device.deviceId));
}));

// ── Pareamento do app pelo painel (QR Code / código) ─────────────────────────
router.post('/pair', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        code: z.string().trim().min(8).max(20),
        deviceUuid: z.string().max(120).optional(),
        model: z.string().max(120).optional(),
        os: z.string().max(60).optional(),
        appVersion: z.string().max(30).optional(),
    }), req.body);
    res.status(201).json(await devices.pair(body));
}));

// ── Login do operador em aparelho pareado ────────────────────────────────────
router.post('/app-login', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        login: z.string().trim().min(1),
        pin: z.string().min(4).max(12),
        appVersion: z.string().max(30).optional(),
    }), req.body);
    const device = await devices.authenticate(req.get('X-Device-Key'));
    if (!(await isTenantLicensed(device.tenant_id))) throw forbidden('Licença do módulo Estoque suspensa', 'LICENSE_DENIED');

    const user = await findUser(device.tenant_id, body.login);
    if (!user || !user.active || !(await verifySecret(body.pin, user.pin_hash))) {
        throw unauthorized('Usuário ou PIN inválidos', 'INVALID_CREDENTIALS');
    }
    await devices.touch(device.id, user.id, body.appVersion);
    res.json(await session(user, device.id));
}));

router.get('/me', requireUser(), route(async (req, res) => {
    const { rows } = await db.query('SELECT name FROM tenants WHERE id = $1', [req.tenantId]);
    res.json({
        user: req.user,
        company: { id: req.tenantId, name: rows[0]?.name || '' },
        settings: await getSettings(req.tenantId),
    });
}));

/** Renova o token antes de expirar (app em turno longo, dashboard aberto o dia todo). */
router.post('/refresh', requireUser(), route(async (req, res) => {
    res.json({ token: signUserToken({ tenantId: req.tenantId, userId: req.user.id, role: req.user.role, deviceId: req.deviceId }) });
}));

module.exports = router;
