'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
const { newCode, normalizeCode } = require('../src/services/devices');

test('código de pareamento: XXXX-XXXX sem caracteres ambíguos', () => {
    for (let i = 0; i < 200; i++) {
        const c = newCode();
        assert.match(c, /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
    }
});

test('código digitado com espaço, hífen ou minúsculas é normalizado', () => {
    assert.equal(normalizeCode(' abcd-ef23 '), 'ABCDEF23');
    assert.equal(normalizeCode('ABCD EF23'), 'ABCDEF23');
});
