/**
 * Recebimento (notas de entrada): importação do XML da NF-e, vínculo de produtos
 * e críticas. A conferência em si usa o mesmo serviço de documentos das saídas.
 */
'use strict';

const db = require('../db');
const bus = require('../realtime/bus');
const { audit } = require('./audit');
const { getSettings } = require('./settings');
const { parseNfeXml, buildEntry, entryCritiques, isPlaceholder, isValidAccessKey } = require('../domain/nfe');
const { notFound, conflict, badRequest } = require('../http');

const critiqueOptions = (settings) => ({
    companyCnpj: settings.companyCnpj, expiryAlertDays: settings.expiryAlertDays, oldDays: settings.entryOldDays,
});
const summarize = (critiques) => ({
    erro: critiques.filter((c) => c.level === 'erro').length,
    alerta: critiques.filter((c) => c.level === 'alerta').length,
    info: critiques.filter((c) => c.level === 'info').length,
});

/** Recalcula e grava o resumo das críticas no cabeçalho (usado na lista). */
async function refreshCritiques(runner, tenantId, documentId, settings) {
    const { rows: [doc] } = await runner.query('SELECT meta, issued_at FROM documents WHERE id = $1', [documentId]);
    const { rows: items } = await runner.query(
        'SELECT seq, product_erp_id, description, unit, meta FROM document_items WHERE document_id = $1 AND NOT is_extra', [documentId]);
    const critiques = entryCritiques(
        { meta: doc.meta, issuedAt: doc.issued_at },
        items.map((i) => ({ seq: i.seq, productErpId: i.product_erp_id, description: i.description, unit: i.unit, meta: i.meta })),
        critiqueOptions(settings),
    );
    await runner.query(
        `UPDATE documents SET meta = jsonb_set(meta, '{critiques}', $2::jsonb), updated_at = now() WHERE id = $1`,
        [documentId, JSON.stringify(summarize(critiques))],
    );
    return critiques;
}

/**
 * Importa um XML de NF-e como documento de entrada.
 * `expectedKey` (opcional): chave lida no DANFE — o XML precisa ser da mesma nota.
 * `force`: importa mesmo com crítica de destinatário (nota de outra empresa).
 */
async function importNfe(tenantId, user, { xml, expectedKey, force = false }) {
    let nfe;
    try { nfe = parseNfeXml(xml); } catch (err) { throw badRequest(err.message, { code: 'INVALID_XML' }); }
    if (!isValidAccessKey(nfe.key)) throw badRequest(`Chave de acesso inválida no XML (${nfe.key})`, { code: 'INVALID_KEY' });
    if (expectedKey && expectedKey.replace(/\D/g, '') !== nfe.key) {
        throw conflict(`O XML é da NF ${nfe.number}, mas o DANFE lido é de outra nota`, 'KEY_MISMATCH');
    }

    const settings = await getSettings(tenantId);
    const own = String(settings.companyCnpj || '').replace(/\D/g, '');
    const dest = String(nfe.recipient.cnpj || '').replace(/\D/g, '');
    if (!force && own && dest && own !== dest) {
        throw conflict(`Esta NF-e foi emitida para o CNPJ ${dest}, não para esta empresa`, 'DEST_MISMATCH', { key: nfe.key, number: nfe.number });
    }
    if (own && nfe.supplier.cnpj === own) {
        throw conflict('Esta NF-e foi emitida pela própria empresa — é uma saída, não uma entrada', 'OWN_INVOICE');
    }

    const result = await db.tx(async (client) => {
        const { rows: dup } = await client.query(
            `SELECT id, status FROM documents WHERE tenant_id = $1 AND source = 'NFE' AND erp_key = $2`, [tenantId, nfe.key]);
        if (dup[0]) throw conflict(`NF ${nfe.number} já foi importada`, 'DUPLICATE', { documentId: dup[0].id, status: dup[0].status });

        // Catálogo: GTINs da nota e de-para do fornecedor.
        const gtins = [...new Set(nfe.items.flatMap((i) => [i.gtin, i.gtinTrib]).filter(Boolean))];
        const codes = [...new Set(nfe.items.map((i) => i.code).filter(Boolean))];
        const [{ rows: bc }, { rows: map }] = await Promise.all([
            client.query('SELECT barcode, erp_id, factor::text AS factor FROM product_barcodes WHERE tenant_id = $1 AND barcode = ANY($2)', [tenantId, gtins]),
            client.query(
                `SELECT supplier_code, product_erp_id FROM supplier_products
                  WHERE tenant_id = $1 AND supplier_cnpj = $2 AND supplier_code = ANY($3)`,
                [tenantId, nfe.supplier.cnpj || '', codes]),
        ]);
        const erpIds = [...new Set([...bc.map((b) => b.erp_id), ...map.map((m) => m.product_erp_id)])];
        const { rows: prods } = erpIds.length
            ? await client.query('SELECT erp_id, description, unit FROM products WHERE tenant_id = $1 AND erp_id = ANY($2)', [tenantId, erpIds])
            : { rows: [] };

        const entry = buildEntry(nfe, {
            byBarcode: new Map(bc.map((b) => [b.barcode, { erpId: b.erp_id, factor: b.factor }])),
            bySupplierCode: new Map(map.map((m) => [m.supplier_code, m.product_erp_id])),
            products: new Map(prods.map((p) => [p.erp_id, { description: p.description, unit: p.unit }])),
        });

        const h = entry.header;
        const { rows: [doc] } = await client.query(
            `INSERT INTO documents (tenant_id, source, erp_key, number, series, issued_at, customer_code, customer_name,
                                    order_number, status, meta, imported_by, imported_at, erp_hash)
             VALUES ($1, 'NFE', $2, $3, $4, $5, $6, $7, $8, 'AGUARDANDO', $9, $10, now(), $2)
             RETURNING id`,
            [tenantId, h.erpKey, h.number, h.series, h.issuedAt, h.customerCode, h.customerName, h.orderNumber,
                JSON.stringify(entry.meta), user.id],
        );
        await client.query(
            `INSERT INTO document_items (document_id, seq, tenant_id, product_erp_id, description, unit, expected_qty, meta)
             SELECT $1, i.seq, $2, i."productErpId", i.description, i.unit, i.qty, i.meta
               FROM jsonb_to_recordset($3::jsonb) AS i(seq int, "productErpId" text, description text, unit text, qty numeric, meta jsonb)`,
            [doc.id, tenantId, JSON.stringify(entry.items)],
        );
        if (entry.barcodes.length) {
            await client.query(
                `INSERT INTO document_barcodes (document_id, barcode, product_erp_id, factor)
                 SELECT $1, b.barcode, b."productErpId", b.factor
                   FROM jsonb_to_recordset($2::jsonb) AS b(barcode text, "productErpId" text, factor numeric)`,
                [doc.id, JSON.stringify(entry.barcodes)],
            );
        }
        const critiques = await refreshCritiques(client, tenantId, doc.id, settings);
        await audit(client, { tenantId, documentId: doc.id, userId: user.id, action: 'entry.imported',
            details: { key: nfe.key, number: nfe.number, supplier: nfe.supplier.cnpj, items: entry.items.length } });
        return { documentId: doc.id, number: nfe.number, supplier: h.customerName, items: entry.items.length,
            unlinked: entry.items.filter((i) => isPlaceholder(i.productErpId)).length, critiques };
    });
    bus.publish(tenantId, 'documents.synced', { count: 1 });
    return result;
}

/**
 * Vincula um item da nota a um produto do cadastro e aprende o de-para do fornecedor.
 * Leituras já feitas para o item acompanham o vínculo (mesmo produto físico).
 */
async function linkItem(tenantId, user, documentId, seq, productErpId) {
    const settings = await getSettings(tenantId);
    const result = await db.tx(async (client) => {
        const { rows: [doc] } = await client.query(
            `SELECT id, source, status, customer_code FROM documents WHERE tenant_id = $1 AND id = $2 FOR UPDATE`, [tenantId, documentId]);
        if (!doc) throw notFound('Documento não encontrado');
        if (doc.source !== 'NFE') throw badRequest('Vínculo de produto só existe em notas de entrada');
        if (['CONCLUIDO', 'CANCELADO'].includes(doc.status)) throw conflict(`Nota está ${doc.status}`, 'INVALID_STATUS');

        const { rows: [item] } = await client.query(
            'SELECT product_erp_id, meta FROM document_items WHERE document_id = $1 AND seq = $2', [documentId, seq]);
        if (!item) throw notFound('Item não encontrado');
        const { rows: [prod] } = await client.query(
            'SELECT erp_id, description, unit FROM products WHERE tenant_id = $1 AND erp_id = $2', [tenantId, productErpId]);
        if (!prod) throw notFound('Produto não encontrado no cadastro');

        const from = item.product_erp_id;
        // Todas as linhas do mesmo código do fornecedor seguem juntas.
        await client.query(
            `UPDATE document_items
                SET product_erp_id = $3,
                    meta = meta || jsonb_build_object('linkedBy', 'manual', 'catalogUnit', $4::text, 'catalogDescription', $5::text)
              WHERE document_id = $1 AND product_erp_id = $2`,
            [documentId, from, prod.erp_id, prod.unit, prod.description],
        );
        await client.query('UPDATE document_barcodes SET product_erp_id = $3 WHERE document_id = $1 AND product_erp_id = $2', [documentId, from, prod.erp_id]);
        await client.query('UPDATE scan_events SET product_erp_id = $3 WHERE document_id = $1 AND product_erp_id = $2', [documentId, from, prod.erp_id]);

        if (doc.customer_code && item.meta?.supplierCode) {
            await client.query(
                `INSERT INTO supplier_products (tenant_id, supplier_cnpj, supplier_code, product_erp_id, updated_by)
                 VALUES ($1, $2, $3, $4, $5)
                 ON CONFLICT (tenant_id, supplier_cnpj, supplier_code)
                 DO UPDATE SET product_erp_id = EXCLUDED.product_erp_id, updated_by = EXCLUDED.updated_by, updated_at = now()`,
                [tenantId, doc.customer_code, item.meta.supplierCode, prod.erp_id, user.id],
            );
        }
        await refreshCritiques(client, tenantId, documentId, settings);
        await audit(client, { tenantId, documentId, userId: user.id, action: 'entry.item_linked',
            details: { seq, from, to: prod.erp_id, supplierCode: item.meta?.supplierCode } });
        return { productErpId: prod.erp_id, description: prod.description };
    });
    bus.publish(tenantId, 'document.updated', { documentId });
    return result;
}

/** Exclui uma importação que ainda não começou a ser conferida (XML errado, nota recusada). */
async function deleteEntry(tenantId, user, documentId) {
    await db.tx(async (client) => {
        const { rows: [doc] } = await client.query(
            'SELECT id, source, number, erp_key, status FROM documents WHERE tenant_id = $1 AND id = $2 FOR UPDATE', [tenantId, documentId]);
        if (!doc) throw notFound('Documento não encontrado');
        if (doc.source !== 'NFE') throw badRequest('Só notas de entrada importadas podem ser excluídas');
        const { rows } = await client.query('SELECT 1 FROM scan_events WHERE document_id = $1 AND NOT voided LIMIT 1', [documentId]);
        if (rows.length || !['AGUARDANDO', 'CANCELADO'].includes(doc.status)) {
            throw conflict('A conferência já começou. Zere a conferência antes de excluir a nota.', 'IN_PROGRESS');
        }
        await client.query('DELETE FROM documents WHERE id = $1', [documentId]);
        await audit(client, { tenantId, documentId, userId: user.id, action: 'entry.deleted', details: { number: doc.number, key: doc.erp_key } });
    });
    bus.publish(tenantId, 'documents.synced', { count: 1 });
}

/** Críticas atuais de uma nota de entrada (calculadas na hora — validade depende do dia). */
async function critiquesFor(tenantId, doc, items) {
    const settings = await getSettings(tenantId);
    return entryCritiques({ meta: doc.meta, issuedAt: doc.issuedAt }, items, critiqueOptions(settings));
}

module.exports = { importNfe, linkItem, deleteEntry, critiquesFor };
