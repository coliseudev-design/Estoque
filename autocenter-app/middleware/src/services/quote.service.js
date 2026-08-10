'use strict';

const db = require('../db/postgres');
const logger = require('../config/logger');

/**
 * Cria um novo orçamento no status DRAFT.
 * 
 * @param {string} tenantId 
 * @param {string} deviceId 
 * @param {Object} data 
 * @returns {Promise<Object>}
 */
async function createDraft(tenantId, deviceId, data, branchId) {
    const { plate, vehicleInfo, customerName, customerPhone, items = [] } = data;

    const client = await db.pool.connect();
    try {
        await client.query('BEGIN');

        // 0. Checagem de Concorrência (HTTP 409)
        const checkRes = await client.query(
            `SELECT id FROM quotes WHERE tenant_id = $1 AND plate = $2 AND status IN ('DRAFT', 'PENDING_APPROVAL')`,
            [tenantId, plate]
        );

        if (checkRes.rowCount > 0) {
            const err = new Error('O ticket já está em edição por outro mecânico.');
            err.status = 409;
            err.code = 'CONCURRENCY_ERROR';
            throw err;
        }

        // Resolvendo dados da filial
        let deptoId = null;
        let empresaErp = 1;
        let centroCusto = null;

        if (branchId) {
            const branchRes = await client.query(
                `SELECT depto_id, empresa_erp, centro_custo 
                 FROM dash_filiais 
                 WHERE tenant_id = $1 AND (id = $2::int OR depto_id = $2::int)`,
                [tenantId, isNaN(Number(branchId)) ? 0 : Number(branchId)]
            );
            if (branchRes.rowCount > 0) {
                deptoId = branchRes.rows[0].depto_id;
                empresaErp = branchRes.rows[0].empresa_erp;
                centroCusto = branchRes.rows[0].centro_custo;
            }
        }

        // 1. Inserir Orçamento
        const quoteRes = await client.query(
            `INSERT INTO quotes (tenant_id, device_id, plate, vehicle_info, customer_name, customer_phone, status, total_amount, branch_id, depto_id, empresa_erp, centro_custo)
             VALUES ($1, $2, $3, $4, $5, $6, 'DRAFT', 0, $7, $8, $9, $10)
             RETURNING id`,
            [tenantId, deviceId, plate, vehicleInfo, customerName, customerPhone, branchId || null, deptoId, empresaErp, centroCusto]
        );
        const quoteId = quoteRes.rows[0].id;

        // 2. Inserir Itens e calcular total
        let totalAmount = 0;
        for (const item of items) {
            const { productCode, productDescription, quantity, unitPrice, itemType } = item;
            const totalPrice = Number((quantity * unitPrice).toFixed(2));
            totalAmount += totalPrice;

            await client.query(
                `INSERT INTO quote_items (quote_id, product_code, product_description, quantity, unit_price, total_price, item_type)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
                [quoteId, productCode, productDescription, quantity, unitPrice, totalPrice, itemType || 'PART']
            );
        }

        // 3. Atualiza total do orçamento
        await client.query(
            `UPDATE quotes SET total_amount = $1 WHERE id = $2`,
            [totalAmount, quoteId]
        );

        await client.query('COMMIT');
        logger.info('[QuoteService] Orçamento DRAFT criado', { quoteId, tenantId, deviceId });

        return { id: quoteId, status: 'DRAFT', totalAmount };
    } catch (err) {
        await client.query('ROLLBACK');
        logger.error('[QuoteService] Falha ao criar orçamento', { error: err.message, tenantId });
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Lista orçamentos recentes de uma placa num tenant específico.
 * 
 * @param {string} tenantId 
 * @param {string} plate 
 * @returns {Promise<Array>}
 */
async function getQuotesByPlate(tenantId, plate) {
    const res = await db.query(
        `SELECT id, status, total_amount, created_at, customer_name 
         FROM quotes 
         WHERE tenant_id = $1 AND plate = $2 
         ORDER BY created_at DESC LIMIT 10`,
        [tenantId, plate]
    );
    return res.rows;
}

/**
 * Filtro Rigoroso: Lista N orçamentos apenas com status APPROVED prontos para integração.
 * O Worker .NET consumirá esse método para varrer a fila em batch.
 * 
 * @param {string} tenantId 
 * @returns {Promise<Array>}
 */
async function getApprovedQuotes(tenantId, branchId) {
    let queryStr = `
         SELECT q.id, q.plate, q.customer_name AS "customerName", q.tenant_id AS "customerId", 
                q.device_id AS "mechanicId", 'Dinheiro' AS "paymentSpeciesId", '1' AS "paymentConditionId",
                'ORCAMENTO' AS "naturezaId", q.total_amount AS "totalAmount",
                (
                  SELECT json_agg(json_build_object(
                      'productCode', qi.product_code,
                      'quantity', qi.quantity,
                      'unitPrice', qi.unit_price,
                      'discount', 0
                  ))
                  FROM quote_items qi WHERE qi.quote_id = q.id
                ) as items,
                q.depto_id AS "deptoId",
                q.empresa_erp AS "empresaErp"
         FROM quotes q
         WHERE q.tenant_id = $1 AND q.status = 'APPROVED'
    `;
    const params = [tenantId];

    if (branchId) {
        queryStr += ` AND (q.branch_id = $2 OR q.depto_id = $2::int)`;
        params.push(branchId);
    }

    queryStr += ` ORDER BY q.created_at ASC LIMIT 50`;

    const res = await db.query(queryStr, params);

    // Formata default vazio pros items se nulo
    return res.rows.map(r => ({
        ...r,
        items: r.items || []
    }));
}

/**
 * Transita o status de um orçamento (ex: DRAFT -> APPROVED).
 * O Worker ficará escutando orçamentos "APPROVED" para jogar pro Firebird.
 * 
 * @param {string} tenantId 
 * @param {string} quoteId 
 * @param {string} newStatus 
 */
async function updateStatus(tenantId, quoteId, newStatus) {
    const validStatuses = ['DRAFT', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'INTEGRATED'];
    
    if (!validStatuses.includes(newStatus)) {
        const err = new Error('Status inválido');
        err.status = 400;
        throw err;
    }

    const res = await db.query(
        `UPDATE quotes SET status = $1, updated_at = NOW() 
         WHERE id = $2 AND tenant_id = $3 
         RETURNING id, status`,
        [newStatus, quoteId, tenantId]
    );

    if (res.rowCount === 0) {
        const err = new Error('Orçamento não encontrado');
        err.status = 404;
        throw err;
    }

    logger.info('[QuoteService] Orçamento atualizado', { quoteId, newStatus, tenantId });
    return res.rows[0];
}

/**
 * Adiciona fotos a um orçamento.
 */
async function addQuotePhotos(tenantId, quoteId, photoUrls) {
    const client = await db.pool.connect();
    try {
        await client.query('BEGIN');

        for (const url of photoUrls) {
            await client.query(
                `INSERT INTO quote_photos (quote_id, photo_url, photo_type)
                 VALUES ($1, $2, 'GENERAL')`,
                [quoteId, url]
            );
        }

        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        logger.error(`[QuoteService] Erro ao adicionar fotos (Quote ${quoteId}):`, err.message);
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Busca histórico de vistorias recentes abertas por este device / tenant
 */
async function getDeviceHistory(tenantId, deviceId) {
    const res = await db.query(
        `SELECT id, plate, customer_name, status, total_amount, created_at
         FROM quotes
         WHERE tenant_id = $1 AND device_id = $2
         ORDER BY created_at DESC
         LIMIT 50`,
        [tenantId, deviceId]
    );
    return res.rows;
}

module.exports = {
    createDraft,
    getQuotesByPlate,
    updateStatus,
    getApprovedQuotes,
    addQuotePhotos,
    getDeviceHistory
};
