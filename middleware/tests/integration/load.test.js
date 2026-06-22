/**
 * load.test.js — Testes de carga e concorrência (N2).
 *
 * Cobre:
 *  1. Pedido com 50 itens → 200 e tempo < 3s
 *  2. Pedido com 200 itens → 200 e tempo < 5s
 *  3. 20 pedidos simultâneos → todos retornam 200 (concorrência)
 *  4. 50 pedidos simultâneos → taxa de sucesso >= 80% (stress)
 *  5. Idempotência sob carga → mesmo id enviado 10x simultâneo → 200
 *  6. Sync misto (catalog + orders) simultâneo → sem interferência
 *  7. Pedido com item de qty 99999 → 200 (fronteira numérica)
 *
 * Rodar: jest --testPathPattern=load --forceExit --verbose
 *
 * @module tests/load.test
 */
'use strict';

process.env.FB_MOCK = 'true';
process.env.NODE_ENV = 'test';
process.env.API_KEY = 'test-key';
process.env.ADMIN_API_KEY = 'admin-test';

const request = require('supertest');
const { v4: uuidv4 } = require('uuid');

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('../../src/middleware/auth', () => {
    const requireApiKey = (req, res, next) => {
        req.company = { id: 'company-load-test-0001', name: 'Empresa Carga' };
        next();
    };
    return {
        requireApiKey,
        authenticateSyncRequest: requireApiKey,
        invalidateAuthCache: () => { },
        sha256hex: s => s,
    };
});

jest.mock('../../src/services/dataStore', () => {
    const store = new Map();
    return {
        upsert: async (cId, entity, data) => { store.set(`${cId}:${entity}`, data); return { count: data.length, syncedAt: new Date().toISOString() }; },
        get: async (cId, entity) => { const d = store.get(`${cId}:${entity}`) ?? []; return { data: d, syncedAt: null, source: d.length ? 'redis' : 'empty' }; },
        warmCache: async () => ({ warmed: [] }),
        getStatus: async () => ({}),
    };
});

jest.mock('../../src/db/postgres', () => {
    const _orders = [];
    return {
        pgQuery: jest.fn(async (sql, params) => {
            // Simula INSERT id-empotente
            if (sql.includes('INSERT INTO orders')) {
                const id = params?.[0];
                if (!_orders.find(o => o.id === id)) _orders.push({ id });
                return { rows: [], rowCount: 1 };
            }
            if (sql.includes('COUNT(*)')) return { rows: [{ total: 0 }] };
            return { rows: [], rowCount: 0 };
        }),
        pgPing: async () => true,
        pool: { connect: jest.fn() },
    };
});

const app = require('../../src/app');

// ── Builders ──────────────────────────────────────────────────────────────────

/**
 * Gera um pedido de teste com N itens.
 * @param {number} itemCount — número de itens no pedido
 * @param {string} [id]      — UUID do pedido (gerado se omitido)
 */
function buildOrder(itemCount, id = uuidv4()) {
    const items = Array.from({ length: itemCount }, (_, i) => ({
        productCode: String(i + 1),
        productName: `Produto ${i + 1}`,
        quantity: i + 1,
        unitPrice: 10.0 + i,
        discount: 0,
    }));
    const totalAmount = items.reduce((s, it) => s + it.quantity * it.unitPrice, 0);
    return {
        id,
        sellerId: 'seller-001',
        customerId: 'customer-A01',
        naturezaId: '1',
        paymentSpeciesId: '1',
        items,
        totalAmount,
        discountValue: 0,
    };
}

/**
 * Envia N pedidos simultâneos e retorna os resultados.
 * @param {object[]} orders
 * @returns {Promise<{status: number, ms: number}[]>}
 */
async function sendOrdersBatch(orders) {
    return Promise.all(
        orders.map(async (order) => {
            const t0 = Date.now();
            const res = await request(app)
                .post('/api/sync/orders')
                .set('API-Key', 'test-key')
                .send({ orders: [order] });
            return { status: res.status, ms: Date.now() - t0 };
        })
    );
}

// ── Testes ────────────────────────────────────────────────────────────────────

// ── Warm-up ───────────────────────────────────────────────────────────────────
// O ioredis em mock faz ~5 tentativas de reconexão (≈ 7-9s) na primeira chamada.
// Aquecemos o path de orders antes para que as métricas de desempenho meçam
// apenas o processamento real, não o overhead de inicialização do Redis.
beforeAll(async () => {
    const warmupOrder = buildOrder(1, 'warmup-order-uuid');
    await request(app)
        .post('/api/sync/orders')
        .set('API-Key', 'test-key')
        .send({ orders: [warmupOrder] });
}, 15000);  // timeout de 15s para o warm-up

describe('Load Tests — Pedidos com muitos itens', () => {

    test('Pedido com 50 itens → 200 e resposta < 2000ms (pós warm-up)', async () => {
        const order = buildOrder(50);
        const t0 = Date.now();
        const res = await request(app)
            .post('/api/sync/orders')
            .set('API-Key', 'test-key')
            .send({ orders: [order] });
        const ms = Date.now() - t0;

        expect(res.status).toBe(200);
        expect(ms).toBeLessThan(2000);
        console.log(`  📦 50 itens: ${ms}ms (pós warm-up)`);
    });

    test('Pedido com 200 itens → 200 e resposta < 5000ms', async () => {
        const order = buildOrder(200);
        const t0 = Date.now();
        const res = await request(app)
            .post('/api/sync/orders')
            .set('API-Key', 'test-key')
            .send({ orders: [order] });
        const ms = Date.now() - t0;

        expect(res.status).toBe(200);
        expect(ms).toBeLessThan(5000);
        console.log(`  📦 200 itens: ${ms}ms`);
    });

    test('Pedido com item qty=99999 (fronteira numérica) → 200', async () => {
        const order = buildOrder(1);
        order.items[0].quantity = 99999;
        order.totalAmount = 99999 * order.items[0].unitPrice;

        const res = await request(app)
            .post('/api/sync/orders')
            .set('API-Key', 'test-key')
            .send({ orders: [order] });
        expect(res.status).toBe(200);
    });

});

describe('Load Tests — Sincronização simultânea', () => {

    test('20 pedidos simultâneos com 10 itens cada → todos 200', async () => {
        const orders = Array.from({ length: 20 }, () => buildOrder(10));
        const results = await sendOrdersBatch(orders);

        const failures = results.filter(r => r.status !== 200);
        const maxMs = Math.max(...results.map(r => r.ms));
        const avgMs = Math.round(results.reduce((s, r) => s + r.ms, 0) / results.length);

        console.log(`  ⚡ 20 concurrent: avg=${avgMs}ms max=${maxMs}ms failures=${failures.length}`);
        expect(failures.length).toBe(0);
    });

    test('50 pedidos simultâneos com 5 itens cada → ≥ 80% de sucesso (stress)', async () => {
        const orders = Array.from({ length: 50 }, () => buildOrder(5));
        const results = await sendOrdersBatch(orders);

        const successCount = results.filter(r => r.status === 200).length;
        const successRate = successCount / results.length;
        const maxMs = Math.max(...results.map(r => r.ms));

        console.log(`  🔥 50 concurrent: ${successCount}/50 ok (${Math.round(successRate * 100)}%) max=${maxMs}ms`);
        expect(successRate).toBeGreaterThanOrEqual(0.8);
    });

    test('Mesmo id enviado 10x simultâneo → idempotência, todos retornam 200', async () => {
        const FIXED_ID = 'idempotency-load-test-uuid';
        const order = buildOrder(5, FIXED_ID);
        const results = await Promise.all(
            Array.from({ length: 10 }, () =>
                request(app)
                    .post('/api/sync/orders')
                    .set('API-Key', 'test-key')
                    .send({ orders: [order] })
                    .then(r => r.status)
            )
        );
        const failures = results.filter(s => s !== 200);
        console.log(`  🔁 10x mesmo id: ${results.join(',')} - failures: ${failures.length}`);
        expect(failures.length).toBe(0);
    });

});

describe('Load Tests — Sync misto simultâneo', () => {

    test('Catalog push + 10 orders simultâneos → sem interferência de dados', async () => {
        const bigCatalog = Array.from({ length: 100 }, (_, i) => ({
            code: String(i + 100),
            name: `Item-Carga-${i}`,
            price: 10 + i,
            stock: 50,
            unit: 'UN',
        }));

        const orders = Array.from({ length: 10 }, () => buildOrder(8));

        // Dispara catalog push e orders simultaneamente
        const [catalogRes, ...orderResults] = await Promise.all([
            request(app)
                .post('/api/sync/catalog')
                .set('API-Key', 'test-key')
                .send({ products: bigCatalog }),
            ...await sendOrdersBatch(orders).then(rs => rs.map(r => r.status)),
        ]);

        expect(catalogRes.status).toBe(200);
        // Ao menos 80% dos orders devem ter sucesso sob carga mista
        const orderSuccess = orderResults.filter(s => s === 200).length;
        console.log(`  🔀 Mixed load: catalog=200 orders=${orderSuccess}/10`);
        expect(orderSuccess).toBeGreaterThanOrEqual(8);
    });

});
