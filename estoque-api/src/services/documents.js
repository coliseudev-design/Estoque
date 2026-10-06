/**
 * Serviço de documentos e conferência.
 *
 * Toda transição de estado acontece dentro de transação com SELECT ... FOR UPDATE
 * no documento: dois operadores (ou app + dashboard) agindo ao mesmo tempo no mesmo
 * documento são serializados pelo Postgres, nunca pela aplicação.
 */
'use strict';

const db = require('../db');
const bus = require('../realtime/bus');
const { audit } = require('./audit');
const { getSettings } = require('./settings');
const { canSeeExpected } = require('../auth/middleware');
const { evaluateRound, productsToRecount, blindItem, toUnits, fromUnits } = require('../domain/conference');
const { documentAlerts, flowOf, ATTENTION_SQL } = require('../domain/alerts');
const { parseAccessKey } = require('../domain/nfe');
const { critiquesFor } = require('./entries');
const { notFound, conflict, forbidden, badRequest } = require('../http');

const OPEN_STATUSES = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE'];
const COUNTING_STATUSES = ['EM_CONFERENCIA', 'DIVERGENTE'];
const isSupervisor = (user) => user.role === 'supervisor' || user.role === 'admin';

// ─────────────────────────────────────────────────────────────────────────────
// Mapeamentos
// ─────────────────────────────────────────────────────────────────────────────

const mapItem = (r) => ({
    seq: r.seq,
    productErpId: r.product_erp_id,
    description: r.description,
    unit: r.unit,
    expectedQty: r.expected_qty,
    countedQty: r.counted_qty,
    result: r.result,
    isExtra: r.is_extra,
    countedRound: r.counted_round,
    meta: r.meta && Object.keys(r.meta).length ? r.meta : undefined,
});

function mapHeader(r, user, settings) {
    const lockActive = r.locked_by && r.lock_expires_at && new Date(r.lock_expires_at) > new Date();
    const full = canSeeExpected(user);
    const header = {
        id: r.id,
        source: r.source,
        flow: flowOf(r.source),
        erpKey: r.erp_key,
        number: r.number,
        series: r.series,
        movementType: r.movement_type,
        issuedAt: r.issued_at,
        customerCode: r.customer_code,
        customerName: r.customer_name,
        sellerName: r.seller_name,
        branchCode: r.branch_code,
        invoiceNumber: r.invoice_number,
        invoicedAt: r.invoiced_at,
        orderNumber: r.order_number,
        status: r.status,
        priority: r.priority,
        round: r.round,
        lock: lockActive
            ? { userId: r.locked_by, userName: r.locked_by_name, deviceId: r.locked_device,
                expiresAt: r.lock_expires_at, mine: r.locked_by === user.id }
            : null,
        startedAt: r.started_at,
        startedByName: r.started_by_name,
        finishedAt: r.finished_at,
        finishedByName: r.finished_by_name,
        approvedAt: r.approved_at,
        approvedByName: r.approved_by_name,
        justification: r.justification,
        hasDivergence: r.has_divergence,
        erpChanged: r.erp_changed,
        erpCancelled: r.erp_cancelled,
        writebackStatus: r.writeback_status,
        writebackAt: r.writeback_at,
        writebackError: canSeeExpected(user) ? r.writeback_error : undefined,
        itemCount: r.item_count !== undefined ? Number(r.item_count) : undefined,
        // Progresso da separação: produtos distintos já lidos nesta rodada ÷ produtos do documento.
        // Não revela quantidade esperada — seguro para a conferência cega.
        productCount: r.product_count !== undefined ? Number(r.product_count) : undefined,
        countedProducts: r.counted_products !== undefined ? Number(r.counted_products) : undefined,
        updatedAt: r.updated_at,
        importedAt: r.imported_at || undefined,
        // Dados da NF-e de entrada (valor, protocolo, pedidos de compra) — só para quem vê o esperado.
        entry: r.source === 'NFE' && full ? {
            supplierCnpj: r.customer_code, totalValue: r.meta?.totalValue, orderNumbers: r.meta?.orderNumbers || [],
            operation: r.meta?.operation, protocol: r.meta?.protocol, recipient: r.meta?.recipient,
            supplier: r.meta?.supplier, critiques: r.meta?.critiques,
        } : undefined,
    };
    // Críticas operacionais (SLA, ERP alterou, retorno com erro…) — iguais no app e no painel.
    header.alerts = documentAlerts(header, { slaHours: settings?.outboundSlaHours, critiques: r.meta?.critiques });
    return header;
}

const HEADER_SQL = `
    SELECT d.*,
           lu.name AS locked_by_name, su.name AS started_by_name,
           fu.name AS finished_by_name, au.name AS approved_by_name
      FROM documents d
      LEFT JOIN users lu ON lu.id = d.locked_by
      LEFT JOIN users su ON su.id = d.started_by
      LEFT JOIN users fu ON fu.id = d.finished_by
      LEFT JOIN users au ON au.id = d.approved_by`;

// ─────────────────────────────────────────────────────────────────────────────
// Consultas
// ─────────────────────────────────────────────────────────────────────────────

async function listDocuments(tenantId, user, filters) {
    const settings = await getSettings(tenantId);
    const where = ['d.tenant_id = $1'];
    const params = [tenantId];
    const add = (sql, value) => { params.push(value); where.push(sql.replace('?', `$${params.length}`)); };

    if (filters.status?.length) add('d.status = ANY(?)', filters.status);
    else where.push(`(d.status <> 'CANCELADO')`);
    if (filters.from) add('d.issued_at >= ?', filters.from);
    else if (filters.days && !filters.q) {
        add(`(d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE','AGUARDANDO_APROVACAO')
              OR d.issued_at >= now() - (? || ' days')::interval)`, String(filters.days));
    }
    else if (!filters.q) {
        // Sem janela explícita (ex.: fila do app): trabalho pendente aparece SEMPRE,
        // qualquer que seja a idade; a janela padrão só limita os já finalizados.
        add(`(d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE','AGUARDANDO_APROVACAO')
              OR d.issued_at >= now() - (? || ' days')::interval)`, String(settings.queueDays));
    }
    if (filters.to) add('d.issued_at < ?', filters.to);
    if (filters.q) {
        params.push(`%${filters.q}%`, filters.q.trim());
        const like = `$${params.length - 1}`;
        const exact = `$${params.length}`;
        where.push(`(d.number ILIKE ${like} OR d.customer_name ILIKE ${like} OR d.erp_key = ${exact}
                     OR d.invoice_number = ${exact} OR d.order_number = ${exact})`);
    }
    if (filters.mine) add('d.locked_by = ?', user.id);
    if (filters.writeback) add('d.writeback_status = ?', filters.writeback);
    if (filters.flow === 'entrada') where.push(`d.source = 'NFE'`);
    else if (filters.flow === 'saida') where.push(`d.source <> 'NFE'`);
    if (filters.attention) add(ATTENTION_SQL, String(settings.outboundSlaHours));
    if (filters.priority) where.push('d.priority > 0');

    params.push(filters.limit, filters.offset);
    const { rows } = await db.query(
        `${HEADER_SQL.replace('SELECT d.*,', `SELECT d.*,
               (SELECT count(*) FROM document_items i WHERE i.document_id = d.id AND NOT i.is_extra) AS item_count,
               (SELECT count(DISTINCT i.product_erp_id) FROM document_items i
                 WHERE i.document_id = d.id AND NOT i.is_extra) AS product_count,
               (SELECT count(DISTINCT e.product_erp_id) FROM scan_events e
                 WHERE e.document_id = d.id AND e.round = d.round AND NOT e.voided
                   AND e.product_erp_id IN (SELECT i.product_erp_id FROM document_items i
                                             WHERE i.document_id = d.id AND NOT i.is_extra)) AS counted_products,`)}
          WHERE ${where.join(' AND ')}
          ORDER BY CASE d.status WHEN 'DIVERGENTE' THEN 0 WHEN 'EM_CONFERENCIA' THEN 1
                                 WHEN 'AGUARDANDO' THEN 2 WHEN 'AGUARDANDO_APROVACAO' THEN 3 ELSE 4 END,
                   d.priority DESC, d.issued_at ASC
          LIMIT $${params.length - 1} OFFSET $${params.length}`,
        params,
    );
    return rows.map((r) => mapHeader(r, user, settings));
}

/**
 * Contagem por status para as pílulas de filtro. Pendentes contam sempre;
 * concluídos e cancelados, só dentro da janela de dias.
 */
async function countDocuments(tenantId, { flow, days = 7 }) {
    const settings = await getSettings(tenantId);
    const flowSql = flow === 'entrada' ? `AND d.source = 'NFE'` : flow === 'saida' ? `AND d.source <> 'NFE'` : '';
    const { rows } = await db.query(
        `SELECT d.status, count(*)::int AS n,
                count(*) FILTER (WHERE ${ATTENTION_SQL.replace('?', '$3')})::int AS attention
           FROM documents d
          WHERE d.tenant_id = $1 ${flowSql}
            AND (d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE','AGUARDANDO_APROVACAO')
                 OR COALESCE(d.finished_at, d.updated_at) >= now() - ($2 || ' days')::interval)
          GROUP BY d.status`,
        [tenantId, String(days), String(settings.outboundSlaHours)],
    );
    return {
        byStatus: Object.fromEntries(rows.map((r) => [r.status, r.n])),
        attention: rows.reduce((sum, r) => sum + r.attention, 0),
    };
}

/**
 * Interpreta um código lido no leitor e devolve os documentos correspondentes.
 *
 * Aceita: número do pedido, número da NF, chave interna do ERP e a chave de acesso
 * da NF-e (44 dígitos, código de barras do DANFE) — dela sai a série e o número.
 * Prefixos de etiqueta (ex.: "PE114536") são ignorados.
 */
function parseLookupCode(raw) {
    const code = String(raw || '').trim();
    const digits = code.replace(/\D/g, '');
    if (digits.length === 44) {
        // cUF(2) AAMM(4) CNPJ(14) modelo(2) série(3) nNF(9) tpEmis(1) cNF(8) DV(1)
        const k = parseAccessKey(digits);
        return { kind: 'nfe', key: digits, number: k.number, series: k.series, cnpj: k.cnpj, valid: k.valid };
    }
    return { kind: 'code', exact: code, number: digits ? String(Number(digits)) : code };
}

async function lookupDocuments(tenantId, user, raw) {
    const p = parseLookupCode(raw);
    const settings = await getSettings(tenantId);
    const own = String(settings.companyCnpj || '').replace(/\D/g, '');
    // DANFE de fornecedor (CNPJ da chave ≠ empresa): só a nota de entrada com a mesma chave.
    // Sem o CNPJ configurado não dá para separar: procura entrada pela chave e saída pelo número.
    let match;
    if (p.kind === 'nfe') {
        match = own && p.cnpj !== own
            ? `d.source = 'NFE' AND d.erp_key = $3 AND $2::text IS NOT NULL`
            : `((d.source = 'NFE' AND d.erp_key = $3)
                OR (d.source <> 'NFE' AND (d.erp_key = $3 OR (d.source = 'NFS' AND d.number = $2) OR d.invoice_number = $2)))`;
    } else {
        match = `(d.number = $2 OR d.invoice_number = $2 OR d.order_number = $2 OR d.erp_key = $2 OR d.erp_key = $3)`;
    }
    const { rows } = await db.query(
        `${HEADER_SQL.replace('SELECT d.*,', `SELECT d.*,
               (SELECT count(*) FROM document_items i WHERE i.document_id = d.id AND NOT i.is_extra) AS item_count,`)}
          WHERE d.tenant_id = $1
            AND ${match}
          ORDER BY CASE WHEN d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE') THEN 0 ELSE 1 END,
                   -- pedido antes da NF: é ele que se confere quando há os dois
                   CASE d.source WHEN 'PED' THEN 0 ELSE 1 END,
                   d.issued_at DESC NULLS LAST
          LIMIT 5`,
        [tenantId, p.number, p.kind === 'nfe' ? p.key : p.exact],
    );
    return {
        parsed: { ...p, incoming: p.kind === 'nfe' && own ? p.cnpj !== own : undefined },
        items: rows.map((r) => mapHeader(r, user, settings)),
    };
}

/** Soma das leituras válidas da rodada, por produto. */
async function roundTotals(runner, documentId, round) {
    const { rows } = await runner.query(
        `SELECT product_erp_id, sum(qty)::text AS qty
           FROM scan_events
          WHERE document_id = $1 AND round = $2 AND NOT voided AND product_erp_id IS NOT NULL
          GROUP BY product_erp_id`,
        [documentId, round],
    );
    return new Map(rows.map((r) => [r.product_erp_id, r.qty]));
}

async function unknownScans(runner, documentId, round) {
    const { rows } = await runner.query(
        `SELECT id, barcode, qty::text AS qty, scanned_at
           FROM scan_events
          WHERE document_id = $1 AND round = $2 AND NOT voided AND product_erp_id IS NULL
          ORDER BY scanned_at`,
        [documentId, round],
    );
    return rows.map((r) => ({ eventId: r.id, barcode: r.barcode, qty: r.qty, scannedAt: r.scanned_at }));
}

async function getDocument(tenantId, user, id) {
    const { rows } = await db.query(`${HEADER_SQL} WHERE d.tenant_id = $1 AND d.id = $2`, [tenantId, id]);
    if (!rows[0]) throw notFound('Documento não encontrado');
    const settings = await getSettings(tenantId);
    const header = mapHeader(rows[0], user, settings);

    const [{ rows: itemRows }, totals, unknown] = await Promise.all([
        db.query('SELECT * FROM document_items WHERE document_id = $1 ORDER BY seq', [id]),
        roundTotals(db, id, header.round),
        unknownScans(db, id, header.round),
    ]);
    const items = itemRows.map(mapItem);
    const recount = productsToRecount(items, header.round);

    // Códigos de barras dos itens: o app guarda para conferir offline.
    // Os da própria nota (entrada) vêm por último e prevalecem sobre os do cadastro.
    const { rows: barcodeRows } = await db.query(
        `SELECT b.erp_id, b.barcode, b.factor::text AS factor
           FROM product_barcodes b
          WHERE b.tenant_id = $1 AND b.erp_id = ANY($2)
            AND NOT EXISTS (SELECT 1 FROM document_barcodes x WHERE x.document_id = $3 AND x.barcode = b.barcode)
         UNION ALL
         SELECT product_erp_id, barcode, factor::text FROM document_barcodes WHERE document_id = $3`,
        [tenantId, [...new Set(items.map((i) => i.productErpId))], id],
    );

    const full = canSeeExpected(user);
    const critiques = full && header.source === 'NFE'
        ? await critiquesFor(tenantId, { meta: rows[0].meta, issuedAt: header.issuedAt }, items.filter((i) => !i.isExtra))
        : undefined;
    return {
        ...header,
        critiques,
        items: full
            ? items
            : settings.showItemList || header.round > 0
                ? items.filter((i) => !i.isExtra || recount.has(i.productErpId)).map((i) => blindItem(i, { recount }))
                : [],
        barcodes: barcodeRows.map((b) => ({ productErpId: b.erp_id, barcode: b.barcode, factor: b.factor })),
        counts: Object.fromEntries(totals), // o que já foi contado nesta rodada (não revela o esperado)
        unknownScans: unknown,
        recount: [...recount],
        settings: { allowManualQty: settings.allowManualQty, showItemList: settings.showItemList },
    };
}

async function listScans(tenantId, id) {
    const { rows } = await db.query(
        `SELECT e.id, e.round, e.product_erp_id, p.description, e.barcode, e.qty::text AS qty,
                e.origin, e.device_id, e.scanned_at, e.voided, u.name AS user_name
           FROM scan_events e
           LEFT JOIN users u ON u.id = e.user_id
           LEFT JOIN products p ON p.tenant_id = e.tenant_id AND p.erp_id = e.product_erp_id
          WHERE e.tenant_id = $1 AND e.document_id = $2
          ORDER BY e.scanned_at DESC
          LIMIT 2000`,
        [tenantId, id],
    );
    return rows;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reserva (lock)
// ─────────────────────────────────────────────────────────────────────────────

async function lockForUpdate(client, tenantId, id) {
    const { rows } = await client.query(
        'SELECT * FROM documents WHERE tenant_id = $1 AND id = $2 FOR UPDATE',
        [tenantId, id],
    );
    if (!rows[0]) throw notFound('Documento não encontrado');
    return rows[0];
}

const lockedByOther = (doc, user) =>
    doc.locked_by && doc.locked_by !== user.id && doc.lock_expires_at && new Date(doc.lock_expires_at) > new Date();

async function lockOwnerName(client, doc) {
    const { rows } = await client.query('SELECT name FROM users WHERE id = $1', [doc.locked_by]);
    return rows[0]?.name || 'outro operador';
}

async function claim(tenantId, user, deviceId, id, { force = false } = {}) {
    const settings = await getSettings(tenantId);
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (!OPEN_STATUSES.includes(doc.status)) {
            throw conflict(`Documento está ${doc.status} e não pode ser conferido`, 'INVALID_STATUS');
        }
        if (doc.erp_cancelled) throw conflict('Documento cancelado no ERP', 'ERP_CANCELLED');
        if (lockedByOther(doc, user)) {
            if (!(force && isSupervisor(user))) {
                throw conflict(`Em conferência por ${await lockOwnerName(client, doc)}`, 'LOCKED', {
                    lockedBy: doc.locked_by, expiresAt: doc.lock_expires_at,
                });
            }
            await audit(client, { tenantId, documentId: id, userId: user.id, action: 'lock.forced',
                details: { previous: doc.locked_by } });
        }
        await client.query(
            `UPDATE documents
                SET locked_by = $3, locked_device = $4,
                    lock_expires_at = now() + ($5 || ' minutes')::interval,
                    status = CASE WHEN status = 'AGUARDANDO' THEN 'EM_CONFERENCIA' ELSE status END,
                    started_by = COALESCE(started_by, $3), started_at = COALESCE(started_at, now()),
                    updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id, user.id, deviceId, String(settings.lockMinutes)],
        );
        if (doc.locked_by !== user.id) {
            await audit(client, { tenantId, documentId: id, userId: user.id, action: 'document.claimed', details: { deviceId } });
        }
    });
    bus.publish(tenantId, 'document.updated', { documentId: id });
    return getDocument(tenantId, user, id);
}

async function release(tenantId, user, id) {
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (doc.locked_by && doc.locked_by !== user.id && !isSupervisor(user)) throw forbidden('Documento reservado por outro operador');
        const { rows } = await client.query('SELECT 1 FROM scan_events WHERE document_id = $1 AND NOT voided LIMIT 1', [id]);
        await client.query(
            `UPDATE documents
                SET locked_by = NULL, locked_device = NULL, lock_expires_at = NULL,
                    status = CASE WHEN status = 'EM_CONFERENCIA' AND $3 THEN 'AGUARDANDO' ELSE status END,
                    started_by = CASE WHEN $3 THEN NULL ELSE started_by END,
                    started_at = CASE WHEN $3 THEN NULL ELSE started_at END,
                    updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id, rows.length === 0],
        );
        await audit(client, { tenantId, documentId: id, userId: user.id, action: 'document.released' });
    });
    bus.publish(tenantId, 'document.updated', { documentId: id });
}

// ─────────────────────────────────────────────────────────────────────────────
// Leituras
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Registra leituras (idempotente pelo id do evento).
 *
 * Contrato de cada evento:
 *   id          UUID gerado no cliente (repetir o envio não duplica)
 *   barcode     código lido (opcional se productErpId vier)
 *   productErpId produto escolhido manualmente (opcional)
 *   qty         quantidade de EMBALAGENS lidas/digitadas (1 por bip). Negativo = estorno.
 *               O servidor multiplica pelo fator do código (caixa com 12 → ×12).
 *   round       rodada em que o operador estava ao ler — leituras de rodada antiga são recusadas
 *   origin      camera | coletor | teclado | manual | web
 *   scannedAt   instante da leitura no aparelho (a fila offline preserva a ordem real)
 */
async function addScans(tenantId, user, deviceId, id, events) {
    const settings = await getSettings(tenantId);
    if (!settings.allowManualQty && events.some((e) => Math.abs(e.qty) !== 1)) {
        throw badRequest('Esta empresa não permite digitar quantidade: bipe item a item');
    }

    const result = await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (!COUNTING_STATUSES.includes(doc.status)) {
            throw conflict(`Documento está ${doc.status}; leituras não são mais aceitas`, 'INVALID_STATUS');
        }
        if (lockedByOther(doc, user)) {
            throw conflict(`Documento reservado por ${await lockOwnerName(client, doc)}`, 'LOCK_LOST');
        }

        const accepted = events.filter((e) => e.round === doc.round);
        const rejected = events.filter((e) => e.round !== doc.round).map((e) => ({ id: e.id, reason: 'ROUND_CLOSED' }));

        if (accepted.length) {
            // Resolve código → produto e aplica o fator da embalagem, tudo no SQL, em um único INSERT.
            await client.query(
                `INSERT INTO scan_events (id, tenant_id, document_id, round, product_erp_id, barcode, qty,
                                          user_id, device_id, origin, scanned_at)
                 SELECT e.id, $1, $2, e.round,
                        COALESCE(x.product_erp_id, b.erp_id, p.erp_id,
                                 (SELECT i.product_erp_id FROM document_items i
                                   WHERE i.document_id = $2 AND i.product_erp_id = e."productErpId" LIMIT 1)),
                        e.barcode,
                        e.qty * COALESCE(x.factor, b.factor, 1),
                        $3, $4, e.origin, e."scannedAt"
                   FROM jsonb_to_recordset($5::jsonb) AS e(id uuid, round int, barcode text,
                        "productErpId" text, qty numeric, origin text, "scannedAt" timestamptz)
                   -- código da própria nota (entrada) > código do cadastro > produto escolhido
                   LEFT JOIN document_barcodes x ON x.document_id = $2 AND x.barcode = e.barcode
                   LEFT JOIN product_barcodes b ON b.tenant_id = $1 AND b.barcode = e.barcode AND x.barcode IS NULL
                   LEFT JOIN products p ON p.tenant_id = $1 AND p.erp_id = e."productErpId" AND b.erp_id IS NULL AND x.barcode IS NULL
                 ON CONFLICT (id) DO NOTHING`,
                [tenantId, id, user.id, deviceId, JSON.stringify(accepted)],
            );
        }

        // Toda leitura renova a reserva — operador ativo não perde o documento.
        await client.query(
            `UPDATE documents
                SET locked_by = $3, locked_device = COALESCE($4, locked_device),
                    lock_expires_at = now() + ($5 || ' minutes')::interval, updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id, user.id, deviceId, String(settings.lockMinutes)],
        );

        const totals = await roundTotals(client, id, doc.round);
        const unknown = await unknownScans(client, id, doc.round);
        return { round: doc.round, counts: Object.fromEntries(totals), unknownScans: unknown, rejected };
    });

    bus.publish(tenantId, 'scan.added', { documentId: id, userId: user.id, count: events.length });
    return result;
}

async function voidScan(tenantId, user, documentId, eventId) {
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, documentId);
        if (!COUNTING_STATUSES.includes(doc.status)) throw conflict('Documento não está em conferência', 'INVALID_STATUS');
        const { rows } = await client.query(
            'SELECT user_id, round, voided FROM scan_events WHERE id = $1 AND document_id = $2',
            [eventId, documentId],
        );
        const ev = rows[0];
        if (!ev) throw notFound('Leitura não encontrada');
        if (ev.voided) return;
        if (ev.round !== doc.round) throw conflict('Leitura de rodada já encerrada', 'ROUND_CLOSED');
        if (ev.user_id !== user.id && !isSupervisor(user)) throw forbidden('Só quem leu (ou o supervisor) pode estornar');
        await client.query('UPDATE scan_events SET voided = TRUE, voided_by = $2 WHERE id = $1', [eventId, user.id]);
        await audit(client, { tenantId, documentId, userId: user.id, action: 'scan.voided', details: { eventId } });
    });
    bus.publish(tenantId, 'scan.added', { documentId, userId: user.id, count: 0 });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fechamento de rodada
// ─────────────────────────────────────────────────────────────────────────────

async function finalize(tenantId, user, id) {
    const settings = await getSettings(tenantId);

    const outcome = await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (!COUNTING_STATUSES.includes(doc.status)) throw conflict(`Documento está ${doc.status}`, 'INVALID_STATUS');
        if (lockedByOther(doc, user) && !isSupervisor(user)) {
            throw conflict(`Documento reservado por ${await lockOwnerName(client, doc)}`, 'LOCK_LOST');
        }

        const unknown = await unknownScans(client, id, doc.round);
        if (unknown.length) {
            throw conflict('Existem códigos não reconhecidos. Estorne ou identifique o produto antes de finalizar.',
                'UNKNOWN_BARCODES', { unknownScans: unknown });
        }

        const { rows: itemRows } = await client.query('SELECT * FROM document_items WHERE document_id = $1', [id]);
        const items = itemRows.map(mapItem);
        const scanTotals = await roundTotals(client, id, doc.round);

        const extrasIds = [...scanTotals.keys()].filter((p) => !items.some((i) => i.productErpId === p));
        const { rows: infoRows } = extrasIds.length
            ? await client.query('SELECT erp_id, description, unit FROM products WHERE tenant_id = $1 AND erp_id = ANY($2)', [tenantId, extrasIds])
            : { rows: [] };
        const productInfo = new Map(infoRows.map((r) => [r.erp_id, { description: r.description, unit: r.unit }]));

        const evaluation = evaluateRound({ items, round: doc.round, scanTotals, productInfo, maxRecounts: settings.maxRecounts });

        // Grava as linhas (atualiza as existentes, insere as extras) em um único comando.
        await client.query(
            `INSERT INTO document_items (document_id, seq, tenant_id, product_erp_id, description, unit,
                                         expected_qty, counted_qty, result, is_extra, counted_round)
             SELECT $1, i.seq, $2, i."productErpId", COALESCE(i.description, ''), i.unit,
                    i."expectedQty", i."countedQty", i.result, COALESCE(i."isExtra", FALSE), i."countedRound"
               FROM jsonb_to_recordset($3::jsonb) AS i(seq int, "productErpId" text, description text, unit text,
                    "expectedQty" numeric, "countedQty" numeric, result text, "isExtra" boolean, "countedRound" int)
             ON CONFLICT (document_id, seq) DO UPDATE
                SET counted_qty = EXCLUDED.counted_qty, result = EXCLUDED.result,
                    counted_round = EXCLUDED.counted_round`,
            [id, tenantId, JSON.stringify(evaluation.items)],
        );

        const done = evaluation.nextStatus === 'CONCLUIDO';
        const toSupervisor = evaluation.nextStatus === 'AGUARDANDO_APROVACAO';
        await client.query(
            `UPDATE documents
                SET status = $3, round = $4, has_divergence = has_divergence OR $5,
                    finished_by = CASE WHEN $6 OR $7 THEN $8::uuid ELSE finished_by END,
                    finished_at = CASE WHEN $6 OR $7 THEN now() ELSE finished_at END,
                    locked_by = CASE WHEN $6 OR $7 THEN NULL ELSE locked_by END,
                    locked_device = CASE WHEN $6 OR $7 THEN NULL ELSE locked_device END,
                    lock_expires_at = CASE WHEN $6 OR $7 THEN NULL ELSE lock_expires_at END,
                    writeback_status = CASE WHEN $6 AND source <> 'NFE' THEN 'PENDENTE' ELSE writeback_status END,
                    updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id, evaluation.nextStatus, evaluation.nextRound, !evaluation.allOk, done, toSupervisor, user.id],
        );

        await audit(client, {
            tenantId, documentId: id, userId: user.id, action: 'round.closed',
            details: { round: doc.round, status: evaluation.nextStatus, divergent: evaluation.divergentProducts },
        });
        return evaluation;
    });

    bus.publish(tenantId, 'document.updated', { documentId: id, status: outcome.nextStatus });

    // Resposta ao operador: o que fazer a seguir, sem revelar quantidades esperadas.
    const doc = await getDocument(tenantId, user, id);
    return {
        status: outcome.nextStatus,
        round: outcome.nextRound,
        recount: outcome.nextStatus === 'DIVERGENTE'
            ? doc.items.filter((i) => outcome.divergentProducts.includes(i.productErpId))
                .map((i) => ({ productErpId: i.productErpId, description: i.description }))
            : [],
        document: doc,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Ações do supervisor
// ─────────────────────────────────────────────────────────────────────────────

async function approve(tenantId, user, id, justification) {
    const settings = await getSettings(tenantId);
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (!['AGUARDANDO_APROVACAO', 'DIVERGENTE'].includes(doc.status)) {
            throw conflict(`Documento está ${doc.status}; nada a aprovar`, 'INVALID_STATUS');
        }
        if (settings.requireJustification && doc.has_divergence && !justification?.trim()) {
            throw badRequest('Informe a justificativa para aprovar com divergência');
        }
        await client.query(
            `UPDATE documents
                SET status = 'CONCLUIDO', approved_by = $3, approved_at = now(), justification = $4,
                    finished_by = COALESCE(finished_by, $3), finished_at = COALESCE(finished_at, now()),
                    locked_by = NULL, locked_device = NULL, lock_expires_at = NULL,
                    writeback_status = CASE WHEN source = 'NFE' THEN 'NAO_APLICAVEL' ELSE 'PENDENTE' END, updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id, user.id, justification?.trim() || null],
        );
        await audit(client, { tenantId, documentId: id, userId: user.id, action: 'document.approved', details: { justification } });
    });
    bus.publish(tenantId, 'document.updated', { documentId: id, status: 'CONCLUIDO' });
    return getDocument(tenantId, user, id);
}

/** Reabre para recontagem. `products` vazio = recontar tudo que divergiu. */
async function reopen(tenantId, user, id, products = []) {
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (!['AGUARDANDO_APROVACAO', 'CONCLUIDO', 'DIVERGENTE'].includes(doc.status)) {
            throw conflict(`Documento está ${doc.status}`, 'INVALID_STATUS');
        }
        if (doc.status === 'CONCLUIDO' && doc.writeback_status === 'GRAVADO') {
            throw conflict('Resultado já gravado no ERP. Estorne no ERP antes de reabrir.', 'ALREADY_WRITTEN');
        }
        if (products.length) {
            await client.query(
                `UPDATE document_items SET result = 'PENDENTE' WHERE document_id = $1 AND product_erp_id = ANY($2)`,
                [id, products],
            );
        }
        const { rows } = await client.query(`SELECT 1 FROM document_items WHERE document_id = $1 AND result <> 'OK' LIMIT 1`, [id]);
        if (!rows.length) throw badRequest('Nenhum item para recontar. Informe os produtos.');

        await client.query(
            `UPDATE documents
                SET status = 'DIVERGENTE', round = round + 1, approved_by = NULL, approved_at = NULL,
                    finished_by = NULL, finished_at = NULL,
                    writeback_status = 'NAO_APLICAVEL', writeback_error = NULL, updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id],
        );
        await audit(client, { tenantId, documentId: id, userId: user.id, action: 'document.reopened', details: { products } });
    });
    bus.publish(tenantId, 'document.updated', { documentId: id, status: 'DIVERGENTE' });
    return getDocument(tenantId, user, id);
}

/** Zera a conferência: estorna todas as leituras e volta para a fila. */
async function reset(tenantId, user, id) {
    await db.tx(async (client) => {
        const doc = await lockForUpdate(client, tenantId, id);
        if (doc.status === 'CONCLUIDO' && doc.writeback_status === 'GRAVADO') {
            throw conflict('Resultado já gravado no ERP', 'ALREADY_WRITTEN');
        }
        await client.query('UPDATE scan_events SET voided = TRUE, voided_by = $2 WHERE document_id = $1 AND NOT voided', [id, user.id]);
        await client.query('DELETE FROM document_items WHERE document_id = $1 AND is_extra', [id]);
        await client.query(`UPDATE document_items SET counted_qty = NULL, result = 'PENDENTE', counted_round = NULL WHERE document_id = $1`, [id]);
        await client.query(
            `UPDATE documents
                SET status = CASE WHEN erp_cancelled THEN 'CANCELADO' ELSE 'AGUARDANDO' END,
                    round = 0, has_divergence = FALSE, erp_changed = FALSE,
                    locked_by = NULL, locked_device = NULL, lock_expires_at = NULL,
                    started_by = NULL, started_at = NULL, finished_by = NULL, finished_at = NULL,
                    approved_by = NULL, approved_at = NULL, justification = NULL,
                    writeback_status = 'NAO_APLICAVEL', writeback_error = NULL, updated_at = now()
              WHERE tenant_id = $1 AND id = $2`,
            [tenantId, id],
        );
        await audit(client, { tenantId, documentId: id, userId: user.id, action: 'document.reset', details: { from: doc.status } });
    });
    bus.publish(tenantId, 'document.updated', { documentId: id, status: 'AGUARDANDO' });
}

async function setPriority(tenantId, user, id, priority) {
    const { rowCount } = await db.query(
        'UPDATE documents SET priority = $3, updated_at = now() WHERE tenant_id = $1 AND id = $2',
        [tenantId, id, priority],
    );
    if (!rowCount) throw notFound('Documento não encontrado');
    await audit(null, { tenantId, documentId: id, userId: user.id, action: 'document.priority', details: { priority } });
    bus.publish(tenantId, 'document.updated', { documentId: id });
}

module.exports = {
    listDocuments, countDocuments, getDocument, listScans, lookupDocuments, parseLookupCode,
    claim, release, addScans, voidScan, finalize,
    approve, reopen, reset, setPriority,
    // expostos para testes/relatórios
    roundTotals, toUnits, fromUnits,
};
