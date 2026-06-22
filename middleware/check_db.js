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
    console.log('Conectado ao Postgres!');

    try {
        const resCompanies = await client.query('SELECT * FROM companies');
        console.log('\n=== COMPANIES ===');
        console.log(resCompanies.rows);

        const resBranches = await client.query('SELECT * FROM branches');
        console.log('\n=== BRANCHES ===');
        console.log(resBranches.rows);
    } catch (e) {
        console.error('ERRO:', e);
    } finally {
        await client.end();
    }
}

run();
