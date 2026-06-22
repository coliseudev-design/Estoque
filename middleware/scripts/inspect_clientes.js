// Busca onde o campo CELULAR fica no Firebird
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const options = {
    host: process.env.FB_HOST || 'localhost', port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE, user: process.env.FB_USER, password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',
};
Firebird.attach(options, (err, db) => {
    if (err) { console.error(err.message); process.exit(1); }

    // 1) Onde existe CELULAR como coluna base (tabelas reais, não views)
    db.query(`
        SELECT DISTINCT TRIM(RF.RDB$RELATION_NAME) AS tabela, TRIM(RF.RDB$FIELD_NAME) AS campo
        FROM RDB$RELATION_FIELDS RF
        INNER JOIN RDB$RELATIONS R ON R.RDB$RELATION_NAME = RF.RDB$RELATION_NAME
        WHERE RF.RDB$FIELD_NAME CONTAINING 'CELULAR'
          AND R.RDB$RELATION_TYPE = 0
        ORDER BY RF.RDB$RELATION_NAME`, [], (e, rows) => {
        console.log('\n=== TABELAS com CELULAR ===');
        if (e) console.error(e.message);
        else rows.forEach(r => console.log(` [${r.TABELA}] ${r.CAMPO}`));

        // 2) Lê o CLIENTES_DADOS do cliente 5735 para ver o que foi gravado
        db.query(`SELECT * FROM CLIENTES_DADOS WHERE ID_CLIENTE = 5735`, [], (e2, r2) => {
            console.log('\n=== CLIENTES_DADOS: cliente 5735 ===');
            if (e2) console.error(e2.message);
            else if (r2 && r2.length) {
                for (const [k, v] of Object.entries(r2[0])) {
                    if (v !== null && v !== undefined) console.log(` ${k}: ${v}`);
                }
            } else console.log('Sem dados');
            db.detach(); process.exit(0);
        });
    });
});
