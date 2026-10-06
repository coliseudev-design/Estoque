/**
 * Sincronismo com o Worker (ERP → nuvem e nuvem → ERP).
 *
 * Cargas em lote com um único comando SQL por lote (jsonb_to_recordset), e
 * ON CONFLICT ... WHERE IS DISTINCT FROM para não reescrever linha que não mudou
 * (sem bloat de MVCC e sem disparar updated_at à toa — o app baixa catálogo por delta).
 */
'use strict';

const crypto = require('node:crypto');
const db = require('../db');
const bus = require('../realtime/bus');
const { audit } = require('./audit');

async function touchSyncState(runner, tenantId, entity, rows) {
    await runner.query(
        `INSERT INTO sync_state (tenant_id, entity, last_at, rows) VALUES ($1, $2, now(), $3)
         ON CONFLICT (tenant_id, entity) DO UPDATE SET last_at = now(), rows = EXCLUDED.rows`,
        [tenantId, entity, rows],
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Produtos e códigos de barras
// ─────────────────────────────────────────────────────────────────────────────

async function upsertProducts(tenantId, rows) {
    return db.tx(async (client) => {
        const { rowCount } = await client.query(
            `INSERT INTO products AS p (tenant_id, erp_id, sku, description, unit, brand, group_name, stock, active, updated_at)
             SELECT $1, r."erpId", r.sku, COALESCE(r.description, ''), r.unit, r.brand, r."group",
                    COALESCE(r.stock, 0), COALESCE(r.active, TRUE), now()
               FROM jsonb_to_recordset($2::jsonb) AS r("erpId" text, sku text, description text, unit text,
                    brand text, "group" text, stock numeric, active boolean)
             ON CONFLICT (tenant_id, erp_id) DO UPDATE
                SET sku = EXCLUDED.sku, description = EXCLUDED.description, unit = EXCLUDED.unit,
                    brand = EXCLUDED.brand, group_name = EXCLUDED.group_name, stock = EXCLUDED.stock,
                    active = EXCLUDED.active, updated_at = now()
              WHERE (p.sku, p.description, p.unit, p.brand, p.group_name, p.stock, p.active)
                    IS DISTINCT FROM
                    (EXCLUDED.sku, EXCLUDED.description, EXCLUDED.unit, EXCLUDED.brand,
                     EXCLUDED.group_name, EXCLUDED.stock, EXCLUDED.active)`,
            [tenantId, JSON.stringify(rows)],
        );

        // Códigos: só mexe nos produtos que vieram com a lista `barcodes` preenchida.
        const withCodes = rows.filter((r) => Array.isArray(r.barcodes));
        if (withCodes.length) {
            const pairs = withCodes.flatMap((r) => r.barcodes
                .filter((b) => b?.barcode && String(b.barcode).trim())
                .map((b) => ({ erpId: r.erpId, barcode: String(b.barcode).trim(), factor: b.factor > 0 ? b.factor : 1 })));

            await client.query(
                `DELETE FROM product_barcodes b
                  WHERE b.tenant_id = $1 AND b.erp_id = ANY($2)
                    AND NOT EXISTS (SELECT 1 FROM jsonb_to_recordset($3::jsonb) AS n("erpId" text, barcode text)
                                     WHERE n.barcode = b.barcode AND n."erpId" = b.erp_id)`,
                [tenantId, withCodes.map((r) => r.erpId), JSON.stringify(pairs)],
            );
            if (pairs.length) {
                await client.query(
                    `INSERT INTO product_barcodes AS b (tenant_id, barcode, erp_id, factor, updated_at)
                     SELECT DISTINCT ON (n.barcode) $1, n.barcode, n."erpId", n.factor, now()
                       FROM jsonb_to_recordset($2::jsonb) AS n("erpId" text, barcode text, factor numeric)
                     ON CONFLICT (tenant_id, barcode) DO UPDATE
                        SET erp_id = EXCLUDED.erp_id, factor = EXCLUDED.factor, updated_at = now()
                      WHERE (b.erp_id, b.factor) IS DISTINCT FROM (EXCLUDED.erp_id, EXCLUDED.factor)`,
                    [tenantId, JSON.stringify(pairs)],
                );
            }
        }
        await touchSyncState(client, tenantId, 'produtos', rows.length);
        return { aplicados: rowCount };
    });
}

async function upsertStock(tenantId, rows) {
    const { rowCount } = await db.query(
        `UPDATE products p SET stock = r.stock, updated_at = now()
           FROM jsonb_to_recordset($2::jsonb) AS r("erpId" text, stock numeric)
          WHERE p.tenant_id = $1 AND p.erp_id = r."erpId" AND p.stock IS DISTINCT FROM r.stock`,
        [tenantId, JSON.stringify(rows)],
    );
    await touchSyncState(db, tenantId, 'saldos', rows.length);
    return { aplicados: rowCount };
}

// ─────────────────────────────────────────────────────────────────────────────
// Documentos
// ─────────────────────────────────────────────────────────────────────────────

/** Hash do conteúdo conferível: itens + cancelamento. Cabeçalho (nome do cliente etc.) não conta. */
function documentHash(doc) {
    const items = [...doc.items]
        .sort((a, b) => a.seq - b.seq)
        .map((i) => `${i.seq}|${i.productErpId}|${Number(i.qty)}`)
        .join(';');
    return crypto.createHash('sha1').update(`${doc.cancelled ? 1 : 0}#${items}`).digest('hex');
}

async function insertItems(client, tenantId, documentId, items) {
    if (!items.length) return;
    await client.query(
        `INSERT INTO document_items (document_id, seq, tenant_id, product_erp_id, description, unit, expected_qty)
         SELECT $1, i.seq, $2, i."productErpId", COALESCE(i.description, ''), i.unit, i.qty
           FROM jsonb_to_recordset($3::jsonb) AS i(seq int, "productErpId" text, description text, unit text, qty numeric)`,
        [documentId, tenantId, JSON.stringify(items)],
    );
}

/**
 * Regras quando o ERP altera um documento já recebido:
 *  - AGUARDANDO / EM_CONFERENCIA na rodada 0: itens são substituídos. É seguro — as
 *    leituras ficam em scan_events e só são comparadas na finalização.
 *  - Recontagem, aprovação ou concluído: NÃO mexe. Marca erp_changed e registra na
 *    auditoria; o supervisor decide (zerar a conferência ou aprovar como está).
 *  - Cancelado no ERP: sai da fila (CANCELADO), exceto se já concluído — aí só sinaliza.
 */
async function upsertDocuments(tenantId, docs) {
    let created = 0, updated = 0, flagged = 0;
    const touched = [];

    await db.tx(async (client) => {
        const { rows: existingRows } = await client.query(
            `SELECT id, source, erp_key, status, round, erp_hash, erp_cancelled, invoice_number
               FROM documents
              WHERE tenant_id = $1 AND (source, erp_key) IN (SELECT * FROM unnest($2::text[], $3::text[]))
              FOR UPDATE`,
            [tenantId, docs.map((d) => d.source), docs.map((d) => d.erpKey)],
        );
        const existing = new Map(existingRows.map((r) => [`${r.source}|${r.erp_key}`, r]));

        for (const doc of docs) {
            const hash = documentHash(doc);
            const header = [doc.number ?? null, doc.series ?? null, doc.movementType ?? null, doc.issuedAt ?? null,
                doc.customerCode ?? null, doc.customerName ?? null, doc.sellerName ?? null, doc.branchCode ?? null,
                doc.invoiceNumber ?? null, doc.orderNumber ?? null];
            const current = existing.get(`${doc.source}|${doc.erpKey}`);

            if (!current) {
                const { rows } = await client.query(
                    `INSERT INTO documents (tenant_id, source, erp_key, number, series, movement_type, issued_at,
                                            customer_code, customer_name, seller_name, branch_code,
                                            invoice_number, order_number, invoiced_at,
                                            status, erp_hash, erp_cancelled)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                             CASE WHEN $12::text IS NULL THEN NULL ELSE now() END, $14, $15, $16)
                     RETURNING id`,
                    [tenantId, doc.source, doc.erpKey, ...header,
                        doc.cancelled ? 'CANCELADO' : (doc.status || (doc.invoiceNumber ? 'CONCLUIDO' : 'AGUARDANDO')), hash, !!doc.cancelled],
                );
                await insertItems(client, tenantId, rows[0].id, doc.items);
                created++;
                touched.push(rows[0].id);
                continue;
            }

            // Cabeçalho sempre atualiza (nome do cliente corrigido no ERP etc.).
            await client.query(
                `UPDATE documents SET number = $3, series = $4, movement_type = $5, issued_at = $6,
                        customer_code = $7, customer_name = $8, seller_name = $9, branch_code = $10,
                        invoice_number = $11, order_number = $12,
                        invoiced_at = CASE WHEN $11::text IS NULL THEN NULL ELSE COALESCE(invoiced_at, now()) END,
                        updated_at = now()
                  WHERE id = $1 AND tenant_id = $2
                    AND (number, series, movement_type, issued_at, customer_code, customer_name, seller_name, branch_code,
                         invoice_number, order_number)
                        IS DISTINCT FROM ($3, $4, $5, $6::timestamptz, $7, $8, $9, $10, $11::text, $12::text)`,
                [current.id, tenantId, ...header],
            );

            // Pedido faturado no ERP: se ainda não foi conferido, a mercadoria pode ter saído sem conferência.
            if (doc.invoiceNumber && current.invoice_number !== doc.invoiceNumber) {
                const early = !['CONCLUIDO', 'CANCELADO'].includes(current.status);
                await audit(client, {
                    tenantId, documentId: current.id,
                    action: early ? 'erp.invoiced_before_conference' : 'erp.invoiced',
                    details: { invoiceNumber: doc.invoiceNumber, status: current.status },
                });
                touched.push(current.id);
            }
            if (current.erp_hash === hash) continue;

            const cancelledNow = !!doc.cancelled && !current.erp_cancelled;
            const safeToReplace = current.status === 'AGUARDANDO'
                || (current.status === 'EM_CONFERENCIA' && current.round === 0);

            if (cancelledNow && current.status !== 'CONCLUIDO') {
                await client.query(
                    `UPDATE documents SET status = 'CANCELADO', erp_cancelled = TRUE, erp_hash = $2,
                            locked_by = NULL, locked_device = NULL, lock_expires_at = NULL, updated_at = now()
                      WHERE id = $1`,
                    [current.id, hash],
                );
                await audit(client, { tenantId, documentId: current.id, action: 'erp.cancelled' });
                flagged++;
            } else if (!doc.cancelled && safeToReplace) {
                await client.query('DELETE FROM document_items WHERE document_id = $1', [current.id]);
                await insertItems(client, tenantId, current.id, doc.items);
                await client.query(
                    `UPDATE documents SET erp_hash = $2, erp_cancelled = FALSE,
                            status = CASE WHEN status = 'CANCELADO' THEN 'AGUARDANDO' ELSE status END,
                            updated_at = now()
                      WHERE id = $1`,
                    [current.id, hash],
                );
                await audit(client, { tenantId, documentId: current.id, action: 'erp.items_replaced' });
                updated++;
            } else {
                await client.query(
                    `UPDATE documents SET erp_changed = TRUE, erp_cancelled = $3, erp_hash = $2, updated_at = now()
                      WHERE id = $1`,
                    [current.id, hash, !!doc.cancelled],
                );
                await audit(client, { tenantId, documentId: current.id, action: 'erp.changed_during_conference',
                    details: { status: current.status, cancelled: !!doc.cancelled } });
                flagged++;
            }
            touched.push(current.id);
        }
        await touchSyncState(client, tenantId, 'documentos', docs.length);
    });

    if (touched.length) bus.publish(tenantId, 'documents.synced', { count: touched.length });
    return { aplicados: created + updated + flagged, criados: created, atualizados: updated, sinalizados: flagged };
}

// ─────────────────────────────────────────────────────────────────────────────
// Retorno ao ERP (write-back)
// ─────────────────────────────────────────────────────────────────────────────

/** Concluídos aguardando gravação no ERP; erros são retentados após 5 minutos. */
async function pendingWriteback(tenantId, limit) {
    const { rows: docs } = await db.query(
        `SELECT d.id, d.source, d.erp_key, d.number, d.status, d.has_divergence, d.justification,
                d.started_at, d.finished_at, d.approved_at, d.round,
                fu.name AS finished_by_name, fu.login AS finished_by_login,
                au.name AS approved_by_name
           FROM documents d
           LEFT JOIN users fu ON fu.id = d.finished_by
           LEFT JOIN users au ON au.id = d.approved_by
          WHERE d.tenant_id = $1 AND d.status = 'CONCLUIDO'
            AND (d.writeback_status = 'PENDENTE'
                 OR (d.writeback_status = 'ERRO' AND d.writeback_at < now() - interval '5 minutes'))
          ORDER BY d.finished_at
          LIMIT $2`,
        [tenantId, limit],
    );
    if (!docs.length) return [];

    const { rows: items } = await db.query(
        `SELECT document_id, seq, product_erp_id, expected_qty::text AS expected_qty,
                COALESCE(counted_qty, 0)::text AS counted_qty, result, is_extra
           FROM document_items WHERE document_id = ANY($1) ORDER BY document_id, seq`,
        [docs.map((d) => d.id)],
    );
    const byDoc = Map.groupBy ? Map.groupBy(items, (i) => i.document_id) : groupBy(items, (i) => i.document_id);

    return docs.map((d) => ({
        documentId: d.id,
        source: d.source,
        erpKey: d.erp_key,
        number: d.number,
        hasDivergence: d.has_divergence,
        justification: d.justification,
        rounds: d.round + 1,
        startedAt: d.started_at,
        finishedAt: d.finished_at,
        approvedAt: d.approved_at,
        operator: d.finished_by_name,
        operatorLogin: d.finished_by_login,
        approver: d.approved_by_name,
        items: (byDoc.get(d.id) || []).map((i) => ({
            seq: i.seq, productErpId: i.product_erp_id, expectedQty: i.expected_qty,
            countedQty: i.counted_qty, result: i.result, isExtra: i.is_extra,
        })),
    }));
}

function groupBy(list, keyFn) {
    const map = new Map();
    for (const item of list) {
        const k = keyFn(item);
        if (!map.has(k)) map.set(k, []);
        map.get(k).push(item);
    }
    return map;
}

async function ackWriteback(tenantId, results) {
    let ok = 0, failed = 0;
    for (const r of results) {
        await db.query(
            `UPDATE documents SET writeback_status = $3, writeback_at = now(), writeback_error = $4
              WHERE tenant_id = $1 AND id = $2 AND status = 'CONCLUIDO'`,
            [tenantId, r.documentId, r.ok ? 'GRAVADO' : 'ERRO', r.ok ? null : String(r.error || 'erro').slice(0, 1000)],
        );
        r.ok ? ok++ : failed++;
        bus.publish(tenantId, 'document.updated', { documentId: r.documentId });
    }
    if (failed) await audit(null, { tenantId, action: 'writeback.failed', details: { failed } });
    return { aplicados: ok, erros: failed };
}

async function heartbeat(tenantId, info) {
    await db.query('UPDATE tenants SET worker_seen_at = now(), worker_info = $2 WHERE id = $1', [tenantId, JSON.stringify(info)]);
    bus.publish(tenantId, 'worker.heartbeat', { version: info.version, machine: info.machine });
}

module.exports = { upsertProducts, upsertStock, upsertDocuments, pendingWriteback, ackWriteback, heartbeat, documentHash };
