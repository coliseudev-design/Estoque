/**
 * migrate.js — Runner de migrations SQL versionado (P1-A).
 *
 * Melhorias vs versão anterior:
 *   - Tabela `schema_migrations` controla quais migrations já foram aplicadas
 *   - Checksum SHA-256: detecta se o arquivo SQL foi alterado após ser aplicado
 *   - Idempotência real: só executa migrations novas
 *   - Rollback automático: cada migration roda em transaction separada
 *
 * @module db/migrate
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { pool } = require('./postgres');
const logger = require('../config/logger');

const SQL_DIR = path.join(__dirname, '..', '..', 'sql');

const MIGRATIONS = [
    // 001_companies.sql REMOVIDO — a tabela `companies` é gerenciada pelo
    // EF Core da Identity API (schema PascalCase: "CompanyKeyHash", "Status", etc).
    // O middleware apenas LEIA essa tabela via auth.js findCompanyByKeyHash().
    '002_orders.sql',
    '003_improvements.sql',
    // 004_firebird_config.sql REMOVIDO — colunas Firebird (FirebirdHost, etc)
    // já existem no schema EF Core da Identity API.
    // 005-007 já aplicadas em produção
    '008_orders_payload.sql',  // Adiciona payload JSONB para o Worker processar pedidos completos
];

/**
 * Calcula SHA-256 de uma string.
 * @param {string} content
 * @returns {string} hex digest
 */
function checksum(content) {
    return crypto.createHash('sha256').update(content, 'utf8').digest('hex');
}

/**
 * Garante que a tabela schema_migrations existe (bootstrap).
 * @param {import('pg').PoolClient} client
 */
async function ensureMigrationsTable(client) {
    await client.query(`
        CREATE TABLE IF NOT EXISTS schema_migrations (
            filename   TEXT        PRIMARY KEY,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            checksum   TEXT        NOT NULL
        )
    `);
}

/**
 * Executa todas as migrations na ordem definida.
 * Migrations já aplicadas são puladas (verifica `schema_migrations`).
 * Migrations alteradas geram WARNING (não bloqueiam — apenas alerta).
 */
async function runMigrations() {
    logger.info('[Migrate] Verificando migrations PostgreSQL...');

    const client = await pool.connect();
    try {
        await ensureMigrationsTable(client);

        // Carrega migrations já aplicadas
        const { rows: applied } = await client.query('SELECT filename, checksum FROM schema_migrations');
        const appliedMap = new Map(applied.map(r => [r.filename, r.checksum]));

        let ran = 0;
        let skipped = 0;

        for (const file of MIGRATIONS) {
            const sqlPath = path.join(SQL_DIR, file);

            if (!fs.existsSync(sqlPath)) {
                logger.warn(`[Migrate] Arquivo não encontrado: ${file} — pulando.`);
                skipped++;
                continue;
            }

            const sql = fs.readFileSync(sqlPath, 'utf8');
            const hash = checksum(sql);

            if (appliedMap.has(file)) {
                if (appliedMap.get(file) !== hash) {
                    logger.warn(`[Migrate] ⚠ ${file} foi modificado após aplicação — verifique se precisa de uma nova migration.`);
                }
                skipped++;
                continue;
            }

            // Roda em transaction isolada
            try {
                await client.query('BEGIN');
                await client.query(sql);
                await client.query(
                    'INSERT INTO schema_migrations (filename, checksum) VALUES ($1, $2)',
                    [file, hash]
                );
                await client.query('COMMIT');
                logger.info(`[Migrate] ✓ ${file}`);
                ran++;
            } catch (err) {
                await client.query('ROLLBACK');
                logger.error(`[Migrate] ✗ Falha em ${file}`, { error: err.message });
                throw err;
            }
        }

        logger.info(`[Migrate] Concluído. ${ran} aplicadas, ${skipped} puladas.`);
    } finally {
        client.release();
    }
}

/**
 * Auto-registra a empresa padrão usando COMPANY_NAME + API_KEY do .env.
 *
 * Executado uma vez após as migrations, idempotente (ON CONFLICT DO NOTHING).
 * Permite que o Worker autentique sem necessidade de SSH/SQL manual no VPS.
 *
 * IMPORTANTE: o hash usa `.trim().toUpperCase()` antes do SHA-256,
 * alinhado com o mesmo padrão de `auth.js` (sha256hex) e com o
 * CompanyKeyGenerator.cs da Identity API.
 * SHA256("rawKey".Trim().ToUpperInvariant())
 */
async function seedDefaultCompany() {
    const apiKeyRaw = process.env.API_KEY;
    const companyName = process.env.COMPANY_NAME || 'Empresa Padrão';
    // COMPANY_ID pode ser um UUID fixo para tornar o seed determinístico.
    // Se não definido, PostgreSQL gera automaticamente via gen_random_uuid().
    const companyId = process.env.COMPANY_ID || null;

    if (!apiKeyRaw) {
        logger.warn('[Migrate] API_KEY não definido — empresa padrão não será criada.');
        return;
    }

    // Canonicaliza a chave antes do hash: trim + UPPER — DEVE bater com auth.js sha256hex()
    const normalized = apiKeyRaw.trim().toUpperCase();
    const keyHash = crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');

    const client = await pool.connect();
    try {
        // Monta query com COMPANY_ID como parâmetro ($3) para evitar interpolação insegura.
        // Se COMPANY_ID não for definido, o PG usa gen_random_uuid() via COALESCE.
        const params = [companyName, keyHash];
        let idExpr;
        if (companyId) {
            params.push(companyId);   // $3 — passado como parâmetro, nunca interpolado
            idExpr = `$${params.length}::uuid`;
        } else {
            idExpr = 'gen_random_uuid()';
        }

        const { rows } = await client.query(
            `INSERT INTO companies
                 ("Id", "Name", "CompanyKeyHash", "Status", "CreatedAt", "DeviceLimit",
                  "FirebirdHost", "FirebirdDatabasePath", "FirebirdUser", "FirebirdPasswordEncrypted")
             VALUES
                 (${idExpr}, $1, $2, 0, NOW(), 10,
                  'localhost', 'C:/Coliseu/Data/EMPRESA.FDB', 'SYSDBA', 'placeholder-update-from-admin')
             ON CONFLICT ("CompanyKeyHash") DO NOTHING
             RETURNING "Id" AS id, "Name" AS name`,
            params
        );

        if (rows.length > 0) {
            logger.info('[Migrate] ✓ Empresa registrada automaticamente no banco Identity', {
                id: rows[0].id,
                name: rows[0].name,
            });
        } else {
            logger.info('[Migrate] Empresa já existente (CompanyKeyHash já registrado) — nenhuma ação.');
        }
    } catch (err) {
        // Loga o erro com stack para facilitar diagnóstico — não é mais silencioso
        logger.error('[Migrate] ✗ Falha ao registrar empresa padrão', {
            error: err.message,
            hint: 'Verifique se as colunas EF Core ("CompanyKeyHash", "Status", etc.) existem na tabela companies.',
        });
    } finally {
        client.release();
    }
}

module.exports = { runMigrations, seedDefaultCompany };
