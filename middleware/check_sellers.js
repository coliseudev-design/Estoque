
'use strict';
const Firebird = require('node-firebird');
const options = {
    host: 'localhost', port: 3050,
    database: 'C:\\Coliseu\\Data\\PIVETA.FDB',
    user: 'SYSDBA', password: 'masterkey',
    lowercase_keys: false, WireCrypt: false,
};

console.log('Conectando ao Firebird...');
Firebird.attach(options, (err, db) => {
    if (err) { console.error('ERRO CONEXÃO:', err.message); process.exit(1); }
    console.log('Conectado!');

    // Total de funcionários
    db.query('SELECT COUNT(*) AS TOTAL FROM FUNCIONARIOS', [], (e1, r1) => {
        console.log('\n=== FUNCIONARIOS ===');
        console.log('Total:', r1?.[0]?.TOTAL ?? r1?.[0]?.['COUNT(*)']);

        // Com MOB_ACESSO=1
        db.query('SELECT COUNT(*) AS TOTAL FROM FUNCIONARIOS WHERE MOB_ACESSO = 1', [], (e2, r2) => {
            console.log('Com MOB_ACESSO=1:', r2?.[0]?.TOTAL ?? r2?.[0]?.['COUNT(*)']);

            // Listagem
            db.query('SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, MOB_SENHA FROM FUNCIONARIOS WHERE MOB_ACESSO IS NOT NULL ORDER BY NOME ROWS 10', [], (e3, r3) => {
                console.log('\nFuncionários (top 10 com MOB_ACESSO definido):');
                r3?.forEach(r => console.log(`  ID=${r.ID_FUNCIONARIO} | ${r.NOME?.trim()} | MOB_ACESSO=${r.MOB_ACESSO} | SENHA=${r.MOB_SENHA ? '***' : 'VAZIA'}`));
                db.detach();
            });
        });
    });
});
