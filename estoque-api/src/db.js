/**
 * Pool PostgreSQL, helper de transação e runner de migrations versionadas.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const config = require('./config');
const log = require('./log');

const pool = new Pool({
    ...(config.pg.connectionString
        ? { connectionString: config.pg.connectionString }
        : {
            host: config.pg.host,
            port: config.pg.port,
            database: config.pg.database,
            user: config.pg.user,
            password: config.pg.password,
        }),
    ssl: config.pg.ssl,
    max: config.pg.max,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    statement_timeout: 30_000,
});

pool.on('error', (err) => log.error('[PG] erro no pool', { error: err.message }));

const query = (sql, params) => pool.query(sql, params);

/** Executa `fn(client)` dentro de BEGIN/COMMIT, com ROLLBACK em erro. */
async function tx(fn) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const result = await fn(client);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

const SQL_DIR = path.join(__dirname, '..', 'sql');

/** Aplica, em ordem, os arquivos sql/NNN_*.sql ainda não aplicados. */
async function migrate() {
    const client = await pool.connect();
    try {
        // Lock consultivo: duas instâncias subindo juntas não aplicam a mesma migration.
        await client.query('SELECT pg_advisory_lock(727001)');
        await client.query(`
            CREATE TABLE IF NOT EXISTS schema_migrations (
                filename   TEXT PRIMARY KEY,
                checksum   TEXT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )`);
        const { rows } = await client.query('SELECT filename, checksum FROM schema_migrations');
        const applied = new Map(rows.map((r) => [r.filename, r.checksum]));

        const files = fs.readdirSync(SQL_DIR).filter((f) => /^\d{3}_.+\.sql$/.test(f)).sort();
        for (const file of files) {
            const sql = fs.readFileSync(path.join(SQL_DIR, file), 'utf8');
            const sum = crypto.createHash('sha256').update(sql).digest('hex');
            if (applied.has(file)) {
                if (applied.get(file) !== sum) log.warn('[Migrate] arquivo alterado após aplicado', { file });
                continue;
            }
            await client.query('BEGIN');
            try {
                await client.query(sql);
                await client.query('INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)', [file, sum]);
                await client.query('COMMIT');
                log.info('[Migrate] aplicada', { file });
            } catch (err) {
                await client.query('ROLLBACK');
                throw new Error(`[Migrate] falha em ${file}: ${err.message}`);
            }
        }
    } finally {
        await client.query('SELECT pg_advisory_unlock(727001)').catch(() => {});
        client.release();
    }
}

module.exports = { pool, query, tx, migrate };
