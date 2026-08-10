'use strict';

// Configure mandatory environment variables for boot
process.env.JWT_DEVICE_KEY = 'aQbY3eqVz2xd8PSr0AUKtfwFRo7n1IickE6sMGWTNCpXhZ95';
process.env.NODE_ENV = 'test';

const test = require('node:test');
const assert = require('node:assert');
const jwt = require('jsonwebtoken');

// Mock pg and ioredis to prevent real connection attempts during tests
const pg = require('pg');
pg.Pool.prototype.connect = async function() {
    return {
        query: async () => {
            return { rows: [] };
        },
        release: () => {}
    };
};

pg.Pool.prototype.query = async function(text, params) {
    // Mock response for vehicles query
    if (text.includes('FROM vehicles')) {
        if (params && params[1] === 'AAA1234') {
            return {
                rows: [{
                    id_cliente: 123,
                    id_veiculo: 456,
                    brand: 'TOYOTA',
                    model: 'COROLLA',
                    plate: 'AAA1234',
                    ano_fabrica: 2021,
                    ano_modelo: 2022,
                    cor: 'PRATA',
                    obs: 'Particular',
                    numero: '123',
                    numero_chassi: '9BWZZZ',
                    id_seguradora: 1,
                    status: 1,
                    numero_1: '99999',
                    numero_2: '88888',
                    combustivel: 'FLEX',
                    customerName: 'Cliente Local'
                }]
            };
        }
        return { rows: [] };
    }
    
    // Mock response for pending_customers insertion
    if (text.includes('INSERT INTO pending_customers')) {
        return {
            rows: [{
                id: 'pending-uuid-123',
                tenantId: params[0],
                localId: params[1],
                name: params[2],
                status: 'PENDING',
                createdAt: new Date()
            }]
        };
    }

    // Mock response for paginated customers
    if (text.includes('COUNT(*) AS total')) {
        return { rows: [{ total: 1 }] };
    }
    if (text.includes('SELECT erp_id AS "erpId"')) {
        return {
            rows: [{
                erpId: 10,
                name: 'Cliente Sincronizado',
                fantasyName: 'Fantasia',
                cpfCnpj: '12345678901',
                phone: '11999999999',
                phone2: '11888888888',
                email: 'cliente@erp.com',
                city: 'São Paulo',
                address: 'Av. Paulista, 1000'
            }]
        };
    }

    return { rows: [] };
};

const ioredis = require('ioredis');
// Stub out redis methods so they don't hit port 6379
class MockRedis {
    async get() { return null; }
    async setex() { return 'OK'; }
    on() {}
}
// Override ioredis export
require.cache[require.resolve('ioredis')] = {
    exports: MockRedis
};

// Mock global fetch for APIBrasil lookup
globalThis.fetch = async (url, options) => {
    if (url.includes('apibrasil.io')) {
        return {
            ok: true,
            status: 200,
            json: async () => ({
                error: false,
                data: {
                    resultados: [
                        {
                            principal: true,
                            marca: 'HONDA',
                            modelo: 'CIVIC EXL',
                            anoFabricacao: '2020',
                            anoModelo: '2020',
                            cor: 'PRETA',
                            chassi: '***1234***'
                        }
                    ]
                }
            })
        };
    }
    return { ok: false, status: 404, json: async () => ({}) };
};

// Now import app and supertest
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

test('Plate Lookup - local PostgreSQL hit', async () => {
    const res = await request(app)
        .get('/api/vehicles/AAA1234')
        .set('Authorization', `Bearer ${token}`);
    
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.plate, 'AAA1234');
    assert.strictEqual(res.body.customerName, 'Cliente Local');
    assert.strictEqual(res.body.marca, 'TOYOTA');
});

test('Plate Lookup - local PostgreSQL miss, APIBrasil mock hit', async () => {
    const res = await request(app)
        .get('/api/vehicles/BBB9999')
        .set('Authorization', `Bearer ${token}`);
    
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.placa, 'BBB9999');
    assert.strictEqual(res.body.marca, 'HONDA'); // Mocked fallback data in vehicle.service
});

test('Customer Creation - pending customer offline upload', async () => {
    const payload = {
        localId: 'local_999',
        name: 'Offline Customer Test',
        fantasyName: 'Offline Fantasy',
        cpfCnpj: '00011122233',
        phone: '11999999999',
        email: 'offline@test.com',
        city: 'São Paulo',
        address: 'Rua Direita, 50'
    };

    const res = await request(app)
        .post('/api/customers/new')
        .set('Authorization', `Bearer ${token}`)
        .send(payload);

    assert.strictEqual(res.statusCode, 201);
    assert.strictEqual(res.body.localId, 'local_999');
    assert.strictEqual(res.body.name, 'Offline Customer Test');
    assert.strictEqual(res.body.status, 'PENDING');
});

test('Customer Sync - paginated download of ERP customers', async () => {
    const res = await request(app)
        .get('/api/customers/sync?page=1&limit=5')
        .set('Authorization', `Bearer ${token}`);

    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.body.page, 1);
    assert.strictEqual(res.body.limit, 5);
    assert.strictEqual(res.body.total, 1);
    assert.strictEqual(res.body.customers.length, 1);
    assert.strictEqual(res.body.customers[0].name, 'Cliente Sincronizado');
});
