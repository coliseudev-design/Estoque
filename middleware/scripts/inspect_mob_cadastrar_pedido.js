// Inspeciona parâmetros de entrada da SP MOB_CADASTRAR_PEDIDO no Firebird
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');

const options = {
    host: process.env.FB_HOST || 'localhost',
    port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE,
    user: process.env.FB_USER,
    password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252',
    lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',  // true por padrão; false em dev local
};

Firebird.attach(options, (err, db) => {
    if (err) { console.error('Conexão falhou:', err.message); process.exit(1); }

    // Busca parâmetros de INPUT da SP (PARAMETER_TYPE=0)
    const sql = `
        SELECT
            PP.RDB$PARAMETER_NAME   AS PARAM_NAME,
            PP.RDB$PARAMETER_NUMBER AS PARAM_NUM,
            PP.RDB$PARAMETER_TYPE   AS PARAM_TYPE,   -- 0=INPUT, 1=OUTPUT
            F.RDB$FIELD_TYPE        AS FIELD_TYPE,   -- 7=Short, 8=Long, 10=Float, 14=Char, 16=Int64, 37=Varchar, 40=Cstring
            F.RDB$FIELD_LENGTH      AS FIELD_LENGTH,
            F.RDB$FIELD_SCALE       AS FIELD_SCALE
        FROM RDB$PROCEDURE_PARAMETERS PP
        LEFT JOIN RDB$FIELDS F ON F.RDB$FIELD_NAME = PP.RDB$FIELD_SOURCE
        WHERE PP.RDB$PROCEDURE_NAME = 'MOB_CADASTRAR_PEDIDO'
        ORDER BY PP.RDB$PARAMETER_TYPE, PP.RDB$PARAMETER_NUMBER`;

    db.query(sql, [], (e, rows) => {
        if (e) { console.error('Erro na query:', e.message); db.detach(); return; }

        console.log('\n=== Parâmetros de MOB_CADASTRAR_PEDIDO ===\n');

        const FIELD_TYPES = {
            7: 'SMALLINT', 8: 'INTEGER', 10: 'FLOAT', 14: 'CHAR',
            16: 'BIGINT', 37: 'VARCHAR', 40: 'CSTRING', 35: 'TIMESTAMP', 12: 'DATE'
        };

        const inputs = rows.filter(r => r['PARAM_TYPE'] === 0);
        const outputs = rows.filter(r => r['PARAM_TYPE'] === 1);

        console.log('INPUT parameters:');
        inputs.forEach(p => {
            const name = (p['PARAM_NAME'] || '').trim();
            const type = FIELD_TYPES[p['FIELD_TYPE']] || `TYPE${p['FIELD_TYPE']}`;
            const len = p['FIELD_LENGTH'] ? `(${p['FIELD_LENGTH']})` : '';
            console.log(`  [${p['PARAM_NUM']}] ${name} : ${type}${len}`);
        });

        console.log('\nOUTPUT parameters:');
        outputs.forEach(p => {
            const name = (p['PARAM_NAME'] || '').trim();
            const type = FIELD_TYPES[p['FIELD_TYPE']] || `TYPE${p['FIELD_TYPE']}`;
            console.log(`  [${p['PARAM_NUM']}] ${name} : ${type}`);
        });

        // Também verifica MOB_CADASTRAR_PEDIDO_ITEM
        db.query(sql.replace('MOB_CADASTRAR_PEDIDO', 'MOB_CADASTRAR_PEDIDO_ITEM'), [], (e2, rows2) => {
            db.detach();
            if (e2) return;

            console.log('\n=== Parâmetros de MOB_CADASTRAR_PEDIDO_ITEM ===\n');
            const i2 = rows2.filter(r => r['PARAM_TYPE'] === 0);
            const o2 = rows2.filter(r => r['PARAM_TYPE'] === 1);

            console.log('INPUT parameters:');
            i2.forEach(p => {
                const name = (p['PARAM_NAME'] || '').trim();
                const type = FIELD_TYPES[p['FIELD_TYPE']] || `TYPE${p['FIELD_TYPE']}`;
                const len = p['FIELD_LENGTH'] ? `(${p['FIELD_LENGTH']})` : '';
                console.log(`  [${p['PARAM_NUM']}] ${name} : ${type}${len}`);
            });
            console.log('OUTPUT parameters:');
            o2.forEach(p => {
                const name = (p['PARAM_NAME'] || '').trim();
                const type = FIELD_TYPES[p['FIELD_TYPE']] || `TYPE${p['FIELD_TYPE']}`;
                console.log(`  [${p['PARAM_NUM']}] ${name} : ${type}`);
            });
            process.exit(0);
        });
    });
});
