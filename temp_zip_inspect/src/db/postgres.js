/**
 * postgres.js — Pool de conexão PostgreSQL para o middleware multi-tenant.
 *
 * Cada empresa usa o mesmo banco PostgreSQL, isolada por company_id em cada tabela.
 * Row-Level Security (RLS) garante isolamento mesmo se uma query esquecer o filtro.
 *
 * Variáveis de ambiente necessárias:
 *   PG_HOST      (default: localhost)
 *   PG_PORT      (default: 5432)
 *   PG_DATABASE  (default: coliseu_sales)
 *   PG_USER      (default: postgres)
 *   PG_PASSWORD  (obrigatório em produção)
 *   PG_SSL       (default: false — use true em produção)
 *
 * @module db/postgres
 */
'use strict';

const { Pool } = require('pg');
const logger = require('../config/logger');

const pool = new Pool({
    host: process.env.PG_HOST || 'localhost',
    port: Number(process.env.PG_PORT || 5432),
    database: process.env.PG_DATABASE || 'coliseu_sales',
    user: process.env.PG_USER || 'postgres',
    password: process.env.PG_PASSWORD || '',
    ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    // statement_timeout: impede qualquer query de travar o pool por mais de 8s
    // Isso evita que queries lentas de autenticação bloqueiem os requests do Worker
    statement_timeout: 8_000,
});

// ── Diagnóstico de startup ──────────────────────────────────────────────────
// Loga configuração mascarada para debugging sem expor credenciais (Rule-04)
const pgPass = process.env.PG_PASSWORD || '';
const maskedPgPass = pgPass.length > 0
    ? pgPass.slice(0, 4) + '*'.repeat(Math.max(pgPass.length - 4, 0)) + ` (${pgPass.length} chars)`
    : '(empty!)';
logger.info('[PostgreSQL] Config', {
    host: process.env.PG_HOST || 'localhost',
    port: process.env.PG_PORT || '5432',
    database: process.env.PG_DATABASE || 'coliseu_sales',
    user: process.env.PG_USER || 'postgres',
    password: maskedPgPass,
});

pool.on('error', (err) => {
    logger.error('[PostgreSQL] Erro no pool de conexões', { error: err.message });
});

/**
 * Executa uma query SQL parametrizada.
 *
 * @param {string}  sql    Query SQL com placeholders $1, $2, ...
 * @param {Array}   [params]  Parâmetros posicionais
 * @returns {Promise<import('pg').QueryResult>}
 *
 * @example
 *   const { rows } = await pgQuery(
 *     'SELECT * FROM orders WHERE company_id = $1',
 *     [companyId]
 *   );
 */
async function pgQuery(sql, params = []) {
    const client = await pool.connect();
    try {
        return await client.query(sql, params);
    } finally {
        client.release();
    }
}

/**
 * Executa uma query com timeout explícito de aplicação (fallback de segurança).
 * Usa Promise.race para garantir que a query nunca bloqueie mais de `timeoutMs`.
 *
 * @param {string}  sql
 * @param {Array}   params
 * @param {number}  [timeoutMs]  — default: 8000ms
 */
async function pgQuerySafe(sql, params = [], timeoutMs = 8_000) {
    const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error(`pgQuery timeout após ${timeoutMs}ms`)), timeoutMs)
    );
    return Promise.race([pgQuery(sql, params), timeoutPromise]);
}

/**
 * Verifica se o banco está acessível (para health check).
 * @returns {Promise<boolean>}
 */
async function pgPing() {
    try {
        await pgQuery('SELECT 1');
        return true;
    } catch {
        return false;
    }
}

module.exports = { pool, pgQuery, pgQuerySafe, pgPing };
