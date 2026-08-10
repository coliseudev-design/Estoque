'use strict';

const { Pool } = require('pg');
const config = require('../config/env');
const logger = require('../config/logger');

// PostgreSQL Pool for AutoCenter
const pool = new Pool({
    host: config.postgres.host,
    port: config.postgres.port,
    database: config.postgres.database,
    user: config.postgres.user,
    password: config.postgres.password,
    ssl: config.postgres.ssl ? { rejectUnauthorized: false } : false,
    max: 20, // Max number of clients
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
    logger.error('[DB] Erro inesperado em cliente ocioso do PostgreSQL', err);
});

/**
 * Executa uma query no PostgreSQL.
 * @param {string} text - Query SQL
 * @param {any[]} params - Parâmetros
 * @returns {Promise<import('pg').QueryResult<any>>}
 */
async function query(text, params) {
    const start = Date.now();
    try {
        const res = await pool.query(text, params);
        const duration = Date.now() - start;
        logger.debug('[DB] Executed query', { text: text.substring(0, 100), duration, rows: res.rowCount });
        return res;
    } catch (err) {
        logger.error('[DB] Falha ao executar query', { text: text.substring(0, 100), error: err.message });
        throw err;
    }
}

/**
 * Usado para inicialização e checagem de saúde.
 */
async function checkConnection() {
    try {
        await query('SELECT 1 AS ok', []);
        logger.info('[DB] Conectado ao PostgreSQL (AutoCenter_DB)');
        return true;
    } catch (err) {
        logger.error('[DB] Falha ao conectar ao PostgreSQL', { error: err.message });
        return false;
    }
}

/**
 * Executa todas as migrations de forma idempotente.
 */
async function runMigrations() {
    const fs = require('fs');
    const path = require('path');
    
    try {
        const migrationsDir = path.join(__dirname, 'migrations');
        if (!fs.existsSync(migrationsDir)) {
            logger.warn('[DB] Diretório de migrations não encontrado:', migrationsDir);
            return;
        }

        const files = fs.readdirSync(migrationsDir)
            .filter(file => file.endsWith('.sql'))
            .sort();

        logger.info(`[DB] Encontradas ${files.length} migrations. Iniciando execução...`);

        for (const file of files) {
            const filePath = path.join(migrationsDir, file);
            const sql = fs.readFileSync(filePath, 'utf8');
            logger.info(`[DB] Executando migration: ${file}`);
            await pool.query(sql);
        }
        logger.info('[DB] Todas as migrations foram executadas com sucesso.');
    } catch (err) {
        logger.error('[DB] Falha crítica ao executar migrations', { error: err.message });
        throw err;
    }
}

module.exports = {
    query,
    pool,
    checkConnection,
    runMigrations
};
