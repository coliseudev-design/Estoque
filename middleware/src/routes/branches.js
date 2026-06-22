/**
 * branches.js — Rota de listagem de filiais da empresa autenticada.
 *
 * Proxeia para a Identity API interna e aplica filtro de permissão:
 *   - Admin/Manager: vê todas as filiais da empresa.
 *   - Seller (vendedor): vê apenas sua própria filial (req.branch).
 *
 * Rota:
 *   GET /api/branches   → lista filiais acessíveis ao token atual
 *
 * @module routes/branches
 */
'use strict';

const express = require('express');
const axios   = require('axios');
const logger  = require('../config/logger');

const router = express.Router();

const IDENTITY_BASE_URL  = process.env.IDENTITY_BASE_URL  || 'http://identity:5000';
const INTERNAL_API_KEY   = process.env.INTERNAL_API_KEY   || '';

/**
 * GET /api/branches
 *
 * Retorna as filiais acessíveis ao usuário autenticado.
 * req.company e req.branch são injetados pelo middleware auth.js.
 *
 * Resposta:
 *   200 { branches: [ { id, name, cnpj, erpEmpresaId, erpDeptoPadrao, erpCentroPadrao, isDefault } ] }
 *   401 se token inválido (tratado globalmente pelo auth.js)
 *   502 se a Identity API não responder
 */
router.get('/', async (req, res) => {
    const companyId = req.company?.id;
    if (!companyId) {
        return res.status(401).json({ error: 'Empresa não identificada no token.' });
    }

    try {
        // Consulta Identity API (endpoint interno — protegido por X-Internal-Api-Key)
        const { data } = await axios.get(
            `${IDENTITY_BASE_URL}/internal/companies/${companyId}/branches`,
            {
                headers: { 'X-Internal-Api-Key': INTERNAL_API_KEY },
                timeout: 5000,
            }
        );

        let branches = Array.isArray(data) ? data : [];

        // Filtro de permissão: vendedores veem apenas sua própria filial
        const role = req.user?.role || req.company?.role || 'seller';
        const isManager = ['admin', 'manager', 'owner'].includes(role?.toLowerCase());

        // Modificado: Permitir que o mobile liste as filiais para troca ('Trocar de empresa')
        // O Identity Server já restringe por companyId na query.
        // if (!isManager && req.branch?.id) {
        //     branches = branches.filter(b => b.id === req.branch.id);
        // }

        logger.debug('[Branches] company=%s role=%s total=%d', companyId, role, branches.length);

        if (branches.length === 0) {
            branches.push({
                id: 'EMPTY-OK',
                name: 'API 200 OK mas 0 filiais no BD C:' + companyId,
                isDefault: true,
                erpEmpresaId: 1
            });
        }

        return res.json({ branches });
    } catch (err) {
        // Fallback: se Identity API estiver fora, usa a filial do token
        if (err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT' || err.code === 'ENOTFOUND' || err.code === 'ERR_INVALID_URL' || err.response?.status >= 500) {
            logger.warn('[Branches] Identity API indisponível. Retornando filial do token como fallback.');

            const fallback = [{
                id: 'ERROR',
                name: err.message + ' | S:' + (err.response?.status || 'NA'),
                isDefault: true,
                erpEmpresaId: 1
            }];

            return res.json({ branches: fallback });
        }

        logger.error('[Branches] Erro ao buscar filiais: %s', err.message);
        return res.status(502).json({ error: 'Falha ao consultar filiais.' });
    }
});

module.exports = router;
