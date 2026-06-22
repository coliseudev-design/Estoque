// Inspeciona colunas de MOB_PRODUTOS, MOB_LISTACONTAS, MOB_LISTAESTOQUE, FUNCIONARIOS e ESPECIE_PGTO
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const options = {
    host: process.env.FB_HOST || 'localhost', port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE, user: process.env.FB_USER, password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',  // true por padrão; false em dev local
};

const tables = ['MOB_PRODUTOS', 'MOB_LISTACONTAS', 'MOB_LISTAESTOQUE', 'FUNCIONARIOS', 'ESPECIE_PGTO', 'MOBILE'];

Firebird.attach(options, (err, db) => {
    if (err) { console.error(err.message); process.exit(1); }
    let i = 0;
    function next() {
        if (i >= tables.length) { db.detach(); process.exit(0); }
        const tbl = tables[i++];
        db.query(
            `SELECT RF.RDB$FIELD_NAME FROM RDB$RELATION_FIELDS RF
             WHERE RF.RDB$RELATION_NAME = ? ORDER BY RF.RDB$FIELD_POSITION`,
            [tbl],
            (e, rows) => {
                if (e || !rows) {
                    console.log(`\n❌ ${tbl}: ${e?.message}`);
                } else {
                    console.log(`\n=== ${tbl} ===`);
                    rows.forEach(r => console.log(' -', r['RDB$FIELD_NAME'].trim()));
                }
                next();
            }
        );
    }
    next();
});
