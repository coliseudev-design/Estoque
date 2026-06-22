'use strict';
const { Client } = require('pg');

const client = new Client({
    host: 'localhost',
    port: 5432,
    database: 'coliseu_sales',
    user: 'postgres',
    password: '',
});

async function run() {
    await client.connect();
    try {
        const res = await client.query('SELECT id, company_id, branch_id, sync_status, erp_order_id, error_message, total_amount, created_at FROM orders ORDER BY created_at DESC LIMIT 10');
        console.log('\n=== RECENT ORDERS ===');
        console.table(res.rows);
    } catch (e) {
        console.error('ERRO:', e);
    } finally {
        await client.end();
    }
}

run();
