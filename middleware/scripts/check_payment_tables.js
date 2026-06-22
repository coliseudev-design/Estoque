'use strict';
/**
 * check_payment_tables.js — Diagnóstico de tabelas de condição e natureza no Firebird.
 * 
 * Executa: node scripts/check_payment_tables.js
 */
require('dotenv').config({ path: require('path').join(__dirname, '../.env') });

const Firebird = require('node-firebird');

const opts = {
    host: process.env.FB_HOST || 'localhost',
    port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE,
    user: process.env.FB_USER || 'SYSDBA',
    password: process.env.FB_PASSWORD || 'masterkey',
    lowercase_keys: false,
    role: null,
    pageSize: 4096,
};

function q(db, sql) {
    return new Promise((res, rej) => db.query(sql, [], (err, rows) => err ? rej(err) : res(rows)));
}

Firebird.attach(opts, async (err, db) => {
    if (err) { console.error('Conexão falhou:', err.message); process.exit(1); }

    console.log('✅ Conectado ao Firebird:', opts.database);

    // Listando tabelas que contêm "FORMA" ou "PGTO" ou "COND" ou "NATUREZA"
    const tables = await q(db, `
        SELECT TRIM(rdb$relation_name) AS tabname
        FROM rdb$relations
        WHERE rdb$system_flag = 0
          AND (rdb$relation_name LIKE '%FORMA%'
            OR rdb$relation_name LIKE '%PGTO%'  
            OR rdb$relation_name LIKE '%COND%'
            OR rdb$relation_name LIKE '%NATUREZ%'
            OR rdb$relation_name LIKE '%PARCEL%'
            OR rdb$relation_name LIKE '%PRAZO%')
        ORDER BY rdb$relation_name
    `).catch(() => []);

    console.log('\n📋 Tabelas/Views relacionadas a pagamento/natureza:');
    for (const t of tables) {
        // Conta registros em cada tabela
        const cnt = await q(db, `SELECT COUNT(*) AS c FROM "${t.TABNAME || t.tabname}"`).catch(() => [{ c: '?' }]);
        console.log(`  ${(t.TABNAME || t.tabname).padEnd(40)} → ${cnt[0]?.C ?? cnt[0]?.c} registros`);
    }

    // Testar MOB_TABELAFORMASPAGTO especificamente
    console.log('\n🔍 Tentando SELECT em MOB_TABELAFORMASPAGTO:');
    const cond = await q(db, 'SELECT FIRST 3 * FROM MOB_TABELAFORMASPAGTO').catch(e => ({ error: e.message }));
    if (cond.error) {
        console.log('  ❌ Não existe ou erro:', cond.error);
    } else {
        console.log('  ✅ Retornou', cond.length, 'registros (sample):', JSON.stringify(cond[0]));
    }

    // Testar FORMA_PGTO especificamente
    console.log('\n🔍 Tentando SELECT em FORMA_PGTO:');
    const formaPgto = await q(db, 'SELECT FIRST 3 * FROM FORMA_PGTO').catch(e => ({ error: e.message }));
    if (formaPgto.error) {
        console.log('  ❌ Não existe ou erro:', formaPgto.error);
    } else {
        console.log('  ✅ Retornou', formaPgto.length, 'registros (sample):', JSON.stringify(formaPgto[0]));
    }

    // Testar NATUREZA_OPERACAO
    console.log('\n🔍 Tentando SELECT em NATUREZA_OPERACAO:');
    const nat = await q(db, 'SELECT FIRST 3 * FROM NATUREZA_OPERACAO').catch(e => ({ error: e.message }));
    if (nat.error) {
        console.log('  ❌ Não existe ou erro:', nat.error);
    } else {
        console.log('  ✅ Retornou', nat.length, 'registros (sample):', JSON.stringify(nat[0]));
    }

    db.detach();
    console.log('\n✅ Diagnóstico concluído.');
});
