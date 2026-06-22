// Testa cada endpoint individualmente e imprime o erro real
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const options = {
    host: process.env.FB_HOST || 'localhost', port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE, user: process.env.FB_USER, password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',  // true por padrão; false em dev local
};

const queries = {
    'MOB_TABELAPRODUTOS2': 'SELECT FIRST 1 * FROM MOB_TABELAPRODUTOS2',
    'MOB_LISTACLIENTES': 'SELECT FIRST 1 * FROM MOB_LISTACLIENTES',
    'FUNCIONARIOS MOB': 'SELECT FIRST 1 * FROM FUNCIONARIOS WHERE MOB_ACESSO = 1',
    'MOB_TABELAFORMASPAGTO': 'SELECT FIRST 1 * FROM MOB_TABELAFORMASPAGTO',
    'ESPECIE_PGTO MOB': 'SELECT FIRST 1 * FROM ESPECIE_PGTO WHERE MOB_ACESSO = 1',
    'LISTACONTAS': 'SELECT FIRST 1 * FROM LISTACONTAS',
};

Firebird.attach(options, (err, db) => {
    if (err) { console.error('Conexão:', err.message); process.exit(1); }
    const names = Object.keys(queries);
    let i = 0;
    function next() {
        if (i >= names.length) { db.detach(); return; }
        const name = names[i++];
        db.query(queries[name], [], (e, rows) => {
            if (e) {
                console.log(`❌ ${name}: ${e.message}`);
            } else {
                const cols = rows.length > 0 ? Object.keys(rows[0]).join(', ') : '(vazio)';
                console.log(`✅ ${name}: ${rows.length} rows | cols: ${cols}`);
            }
            next();
        });
    }
    next();
});
