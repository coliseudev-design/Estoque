'use strict';
/**
 * Rota de sincronização de pedidos (POST only).
 *
 * Fluxo:
 *  1. Validação estrutural (uuid, campos obrigatórios)
 *  2. Idempotência via PostgreSQL (evita pedido duplicado)
 *  3. Tentativa de gravação direta no Firebird (modo direct/fallback)
 *     3a. MOB_CADASTRAR_PEDIDO
 *     3b. MOB_CADASTRAR_PEDIDO_ITEM por item
 *     3c. Reescrita de PEDIDOS_DOCS com N parcelas corretas
 *  4. Registro de status no PostgreSQL (synced | pending)
 *
 * @module routes/sync/orders
 * @route  POST /api/sync/orders
 */

const express = require('express');
const { fbQuery, fbExec, validateOrder, padDate, padTime } = require('./helpers');
const { pgQuery } = require('../../db/postgres');
const { createError } = require('../../middleware/errorHandler');
const logger = require('../../config/logger');
const config = require('../../config/env');

const router = express.Router();

/**
 * Recebe pedidos do app, verifica idempotência e grava no ERP.
 *
 * @route POST /api/sync/orders
 * @body  {{ orders: OrderPayload[] }}
 */
router.post('/orders', async (req, res, next) => {
    try {
        const { orders } = req.body;
        if (!Array.isArray(orders)) {
            return next(createError('O campo "orders" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }

        const results = { accepted: 0, duplicates: 0, errors: [] };

        for (const order of orders) {
            // ── 1. Validação estrutural ──────────────────────────────────────
            const { valid, reason } = validateOrder(order);
            if (!valid) {
                results.errors.push({ id: order.id || 'desconhecido', reason });
                continue;
            }

            // ── 2. Idempotência ──────────────────────────────────────────────
            let alreadySynced = false;
            try {
                const pgRes = await pgQuery(
                    'SELECT sync_status FROM orders WHERE id = $1 AND company_id = $2',
                    [order.id, req.company.id]
                );
                if (pgRes.rows.length > 0 && pgRes.rows[0].sync_status === 'synced') {
                    alreadySynced = true;
                }
            } catch (pgErr) {
                logger.debug('[Sync/Orders] Erro consulta idempotência PG', { error: pgErr.message });
            }

            if (alreadySynced) {
                logger.debug('[Sync/Orders] Pedido já sincronizado', { orderId: order.id });
                results.duplicates++;
                continue;
            }

            const mode = config.syncMode; // direct | async | fallback
            let integratedInErp = false;
            let erpIdValue = null;
            let skipFirebird = false;

            // ── Resolve cliente local → ERP ID (ANTES do Firebird) ───────────
            if (String(order.customerId).startsWith('local_')) {
                try {
                    const resolved = await pgQuery(
                        `SELECT erp_customer_id FROM pending_customers
                         WHERE local_id = $1 AND company_id = $2 AND sync_status = 'synced'
                         LIMIT 1`,
                        [order.customerId, req.company.id]
                    );
                    if (resolved.rows.length > 0 && resolved.rows[0].erp_customer_id) {
                        const originalId = order.customerId;
                        order.customerId = resolved.rows[0].erp_customer_id;
                        logger.info('[Sync/Orders] Cliente local resolvido para ERP', {
                            localId: originalId, erpId: order.customerId, orderId: order.id,
                        });
                    } else {
                        logger.warn('[Sync/Orders] Cliente local ainda pendente — pedido salvo como pending', {
                            customerId: order.customerId, orderId: order.id,
                        });
                        skipFirebird = true;
                    }
                } catch (resolveErr) {
                    logger.error('[Sync/Orders] Erro ao resolver cliente local', { error: resolveErr.message });
                    skipFirebird = true;
                }
            }

            // ── 3. Gravação direta no Firebird ───────────────────────────────
            if (!skipFirebird && (mode === 'direct' || mode === 'fallback')) {
                try {
                    const now     = order.createdAt ? new Date(order.createdAt) : new Date();
                    const obs     = (order.notes || '').substring(0, 100);
                    const condStr = String(order.paymentConditionId || '0');
                    const prazo   = condStr.substring(0, 20);
                    const pagamentoId = Number(order.paymentSpeciesId || 1);

                    const items = order.items || [];

                    // Subtotal de itens após desconto individual + desconto extra do pedido
                    let itemDiscountsTotal = 0;
                    const subtotalAposDescontoItem = items.reduce((s, it) => {
                        const itGross = Number(it.unitPrice) * Number(it.quantity);
                        const itDisc  = itGross * (Number(it.discount || 0) / 100);
                        itemDiscountsTotal += itDisc;
                        return s + (itGross - itDisc);
                    }, 0);
                    const totalAppDiscount   = Number(order.discountValue || 0);
                    const extraOrderDiscount = Math.max(0, totalAppDiscount - itemDiscountsTotal);

                    // WARNING-4 fix: valida inteiros antes de chamar SP
                    const sellerIdNum   = Number(order.sellerId);
                    const customerIdNum = Number(order.customerId);
                    if (!Number.isInteger(sellerIdNum)   || sellerIdNum   <= 0)
                        throw new Error(`sellerId inválido: '${order.sellerId}' no pedido ${order.id}`);
                    if (!Number.isInteger(customerIdNum) || customerIdNum <= 0)
                        throw new Error(`customerId inválido: '${order.customerId}' no pedido ${order.id}`);

                    await fbExec(req,
                        'EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(?,?,?,?,?,?,?,?,?,?)',
                        [
                            sellerIdNum,                    // 1. USUARIO
                            customerIdNum,                  // 2. CLIENTE
                            padDate(now),                   // 3. DATA
                            padTime(now),                   // 4. HORA
                            obs,                            // 5. OBSERVACAO
                            prazo,                          // 6. PRAZO_PEDIDO (condição)
                            (order.naturezaId === 'null' || !order.naturezaId) ? '' : String(order.naturezaId), // 7. TIPO_OPERACAO
                            pagamentoId,                    // 8. PAGAMENTO
                            extraOrderDiscount,             // 9. VALOR_DESCONTO do Pedido
                            subtotalAposDescontoItem,        // 10. TOTAL_PEDIDO
                        ]
                    );

                    // GEN_ID(PEDIDOS, 0): lê o ID atual sem incrementar (race-condition-safe)
                    const lastRows = await fbQuery(req,
                        'SELECT GEN_ID(PEDIDOS, 0) AS ID_PEDIDO FROM RDB$DATABASE');
                    erpIdValue = lastRows[0]?.ID_PEDIDO ?? lastRows[0]?.id_pedido;

                    if (erpIdValue) {
                        // Itens do pedido
                        for (const item of items) {
                            const qty       = Number(item.quantity);
                            const unitPx    = Number(item.unitPrice);
                            const itemGross = unitPx * qty;
                            const itemDiscR = itemGross * (Number(item.discount || 0) / 100);
                            const itemTotal = itemGross - itemDiscR;

                            await fbExec(req,
                                'EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO_ITEM(?,?,?,?,?,?,?)',
                                [erpIdValue, item.productCode, qty, item.notes || '', unitPx, itemDiscR, itemTotal]
                            );
                        }
                        integratedInErp = true;
                        logger.info('[Sync/Orders] Pedido criado no ERP (Direct)', { uuid: order.id, erpIdValue });

                        // Reescreve PEDIDOS_DOCS com N parcelas corretas (rounding-safe)
                        const nParcelas   = Math.max(1, Number(order.paymentInstallments || 1));
                        const diasParc    = Math.max(1, Number(order.paymentDaysPerInstallment || 30));
                        const diasEntrada = Number(order.paymentEntryDays || 0);
                        const totalLiquido = subtotalAposDescontoItem - extraOrderDiscount;
                        const valorBase   = parseFloat((totalLiquido / nParcelas).toFixed(2));
                        const valorUltima = parseFloat((totalLiquido - valorBase * (nParcelas - 1)).toFixed(2));

                        logger.info('[Sync/Orders] Parcelamento', {
                            uuid: order.id, parcelas: nParcelas, valorBase, valorUltima,
                            diasEntrada, diasParcelas: diasParc,
                        });

                        await fbExec(req, 'DELETE FROM PEDIDOS_DOCS WHERE ID_PEDIDO = ?', [erpIdValue]);

                        for (let p = 1; p <= nParcelas; p++) {
                            const diasTotal = diasEntrada + diasParc * p;
                            const vencDate  = new Date(now);
                            vencDate.setDate(vencDate.getDate() + diasTotal);
                            const valorAtual = (p === nParcelas) ? valorUltima : valorBase;

                            await fbExec(req,
                                `INSERT INTO PEDIDOS_DOCS
                                    (ID_PEDIDO, PARCELA, N_DOC, ID_ESPECIE, DATA_VENCIMENTO, VALOR, ID_CHEQUE, TIPO_CARTAO)
                                VALUES (?, ?, ?, ?, ?, ?, 0, 2)`,
                                [erpIdValue, p, String(p), pagamentoId, padDate(vencDate), valorAtual]
                            );
                        }
                    }
                } catch (err) {
                    if (mode === 'direct') {
                        logger.error('[Sync/Orders] Falha direct', { error: err.message });
                        results.errors.push({ id: order.id, reason: err.message });
                        continue;
                    }
                    logger.warn('[Sync/Orders] Falha direct → Fallback Async', { error: err.message });
                }
            }

            // ── 4. Registro de status no PostgreSQL ──────────────────────────
            try {
                const companyId = req.company.id;
                const branchId = req.branch?.id || null;
                const status = integratedInErp ? 'synced' : 'pending';

                await pgQuery(
                    `INSERT INTO orders
                         (id, company_id, branch_id, sync_status, erp_order_id, customer_name, seller_name, total_amount, payload, created_at)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
                     ON CONFLICT (id) DO UPDATE SET
                         sync_status  = EXCLUDED.sync_status,
                         branch_id    = COALESCE(EXCLUDED.branch_id, orders.branch_id),
                         erp_order_id = COALESCE(EXCLUDED.erp_order_id, orders.erp_order_id),
                         payload      = COALESCE(orders.payload, EXCLUDED.payload),
                         updated_at   = NOW()`,
                    [
                        order.id, companyId, branchId, status,
                        erpIdValue ? String(erpIdValue) : null,
                        order.customerName ?? String(order.customerId),
                        order.sellerName   ?? String(order.sellerId),
                        Number(order.totalAmount) || 0,
                        JSON.stringify(order),
                    ]
                );

                results.accepted++;
                logger.info(`[Sync/Orders] Pedido registrado como ${status}`, {
                    uuid: order.id, companyId, erpId: erpIdValue,
                });
            } catch (pgErr) {
                if (integratedInErp) {
                    results.accepted++;
                    logger.warn('[Sync/Orders] Integrado no ERP porém falha ao salvar no PG', { error: pgErr.message });
                } else {
                    logger.error('[Sync/Orders] Falha crítica: impossível enfileirar pedido', { error: pgErr.message });
                    results.errors.push({ id: order.id, reason: 'Erro interno ao enfileirar pedido (DB Offline)' });
                }
            }
        }

        res.json(results);
    } catch (err) { next(err); }
});

module.exports = router;
