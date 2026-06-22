'use strict';
require('dotenv').config();
const { pgQuery } = require('./src/db/postgres');

async function run() {
    try {
        const resCompanies = await pgQuery('SELECT "Id", "Name" FROM companies');
        console.log('\n=== COMPANIES ===');
        console.log(resCompanies.rows);

        const resBranches = await pgQuery('SELECT "Id", "Name", "CompanyId", "ErpEmpresaId", "ErpDeptoPadrao", "IsDefault" FROM branches');
        console.log('\n=== BRANCHES ===');
        console.log(resBranches.rows);
    } catch (e) {
        console.error('ERRO:', e);
    }
}
run();
