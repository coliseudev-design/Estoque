'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateRound, toUnits, fromUnits } = require('../src/domain/conference');

const item = (seq, productErpId, expectedQty, extra = {}) => ({ seq, productErpId, expectedQty, result: 'PENDENTE', ...extra });

test('toUnits/fromUnits preservam 4 casas sem float', () => {
    assert.equal(toUnits('12.5'), 125000);
    assert.equal(toUnits('0.0001'), 1);
    assert.equal(toUnits('-3.25'), -32500);
    assert.equal(fromUnits(toUnits('0.1') + toUnits('0.2')), '0.3');
});

test('tudo confere → CONCLUIDO na primeira rodada', () => {
    const r = evaluateRound({
        items: [item(1, 'A', '2'), item(2, 'B', '1')],
        round: 0,
        scanTotals: new Map([['A', '2'], ['B', '1']]),
        maxRecounts: 1,
    });
    assert.equal(r.allOk, true);
    assert.equal(r.nextStatus, 'CONCLUIDO');
    assert.deepEqual(r.items.map((i) => i.result), ['OK', 'OK']);
});

test('falta e sobra → DIVERGENTE com recontagem', () => {
    const r = evaluateRound({
        items: [item(1, 'A', '5'), item(2, 'B', '1')],
        round: 0,
        scanTotals: new Map([['A', '4'], ['B', '2']]),
        maxRecounts: 1,
    });
    assert.equal(r.nextStatus, 'DIVERGENTE');
    assert.equal(r.nextRound, 1);
    assert.deepEqual(r.divergentProducts.sort(), ['A', 'B']);
    assert.equal(r.items.find((i) => i.productErpId === 'A').result, 'FALTA');
    assert.equal(r.items.find((i) => i.productErpId === 'B').result, 'SOBRA');
});

test('mesmo produto em duas linhas é comparado pelo total', () => {
    const r = evaluateRound({
        items: [item(1, 'A', '3'), item(2, 'A', '2')],
        round: 0,
        scanTotals: new Map([['A', '5']]),
        maxRecounts: 1,
    });
    assert.equal(r.allOk, true);
    assert.deepEqual(r.items.map((i) => i.countedQty), ['3', '2']);
});

test('excedente fica na última linha do produto', () => {
    const r = evaluateRound({
        items: [item(1, 'A', '3'), item(2, 'A', '2')],
        round: 0,
        scanTotals: new Map([['A', '7']]),
        maxRecounts: 1,
    });
    assert.deepEqual(r.items.map((i) => i.countedQty), ['3', '4']);
    assert.ok(r.items.every((i) => i.result === 'SOBRA'));
});

test('produto fora do documento vira item extra', () => {
    const r = evaluateRound({
        items: [item(1, 'A', '1')],
        round: 0,
        scanTotals: new Map([['A', '1'], ['Z', '2']]),
        productInfo: new Map([['Z', { description: 'Produto Z' }]]),
        maxRecounts: 1,
    });
    const extra = r.items.find((i) => i.productErpId === 'Z');
    assert.equal(extra.isExtra, true);
    assert.equal(extra.result, 'SOBRA');
    assert.equal(extra.seq, 100000);
    assert.equal(extra.description, 'Produto Z');
    assert.equal(r.nextStatus, 'DIVERGENTE');
});

test('recontagem só altera o que divergiu e ignora o que já bateu', () => {
    const afterRound0 = [
        { ...item(1, 'A', '5'), countedQty: '4', result: 'FALTA' },
        { ...item(2, 'B', '1'), countedQty: '1', result: 'OK' },
    ];
    const r = evaluateRound({
        items: afterRound0,
        round: 1,
        scanTotals: new Map([['A', '5'], ['B', '9']]),
        maxRecounts: 1,
    });
    assert.equal(r.allOk, true);
    assert.equal(r.items.find((i) => i.productErpId === 'B').countedQty, '1');
    assert.deepEqual(r.ignoredProducts, ['B']);
});

test('limite de recontagens atingido → AGUARDANDO_APROVACAO', () => {
    const r = evaluateRound({
        items: [{ ...item(1, 'A', '5'), countedQty: '4', result: 'FALTA' }],
        round: 1,
        scanTotals: new Map([['A', '4']]),
        maxRecounts: 1,
    });
    assert.equal(r.nextStatus, 'AGUARDANDO_APROVACAO');
    assert.equal(r.nextRound, 1);
});

test('produto da recontagem sem leitura conta como zero', () => {
    const r = evaluateRound({
        items: [{ ...item(1, 'A', '2'), countedQty: '1', result: 'FALTA' }],
        round: 1,
        scanTotals: new Map(),
        maxRecounts: 2,
    });
    assert.equal(r.items[0].countedQty, '0');
    assert.equal(r.items[0].result, 'FALTA');
    assert.equal(r.nextStatus, 'DIVERGENTE');
});

test('extra recontado com zero deixa de divergir', () => {
    const r = evaluateRound({
        items: [
            { ...item(1, 'A', '1'), countedQty: '1', result: 'OK' },
            { seq: 100000, productErpId: 'Z', expectedQty: '0', countedQty: '2', result: 'SOBRA', isExtra: true },
        ],
        round: 1,
        scanTotals: new Map(),
        maxRecounts: 1,
    });
    assert.equal(r.allOk, true);
    assert.equal(r.items.find((i) => i.productErpId === 'Z').result, 'OK');
});
