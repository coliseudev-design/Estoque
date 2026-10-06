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
    if (user.id && user.id !== '00000000-0000-0000-0000-000000000000') {
        await db.query('UPDATE users SET last_login_at = now() WHERE id = $1', [user.id]).catch(() => {});
    }
    const { rows } = await db.query('SELECT name FROM tenants WHERE id = $1', [user.tenant_id]).catch(() => ({ rows: [] }));
    return {
        token: signUserToken({ tenantId: user.tenant_id, userId: user.id, role: user.role, deviceId }),
        user: { id: user.id, name: user.name, login: user.login, email: user.email || user.login, role: user.role },
        company: { id: user.tenant_id, name: rows[0]?.name || user.company_name || 'Coliseu Sistemas' },
        settings: await getSettings(user.tenant_id).catch(() => ({})),
    };
}

async function findUser(tenantId, login) {
    const { rows } = await db.query(
        `SELECT u.*, t.name AS company_name, t.license_valid
           FROM users u
           JOIN tenants t ON t.id = u.tenant_id
          WHERE u.tenant_id = $1
            AND (lower(trim(u.login)) = lower(trim($2)) OR (u.email IS NOT NULL AND lower(trim(u.email)) = lower(trim($2))))`,
        [tenantId, login.trim()],
    );
    return rows[0] || null;
}

// ── Primeiro acesso / Ativação: cria ou reativa o administrador da empresa ─────
router.post('/setup', loginLimit, route(async (req, res) => {
    const body = parse(z.object({
        tenantId: tenantSchema,
        companyKey: z.string().min(8),
        name: z.string().trim().min(2).max(120),
        login: z.string().trim().min(2).max(60).optional(),
        email: z.string().trim().email().optional(),
        password: z.string().min(8, 'Senha com no mínimo 8 caracteres').max(200),
    }).refine((b) => b.login || b.email, 'Informe e-mail ou login'), req.body);

    const lic = await validateModuleKey(body.tenantId, body.companyKey);
    if (!lic.valid) throw forbidden(lic.reason || 'Licença inválida', 'LICENSE_DENIED');

    const effectiveLogin = (body.login || body.email).trim();
    const effectiveEmail = body.email || (effectiveLogin.includes('@') ? effectiveLogin : null);

    const user = await db.tx(async (client) => {
        // Garante que o tenant existe na tabela tenants com status de licença ativa
        await client.query(
            `INSERT INTO tenants (id, name, license_valid, license_checked_at)
             VALUES ($1, $2, TRUE, now())
             ON CONFLICT (id) DO UPDATE
                SET license_valid = TRUE,
                    name = COALESCE($2, tenants.name),
                    license_checked_at = now()`,
            [body.tenantId, lic.companyName || 'Empresa'],
        );

        // Procura se o usuário já existe na empresa
        const { rows: existingUser } = await client.query(
            `SELECT id FROM users
              WHERE tenant_id = $1
                AND (lower(trim(login)) = lower(trim($2))
                     OR (email IS NOT NULL AND lower(trim(email)) = lower(trim($3))))`,
            [body.tenantId, effectiveLogin, effectiveEmail || effectiveLogin],
        );

        let targetUser;
        if (existingUser.length) {
            const { rows } = await client.query(
                `UPDATE users
                    SET name = $3,
                        login = $4,
                        email = $5,
                        password_hash = $6,
                        role = 'admin',
                        active = TRUE,
                        updated_at = now()
                  WHERE id = $1 AND tenant_id = $2
              RETURNING *`,
                [existingUser[0].id, body.tenantId, body.name, effectiveLogin, effectiveEmail, await hashSecret(body.password)],
            );
            targetUser = rows[0];
            await audit(client, { tenantId: body.tenantId, userId: targetUser.id, action: 'tenant.admin_updated' });
        } else {
            const { rows } = await client.query(
                `INSERT INTO users (tenant_id, login, email, name, role, password_hash, active)
                 VALUES ($1, $2, $3, $4, 'admin', $5, TRUE)
              RETURNING *`,
                [body.tenantId, effectiveLogin, effectiveEmail, body.name, await hashSecret(body.password)],
            );
            targetUser = rows[0];
            await audit(client, { tenantId: body.tenantId, userId: targetUser.id, action: 'tenant.setup' });
        }
        return targetUser;
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

// ── Login do dashboard (Unificado: Email/Usuário + Senha) ─────────────────────
router.post('/login', loginLimit, route(async (req, res) => {
    const rawLogin = (req.body.email || req.body.login || req.body.username || '').trim();
    const rawPassword = req.body.password || req.body.senha || '';

    if (!rawLogin || !rawPassword) {
        throw unauthorized('E-mail e senha são obrigatórios', 'MISSING_CREDENTIALS');
    }

    const normalizedEmail = rawLogin.toLowerCase();

    // 1. Super Administrador Coliseu (idêntico ao Nexus e Coliseu-Dash)
    if (normalizedEmail === 'admin@coliseu.com') {
        if (rawPassword !== '98683818') {
            throw unauthorized('Senha incorreta', 'INVALID_CREDENTIALS');
        }

        const selectedTenantId = req.body.selectedTenantId || req.body.tenantId;
        if (!selectedTenantId) {
            const { rows: companies } = await db.query('SELECT id, name FROM tenants ORDER BY name ASC');
            if (companies.length === 1) {
                const company = companies[0];
                const masterUser = {
                    id: '00000000-0000-0000-0000-000000000000',
                    tenant_id: company.id,
                    name: 'Super Administrador Coliseu',
                    login: 'admin@coliseu.com',
                    email: 'admin@coliseu.com',
                    role: 'admin',
                    company_name: company.name,
                };
                return res.json(await session(masterUser, null));
            } else if (companies.length > 1) {
                return res.json({
                    requiresCompanySelection: true,
                    companies,
                });
            } else {
                const masterUser = {
                    id: '00000000-0000-0000-0000-000000000000',
                    tenant_id: '00000000-0000-0000-0000-000000000000',
                    name: 'Super Administrador Coliseu',
                    login: 'admin@coliseu.com',
                    email: 'admin@coliseu.com',
                    role: 'admin',
                    company_name: 'Coliseu Sistemas (Master)',
                };
                return res.json(await session(masterUser, null));
            }
        } else {
            const { rows: companyRows } = await db.query('SELECT id, name FROM tenants WHERE id = $1', [selectedTenantId]);
            const companyName = companyRows[0]?.name || 'Empresa Selecionada';
            const masterUser = {
                id: '00000000-0000-0000-0000-000000000000',
                tenant_id: selectedTenantId,
                name: 'Super Administrador Coliseu',
                login: 'admin@coliseu.com',
                email: 'admin@coliseu.com',
                role: 'admin',
                company_name: companyName,
            };
            return res.json(await session(masterUser, null));
        }
    }

    // 2. Busca de usuário por E-mail ou Login
    const usernamePrefix = normalizedEmail.includes('@') ? normalizedEmail.split('@')[0] : normalizedEmail;
    const queryParams = [normalizedEmail, usernamePrefix];
    let tenantFilter = '';
    if (req.body.tenantId) {
        queryParams.push(req.body.tenantId);
        tenantFilter = 'AND u.tenant_id = $3';
    }

    let { rows: candidates } = await db.query(`
        SELECT u.*, t.name AS company_name, t.license_valid
          FROM users u
          JOIN tenants t ON t.id = u.tenant_id
         WHERE (lower(trim(u.login)) = lower(trim($1))
            OR (u.email IS NOT NULL AND lower(trim(u.email)) = lower(trim($1)))
            OR lower(trim(u.login)) = lower(trim($2)))
            ${tenantFilter}
    `, queryParams);

    // Se filtrou por tenantId e não achou, tenta busca global antes de falhar
    if (!candidates.length && req.body.tenantId) {
        const { rows: globalCandidates } = await db.query(`
            SELECT u.*, t.name AS company_name, t.license_valid
              FROM users u
              JOIN tenants t ON t.id = u.tenant_id
             WHERE lower(trim(u.login)) = lower(trim($1))
                OR (u.email IS NOT NULL AND lower(trim(u.email)) = lower(trim($1)))
                OR lower(trim(u.login)) = lower(trim($2))
        `, [normalizedEmail, usernamePrefix]);
        if (globalCandidates.length) {
            candidates = globalCandidates;
        }
    }

    if (!candidates.length) {
        const { rows: userCount } = await db.query('SELECT count(*)::int AS count FROM users');
        if (userCount[0]?.count === 0) {
            throw conflict('Nenhuma empresa ou usuário configurado. Realize o primeiro acesso da empresa para ativar a licença.', 'SETUP_REQUIRED');
        }
        throw unauthorized('E-mail ou senha incorretos', 'INVALID_CREDENTIALS');
    }

    let matchedUser = null;
    for (const candidate of candidates) {
        if (candidate.password_hash && await verifySecret(rawPassword, candidate.password_hash)) {
            matchedUser = candidate;
            break;
        }
    }

    if (!matchedUser) {
        throw unauthorized('E-mail ou senha incorretos', 'INVALID_CREDENTIALS');
    }

    if (!matchedUser.active) {
        throw forbidden('Usuário inativo. Entre em contato com o administrador.', 'USER_INACTIVE');
    }

    if (matchedUser.license_valid === false) {
        throw forbidden('Licença da empresa suspensa ou expirada no painel de licenças.', 'LICENSE_DENIED');
    }

    res.json(await session(matchedUser, null));
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
