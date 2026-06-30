#!/usr/bin/env node
/**
 * register_company.js — Registra ou atualiza a empresa no PostgreSQL do middleware.
 *
 * Uso:
 *   node scripts/register_company.js "Nome da Empresa" "SUA_API_KEY"
 *
 * Exemplo:
 *   node scripts/register_company.js "Coliseu Sistemas" "Col@13894645"
 *
 * O script calcula o SHA-256 da API Key e insere na tabela companies.
 * Se já existir uma entrada com a mesma api_key, apenas garante que está ativa.
 */
'use strict';

require('dotenv').config();

const { createHash } = require('crypto');
const { Client } = require('pg');

const [, , companyName, apiKeyRaw] = process.argv;

if (!companyName || !apiKeyRaw) {
    console.error('Uso: node scripts/register_company.js "Nome da Empresa" "API_KEY"');
    process.exit(1);
}

const apiKeyHash = createHash('sha256').update(apiKeyRaw, 'utf8').digest('hex');

async function main() {
    const client = new Client({
        host: process.env.PG_HOST || 'localhost',
        port: parseInt(process.env.PG_PORT || '5432', 10),
        database: process.env.PG_DATABASE || 'coliseu_speed',
        user: process.env.PG_USER || 'postgres',
        password: process.env.PG_PASSWORD || '',
        ssl: process.env.PG_SSL === 'true' ? { rejectUnauthorized: false } : false,
    });

    await client.connect();
    console.log('✅ PostgreSQL conectado.');

    // Garante que a migration 004 foi aplicada
    await client.query(`
        ALTER TABLE companies
            ADD COLUMN IF NOT EXISTS fb_host       TEXT,
            ADD COLUMN IF NOT EXISTS fb_port       INTEGER DEFAULT 3050,
            ADD COLUMN IF NOT EXISTS fb_database   TEXT,
            ADD COLUMN IF NOT EXISTS fb_user       TEXT DEFAULT 'SYSDBA',
            ADD COLUMN IF NOT EXISTS fb_password   TEXT,
            ADD COLUMN IF NOT EXISTS fb_charset    TEXT DEFAULT 'WIN1252',
            ADD COLUMN IF NOT EXISTS fb_wire_crypt BOOLEAN DEFAULT FALSE
    `).catch(() => { }); // ignora se as colunas já existem

    const result = await client.query(`
        INSERT INTO companies (name, api_key, active)
        VALUES ($1, $2, TRUE)
        ON CONFLICT (api_key) DO UPDATE
            SET name   = EXCLUDED.name,
                active = TRUE
        RETURNING id, name, active, created_at
    `, [companyName, apiKeyHash]);

    const company = result.rows[0];
    console.log('🏢 Empresa registrada:');
    console.log(`   ID:       ${company.id}`);
    console.log(`   Nome:     ${company.name}`);
    console.log(`   Ativa:    ${company.active}`);
    console.log(`   Criada:   ${company.created_at}`);
    console.log('');
    console.log('🔑 API Key (hash SHA-256):');
    console.log(`   ${apiKeyHash}`);
    console.log('');
    console.log('✅ O Worker agora pode autenticar com essa API Key no middleware.');

    await client.end();
}

main().catch((err) => {
    console.error('❌ Erro:', err.message);
    process.exit(1);
});
