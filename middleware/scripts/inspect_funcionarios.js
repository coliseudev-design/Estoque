// Inspeciona colunas de FUNCIONARIOS para mapear sellerId correto
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const options = {
    host: process.env.FB_HOST || 'localhost', port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE, user: process.env.FB_USER, password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',  // true por padrão; false em dev local
};
Firebird.attach(options, (err, db) => {
    if (err) { console.error(err.message); process.exit(1); }
    db.query(`SELECT RF.RDB$FIELD_NAME FROM RDB$RELATION_FIELDS RF
              WHERE RF.RDB$RELATION_NAME = 'FUNCIONARIOS' ORDER BY RF.RDB$FIELD_POSITION`,
        [], (e, rows) => {
            db.detach();
            console.log('\n=== Colunas FUNCIONARIOS ===');
            rows?.forEach(r => console.log(' -', r['RDB$FIELD_NAME'].trim()));
            process.exit(0);
        });
});
