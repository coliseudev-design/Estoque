'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

// parseLookupCode é pura; o módulo de documentos carrega o pool do pg sem conectar.
process.env.NODE_ENV = 'test';
const { parseLookupCode } = require('../src/services/documents');

test('chave de acesso da NF-e (DANFE) vira série e número', () => {
    // Chave da NF 469475 (VetMatriz), como impressa no DANFE, com espaços.
    const r = parseLookupCode('5025 0905 8080 8500 0152 5500 1000 4694 7515 7777 5128');
    assert.equal(r.kind, 'nfe');
    assert.equal(r.number, '469475');
    assert.equal(r.series, '1');
});

test('número do pedido puro', () => {
    assert.deepEqual(parseLookupCode('114536'), { kind: 'code', exact: '114536', number: '114536' });
});

test('etiqueta com prefixo e zeros à esquerda', () => {
    assert.equal(parseLookupCode('PE00114536').number, '114536');
});
