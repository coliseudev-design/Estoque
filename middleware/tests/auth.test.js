/**
 * auth.test.js — Testes de autenticação e comportamento de rotas protegidas.
 *
 * Modo de teste: FB_MOCK=true com requireApiKeyMock que injeta empresa
 * sem validar o header. Portanto este arquivo testa:
 *
 *  1. sha256hex() — função de hashing determinística exportada por auth.js
 *  2. Rotas protegidas respondem SEM 401 quando app está em modo mock
 *     (validação da pipeline completa: auth → handler → response)
 *  3. POST sem body obrigatório retorna 400 (validação de input independente de auth)
 *  4. GET /api/sync/sellers com e sem header retornam o mesmo status (mock ignora header)
 *
 * NOTA: Testes de 401 real (auth PG) pertencem a testes E2E com banco real.
 *
 * @module tests/auth.test
 */
'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { app, API_KEY } = require('./helpers/testApp');

// Importa sha256hex para teste unitário
const { sha256hex } = require('../src/middleware/auth');

const PROTECTED = '/api/sync/sellers';

describe('Auth — sha256hex (unit)', () => {

    it('deve produzir hash SHA-256 em hex deterministico', () => {
        const hash1 = sha256hex('coliseu-test-key');
        const hash2 = sha256hex('coliseu-test-key');
        assert.equal(hash1, hash2, 'mesmo input deve produzir mesmo hash');
        assert.equal(hash1.length, 64, 'SHA-256 hex tem 64 caracteres');
        assert.ok(/^[0-9a-f]+$/.test(hash1), 'deve ser hexadecimal lowercase');
    });

    it('hashes diferentes para inputs diferentes', () => {
        const h1 = sha256hex('key-abc');
        const h2 = sha256hex('key-xyz');
        assert.notEqual(h1, h2);
    });

});

describe('Auth — modo mock (FB_MOCK=true)', () => {

    it('GET rota protegida com key — pipeline funciona até o handler (não 500)', async () => {
        const res = await request(app)
            .get(PROTECTED)
            .set('API-Key', API_KEY);
        // No modo mock a auth injeta empresa; a rota deve retornar 200 (dados do fixture)
        assert.equal(res.status, 200, `Esperado 200, recebido ${res.status}: ${JSON.stringify(res.body)}`);
    });

    it('GET rota protegida sem key — mock bypassa auth, ainda retorna 200', async () => {
        // No modo mock qualquer request passa — comportamento esperado em teste
        const res = await request(app).get(PROTECTED);
        assert.equal(res.status, 200);
    });

    it('POST /api/sync/sellers sem body retorna 400 (validação de input)', async () => {
        const res = await request(app)
            .post('/api/sync/sellers')
            .set('API-Key', API_KEY)
            .send({});
        assert.equal(res.status, 400);
        assert.ok(res.body.error, 'deve ter campo error no body');
    });

    it('POST /api/sync/catalog com body válido retorna 200', async () => {
        const res = await request(app)
            .post('/api/sync/catalog')
            .set('API-Key', API_KEY)
            .send({ products: [{ code: '1', name: 'Teste', price: 10, stock: 5, unit: 'UN' }] });
        assert.equal(res.status, 200);
    });

});
