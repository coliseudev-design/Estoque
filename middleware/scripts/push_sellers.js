
'use strict';
require('dotenv').config();
const Firebird = require('node-firebird');
const https = require('https');

const opts = {
    host: process.env.FB_HOST || 'localhost',
    port: parseInt(process.env.FB_PORT) || 3050,
    database: process.env.FB_DATABASE,
    user: process.env.FB_USER,
    password: process.env.FB_PASSWORD,
    WireCrypt: process.env.FB_WIRE_CRYPT !== 'false',
};

Firebird.attach(opts, (err, db) => {
    if (err) { console.error('Erro Firebird:', err.message); process.exit(1); }

    db.query(
        `SELECT F.ID_FUNCIONARIO AS id, F.ID_MOBILE AS mobileId,
                F.NOME AS name, F.EMAIL AS email,
                F.MOB_SENHA AS passwordHash,
                F.DESCONTO_MAX AS maxDiscount,
                F.COMISSAO AS commissionRate,
                F.ID_EMPRESA AS erpEmpresaId
         FROM FUNCIONARIOS F
         WHERE F.MOB_ACESSO = 1
         ORDER BY F.NOME`,
        [],
        (e, rows) => {
            db.detach();
            if (e) { console.error('Query erro:', e.message); process.exit(1); }

            console.log(`Sellers do Firebird: ${rows.length}`);
            rows.forEach(r => console.log(` - ${r.NAME} | ID=${r.ID_FUNCIONARIO} | SENHA=${r.PASSWORDHASH ? '✓' : 'vazia'}`));

            if (rows.length === 0) {
                console.log('Nenhum seller com MOB_ACESSO=1. App nao vai mostrar nada.');
                return;
            }

            const body = JSON.stringify({ sellers: rows });
            const reqOpts = {
                hostname: 'licencas.coliseusistemas.com.br',
                path: '/api/sync/sellers',
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'api-key': '97d519634898145e8557b494d13c9c9b',
                    'Content-Length': Buffer.byteLength(body),
                },
            };

            const req = https.request(reqOpts, res => {
                let data = '';
                res.on('data', d => data += d);
                res.on('end', () => {
                    console.log(`\nVPS resposta: HTTP ${res.statusCode}`);
                    try {
                        const parsed = JSON.parse(data);
                        console.log(`Recebido: ${parsed.received || '?'} sellers`);
                    } catch { console.log('Body:', data.substring(0, 200)); }
                });
            });
            req.on('error', e2 => console.error('HTTP erro:', e2.message));
            req.write(body);
            req.end();
        }
    );
});
