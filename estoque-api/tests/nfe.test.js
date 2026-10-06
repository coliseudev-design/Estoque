'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
    isValidAccessKey, parseAccessKey, parseNfeXml, validGtin, buildEntry, entryCritiques, isPlaceholder,
} = require('../src/domain/nfe');
const { documentAlerts } = require('../src/domain/alerts');

const XML = fs.readFileSync(path.join(__dirname, 'fixtures', 'nfe-entrada.xml'), 'utf8');
const KEY = '50251005808085000152550010001234561000000011';

test('chave de acesso: DV válido, inválido e campos', () => {
    assert.equal(isValidAccessKey(KEY), true);
    assert.equal(isValidAccessKey(KEY.slice(0, 43) + '2'), false);
    const k = parseAccessKey(KEY);
    assert.equal(k.cnpj, '05808085000152');
    assert.equal(k.number, '123456');
    assert.equal(k.series, '1');
});

test('GTIN: aceita válido, recusa SEM GTIN e DV errado', () => {
    assert.equal(validGtin('7891000000014'), '7891000000014');
    assert.equal(validGtin('SEM GTIN'), null);
    assert.equal(validGtin('7891000000015'), null);
    assert.equal(validGtin('0000000000000'), null);
});

test('lê nfeProc: cabeçalho, emitente, protocolo, itens e lote', () => {
    const n = parseNfeXml(XML);
    assert.equal(n.key, KEY);
    assert.equal(n.number, '123456');
    assert.equal(n.supplier.name, 'DISTRIBUIDORA PET & VET LTDA');
    assert.equal(n.supplier.cnpj, '05808085000152');
    assert.equal(n.recipient.cnpj, '99999999000190');
    assert.equal(n.protocol.status, '100');
    assert.equal(n.totalValue, '620');
    assert.equal(n.items.length, 3);
    assert.equal(n.items[1].gtin, null);
    assert.equal(n.items[1].lots[0].expiresAt, '2025-11-15');
    assert.equal(n.items[2].orderNumber, 'PC-777');
});

test('XML que não é NF-e é recusado com mensagem clara', () => {
    assert.throws(() => parseNfeXml('<cte><infCte/></cte>'), /não é um XML de NF-e/);
});

test('caixa com GTIN próprio é conferida em unidades; bipar a caixa soma o fator', () => {
    const e = buildEntry(parseNfeXml(XML), {
        byBarcode: new Map([['7891000000014', { erpId: '100', factor: '1' }]]),
        products: new Map([['100', { description: 'RACAO PREMIUM 1KG', unit: 'UN' }]]),
    });
    const racao = e.items.find((i) => i.seq === 1);
    assert.equal(racao.productErpId, '100');
    assert.equal(racao.qty, '24');
    assert.equal(racao.unit, 'UN');
    assert.deepEqual(e.barcodes.filter((b) => b.productErpId === '100').map((b) => [b.barcode, b.factor]).sort(),
        [['1789100000002', '12'], ['7891000000014', '1'], ['R-500', '1']]);
    // item sem cadastro vira placeholder e é identificado pelo código do fornecedor
    const verm = e.items.find((i) => i.seq === 2);
    assert.equal(isPlaceholder(verm.productErpId), true);
    assert.ok(e.barcodes.some((b) => b.barcode === 'ABC-9' && b.productErpId === verm.productErpId));
    assert.equal(e.header.orderNumber, 'PC-777');
});

test('de-para do fornecedor tem precedência sobre o GTIN', () => {
    const e = buildEntry(parseNfeXml(XML), { bySupplierCode: new Map([['COL-7', '555']]) });
    assert.equal(e.items.find((i) => i.seq === 3).productErpId, '555');
    assert.equal(e.items.find((i) => i.seq === 3).meta.linkedBy, 'de-para');
});

test('críticas: destinatário, vínculo, sem GTIN, validade curta', () => {
    const nfe = parseNfeXml(XML);
    const e = buildEntry(nfe, { byBarcode: new Map([['7891000000014', { erpId: '100' }]]) });
    const doc = { meta: e.meta, issuedAt: e.header.issuedAt };
    const now = new Date('2025-10-05T12:00:00-04:00');

    const ok = entryCritiques(doc, e.items, { companyCnpj: '99.999.999/0001-90', now });
    assert.ok(!ok.some((c) => c.code === 'DEST_MISMATCH'));
    assert.ok(ok.some((c) => c.code === 'UNLINKED' && c.seqs.length === 2));
    assert.ok(ok.some((c) => c.code === 'NO_GTIN' && c.seqs[0] === 2));
    assert.ok(ok.some((c) => c.code === 'LOT_SHORT_EXPIRY'));
    assert.ok(!ok.some((c) => c.code === 'NO_PURCHASE_ORDER'));

    const other = entryCritiques(doc, e.items, { companyCnpj: '11111111000111', now });
    assert.equal(other[0].code, 'DEST_MISMATCH');
    assert.equal(other[0].level, 'erro');

    const expired = entryCritiques(doc, e.items, { now: new Date('2026-01-10T12:00:00Z') });
    assert.ok(expired.some((c) => c.code === 'LOT_EXPIRED' && c.level === 'erro'));
    assert.ok(expired.some((c) => c.code === 'OLD_INVOICE'));
});

test('alertas operacionais: faturado antes, SLA e conferência abandonada', () => {
    const now = new Date('2025-10-05T12:00:00Z');
    const codes = (d, o) => documentAlerts(d, { now, ...o }).map((a) => a.code);
    assert.deepEqual(codes({ status: 'EM_CONFERENCIA', invoiceNumber: '9', lock: { userName: 'x' } }), ['INVOICED_EARLY']);
    assert.deepEqual(codes({ status: 'AGUARDANDO', issuedAt: '2025-10-03T12:00:00Z' }, { slaHours: 24 }), ['SLA']);
    assert.deepEqual(codes({ status: 'AGUARDANDO', issuedAt: '2025-10-05T06:00:00Z' }, { slaHours: 24 }), []);
    assert.deepEqual(codes({ status: 'EM_CONFERENCIA', lock: null }), ['STALLED']);
    assert.deepEqual(codes({ status: 'CONCLUIDO', lock: null }, { critiques: { erro: 1, alerta: 2 } }), []);
});
