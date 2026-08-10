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
    if (text.includes('INSERT INTO technicians')) {
        return { rows: [] };
    }
    
    if (text.includes('FROM technicians')) {
        return {
            rows: [
                { erpId: 1, name: 'Técnico 1', active: true },
                { erpId: 2, name: 'Técnico 2', active: true }
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

test('POST /internal/technicians/sync - sync batch of technicians from worker', async () => {
    const payload = [
        { erpId: 1, name: 'Técnico A', active: true },
        { erpId: 2, name: 'Técnico B', active: false }
    ];

    const res = await request(app)
        .post('/internal/technicians/sync')
        .set('X-Internal-Key', 'mock-internal-key')
        .set('X-Tenant-Id', tenantId)
        .send(payload);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.synced, 2);
    assert.strictEqual(res.body.skipped, 0);
});

test('GET /api/technicians - list active technicians for app', async () => {
    const res = await request(app)
        .get('/api/technicians')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.length, 2);
    assert.strictEqual(res.body[0].name, 'Técnico 1');
});
