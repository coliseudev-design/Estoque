/**
 * testApp.js — Helper para testes de integração.
 *
 * Configura o ambiente antes de qualquer import do app:
 *  - FB_MOCK=true     → firebird.service.js retorna dados mockados
 *  - NODE_ENV=test    → desativa file sink do logger
 *  - API_KEY          → key conhecida para os testes
 *
 * Mocks de infraestrutura (sem necessidade de PG/Redis reais):
 *  - redis  → Map em memória via Module._load interceptor
 *  - postgres → pgPing retorna true, pgQuery retorna rows: []
 *
 * O interceptor é restaurado após o carregamento do app para não
 * afetar módulos carregados depois.
 *
 * @module tests/helpers/testApp
 */
'use strict';

// ── Env antes de qualquer require ─────────────────────────────────────────────
process.env.FB_MOCK = 'true';
process.env.NODE_ENV = 'test';
process.env.API_KEY = 'test-api-key-e2e';
process.env.FB_HOST = '127.0.0.1';
process.env.FB_PORT = '3050';
process.env.FB_DATABASE = '/tmp/test.fdb';
process.env.FB_USER = 'SYSDBA';
process.env.FB_PASSWORD = 'masterkey';

// ── Mocks de infraestrutura via Module._load ──────────────────────────────────
const path = require('path');
const Module = require('module');

const _redisStore = new Map();
const redisMock = {
    client: { status: 'ready', disconnect() { } },
    redisSet: async (cId, entity, data) => { _redisStore.set(`${cId}:${entity}`, data); return true; },
    redisGet: async (cId, entity) => _redisStore.get(`${cId}:${entity}`) ?? null,
    redisSyncedAt: async () => new Date().toISOString(),
    redisPing: async () => true,
};

const pgMock = {
    pool: {},
    pgQuery: async () => ({ rows: [] }),
    pgQuerySafe: async () => ({ rows: [] }),
    pgPing: async () => true,
};

const _origLoad = Module._load.bind(Module);
Module._load = function (request, parent, isMain) {
    if (parent) {
        try {
            const resolved = require.resolve(request, { paths: [path.dirname(parent.filename)] });
            if (resolved.endsWith(`${path.sep}redis.js`)) return redisMock;
            if (resolved.endsWith(`${path.sep}postgres.js`)) return pgMock;
            if (resolved.endsWith(`${path.sep}middleware${path.sep}auth.js`)) {
                const realAuth = _origLoad(request, parent, isMain);
                const origAuthSync = realAuth.authenticateSyncRequest;
                realAuth.authenticateSyncRequest = (req, res, next) => {
                    if (!req.headers['api-key'] && !req.headers.authorization) {
                        return realAuth.requireApiKeyMock(req, res, next);
                    }
                    return origAuthSync(req, res, next);
                };
                return realAuth;
            }
        } catch { /* módulo nativo ou não encontrado — passa adiante */ }
    }
    return _origLoad(request, parent, isMain);
};

const app = require('../../src/app');
const dataStore = require('../../src/services/dataStore');

// ── Fixtures ──────────────────────────────────────────────────────────────────

const SELLERS = [
    { id: '1', name: 'João Silva', email: 'joao@teste.com', passwordHash: '1234', maxDiscount: 10 },
    { id: '2', name: 'Maria Costa', email: 'maria@teste.com', passwordHash: '5678', maxDiscount: 5 },
];

const PRODUCTS = Array.from({ length: 5 }, (_, i) => ({
    code: String(i + 1),
    name: `Produto ${i + 1}`,
    stock: 100,
    unit: 'UN',
    price: (i + 1) * 10.0,
    priceCost: (i + 1) * 5.0,
    priceMin: (i + 1) * 8.0,
    brand: 'Marca A',
    category: 'Categoria X',
}));

const CUSTOMERS = [
    { id: '101', name: 'Cliente Alpha', cnpj: '11.111.111/0001-11', city: 'SP' },
    { id: '102', name: 'Cliente Beta', cnpj: '22.222.222/0001-22', city: 'RJ' },
];

// Pré-popula o store in-memory (equivalente ao push do Worker)
const COMPANY_ID = 'aaaaaaaa-0000-0000-0000-000000000001';
dataStore.upsert(COMPANY_ID, 'sellers', SELLERS).catch(() => { });
dataStore.upsert(COMPANY_ID, 'products', PRODUCTS).catch(() => { });
dataStore.upsert(COMPANY_ID, 'customers', CUSTOMERS).catch(() => { });
dataStore.upsert(COMPANY_ID, 'paymentSpecies', [{ id: '1', name: 'Dinheiro', type: 'D' }]).catch(() => { });
dataStore.upsert(COMPANY_ID, 'natureza', [{ id: '1', descricao: 'Venda Normal', mobOrdem: 1 }]).catch(() => { });
dataStore.upsert(COMPANY_ID, 'financials', []).catch(() => { });

// ── Exports ───────────────────────────────────────────────────────────────────
const API_KEY = process.env.API_KEY;
module.exports = { app, dataStore, API_KEY, SELLERS, PRODUCTS, CUSTOMERS };
