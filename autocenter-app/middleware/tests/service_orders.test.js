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
            if (text.includes('INSERT INTO service_orders')) {
                return { rows: [{ id: 'so-uuid-123' }] };
            }
            return { rows: [] };
        },
        release: () => {}
    };
};

pg.Pool.prototype.query = async function(text, params) {
    if (text.includes('INSERT INTO service_orders')) {
        return { rows: [{ id: 'so-uuid-123' }] };
    }
    
    if (text.includes('UPDATE service_orders')) {
        return { rowCount: 1 };
    }

    if (text.includes('FROM service_orders')) {
        // Detailed lookup by ID
        if (params && params[1] === 'so-uuid-123') {
            return {
                rows: [{
                    id: 'so-uuid-123',
                    tenantId: params[0],
                    quoteId: null,
                    deviceId: 'test-device-id',
                    plate: 'AAA1234',
                    customerId: 123,
                    customerName: 'Cliente OS',
                    customerPhone: '11999999999',
                    status: 'ABERTA',
                    totalAmount: 150.00,
                    observation: 'Test OS',
                    createdAt: new Date(),
                    updatedAt: new Date()
                }],
                rowCount: 1
            };
        }
        
        // List or Approved count
        if (text.includes('COUNT(*) AS total')) {
            return { rows: [{ total: 1 }] };
        }
        
        // List or Approved details
        return {
            rows: [{
                id: 'so-uuid-123',
                tenantId: params[0],
                quoteId: null,
                deviceId: 'test-device-id',
                plate: 'AAA1234',
                customerId: 123,
                customerName: 'Cliente OS',
                customerPhone: '11999999999',
                status: (text.includes("status = 'APPROVED'") || text.includes("status IN")) ? 'APPROVED' : 'ABERTA',
                totalAmount: 150.00,
                observation: 'Test OS',
                createdAt: new Date(),
                updatedAt: new Date()
            }]
        };
    }

    if (text.includes('FROM service_order_items')) {
        return {
            rows: [{
                id: 'item-uuid-1',
                productCode: 'PROD1',
                productDescription: 'Peça Teste',
                quantity: 1,
                unitPrice: 150.00,
                totalPrice: 150.00,
                itemType: 'PART',
                technicianId: 5
            }]
        };
    }

    if (text.includes('FROM service_order_photos')) {
        return {
            rows: [{
                id: 'photo-uuid-1',
                photoUrl: '/uploads/test.jpg',
                photoType: 'GENERAL'
            }]
        };
    }

    if (text.includes('FROM service_order_checklist')) {
        return {
            rows: [{
                id: 'chk-uuid-1',
                itemName: 'Bateria',
                status: 'OK',
                observation: 'Tudo certo'
            }]
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

test('POST /api/service-orders - create service order', async () => {
    const payload = {
        plate: 'AAA1234',
        customerId: 123,
        customerName: 'Cliente OS',
        customerPhone: '11999999999',
        observation: 'Test OS',
        items: [
            {
                productCode: 'PROD1',
                productDescription: 'Peça Teste',
                quantity: 1,
                unitPrice: 150.00,
                itemType: 'PART',
                technicianId: 5
            }
        ],
        checklist: [
            {
                itemName: 'Bateria',
                status: 'OK',
                observation: 'Tudo certo'
            }
        ]
    };

    const res = await request(app)
        .post('/api/service-orders')
        .set('Authorization', `Bearer ${token}`)
        .send(payload);

    assert.strictEqual(res.statusCode, 201);
    assert.strictEqual(res.body.status, 'ABERTA');
    assert.strictEqual(res.body.id, 'so-uuid-123');
});

test('GET /api/service-orders - list service orders', async () => {
    const res = await request(app)
        .get('/api/service-orders?page=1&limit=10')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.page, 1);
    assert.strictEqual(res.body.limit, 10);
    assert.strictEqual(res.body.total, 1);
    assert.strictEqual(res.body.serviceOrders.length, 1);
});

test('GET /api/service-orders/:id - detail service order', async () => {
    const res = await request(app)
        .get('/api/service-orders/so-uuid-123')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.id, 'so-uuid-123');
    assert.strictEqual(res.body.items.length, 1);
    assert.strictEqual(res.body.checklist.length, 1);
});

test('PATCH /api/service-orders/:id/status - update status', async () => {
    const res = await request(app)
        .patch('/api/service-orders/so-uuid-123/status')
        .set('Authorization', `Bearer ${token}`)
        .send({ status: 'EM_EXECUCAO' });

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.status, 'EM_EXECUCAO');
});

test('GET /api/service-orders/approved - approved orders queue', async () => {
    const res = await request(app)
        .get('/api/service-orders/approved')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.length, 1);
    assert.strictEqual(res.body[0].status, 'APPROVED');
});
