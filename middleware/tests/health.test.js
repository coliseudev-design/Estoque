/**
 * health.test.js — Testes de integração para os endpoints /health.
 *
 * Cobre:
 *  1. GET /health                  → 200 pública (PG status desconhecido no mock)
 *  2. GET /health/introspect       → 400 (sem ?table, mas auth passóu via mock)
 *  3. GET /health/introspect com ?table existente → não é 401
 *  4. GET /rota-inexistente        → 404 + code NOT_FOUND
 *
 * NOTA: Em FB_MOCK=true, requireApiKeyMock injeta empresa sem validar o header,
 * então testes de 401/auth não são aplicáveis aqui (cobertos em auth.test.js).
 *
 * @module tests/health.test
 */
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { app, API_KEY } = require('./helpers/testApp');

describe('GET /health', () => {

    it('deve retornar 200 sem autenticação', async () => {
        const res = await request(app).get('/health');
        assert.equal(res.status, 200);
        assert.ok(res.body.status, 'body.status deve existir');
    });

    it('GET /health/introspect sem ?table retorna 400 (parâmetro obrigatório)', async () => {
        // No modo mock a auth é bypassada, então a validação de ?table retorna 400
        const res = await request(app)
            .get('/health/introspect')
            .set('API-Key', API_KEY);
        assert.equal(res.status, 400);
        assert.ok(res.body.error);
    });

    it('GET /health/introspect com ?table não retorna 401', async () => {
        const res = await request(app)
            .get('/health/introspect?table=CUSTOMERS')
            .set('API-Key', API_KEY);
        // Em modo mock FB pode retornar 200 ou 500 (não conectado ao Firebird real)
        // Mas NUNCA deve retornar 401
        assert.notEqual(res.status, 401, 'não deve rejeitar autenticação válida');
    });

    it('deve retornar 404 em rota inexistente', async () => {
        const res = await request(app).get('/rota-nao-existe');
        assert.equal(res.status, 404);
        assert.equal(res.body.code, 'NOT_FOUND');
    });

});

