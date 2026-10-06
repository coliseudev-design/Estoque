/**
 * NF-e de entrada — leitura do XML, chave de acesso e críticas do recebimento.
 * Funções puras, sem banco, testadas em tests/nfe.test.js.
 *
 * O XML da NF-e é regular (sem atributos relevantes além de Id/nItem, sem CDATA),
 * então um extrator de tags basta e evita dependência de parser.
 */
'use strict';

const { toUnits, fromUnits } = require('./conference');

// ─────────────────────────────────────────────────────────────────────────────
// Chave de acesso
// ─────────────────────────────────────────────────────────────────────────────

/** Dígito verificador da chave (módulo 11, pesos 2..9 da direita para a esquerda). */
function accessKeyDv(first43) {
    let sum = 0;
    let weight = 2;
    for (let i = first43.length - 1; i >= 0; i--) {
        sum += Number(first43[i]) * weight;
        weight = weight === 9 ? 2 : weight + 1;
    }
    const rest = sum % 11;
    return rest < 2 ? 0 : 11 - rest;
}

function isValidAccessKey(key) {
    const k = String(key || '').replace(/\D/g, '');
    return k.length === 44 && accessKeyDv(k.slice(0, 43)) === Number(k[43]);
}

/** cUF(2) AAMM(4) CNPJ(14) modelo(2) série(3) nNF(9) tpEmis(1) cNF(8) DV(1) */
function parseAccessKey(key) {
    const k = String(key || '').replace(/\D/g, '');
    if (k.length !== 44) return null;
    return {
        key: k,
        uf: k.slice(0, 2),
        yearMonth: `20${k.slice(2, 4)}-${k.slice(4, 6)}`,
        cnpj: k.slice(6, 20),
        model: k.slice(20, 22),
        series: String(Number(k.slice(22, 25))),
        number: String(Number(k.slice(25, 34))),
        valid: isValidAccessKey(k),
    };
}

const formatAccessKey = (k) => String(k || '').replace(/\D/g, '').replace(/(\d{4})(?=\d)/g, '$1 ');

// ─────────────────────────────────────────────────────────────────────────────
// Extração do XML
// ─────────────────────────────────────────────────────────────────────────────

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const decode = (s) => s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : Number(e.slice(1)));
    return ENTITIES[e] ?? m;
});

const tagRe = (name, flags = '') => new RegExp(`<(?:[\\w-]+:)?${name}(\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w-]+:)?${name}>`, flags);

/** Conteúdo da primeira ocorrência de <name> (o texto bruto, com tags internas). */
function block(xml, name) {
    const m = xml && xml.match(tagRe(name));
    return m ? m[2] : null;
}
/** Todas as ocorrências de <name>, com os atributos. */
function blocks(xml, name) {
    if (!xml) return [];
    return [...xml.matchAll(tagRe(name, 'g'))].map((m) => ({ attrs: m[1] || '', body: m[2] }));
}
/** Texto de uma tag simples, decodificado e sem espaços nas pontas. */
function text(xml, name) {
    const b = block(xml, name);
    return b === null ? null : decode(b.replace(/<[^>]+>/g, '')).trim() || null;
}
const attr = (attrs, name) => (attrs.match(new RegExp(`${name}="([^"]*)"`)) || [])[1] || null;

/** GTIN válido (8/12/13/14 dígitos, DV correto). "SEM GTIN" e lixo viram null. */
function validGtin(raw) {
    const g = String(raw || '').trim();
    if (!/^\d{8}$|^\d{12,14}$/.test(g) || /^0+$/.test(g)) return null;
    const digits = g.split('').map(Number);
    const dv = digits.pop();
    const sum = digits.reverse().reduce((acc, d, i) => acc + d * (i % 2 === 0 ? 3 : 1), 0);
    return (10 - (sum % 10)) % 10 === dv ? g : null;
}

const num = (s) => (s == null || s === '' ? null : String(Number(String(s).replace(',', '.'))));

/**
 * Lê o XML da NF-e (nfeProc ou NFe sozinha).
 * Lança Error com mensagem amigável quando não é uma NF-e.
 */
function parseNfeXml(xml) {
    const src = String(xml || '');
    const inf = blocks(src, 'infNFe')[0];
    if (!inf) throw new Error('O arquivo não é um XML de NF-e (tag infNFe não encontrada)');

    const idKey = (attr(inf.attrs, 'Id') || '').replace(/\D/g, '');
    const prot = block(src, 'infProt');
    const key = text(prot, 'chNFe') || idKey;
    if (!key || key.length !== 44) throw new Error('Chave de acesso não encontrada no XML');

    const ide = block(inf.body, 'ide');
    const emit = block(inf.body, 'emit');
    const dest = block(inf.body, 'dest');
    const tot = block(inf.body, 'ICMSTot');
    const compra = block(inf.body, 'compra');

    const items = blocks(inf.body, 'det').map((det) => {
        const prod = block(det.body, 'prod');
        const lots = blocks(prod, 'rastro').map((r) => ({
            lot: text(r.body, 'nLote'), qty: num(text(r.body, 'qLote')),
            madeAt: text(r.body, 'dFab'), expiresAt: text(r.body, 'dVal'),
        }));
        // Medicamentos (layout antigo) trazem lote em <med>.
        for (const m of blocks(prod, 'med')) {
            if (text(m.body, 'nLote')) {
                lots.push({ lot: text(m.body, 'nLote'), qty: num(text(m.body, 'qLote')),
                    madeAt: text(m.body, 'dFab'), expiresAt: text(m.body, 'dVal') });
            }
        }
        return {
            seq: Number(attr(det.attrs, 'nItem')),
            code: text(prod, 'cProd'),
            gtin: validGtin(text(prod, 'cEAN')),
            gtinTrib: validGtin(text(prod, 'cEANTrib')),
            description: text(prod, 'xProd') || '',
            ncm: text(prod, 'NCM'),
            cfop: text(prod, 'CFOP'),
            unit: text(prod, 'uCom'),
            qty: num(text(prod, 'qCom')) || '0',
            unitTrib: text(prod, 'uTrib'),
            qtyTrib: num(text(prod, 'qTrib')),
            unitPrice: num(text(prod, 'vUnCom')),
            total: num(text(prod, 'vProd')),
            orderNumber: text(prod, 'xPed'),
            orderItem: text(prod, 'nItemPed'),
            lots,
        };
    });
    if (!items.length) throw new Error('A NF-e não tem itens (tag det)');

    return {
        key,
        keyFromId: idKey || null,
        number: text(ide, 'nNF'),
        series: text(ide, 'serie'),
        model: text(ide, 'mod'),
        issuedAt: text(ide, 'dhEmi') || (text(ide, 'dEmi') ? `${text(ide, 'dEmi')}T00:00:00-03:00` : null),
        operation: text(ide, 'natOp'),
        type: text(ide, 'tpNF'), // 0 entrada, 1 saída (do ponto de vista do emitente)
        environment: text(ide, 'tpAmb'), // 1 produção, 2 homologação
        supplier: {
            cnpj: text(emit, 'CNPJ') || text(emit, 'CPF'),
            name: text(emit, 'xNome'),
            tradeName: text(emit, 'xFant'),
            uf: text(block(emit, 'enderEmit'), 'UF'),
        },
        recipient: { cnpj: text(dest, 'CNPJ') || text(dest, 'CPF'), name: text(dest, 'xNome') },
        totalValue: num(text(tot, 'vNF')),
        productsValue: num(text(tot, 'vProd')),
        orderNumber: text(compra, 'xPed'),
        protocol: prot ? { status: text(prot, 'cStat'), reason: text(prot, 'xMotivo'), number: text(prot, 'nProt'), at: text(prot, 'dhRecbto') } : null,
        items,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Montagem do documento de conferência
// ─────────────────────────────────────────────────────────────────────────────

const PLACEHOLDER_PREFIX = 'NFE:';
const isPlaceholder = (productErpId) => String(productErpId || '').startsWith(PLACEHOLDER_PREFIX);

/**
 * Decide em que unidade o item é conferido e quais códigos valem.
 *
 * Caixa com GTIN próprio (cEAN) e unidade com outro GTIN (cEANTrib), com fator inteiro
 * (qTrib ÷ qCom): confere em UNIDADES — bipar a unidade soma 1, bipar a caixa soma o fator.
 * Caso contrário confere na unidade comercial da nota (qCom/uCom).
 */
function countingPlan(item) {
    const qCom = toUnits(item.qty);
    const qTrib = item.qtyTrib ? toUnits(item.qtyTrib) : 0;
    const factor = qCom > 0 && qTrib > 0 && qTrib % qCom === 0 ? qTrib / qCom : 0;
    const codes = [];
    if (item.gtinTrib && item.gtin && item.gtinTrib !== item.gtin && Number.isInteger(factor) && factor > 1) {
        codes.push({ barcode: item.gtinTrib, factor: '1' }, { barcode: item.gtin, factor: String(factor) });
        return { expectedQty: fromUnits(qTrib), unit: item.unitTrib || item.unit, codes, packFactor: factor };
    }
    if (item.gtin) codes.push({ barcode: item.gtin, factor: '1' });
    if (item.gtinTrib && item.gtinTrib !== item.gtin && factor === 1) codes.push({ barcode: item.gtinTrib, factor: '1' });
    return { expectedQty: fromUnits(qCom), unit: item.unit, codes, packFactor: 1 };
}

/**
 * Transforma a NF-e lida em documento + itens + códigos.
 *
 * @param {object} nfe            resultado de parseNfeXml
 * @param {object} catalog
 * @param {Map<string,{erpId:string,factor:string}>} catalog.byBarcode  GTIN → produto do ERP
 * @param {Map<string,string>} catalog.bySupplierCode  código do fornecedor → produto (de-para)
 * @param {Map<string,{description:string,unit:string}>} [catalog.products]
 */
function buildEntry(nfe, { byBarcode = new Map(), bySupplierCode = new Map(), products = new Map() } = {}) {
    const items = [];
    const barcodes = new Map();
    for (const it of nfe.items) {
        const plan = countingPlan(it);
        const viaMap = it.code ? bySupplierCode.get(it.code) : null;
        const viaGtin = [it.gtin, it.gtinTrib].map((g) => g && byBarcode.get(g)).find(Boolean);
        const productErpId = viaMap || viaGtin?.erpId || `${PLACEHOLDER_PREFIX}${it.code || it.seq}`;
        const linkedBy = viaMap ? 'de-para' : viaGtin ? 'gtin' : null;

        items.push({
            seq: it.seq,
            productErpId,
            description: it.description,
            unit: plan.unit,
            qty: plan.expectedQty,
            meta: {
                supplierCode: it.code, gtin: it.gtin, gtinTrib: it.gtinTrib,
                supplierUnit: it.unit, supplierQty: it.qty, packFactor: plan.packFactor,
                ncm: it.ncm, cfop: it.cfop, unitPrice: it.unitPrice, total: it.total,
                orderNumber: it.orderNumber, orderItem: it.orderItem, lots: it.lots,
                linkedBy, catalogUnit: products.get(productErpId)?.unit || null,
                catalogDescription: products.get(productErpId)?.description || null,
            },
        });
        for (const c of plan.codes) if (!barcodes.has(c.barcode)) barcodes.set(c.barcode, { productErpId, factor: c.factor });
        // Código do fornecedor digitado no teclado também identifica o item da nota.
        if (it.code && !barcodes.has(it.code)) barcodes.set(it.code, { productErpId, factor: '1' });
    }
    const orderNumbers = [...new Set([nfe.orderNumber, ...nfe.items.map((i) => i.orderNumber)].filter(Boolean))];
    return {
        header: {
            source: 'NFE',
            erpKey: nfe.key,
            number: nfe.number,
            series: nfe.series,
            issuedAt: nfe.issuedAt,
            customerCode: nfe.supplier.cnpj,
            customerName: nfe.supplier.tradeName || nfe.supplier.name,
            orderNumber: orderNumbers.join(', ') || null,
        },
        meta: {
            supplier: nfe.supplier, recipient: nfe.recipient, operation: nfe.operation,
            totalValue: nfe.totalValue, productsValue: nfe.productsValue, model: nfe.model,
            environment: nfe.environment, protocol: nfe.protocol, orderNumbers,
        },
        items,
        barcodes: [...barcodes].map(([barcode, b]) => ({ barcode, ...b })),
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Críticas
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Críticas do recebimento: o que o supervisor precisa saber ANTES de liberar a conferência.
 *   erro    impede o recebimento correto (nota de outra empresa, lote vencido…)
 *   alerta  exige ação (vincular produto, conferir sem código de barras…)
 *   info    contexto (sem pedido de compra, unidade diferente do cadastro…)
 *
 * @param {object} doc    { meta, issuedAt }
 * @param {Array}  items  [{ seq, productErpId, description, meta }]
 * @param {object} opts   { companyCnpj, expiryAlertDays, oldDays, now }
 */
function entryCritiques(doc, items, { companyCnpj = '', expiryAlertDays = 90, oldDays = 30, now = new Date() } = {}) {
    const out = [];
    const add = (level, code, message, extra = {}) => out.push({ level, code, message, ...extra });
    const meta = doc.meta || {};
    const day = 86_400_000;

    const ownCnpj = String(companyCnpj || '').replace(/\D/g, '');
    const destCnpj = String(meta.recipient?.cnpj || '').replace(/\D/g, '');
    if (ownCnpj && destCnpj && ownCnpj !== destCnpj) {
        add('erro', 'DEST_MISMATCH', `Nota destinada a outro CNPJ (${destCnpj}), não a esta empresa`);
    }
    if (!meta.protocol) add('alerta', 'NO_PROTOCOL', 'XML sem protocolo de autorização da SEFAZ — confirme a autenticidade no portal da NF-e');
    else if (!['100', '150'].includes(meta.protocol.status)) {
        add('erro', 'NOT_AUTHORIZED', `NF-e não autorizada na SEFAZ (${meta.protocol.status} — ${meta.protocol.reason || 'sem motivo'})`);
    }
    if (meta.environment === '2') add('erro', 'HOMOLOGATION', 'NF-e emitida em homologação (sem valor fiscal)');
    if (doc.issuedAt && now - new Date(doc.issuedAt) > oldDays * day) {
        add('alerta', 'OLD_INVOICE', `Emitida há ${Math.floor((now - new Date(doc.issuedAt)) / day)} dias — verifique se já não foi recebida`);
    }
    if (!meta.orderNumbers?.length) add('info', 'NO_PURCHASE_ORDER', 'A nota não referencia pedido de compra (xPed)');

    const unlinked = items.filter((i) => isPlaceholder(i.productErpId));
    if (unlinked.length) {
        add('alerta', 'UNLINKED', `${unlinked.length} item(ns) sem vínculo com o cadastro — vincule para dar entrada no estoque`,
            { seqs: unlinked.map((i) => i.seq) });
    }
    const noGtin = items.filter((i) => !i.meta?.gtin && !i.meta?.gtinTrib);
    if (noGtin.length) {
        add('alerta', 'NO_GTIN', `${noGtin.length} item(ns) sem código de barras na nota — o conferente digita o código do produto`,
            { seqs: noGtin.map((i) => i.seq) });
    }
    for (const i of items) {
        const m = i.meta || {};
        if (m.catalogUnit && i.unit && m.catalogUnit.toUpperCase() !== String(i.unit).toUpperCase()) {
            add('info', 'UNIT_DIFF', `Item ${i.seq}: unidade da nota (${i.unit}) diferente do cadastro (${m.catalogUnit})`, { seqs: [i.seq] });
        }
        for (const lot of m.lots || []) {
            if (!lot.expiresAt) continue;
            const left = Math.floor((new Date(`${lot.expiresAt}T23:59:59`) - now) / day);
            if (left < 0) add('erro', 'LOT_EXPIRED', `Item ${i.seq}: lote ${lot.lot || '?'} vencido em ${lot.expiresAt}`, { seqs: [i.seq] });
            else if (left <= expiryAlertDays) {
                add('alerta', 'LOT_SHORT_EXPIRY', `Item ${i.seq}: lote ${lot.lot || '?'} vence em ${left} dia(s) (${lot.expiresAt})`, { seqs: [i.seq] });
            }
        }
    }
    const order = { erro: 0, alerta: 1, info: 2 };
    return out.sort((a, b) => order[a.level] - order[b.level]);
}

module.exports = {
    accessKeyDv, isValidAccessKey, parseAccessKey, formatAccessKey,
    parseNfeXml, validGtin, countingPlan, buildEntry, entryCritiques,
    isPlaceholder, PLACEHOLDER_PREFIX,
};
