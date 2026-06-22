// Lista TODAS as stored procedures do Firebird com parametros (sem emojis para Windows).
// Uso: node scripts/list_procedures.js
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const fs = require('fs');
const options = {
    host: process.env.FB_HOST || 'localhost', port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE, user: process.env.FB_USER, password: process.env.FB_PASSWORD,
    charset: process.env.FB_CHARSET || 'WIN1252', lowercase_keys: false,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',
};

Firebird.attach(options, (err, db) => {
    if (err) { console.error('[ERRO] Conexao:', err.message); process.exit(1); }

    // 1. Lista todas as procedures
    db.query(
        `SELECT TRIM(RDB$PROCEDURE_NAME) AS PROC_NAME
         FROM RDB$PROCEDURES
         WHERE RDB$SYSTEM_FLAG = 0
         ORDER BY RDB$PROCEDURE_NAME`,
        [],
        (e, procs) => {
            if (e) { console.error(e.message); db.detach(); process.exit(1); }

            // 2. Lista parametros
            db.query(
                `SELECT
                    TRIM(PP.RDB$PROCEDURE_NAME) AS PROC_NAME,
                    TRIM(PP.RDB$PARAMETER_NAME) AS PARAM_NAME,
                    PP.RDB$PARAMETER_TYPE AS PARAM_TYPE,
                    PP.RDB$PARAMETER_NUMBER AS PARAM_NUM,
                    TRIM(COALESCE(
                        CASE F.RDB$FIELD_TYPE
                            WHEN 7  THEN 'SMALLINT'
                            WHEN 8  THEN 'INTEGER'
                            WHEN 10 THEN 'FLOAT'
                            WHEN 12 THEN 'DATE'
                            WHEN 13 THEN 'TIME'
                            WHEN 14 THEN 'CHAR'
                            WHEN 16 THEN CASE F.RDB$FIELD_SUB_TYPE WHEN 1 THEN 'NUMERIC' WHEN 2 THEN 'DECIMAL' ELSE 'BIGINT' END
                            WHEN 23 THEN 'BOOLEAN'
                            WHEN 27 THEN 'DOUBLE'
                            WHEN 35 THEN 'TIMESTAMP'
                            WHEN 37 THEN 'VARCHAR'
                            WHEN 261 THEN 'BLOB'
                            ELSE 'TYPE_' || F.RDB$FIELD_TYPE
                        END,
                    'UNKNOWN')) AS FIELD_TYPE
                FROM RDB$PROCEDURE_PARAMETERS PP
                LEFT JOIN RDB$FIELDS F ON F.RDB$FIELD_NAME = PP.RDB$FIELD_SOURCE
                ORDER BY PP.RDB$PROCEDURE_NAME, PP.RDB$PARAMETER_TYPE, PP.RDB$PARAMETER_NUMBER`,
                [],
                (e2, params) => {
                    db.detach();
                    if (e2) { console.error(e2.message); process.exit(1); }

                    // Agrupa
                    const paramMap = {};
                    for (const p of params) {
                        const name = (p.PROC_NAME || '').trim();
                        if (!paramMap[name]) paramMap[name] = { in: [], out: [] };
                        const entry = { name: (p.PARAM_NAME || '').trim(), type: (p.FIELD_TYPE || 'UNKNOWN').trim(), num: p.PARAM_NUM };
                        if (p.PARAM_TYPE === 0) paramMap[name].in.push(entry);
                        else paramMap[name].out.push(entry);
                    }

                    // Palavras-chave relevantes para vendas
                    const keywords = ['VEND', 'PEDID', 'COMISS', 'FAT', 'RELAT',
                        'MOB_', 'TOTAL', 'CALC', 'DASH', 'META',
                        'SALDO', 'FIN', 'RESULT', 'RANKING',
                        'FISCAL', 'NF', 'NOTA', 'AF_', 'FICHA'];

                    const lines = [];
                    lines.push(`Total: ${procs.length} procedures`);
                    lines.push('');
                    lines.push('=== PROCEDURES RELEVANTES (vendas/desempenho) ===');
                    lines.push('');

                    for (const proc of procs) {
                        const name = (proc.PROC_NAME || '').trim();
                        const pInfo = paramMap[name] || { in: [], out: [] };
                        const isRelevant = keywords.some(k => name.toUpperCase().includes(k));
                        if (!isRelevant) continue;

                        lines.push(`[PROC] ${name}`);
                        if (pInfo.in.length > 0) {
                            lines.push(`  IN:`);
                            pInfo.in.sort((a, b) => a.num - b.num).forEach(p =>
                                lines.push(`    [${p.num}] ${p.name} (${p.type})`));
                        }
                        if (pInfo.out.length > 0) {
                            lines.push(`  OUT:`);
                            pInfo.out.sort((a, b) => a.num - b.num).forEach(p =>
                                lines.push(`    [${p.num}] ${p.name} (${p.type})`));
                        }
                        if (pInfo.in.length === 0 && pInfo.out.length === 0) {
                            lines.push(`  (sem parametros)`);
                        }
                        lines.push('');
                    }

                    const output = lines.join('\n');
                    fs.writeFileSync('procedures_output.txt', output, 'utf8');
                    console.log('Resultado salvo em procedures_output.txt');
                    console.log(`${procs.length} procedures total`);
                    process.exit(0);
                }
            );
        }
    );
});
