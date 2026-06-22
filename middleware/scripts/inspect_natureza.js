// Inspeciona colunas de tabelas relacionadas a Natureza de Operação no Firebird
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

    // 1. Busca tabelas com "NATUR" no nome
    db.query(
        `SELECT DISTINCT RF.RDB$RELATION_NAME FROM RDB$RELATION_FIELDS RF
         WHERE RF.RDB$RELATION_NAME NOT STARTING WITH 'RDB$'
         AND (RF.RDB$RELATION_NAME LIKE '%NATUR%' OR RF.RDB$RELATION_NAME LIKE '%NAT_OP%'
              OR RF.RDB$RELATION_NAME LIKE '%OPERAC%')
         ORDER BY 1`,
        [],
        (e, rows) => {
            console.log('\n=== Tabelas com NATUR/OPERAC ===');
            (rows || []).forEach(r => console.log(' -', r['RDB$RELATION_NAME'].trim()));

            // 2. Inspeciona colunas de NATUREZA_OPERACAO (nome mais provável)
            const candidates = ['NATUREZA_OPERACAO', 'NAT_OPERACAO', 'NATUREZA_OP', 'NATUREZAS', 'NAT_OPER'];
            let i = 0;
            function inspect() {
                if (i >= candidates.length) { db.detach(); process.exit(0); }
                const tbl = candidates[i++];
                db.query(`SELECT RF.RDB$FIELD_NAME FROM RDB$RELATION_FIELDS RF WHERE RF.RDB$RELATION_NAME = ? ORDER BY RF.RDB$FIELD_POSITION`, [tbl], (e2, rows2) => {
                    if (!e2 && rows2 && rows2.length > 0) {
                        console.log(`\n=== ${tbl} ===`);
                        rows2.forEach(r => console.log(' -', r['RDB$FIELD_NAME'].trim()));
                    }
                    inspect();
                });
            }
            inspect();
        }
    );
});
