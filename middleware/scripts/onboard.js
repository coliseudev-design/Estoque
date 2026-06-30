#!/usr/bin/env node
/**
 * onboard.js — Script de onboarding de nova empresa (I3).
 *
 * Uso:
 *   node onboard.js --name "Empresa XYZ" [--url http://localhost:3000] [--admin-key <key>]
 *
 * O que faz:
 *   1. Cria a empresa via POST /api/admin/companies
 *   2. Exibe a API Key gerada (única oportunidade de visualizar)
 *   3. Gera um trecho de appsettings.json para o Worker .NET
 *   4. Informa os próximos passos
 */
'use strict';

const https = require('https');
const http = require('http');

// ── Argumentos ────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
const get = (flag) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : null; };

const name = get('--name') || args.find(a => !a.startsWith('-'));
const baseUrl = get('--url') || 'http://localhost:3000';
const adminKey = get('--admin-key') || process.env.ADMIN_API_KEY || '';

if (!name) {
    console.error('\n❌  Uso: node onboard.js --name "Empresa XYZ" [--url <url>] [--admin-key <key>]\n');
    process.exit(1);
}

// rule-07 — Higiene de Credenciais: Admin API Key deve ter pelo menos 32 chars.
// Chaves muito curtas são vulneráveis a brute-force e devem ser rejeitadas no onboarding.
if (!adminKey || adminKey.length < 32) {
    console.error('\n❌  ADMIN_API_KEY inválida ou muito curta.');
    console.error('   A chave deve ter pelo menos 32 caracteres.');
    console.error('   Use: --admin-key <chave-com-32-ou-mais-chars>');
    console.error('   Ou defina a variável de ambiente ADMIN_API_KEY antes de executar.\n');
    process.exit(1);
}

// ── HTTP helper ───────────────────────────────────────────────────────────────
function request(url, method, body, headers) {
    return new Promise((resolve, reject) => {
        const { hostname, port, pathname, protocol } = new URL(url);
        const bodyStr = body ? JSON.stringify(body) : '';
        const lib = protocol === 'https:' ? https : http;
        const req = lib.request({
            hostname, port, path: pathname, method,
            headers: {
                'Content-Type': 'application/json',
                'Admin-Api-Key': headers?.adminKey || '',
                'Content-Length': Buffer.byteLength(bodyStr),
            },
        }, (res) => {
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => {
                try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch { resolve({ status: res.statusCode, body: data }); }
            });
        });
        req.on('error', reject);
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
    console.log('\n🚀  Coliseu Speed — Onboarding de Empresa');
    console.log('─'.repeat(50));
    console.log(`   Nome:    ${name}`);
    console.log(`   API URL: ${baseUrl}`);
    console.log('─'.repeat(50));

    // 1. Cria empresa
    console.log('\n⏳  Criando empresa...');
    const res = await request(
        `${baseUrl}/api/admin/companies`,
        'POST',
        { name },
        { adminKey }
    );

    if (res.status !== 201) {
        console.error(`\n❌  Erro ${res.status}:`, JSON.stringify(res.body, null, 2));
        process.exit(1);
    }

    const { company, apiKey } = res.body;

    // 2. Exibe resultados
    console.log('\n✅  Empresa criada com sucesso!\n');
    console.log('┌─────────────────────────────────────────────────┐');
    console.log(`│  ID:       ${company.id}`);
    console.log(`│  Nome:     ${company.name}`);
    console.log(`│  Criado:   ${company.created_at}`);
    console.log('├─────────────────────────────────────────────────┤');
    console.log(`│  🔑 API KEY (guarde agora — não será exibida novamente)`);
    console.log(`│`);
    console.log(`│  ${apiKey}`);
    console.log(`│`);
    console.log('└─────────────────────────────────────────────────┘');

    // 3. Gera trecho para appsettings.json
    console.log('\n📋  Copie para o appsettings.json do Worker .NET:\n');
    console.log(JSON.stringify({
        VpsApi: {
            BaseUrl: baseUrl,
            ApiKey: apiKey,
            CompanyId: company.id,
        }
    }, null, 4));

    // 4. Próximos passos
    console.log('\n📌  Próximos passos:');
    console.log('   1. Instale o Worker .NET na máquina da empresa');
    console.log('   2. Cole o trecho acima no appsettings.json');
    console.log('   3. Inicie o Worker: dotnet ColiseuSpeed.Worker.exe');
    console.log('   4. Verifique o sync: GET /health\n');
}

main().catch(err => {
    console.error('\n❌  Erro inesperado:', err.message);
    process.exit(1);
});
