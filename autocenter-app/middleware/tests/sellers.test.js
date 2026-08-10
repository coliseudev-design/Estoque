'use strict';

process.env.JWT_DEVICE_KEY = 'aQbY3eqVz2xd8PSr0AUKtfwFRo7n1IickE6sMGWTNCpXhZ95';
process.env.NODE_ENV = 'test';

const test = require('node:test');
const assert = require('node:assert');
const jwt = require('jsonwebtoken');

// Mock pg and ioredis
const pg = require('pg');
pg.Pool.prototype.connect = async function() {
    return {
        query: async (text, params) => {
            return { rows: [] };
        },
        release: () => {}
    };
};

pg.Pool.prototype.query = async function(text, params) {
    if (text.includes('INSERT INTO sellers')) {
        return { rows: [] };
    }
    
    if (text.includes('FROM sellers')) {
        return {
            rows: [
                { id: 1, name: 'Vendedor 1', email: 'vendedor1@coliseu.com', active: true },
                { id: 2, name: 'Vendedor 2', email: 'vendedor2@coliseu.com', active: true }
            ]
        };
    }

    return { rows: [] };
};

const ioredis = require('ioredis');
class MockRedis {
    async get() { return null; }
    async setex() { return 'OK'; }
    on() {}
}
require.cache[require.resolve('ioredis')] = {
    exports: MockRedis
};

// Mock global fetch for validation and other tests
globalThis.fetch = async (url, options) => {
    if (url.includes('/validate-key')) {
        return {
            status: 200,
            json: async () => ({ valid: true })
        };
    }
    return { status: 404, json: async () => ({}) };
};

const request = require('supertest');
const app = require('../src/app');

// Helpers for tests
const tenantId = '1e40d65f-4319-4c68-ae13-66223820c095';
const deviceId = 'test-device-id';
const token = jwt.sign(
    {
        tenantId,
        tenant: tenantId,
        deviceId,
        module: 'autocenter',
        companyName: 'Piveta Dist.'
    },
    process.env.JWT_DEVICE_KEY,
    { expiresIn: '1h' }
);

test('POST /internal/sellers/sync - sync batch of sellers from worker', async () => {
    const payload = [
        { id: 1, name: 'Vendedor A', email: 'vendedora@coliseu.com', passwordHash: '1234', active: true },
        { id: 2, name: 'Vendedor B', email: 'vendedorb@coliseu.com', passwordHash: '5678', active: false }
    ];

    const res = await request(app)
        .post('/internal/sellers/sync')
        .set('X-Internal-Key', 'mock-internal-key')
        .set('X-Tenant-Id', tenantId)
        .send(payload);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.synced, 2);
    assert.strictEqual(res.body.skipped, 0);
});

test('GET /api/sellers - list active sellers for app', async () => {
    const res = await request(app)
        .get('/api/sellers')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.ok(res.body.sellers);
    assert.strictEqual(res.body.sellers.length, 2);
    assert.strictEqual(res.body.sellers[0].name, 'Vendedor 1');
});
