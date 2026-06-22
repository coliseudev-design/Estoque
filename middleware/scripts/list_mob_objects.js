// Lista todas as views/tabelas MOB_ existentes no banco
// Útil para validar o banco antes de configurar o Worker
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
    if (err) { console.error('[ERRO] Não foi possível conectar ao banco:', err.message); process.exit(1); }
    console.log(`\nConectado a: ${options.host}:${options.port}/${options.database}\n`);

    // Lista todas as views e tabelas que começam com MOB_
    db.query(
        `SELECT RDB$RELATION_NAME, RDB$RELATION_TYPE
         FROM RDB$RELATIONS
         WHERE RDB$RELATION_NAME LIKE 'MOB%' AND RDB$SYSTEM_FLAG = 0
         ORDER BY RDB$RELATION_TYPE, RDB$RELATION_NAME`,
        [],
        (e, rows) => {
            if (e) { console.error(e.message); db.detach(); return; }
            console.log('=== Objetos MOB_ no banco ===');
            if (rows.length === 0) {
                console.log('  (nenhum encontrado — banco pode ser diferente do ERP Coliseu)');
            }
            rows.forEach(r => {
                const tipo = r['RDB$RELATION_TYPE'] === 0 ? 'TABLE' : 'VIEW';
                console.log(` [${tipo}] ${r['RDB$RELATION_NAME'].trim()}`);
            });

            // Verifica tabelas base necessárias para o Worker .NET
            const required = [
                'FUNCIONARIOS', 'PRODUTOS', 'PRODUTO_PRECOS',
                'NATUREZA_OPERACAO', 'ESPECIE_PGTO',
                'PEDIDOS', 'SALES_ORDERS', 'SYNC_ORDERS',  // SYNC_ORDERS via DDL 002
            ];
            db.query(
                `SELECT RDB$RELATION_NAME FROM RDB$RELATIONS
                 WHERE RDB$RELATION_NAME IN (${required.map(() => '?').join(',')})
                   AND RDB$SYSTEM_FLAG = 0
                 ORDER BY RDB$RELATION_NAME`,
                required,
                (e2, rows2) => {
                    db.detach();
                    const found = rows2?.map(r => r['RDB$RELATION_NAME'].trim()) ?? [];
                    const missing = required.filter(t => !found.includes(t));

                    console.log('\n=== Tabelas necessárias para o Worker ===');
                    required.forEach(t => {
                        const ok = found.includes(t);
                        console.log(` ${ok ? '✓' : '✗'} ${t}${!ok ? ' ← AUSENTE' : ''}`);
                    });

                    if (missing.length > 0) {
                        console.log('\n⚠ Tabelas ausentes:', missing.join(', '));
                        console.log('  Execute middleware/sql/001_create_base_tables.sql para criar SALES_ORDERS.');
                        console.log('  As demais devem existir no ERP Coliseu — verifique o banco.');
                    } else {
                        console.log('\n✓ Todas as tabelas necessárias foram encontradas!');
                    }

                    if (e2) console.error('Erro ao verificar tabelas:', e2.message);
                    process.exit(0);
                }
            );
        }
    );
});
