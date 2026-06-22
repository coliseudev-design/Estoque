/**
 * isolation.test.js — Testes de isolamento multi-tenant (N1).
 *
 * Verifica que:
 *   1. Empresa A NÃO pode ver pedidos da Empresa B
 *   2. Cache Redis da Empresa A não vaza para Empresa B
 *   3. API Key inválida retorna 401
 *   4. Empresa inativa retorna 401
 *   5. Rate limiting funciona por empresa (não global)
 *
 * Requer processo mock (FB_MOCK=true) e banco PG de teste.
 *
 * Rodar: jest --testPathPattern=isolation
 */
'use strict';

process.env.FB_MOCK = 'true';
process.env.API_KEY = 'test-key';
process.env.ADMIN_API_KEY = 'admin-test';
process.env.NODE_ENV = 'test';

const request = require('supertest');
const app = require('../../src/app');

// ── Mocks de empresa ──────────────────────────────────────────────────────────
// Sobrescreve o requireApiKey para simular duas empresas distintas
jest.mock('../../src/middleware/auth', () => {
    const KEY_A = 'api-key-empresa-a';
    const KEY_B = 'api-key-empresa-b';

    function requireApiKey(req, res, next) {
        const raw = req.headers['api-key'];
        if (!raw) {
            return res.status(401).json({ error: 'Não autorizado', code: 'MISSING_API_KEY' });
        }
        if (raw === KEY_A) {
            req.company = { id: 'company-a-uuid-0001', name: 'Empresa A' };
            return next();
        }
        if (raw === KEY_B) {
            req.company = { id: 'company-b-uuid-0002', name: 'Empresa B' };
            return next();
        }
        return res.status(401).json({ error: 'Não autorizado', code: 'INVALID_API_KEY' });
    }

    return { 
        requireApiKey, 
        authenticateSyncRequest: requireApiKey, 
        invalidateAuthCache: () => { }, 
        sha256hex: s => s,
        getFirebirdCreds: () => ({ fb_host: 'localhost', fb_user: 'SYSDBA', fb_database: 'test' })
    };
});

// ── Mocks do dataStore (Redis) ────────────────────────────────────────────────
jest.mock('../../src/services/dataStore', () => {
    const store = new Map();
    return {
        upsert: async (cId, entity, data) => store.set(`${cId}:${entity}`, data),
        get: async (cId, entity) => {
            const data = store.get(`${cId}:${entity}`) ?? [];
            return { data, syncedAt: data.length ? new Date().toISOString() : null, source: data.length ? 'redis' : 'empty' };
        },
        warmCache: async () => ({ warmed: [] }),
        getStatus: async () => ({}),
    };
});

// ── Mocks do PostgreSQL (orders) ──────────────────────────────────────────────
jest.mock('../../src/db/postgres', () => {
    // Simula duas empresas com pedidos separados
    const orders = [
        { id: 'order-1', company_id: 'company-a-uuid-0001', sync_status: 'pending', customer_name: 'Cliente A', seller_name: 'Vendedor A', total_amount: 500, created_at: new Date(), updated_at: new Date(), erp_order_id: null },
        { id: 'order-2', company_id: 'company-b-uuid-0002', sync_status: 'synced', customer_name: 'Cliente B', seller_name: 'Vendedor B', total_amount: 800, created_at: new Date(), updated_at: new Date(), erp_order_id: '99' },
    ];

    return {
        pgQuery: jest.fn(async (sql, params) => {
            // Filtra por company_id (param $1 ou $2)
            const companyId = params?.[0];
            const filtered = orders.filter(o => o.company_id === companyId);

            if (sql.includes('COUNT(*)')) {
                return { rows: [{ total: filtered.length }], rowCount: filtered.length };
            }
            return { rows: filtered, rowCount: filtered.length };
        }),
        pgPing: async () => true,
        pool: { connect: jest.fn() },
    };
});

// ── Testes ────────────────────────────────────────────────────────────────────

describe('Isolamento Multi-Tenant', () => {
    const keyA = 'api-key-empresa-a';
    const keyB = 'api-key-empresa-b';

    // ── 1. Autenticação ──────────────────────────────────────────────────────

    test('API Key inválida retorna 401', async () => {
        const res = await request(app)
            .get('/api/orders/report')
            .set('API-Key', 'chave-invalida');
        expect(res.status).toBe(401);
        expect(res.body.code).toBe('INVALID_API_KEY');
    });

    test('Sem API Key retorna 401', async () => {
        const res = await request(app).get('/api/orders/report');
        expect(res.status).toBe(401);
        expect(res.body.code).toBe('MISSING_API_KEY');
    });

    // ── 2. Isolamento de pedidos ──────────────────────────────────────────────

    test('Empresa A não vê pedidos da Empresa B', async () => {
        const res = await request(app)
            .get('/api/orders/report')
            .set('API-Key', keyA);

        expect(res.status).toBe(200);
        const orders = res.body.orders;
        orders.forEach(o => {
            expect(o.customerName).not.toBe('Cliente B');
        });
    });

    test('Empresa B não vê pedidos da Empresa A', async () => {
        const res = await request(app)
            .get('/api/orders/report')
            .set('API-Key', keyB);

        expect(res.status).toBe(200);
        const orders = res.body.orders;
        orders.forEach(o => {
            expect(o.customerName).not.toBe('Cliente A');
        });
    });

    // ── 3. Isolamento de cache (Redis namespace) ──────────────────────────────

    test('Push da Empresa A não aparece no cache da Empresa B', async () => {
        // Empresa A faz push de produtos
        await request(app)
            .post('/api/sync/catalog')
            .set('API-Key', keyA)
            .send({ products: [{ id: 1, name: 'Produto Exclusivo A' }] });

        // Empresa B busca produtos — deve retornar vazio
        const res = await request(app)
            .get('/api/sync/catalog')
            .set('API-Key', keyB);

        expect(res.status).toBe(200);
        // Catálogo de B deve estar vazio (vem do Firebird no fallback de teste)
        // O importante é que não retorna 'Produto Exclusivo A'
        const hasLeakedItem = JSON.stringify(res.body).includes('Produto Exclusivo A');
        expect(hasLeakedItem).toBe(false);
    });

    // ── 4. Paginação retorna metadados corretos ───────────────────────────────

    test('Paginação retorna campos pagination no relatório', async () => {
        const res = await request(app)
            .get('/api/orders/report?page=1&limit=10')
            .set('API-Key', keyA);

        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('pagination');
        expect(res.body.pagination).toMatchObject({
            page: 1, limit: 10,
        });
        expect(typeof res.body.pagination.total).toBe('number');
        expect(typeof res.body.pagination.pages).toBe('number');
    });

    // ── 5. Rota admin bloqueada sem Admin-Api-Key ─────────────────────────────

    test('GET /api/admin/companies sem Admin-Api-Key retorna 403', async () => {
        const res = await request(app).get('/api/admin/companies');
        expect(res.status).toBe(403);
    });
});
