'use strict';

const express = require('express');
const router = express.Router();
const db = require('../db/postgres');
const logger = require('../config/logger');
const config = require('../config/env');

/**
 * GET /api/filiais
 * Retorna a lista de filiais (departamentos) ativas do tenant.
 * Sincroniza dinamicamente com o Identity Server.
 */
router.get('/', async (req, res, next) => {
    const tenantId = req.tenant?.id;
    if (!tenantId) return res.status(401).json({ error: 'Tenant não autenticado.' });

    try {
        let syncDebugInfo = null;

        // 1. Tenta sincronizar as filiais a partir do Identity Server
        try {
            const identityUrl = config.security?.identityApiUrl;
            const internalKey = config.security?.identityInternalKey;

            if (identityUrl && internalKey) {
                const resp = await fetch(`${identityUrl}/internal/companies/${tenantId}/branches`, {
                    headers: { 'x-internal-api-key': internalKey },
                    signal: AbortSignal.timeout(5000),
                });

                if (resp.ok) {
                    const branches = await resp.json();
                    const validBranches = branches.filter(b => b.erpDeptoPadrao != null);
                    
                    // Atualiza ou insere no banco local
                    for (const b of validBranches) {
                        await db.query(
                            `INSERT INTO dash_filiais (tenant_id, empresa_erp, depto_id, centro_custo, nome, documento, is_default, ativo, sincronizado_em)
                             VALUES ($1,$2,$3,$4,$5,$6,$7,true,NOW())
                             ON CONFLICT (tenant_id, depto_id) DO UPDATE
                             SET empresa_erp=$2, centro_custo=$4, nome=$5, documento=$6, is_default=$7, ativo=true, sincronizado_em=NOW()`,
                            [tenantId, b.erpEmpresaId || 1, b.erpDeptoPadrao, b.erpCentroPadrao || null, b.name, b.cnpj || null, b.isDefault || false]
                        );
                    }
                } else {
                    syncDebugInfo = `HTTP ${resp.status} - ${await resp.text().catch(()=>'')}`;
                    logger.warn(`[Filiais] Falha no sync com Identity Server (HTTP ${resp.status}) para tenant ${tenantId}`);
                }
            } else {
                logger.warn('[Filiais] Credenciais do Identity Server não configuradas. Servindo do banco local.');
            }
        } catch (syncErr) {
            syncDebugInfo = syncErr.message;
            logger.warn(`[Filiais] Erro ao sincronizar filiais do Identity Server: ${syncErr.message}`);
        }

        // 2. Busca filiais atualizadas no banco local
        const { rows } = await db.query(
            `SELECT id, empresa_erp AS "empresaErp", depto_id AS "deptoId", centro_custo AS "centroCusto", 
                    nome, documento, is_default AS "isDefault", ativo
             FROM dash_filiais
             WHERE tenant_id = $1 AND ativo = true
             ORDER BY is_default DESC, nome ASC`,
            [tenantId]
        );

        res.json(rows);
    } catch (err) {
        logger.error('[Filiais] Erro ao listar filiais:', err.message);
        next(err);
    }
});

module.exports = router;
