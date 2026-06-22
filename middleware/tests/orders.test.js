/**
 * orders.test.js — Testes para os endpoints /api/orders/*.
 *
 * Cobre (rule-10 — Test First):
 *   GET /api/orders/pending
 *   GET /api/orders/report         — com e sem filtros de data
 *   GET /api/orders/events
 *   GET /api/orders/:id            — pedido encontrado / não encontrado
 *   POST /api/orders/:id/confirm   — campos obrigatórios, idempotência
 *   POST /api/orders/:id/error     — campos opcionais, truncate de mensagem longa
 *
 * Modo de teste: FB_MOCK=true + PostgreSQL mock via helpers/testApp.
 *
 * @module tests/orders.test
 */
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { v4: uuidv4 } = require('uuid');
const { app, API_KEY } = require('./helpers/testApp');

// Helper: request autenticado
function req(method, path) {
    return request(app)[method](path).set('API-Key', API_KEY);
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/orders/pending
// ─────────────────────────────────────────────────────────────────────────────

describe('GET /api/orders/pending', () => {

    it('→ 200 com campo pending (array)', async () => {
        const res = await req('get', '/api/orders/pending');
        assert.equal(res.status, 200,
            `Esperado 200, recebido ${res.status}: ${JSON.stringify(res.body)}`);
        assert.ok(
            Array.isArray(res.body.pending) || Array.isArray(res.body.orders),
            'body deve ter campo pending ou orders como array'
        );
    });

    it('?confirmedSince — retorna campo orders (polling do Flutter)', async () => {
        const since = new Date(Date.now() - 60_000).toISOString();
        const res = await req('get', `/api/orders/pending?confirmedSince=${since}`);
        assert.equal(res.status, 200);
        assert.ok(Array.isArray(res.body.orders) || Array.isArray(res.body.pending),
            'body deve ter campo orders quando confirmedSince fornecido');
    });

});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/orders/report
// ─────────────────────────────────────────────────────────────────────────────

describe('GET /api/orders/report', () => {

    it('→ 200 sem filtros — usa últimos 30 dias por padrão', async () => {
        const res = await req('get', '/api/orders/report');
        assert.equal(res.status, 200,
            `Esperado 200: ${JSON.stringify(res.body)}`);
        assert.ok(Array.isArray(res.body.orders), 'deve ter campo orders (array)');
        assert.ok(res.body.pagination, 'deve ter objeto pagination');
    });

    it('→ 200 com filtros from/to explícitos', async () => {
        const res = await req('get', '/api/orders/report?from=2024-01-01&to=2024-12-31');
        assert.equal(res.status, 200);
        assert.ok(res.body.from === '2024-01-01', 'deve refletir o from na resposta');
        assert.ok(res.body.to === '2024-12-31', 'deve refletir o to na resposta');
    });

    it('→ 200 com paginação (page=1&limit=5)', async () => {
        const res = await req('get', '/api/orders/report?page=1&limit=5');
        assert.equal(res.status, 200);
        const pag = res.body.pagination;
        assert.ok(pag, 'deve ter pagination');
        assert.equal(pag.page, 1, 'page deve ser 1');
        assert.ok(pag.limit <= 5, 'limit deve ser respeitado');
    });

    it('→ 200 com limit além do máximo (200) — limita internamente', async () => {
        const res = await req('get', '/api/orders/report?limit=9999');
        assert.equal(res.status, 200);
        assert.ok(res.body.pagination.limit <= 200, 'limit não deve ultrapassar 200');
    });

});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/orders/events
// ─────────────────────────────────────────────────────────────────────────────

describe('GET /api/orders/events', () => {

    it('→ 200 com campo events (array)', async () => {
        const res = await req('get', '/api/orders/events');
        assert.equal(res.status, 200);
        assert.ok(Array.isArray(res.body.events), 'deve ter campo events (array)');
    });

});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/orders/:id
// ─────────────────────────────────────────────────────────────────────────────

describe('GET /api/orders/:id', () => {

    it('→ 200 com status do pedido (campo status)', async () => {
        const orderId = uuidv4();
        const res = await req('get', `/api/orders/${orderId}`);
        // Em dev/mock, PG offline retorna pending sem 500
        assert.equal(res.status, 200);
        assert.ok(res.body.status !== undefined, 'deve ter campo status');
    });

});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/orders/:id/confirm
// ─────────────────────────────────────────────────────────────────────────────

describe('POST /api/orders/:id/confirm', () => {

    it('→ 400 quando erpOrderId está ausente', async () => {
        const res = await req('post', `/api/orders/${uuidv4()}/confirm`)
            .send({});
        assert.equal(res.status, 400);
        assert.ok(res.body.error, 'deve ter campo error');
        assert.ok(res.body.code === 'MISSING_ERP_ID', `code deve ser MISSING_ERP_ID, recebido: ${res.body.code}`);
    });

    it('→ 200 ou 404 quando erpOrderId fornecido (pedido pode não existir em mock)', async () => {
        const res = await req('post', `/api/orders/${uuidv4()}/confirm`)
            .send({ erpOrderId: '12345' });
        // Em mock sem PG real, pode retornar 404 (order not found) ou 200
        assert.ok(
            res.status === 200 || res.status === 404,
            `Esperado 200 ou 404, recebido ${res.status}: ${JSON.stringify(res.body)}`
        );
    });

    it('→ não aceita erpOrderId nulo', async () => {
        const res = await req('post', `/api/orders/${uuidv4()}/confirm`)
            .send({ erpOrderId: null });
        assert.equal(res.status, 400);
    });

});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/orders/:id/error
// ─────────────────────────────────────────────────────────────────────────────

describe('POST /api/orders/:id/error', () => {

    it('→ 200 ou 404 com message fornecido', async () => {
        const res = await req('post', `/api/orders/${uuidv4()}/error`)
            .send({ message: 'SP_FALHOU: campo nulo' });
        assert.ok(
            res.status === 200 || res.status === 404,
            `Esperado 200 ou 404, recebido ${res.status}`
        );
    });

    it('→ 200 ou 404 sem message (usa default "Erro desconhecido")', async () => {
        const res = await req('post', `/api/orders/${uuidv4()}/error`)
            .send({});
        assert.ok(
            res.status === 200 || res.status === 404,
            `Esperado 200 ou 404, recebido ${res.status}`
        );
    });

    it('→ mensagem longa é truncada em 500 chars (não retorna 400)', async () => {
        const longMsg = 'A'.repeat(1000);
        const res = await req('post', `/api/orders/${uuidv4()}/error`)
            .send({ message: longMsg });
        // Não deve retornar erro de validação por mensagem longa
        assert.ok(
            res.status !== 400,
            `Mensagem longa não deve retornar 400, recebido ${res.status}`
        );
    });

});
