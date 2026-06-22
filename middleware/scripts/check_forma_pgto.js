'use strict';
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
const Firebird = require('node-firebird');

const opts = {
    host: process.env.FB_HOST || 'localhost',
    port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE,
    user: process.env.FB_USER || 'SYSDBA',
    password: process.env.FB_PASSWORD || 'masterkey',
    lowercase_keys: false,
};

function q(db, sql, params) {
    return new Promise((res, rej) => db.query(sql, params || [], (err, rows) => err ? rej(err) : res(rows)));
}

Firebird.attach(opts, async (err, db) => {
    if (err) { console.error('Erro:', err.message); process.exit(1); }

    // Colunas da FORMA_PGTO
    console.log('\n📋 Colunas de FORMA_PGTO:');
    const cols = await q(db, `
        SELECT TRIM(rf.rdb$field_name) as col_name
        FROM rdb$relation_fields rf
        WHERE TRIM(rf.rdb$relation_name) = 'FORMA_PGTO'
        ORDER BY rf.rdb$field_position`);
    cols.forEach(c => console.log(' ', c.COL_NAME || c.col_name));

    // Primeiros 5 registros
    console.log('\n📊 Primeiros 5 registros de FORMA_PGTO:');
    const rows = await q(db, 'SELECT FIRST 5 * FROM FORMA_PGTO');
    rows.forEach(r => console.log(JSON.stringify(r)));

    db.detach();
});
