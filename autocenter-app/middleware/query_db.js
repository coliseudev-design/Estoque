'use strict';

const { Pool } = require('pg');

const pool = new Pool({
    host: 'localhost',
    port: 5432,
    database: 'autocenter_db',
    user: 'postgres',
    password: '',
});

async function main() {
    try {
        console.log('Connecting as postgres user...');
        const dbs = await pool.query('SELECT datname FROM pg_database');
        console.log('Available databases:', dbs.rows.map(r => r.datname));
        
        // Let's connect to autocenter_db and see if it exists
        const tableCols = await pool.query(`
            SELECT column_name, data_type 
            FROM information_schema.columns 
            WHERE table_name = 'service_orders'
        `).catch(e => e.message);
        console.log('service_orders columns:', tableCols.rows || tableCols);
    } catch (err) {
        console.error('Error:', err);
    } finally {
        await pool.end();
    }
}

main();
