// Inspeciona parâmetros das stored procedures móveis e tabelas necessárias
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
    if (err) { console.error('ERRO:', err.message); process.exit(1); }

    // 1. Parâmetros das procedures MOB
    const sqlProcs = `
        SELECT PP.RDB$PROCEDURE_NAME, PP.RDB$PARAMETER_NAME, PP.RDB$PARAMETER_TYPE,
               PP.RDB$PARAMETER_NUMBER
        FROM RDB$PROCEDURE_PARAMETERS PP
        WHERE PP.RDB$PROCEDURE_NAME IN (
            'MOB_CADASTRAR_PEDIDO', 'MOB_CADASTRAR_PEDIDO_ITEM', 'MOB_CADASTRA_CLIENTE'
        )
        ORDER BY PP.RDB$PROCEDURE_NAME, PP.RDB$PARAMETER_TYPE, PP.RDB$PARAMETER_NUMBER`;

    // 2. Verificar se SALES_ORDERS existe
    const sqlTables = `
        SELECT RDB$RELATION_NAME FROM RDB$RELATIONS
        WHERE RDB$RELATION_NAME IN ('SALES_ORDERS', 'SALES_ORDER_ITEMS', 'VENDEDORES', 'FUNCIONARIOS')
          AND RDB$SYSTEM_FLAG = 0`;

    // 3. Colunas de VENDEDORES (para mapear sellerId)
    const sqlVend = `
        SELECT RF.RDB$FIELD_NAME FROM RDB$RELATION_FIELDS RF
        WHERE RF.RDB$RELATION_NAME = 'VENDEDORES'
        ORDER BY RF.RDB$FIELD_POSITION`;

    db.query(sqlProcs, [], (e1, procs) => {
        db.query(sqlTables, [], (e2, tables) => {
            db.query(sqlVend, [], (e3, vend) => {
                db.detach();

                console.log('\n=== PROCEDURES MOB ===');
                if (e1) console.error('Erro procs:', e1.message);
                else procs.forEach(r => {
                    const dir = r['RDB$PARAMETER_TYPE'] === 0 ? 'IN' : 'OUT';
                    console.log(` [${dir}] ${r['RDB$PROCEDURE_NAME'].trim()} #${r['RDB$PARAMETER_NUMBER']}: ${r['RDB$PARAMETER_NAME'].trim()}`);
                });

                console.log('\n=== TABELAS EXISTENTES ===');
                if (e2) console.error('Erro tables:', e2.message);
                else tables.forEach(r => console.log(' -', r['RDB$RELATION_NAME'].trim()));

                console.log('\n=== Colunas VENDEDORES ===');
                if (e3) console.log('Tabela VENDEDORES nao existe ou erro:', e3?.message);
                else vend.forEach(r => console.log(' -', r['RDB$FIELD_NAME'].trim()));

                process.exit(0);
            });
        });
    });
});
