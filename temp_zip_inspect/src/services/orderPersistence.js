/**
 * orderPersistence.js — Persistência do orderIndex em SQLite.
 *
 * Problema resolvido: o `dataStore.js` usa um Map em memória para o orderIndex.
 * Quando o middleware reinicia, todos os status são perdidos — o Flutter nunca
 * recebe o `erpOrderId` de pedidos já confirmados pelo Worker.
 *
 * Solução: ao inicializar, hidratar o Map a partir de um banco SQLite local.
 * Todas as mutações (indexOrder, confirmOrder, errorOrder) também persistem.
 *
 * O arquivo do banco é: ./data/orders.sqlite3
 * (criado automaticamente se não existir)
 *
 * NOTA: usamos `better-sqlite3` (síncrono) porque:
 *  1. O dataStore.js já é síncrono
 *  2. SQLite local não tem latência de rede
 *  3. Evitamos complexidade de promessas em helpers que são chamados em contexto síncrono
 *
 * @module services/orderPersistence
 */
'use strict';

const path = require('path');
const fs = require('fs');
const logger = require('../config/logger');

// ── Lazy load de better-sqlite3 ───────────────────────────────────────────────
// Se o módulo não estiver instalado, cai no modo NO-OP com aviso.

let db = null;

function initDb() {
    if (db) return db;

    try {
        const Database = require('better-sqlite3');
        const dataDir = path.join(__dirname, '..', '..', 'data');
        if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

        const dbPath = path.join(dataDir, 'orders.sqlite3');
        db = new Database(dbPath);

        db.pragma('journal_mode = WAL');  // Write-Ahead Logging — melhor concorrência

        db.exec(`
            CREATE TABLE IF NOT EXISTS order_index (
                id            TEXT PRIMARY KEY,
                status        TEXT NOT NULL DEFAULT 'pending',
                erp_order_id  TEXT,
                error_message TEXT,
                customer_name TEXT,
                seller_name   TEXT,
                total_amount  REAL DEFAULT 0,
                created_at    TEXT,
                updated_at    TEXT NOT NULL
            )
        `);

        logger.info('[OrderPersistence] SQLite inicializado', { path: dbPath });
        return db;
    } catch (err) {
        logger.warn('[OrderPersistence] better-sqlite3 não disponível — modo NO-OP (in-memory apenas)', {
            hint: 'Execute: npm install better-sqlite3',
            error: err.message,
        });
        return null;
    }
}

// ── API pública ───────────────────────────────────────────────────────────────

/**
 * Hidrata um Map com todos os registros salvos no SQLite.
 * Chamado uma vez na inicialização do dataStore.
 * @param {Map} orderIndex — o Map do dataStore a ser hidratado
 */
function hydrate(orderIndex) {
    const database = initDb();
    if (!database) return;

    try {
        const rows = database.prepare('SELECT * FROM order_index').all();
        for (const row of rows) {
            orderIndex.set(row.id, {
                status: row.status,
                erpOrderId: row.erp_order_id,
                errorMessage: row.error_message,
                customerName: row.customer_name,
                sellerName: row.seller_name,
                totalAmount: row.total_amount,
                createdAt: row.created_at,
                updatedAt: row.updated_at,
            });
        }
        logger.info('[OrderPersistence] Hidrataçao concluída', { count: rows.length });
    } catch (err) {
        logger.error('[OrderPersistence] Falha ao hidratar', { error: err.message });
    }
}

/**
 * Persiste um novo pedido no SQLite com status 'pending'.
 * @param {string} id UUID do pedido
 * @param {object} meta Metadata { customerName, sellerName, totalAmount, createdAt }
 */
function persistIndex(id, meta = {}) {
    const database = initDb();
    if (!database) return;
    try {
        const now = new Date().toISOString();
        database.prepare(`
            INSERT OR REPLACE INTO order_index
              (id, status, erp_order_id, error_message, customer_name, seller_name, total_amount, created_at, updated_at)
            VALUES (?, 'pending', NULL, NULL, ?, ?, ?, ?, ?)
        `).run(id, meta.customerName ?? null, meta.sellerName ?? null,
            meta.totalAmount ?? 0, meta.createdAt ?? now, now);
    } catch (err) {
        logger.error('[OrderPersistence] Falha ao persistir pedido', { id, error: err.message });
    }
}

/**
 * Persiste confirmação do Worker (status = 'synced', erpOrderId preenchido).
 * @param {string} id
 * @param {string} erpOrderId
 */
function persistConfirm(id, erpOrderId) {
    const database = initDb();
    if (!database) return;
    try {
        database.prepare(`
            UPDATE order_index SET status = 'synced', erp_order_id = ?, updated_at = ? WHERE id = ?
        `).run(String(erpOrderId), new Date().toISOString(), id);
    } catch (err) {
        logger.error('[OrderPersistence] Falha ao confirmar pedido', { id, error: err.message });
    }
}

/**
 * Persiste erro do Worker (status = 'error', errorMessage preenchido).
 * @param {string} id
 * @param {string} errorMessage
 */
function persistError(id, errorMessage) {
    const database = initDb();
    if (!database) return;
    try {
        database.prepare(`
            UPDATE order_index SET status = 'error', error_message = ?, updated_at = ? WHERE id = ?
        `).run(errorMessage, new Date().toISOString(), id);
    } catch (err) {
        logger.error('[OrderPersistence] Falha ao registrar erro do pedido', { id, error: err.message });
    }
}

module.exports = { hydrate, persistIndex, persistConfirm, persistError };
