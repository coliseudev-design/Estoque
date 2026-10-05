/**
 * Regras da conferência cega — funções puras, sem banco, testadas em tests/.
 *
 * Princípios:
 *  1. O operador nunca vê a quantidade esperada. Ele conta; o servidor compara.
 *  2. A comparação é por PRODUTO, não por linha: uma nota pode repetir o mesmo
 *     produto em duas linhas, e o operador não tem como saber disso.
 *  3. Recontagem é só do que divergiu. O que bateu na rodada anterior fica travado.
 *  4. Produto bipado que não está no documento vira item "extra" (SOBRA).
 *  5. Esgotadas as recontagens, a divergência vai para aprovação do supervisor.
 *
 * Quantidades trafegam como string decimal (NUMERIC do Postgres) e são
 * convertidas para inteiros escalados (×10.000) — nada de float em contagem.
 */
'use strict';

const SCALE = 10_000;
const EXTRA_SEQ_BASE = 100_000;

/** "12.5000" | 12.5 → 125000 */
function toUnits(value) {
    if (value === null || value === undefined || value === '') return 0;
    const [int, frac = ''] = String(value).trim().split('.');
    const negative = int.startsWith('-');
    const whole = Math.abs(parseInt(int, 10) || 0);
    const fraction = parseInt((frac + '0000').slice(0, 4), 10) || 0;
    const units = whole * SCALE + fraction;
    return negative ? -units : units;
}

/** 125000 → "12.5" */
function fromUnits(units) {
    const negative = units < 0;
    const abs = Math.abs(units);
    const whole = Math.floor(abs / SCALE);
    const frac = String(abs % SCALE).padStart(4, '0').replace(/0+$/, '');
    return `${negative ? '-' : ''}${whole}${frac ? '.' + frac : ''}`;
}

const resultFor = (counted, expected) => (counted === expected ? 'OK' : counted < expected ? 'FALTA' : 'SOBRA');

/**
 * Avalia o fechamento de uma rodada de contagem.
 *
 * @param {object} input
 * @param {Array<{seq:number, productErpId:string, description?:string, unit?:string,
 *                expectedQty:string|number, countedQty?:string|number|null,
 *                result?:string, isExtra?:boolean}>} input.items  linhas atuais do documento
 * @param {number} input.round            rodada sendo fechada (0 = contagem inicial)
 * @param {Map<string, string|number>} input.scanTotals  produto → soma das leituras válidas da rodada
 * @param {Map<string, {description?:string, unit?:string}>} [input.productInfo] para nomear itens extras
 * @param {number} input.maxRecounts      quantas recontagens antes de exigir supervisor
 *
 * @returns {{
 *   items: Array<object>,            linhas atualizadas (inclui extras novas)
 *   divergentProducts: string[],     produtos que precisam de recontagem/aprovação
 *   ignoredProducts: string[],       bipados na recontagem mas já conferidos OK
 *   allOk: boolean,
 *   nextStatus: 'CONCLUIDO'|'DIVERGENTE'|'AGUARDANDO_APROVACAO',
 *   nextRound: number,
 * }}
 */
function evaluateRound({ items, round, scanTotals, productInfo = new Map(), maxRecounts }) {
    // Agrupa linhas por produto, preservando a ordem de sequência.
    const byProduct = new Map();
    for (const item of [...items].sort((a, b) => a.seq - b.seq)) {
        if (!byProduct.has(item.productErpId)) byProduct.set(item.productErpId, []);
        byProduct.get(item.productErpId).push(item);
    }

    // Na contagem inicial tudo é contado; nas recontagens, só o que não bateu.
    const inScope = (lines) => round === 0 || lines.some((l) => l.result !== 'OK');

    const updated = [];
    const divergent = [];
    const ignored = [];

    for (const [productId, lines] of byProduct) {
        if (!inScope(lines)) {
            updated.push(...lines.map((l) => ({ ...l })));
            if (scanTotals.has(productId) && toUnits(scanTotals.get(productId)) !== 0) ignored.push(productId);
            continue;
        }

        const expected = lines.reduce((sum, l) => sum + toUnits(l.expectedQty), 0);
        let remaining = toUnits(scanTotals.get(productId) ?? 0);
        const totalCounted = remaining;
        const result = resultFor(totalCounted, expected);
        if (result !== 'OK') divergent.push(productId);

        // Distribui o contado pelas linhas na ordem; o excedente fica na última.
        lines.forEach((line, idx) => {
            const lineExpected = toUnits(line.expectedQty);
            const isLast = idx === lines.length - 1;
            const take = isLast ? remaining : Math.min(Math.max(remaining, 0), lineExpected);
            remaining -= take;
            updated.push({ ...line, countedQty: fromUnits(take), result, countedRound: round });
        });
    }

    // Produtos bipados que não existem no documento → linhas extras (SOBRA).
    let nextExtraSeq = Math.max(EXTRA_SEQ_BASE - 1, ...items.map((i) => i.seq)) + 1;
    for (const [productId, qty] of scanTotals) {
        if (byProduct.has(productId)) continue;
        const counted = toUnits(qty);
        if (counted === 0) continue;
        const info = productInfo.get(productId) || {};
        updated.push({
            seq: nextExtraSeq++,
            productErpId: productId,
            description: info.description || '',
            unit: info.unit || null,
            expectedQty: '0',
            countedQty: fromUnits(counted),
            result: resultFor(counted, 0),
            isExtra: true,
            countedRound: round,
        });
        divergent.push(productId);
    }

    const allOk = divergent.length === 0;
    let nextStatus;
    let nextRound = round;
    if (allOk) nextStatus = 'CONCLUIDO';
    else if (round < maxRecounts) { nextStatus = 'DIVERGENTE'; nextRound = round + 1; }
    else nextStatus = 'AGUARDANDO_APROVACAO';

    return { items: updated, divergentProducts: divergent, ignoredProducts: ignored, allOk, nextStatus, nextRound };
}

/**
 * Produtos que o operador deve recontar na rodada atual.
 * Rodada 0 → conjunto vazio (tudo é contado). Rodadas seguintes → tudo que não está OK,
 * inclusive o que o supervisor reabriu (marcado como PENDENTE).
 */
function productsToRecount(items, round) {
    const set = new Set();
    if (round === 0) return set;
    for (const i of items) if (i.result !== 'OK') set.add(i.productErpId);
    return set;
}

/**
 * Remove dados sensíveis para o operador (conferência cega).
 * Mantém: produto, descrição, unidade, o que ELE contou e se precisa recontar.
 */
function blindItem(item, { recount }) {
    return {
        seq: item.seq,
        productErpId: item.productErpId,
        description: item.description,
        unit: item.unit,
        isExtra: item.isExtra,
        mustRecount: recount.has(item.productErpId),
    };
}

module.exports = { evaluateRound, productsToRecount, blindItem, toUnits, fromUnits, resultFor, EXTRA_SEQ_BASE };
