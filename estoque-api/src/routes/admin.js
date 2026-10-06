/**
 * Gestão: usuários, configurações, auditoria, painel, stream em tempo real.
 */
'use strict';

const express = require('express');
const { z } = require('zod');
const db = require('../db');
const bus = require('../realtime/bus');
const { route, parse, notFound, forbidden, conflict, badRequest } = require('../http');
const { requireUser, invalidateUser, UUID_RE } = require('../auth/middleware');
const { hashSecret } = require('../auth/passwords');
const { getSettings, updateSettings, DEFAULTS } = require('../services/settings');
const { audit } = require('../services/audit');
const { documentAlerts, flowOf, ATTENTION_SQL } = require('../domain/alerts');

const router = express.Router();
const supervisor = requireUser('supervisor', 'admin');
const admin = requireUser('admin');

// ── Painel ───────────────────────────────────────────────────────────────────
router.get('/dashboard/summary', supervisor, route(async (req, res) => {
    const t = req.tenantId;
    const settings = await getSettings(t);
    const [byStatus, today, operators, worker, sync, writeback, byFlow, attention] = await Promise.all([
        db.query(
            `SELECT status, count(*)::int AS n FROM documents
              WHERE tenant_id = $1 AND (status NOT IN ('CONCLUIDO','CANCELADO') OR finished_at >= current_date)
              GROUP BY status`, [t]),
        db.query(
            `SELECT count(*) FILTER (WHERE status = 'CONCLUIDO')::int AS concluidos,
                    count(*) FILTER (WHERE status = 'CONCLUIDO' AND has_divergence)::int AS com_divergencia,
                    COALESCE(avg(EXTRACT(EPOCH FROM finished_at - started_at)) FILTER (WHERE status = 'CONCLUIDO'), 0)::int AS tempo_medio_s
               FROM documents WHERE tenant_id = $1 AND finished_at >= current_date`, [t]),
        db.query(
            `SELECT u.id, u.name,
                    count(DISTINCT e.document_id)::int AS documentos,
                    COALESCE(sum(e.qty), 0)::float AS unidades,
                    count(*)::int AS leituras,
                    max(e.scanned_at) AS ultima_leitura
               FROM scan_events e JOIN users u ON u.id = e.user_id
              WHERE e.tenant_id = $1 AND e.scanned_at >= current_date AND NOT e.voided
              GROUP BY u.id, u.name ORDER BY unidades DESC`, [t]),
        db.query('SELECT worker_seen_at, worker_info FROM tenants WHERE id = $1', [t]),
        db.query('SELECT entity, last_at, rows FROM sync_state WHERE tenant_id = $1 ORDER BY entity', [t]),
        db.query(
            `SELECT count(*) FILTER (WHERE writeback_status = 'PENDENTE')::int AS pendentes,
                    count(*) FILTER (WHERE writeback_status = 'ERRO')::int AS erros
               FROM documents WHERE tenant_id = $1 AND status = 'CONCLUIDO'`, [t]),
        // Entradas × saídas: fila atual + concluídos hoje + conformidade e tempo médio do dia.
        db.query(
            `SELECT CASE WHEN source = 'NFE' THEN 'entrada' ELSE 'saida' END AS flow, status, count(*)::int AS n,
                    count(*) FILTER (WHERE status = 'CONCLUIDO' AND has_divergence)::int AS com_divergencia,
                    COALESCE(avg(EXTRACT(EPOCH FROM finished_at - started_at)) FILTER (WHERE status = 'CONCLUIDO'), 0)::int AS tempo_medio_s
               FROM documents
              WHERE tenant_id = $1 AND (status NOT IN ('CONCLUIDO','CANCELADO') OR finished_at >= current_date)
              GROUP BY 1, 2`, [t]),
        // Críticas abertas mais graves primeiro — o "o que fazer agora" do supervisor.
        db.query(
            `SELECT d.id, d.source, d.number, d.customer_name, d.status, d.issued_at, d.imported_at, d.invoice_number,
                    d.erp_changed, d.erp_cancelled, d.writeback_status, d.lock_expires_at, d.locked_by, d.meta->'critiques' AS critiques
               FROM documents d
              WHERE d.tenant_id = $1 AND ${ATTENTION_SQL.replace('?', '$2')}
              ORDER BY CASE d.status WHEN 'AGUARDANDO_APROVACAO' THEN 0 WHEN 'DIVERGENTE' THEN 1 ELSE 2 END,
                       d.priority DESC, COALESCE(d.imported_at, d.issued_at)
              LIMIT 12`, [t, String(settings.outboundSlaHours)]),
    ]);
    const flows = { entrada: { byStatus: {}, divergentToday: 0, avgSeconds: 0 }, saida: { byStatus: {}, divergentToday: 0, avgSeconds: 0 } };
    for (const r of byFlow.rows) {
        flows[r.flow].byStatus[r.status] = r.n;
        if (r.status === 'CONCLUIDO') { flows[r.flow].divergentToday = r.com_divergencia; flows[r.flow].avgSeconds = r.tempo_medio_s; }
    }
    res.json({
        byStatus: Object.fromEntries(byStatus.rows.map((r) => [r.status, r.n])),
        today: today.rows[0],
        operators: operators.rows,
        worker: { seenAt: worker.rows[0]?.worker_seen_at, info: worker.rows[0]?.worker_info },
        sync: sync.rows,
        writeback: writeback.rows[0],
        flows,
        attention: attention.rows.map((r) => {
            const header = {
                status: r.status, invoiceNumber: r.invoice_number, erpChanged: r.erp_changed, erpCancelled: r.erp_cancelled,
                writebackStatus: r.writeback_status, issuedAt: r.issued_at, importedAt: r.imported_at,
                lock: r.locked_by && r.lock_expires_at && new Date(r.lock_expires_at) > new Date() ? {} : null,
            };
            return {
                id: r.id, source: r.source, flow: flowOf(r.source), number: r.number, customerName: r.customer_name, status: r.status,
                alerts: documentAlerts(header, { slaHours: settings.outboundSlaHours, critiques: r.critiques }),
            };
        }),
        settings: { outboundSlaHours: settings.outboundSlaHours, companyCnpj: Boolean(settings.companyCnpj) },
    });
}));

// ── Usuários ─────────────────────────────────────────────────────────────────
const ROLES = ['operador', 'supervisor', 'admin'];

router.get('/users', supervisor, route(async (req, res) => {
    const { rows } = await db.query(
        `SELECT id, login, name, role, active, last_login_at, created_at,
                password_hash IS NOT NULL AS has_password, pin_hash IS NOT NULL AS has_pin
           FROM users WHERE tenant_id = $1 ORDER BY active DESC, name`,
        [req.tenantId],
    );
    res.json({ items: rows });
}));

/** Supervisor gerencia operadores; só admin cria/edita supervisor e admin. */
function assertCanManage(actor, targetRole) {
    if (actor.role === 'admin') return;
    if (targetRole !== 'operador') throw forbidden('Apenas administradores gerenciam supervisores e administradores');
}

const pinSchema = z.string().regex(/^\d{4,8}$/, 'PIN de 4 a 8 dígitos');
const passwordSchema = z.string().min(8, 'Senha com no mínimo 8 caracteres').max(200);

router.post('/users', supervisor, route(async (req, res) => {
    const body = parse(z.object({
        login: z.string().trim().min(2).max(60).regex(/^[\w.@-]+$/, 'Use letras, números, ponto, hífen ou @'),
        name: z.string().trim().min(2).max(120),
        role: z.enum(ROLES),
        password: passwordSchema.optional(),
        pin: pinSchema.optional(),
    }).refine((b) => b.password || b.pin, 'Informe senha (painel) e/ou PIN (app)'), req.body);
    assertCanManage(req.user, body.role);

    try {
        const { rows } = await db.query(
            `INSERT INTO users (tenant_id, login, name, role, password_hash, pin_hash)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
            [req.tenantId, body.login, body.name, body.role,
                body.password ? await hashSecret(body.password) : null,
                body.pin ? await hashSecret(body.pin) : null],
        );
        await audit(null, { tenantId: req.tenantId, userId: req.user.id, action: 'user.created',
            details: { id: rows[0].id, login: body.login, role: body.role } });
        res.status(201).json({ id: rows[0].id });
    } catch (err) {
        if (err.code === '23505') throw conflict('Já existe um usuário com este login', 'DUPLICATE_LOGIN');
        throw err;
    }
}));

router.patch('/users/:id', supervisor, route(async (req, res) => {
    const id = parse(z.string().regex(UUID_RE), req.params.id);
    const body = parse(z.object({
        name: z.string().trim().min(2).max(120).optional(),
        role: z.enum(ROLES).optional(),
        active: z.boolean().optional(),
        password: passwordSchema.optional(),
        pin: pinSchema.optional(),
    }), req.body);

    const { rows } = await db.query('SELECT role FROM users WHERE id = $1 AND tenant_id = $2', [id, req.tenantId]);
    if (!rows[0]) throw notFound('Usuário não encontrado');
    assertCanManage(req.user, rows[0].role);
    if (body.role) assertCanManage(req.user, body.role);
    if (id === req.user.id && (body.active === false || (body.role && body.role !== req.user.role))) {
        throw badRequest('Você não pode desativar nem rebaixar o próprio usuário');
    }

    const sets = [];
    const params = [id, req.tenantId];
    const set = (col, val) => { params.push(val); sets.push(`${col} = $${params.length}`); };
    if (body.name !== undefined) set('name', body.name);
    if (body.role !== undefined) set('role', body.role);
    if (body.active !== undefined) set('active', body.active);
    if (body.password) set('password_hash', await hashSecret(body.password));
    if (body.pin) set('pin_hash', await hashSecret(body.pin));
    if (!sets.length) return res.status(204).end();

    await db.query(`UPDATE users SET ${sets.join(', ')}, updated_at = now() WHERE id = $1 AND tenant_id = $2`, params);
    invalidateUser(id);
    await audit(null, { tenantId: req.tenantId, userId: req.user.id, action: 'user.updated',
        details: { id, fields: Object.keys(body).filter((k) => k !== 'password' && k !== 'pin'),
            credentials: Boolean(body.password || body.pin) } });
    res.status(204).end();
}));

// ── Configurações ────────────────────────────────────────────────────────────
router.get('/settings', supervisor, route(async (req, res) => {
    res.json(await getSettings(req.tenantId));
}));

router.patch('/settings', admin, route(async (req, res) => {
    const body = parse(z.object({
        maxRecounts: z.number().int().min(0).max(5).optional(),
        lockMinutes: z.number().int().min(5).max(24 * 60).optional(),
        allowManualQty: z.boolean().optional(),
        requireJustification: z.boolean().optional(),
        showItemList: z.boolean().optional(),
        queueDays: z.number().int().min(1).max(90).optional(),
        companyCnpj: z.string().trim().transform((s) => s.replace(/\D/g, ''))
            .refine((s) => s === '' || s.length === 14, 'CNPJ com 14 dígitos').optional(),
        outboundSlaHours: z.number().int().min(1).max(24 * 30).optional(),
        expiryAlertDays: z.number().int().min(0).max(730).optional(),
        entryOldDays: z.number().int().min(1).max(365).optional(),
    }).strict(), req.body);
    const settings = await updateSettings(req.tenantId, body);
    await audit(null, { tenantId: req.tenantId, userId: req.user.id, action: 'settings.updated', details: body });
    res.json(settings);
}));

router.get('/settings/defaults', supervisor, (req, res) => res.json(DEFAULTS));

// ── Auditoria ────────────────────────────────────────────────────────────────
router.get('/audit', supervisor, route(async (req, res) => {
    const q = parse(z.object({
        documentId: z.string().regex(UUID_RE).optional(),
        limit: z.coerce.number().int().min(1).max(500).default(100),
        before: z.coerce.number().int().optional(),
    }), req.query);
    const { rows } = await db.query(
        `SELECT a.id, a.document_id, a.action, a.details, a.at, u.name AS user_name, d.number AS document_number
           FROM audit_log a
           LEFT JOIN users u ON u.id = a.user_id
           LEFT JOIN documents d ON d.id = a.document_id
          WHERE a.tenant_id = $1
            AND ($2::uuid IS NULL OR a.document_id = $2)
            AND ($3::bigint IS NULL OR a.id < $3)
          ORDER BY a.id DESC LIMIT $4`,
        [req.tenantId, q.documentId ?? null, q.before ?? null, q.limit],
    );
    res.json({ items: rows });
}));

// ── Tempo real (SSE) ─────────────────────────────────────────────────────────
router.get('/stream', requireUser('__query'), (req, res) => {
    bus.attach(req.tenantId, res);
});

module.exports = router;
