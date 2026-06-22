/**
 * inspect_table.js — Inspeciona colunas de qualquer tabela do PIVETA.FDB
 *
 * Uso: node scripts/inspect_table.js <NOME_TABELA>
 * Ex:  node scripts/inspect_table.js CLIENTES
 *      node scripts/inspect_table.js NATUREZA_OPERACAO
 *      node scripts/inspect_table.js MOB_LISTACLIENTES
 *
 * Substitui inspect_clientes.js (hardcoded) com versão universal.
 */
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');

const tableName = (process.argv[2] || '').toUpperCase().trim();
if (!tableName) {
    console.error('Uso: node scripts/inspect_table.js <NOME_TABELA>');
    console.error('Ex:  node scripts/inspect_table.js CLIENTES');
    process.exit(1);
}

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
    if (err) {
        console.error('[ERRO] Conexão falhou:', err.message);
        process.exit(1);
    }
    console.log(`\nConectado a: ${options.host}:${options.port}/${options.database}`);
    console.log(`\n=== Colunas de ${tableName} ===\n`);

    // Metadados de colunas + tipo Firebird
    const sql = `
        SELECT
          RF.RDB$FIELD_NAME                     AS COL_NAME,
          F.RDB$FIELD_TYPE                      AS FIELD_TYPE,
          F.RDB$FIELD_LENGTH                    AS FIELD_LENGTH,
          F.RDB$FIELD_PRECISION                 AS FIELD_PRECISION,
          F.RDB$FIELD_SCALE                     AS FIELD_SCALE,
          RF.RDB$NULL_FLAG                      AS NOT_NULL,
          RF.RDB$DEFAULT_SOURCE                 AS DEFAULT_VALUE
        FROM RDB$RELATION_FIELDS RF
        JOIN RDB$FIELDS F ON F.RDB$FIELD_NAME = RF.RDB$FIELD_SOURCE
        WHERE RF.RDB$RELATION_NAME = ?
        ORDER BY RF.RDB$FIELD_POSITION
    `;

    // Mapa de tipo Firebird para nome legível
    const typeNames = {
        7: 'SMALLINT', 8: 'INTEGER', 10: 'FLOAT', 12: 'DATE',
        13: 'TIME', 14: 'CHAR', 16: 'BIGINT/DECIMAL', 27: 'DOUBLE',
        35: 'TIMESTAMP', 37: 'VARCHAR', 40: 'CSTRING', 45: 'BLOB',
        261: 'BLOB',
    };

    db.query(sql, [tableName], (e, rows) => {
        db.detach();
        if (e) {
            console.error('[ERRO] Query falhou:', e.message);
            process.exit(1);
        }
        if (rows.length === 0) {
            console.log(`  Tabela "${tableName}" não encontrada ou sem colunas.`);
            console.log('  Dica: node scripts/list_mob_objects.js para listar objetos disponíveis.');
            process.exit(0);
        }

        const pad = (s, n) => String(s || '').trim().padEnd(n);
        console.log(pad('COLUNA', 30) + pad('TIPO', 18) + pad('NOT NULL', 10) + 'DEFAULT');
        console.log('-'.repeat(75));

        rows.forEach(r => {
            const fieldType = r['FIELD_TYPE'];
            const typeName = typeNames[fieldType] || `TYPE(${fieldType})`;
            const len = r['FIELD_LENGTH'] > 0 ? `(${r['FIELD_LENGTH']})` : '';
            const notNull = r['NOT_NULL'] === 1 ? 'YES' : '-';
            const defVal = (r['DEFAULT_VALUE'] || '').replace('DEFAULT ', '').trim();
            console.log(
                pad(r['COL_NAME'], 30) +
                pad(typeName + len, 18) +
                pad(notNull, 10) +
                defVal
            );
        });

        console.log(`\nTotal: ${rows.length} colunas`);
        process.exit(0);
    });
});
