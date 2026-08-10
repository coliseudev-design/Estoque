'use strict';

const { pool } = require('../db/postgres');
const logger = require('../config/logger');

/**
 * TechnicianService — Gerencia técnicos/mecânicos sincronizados do ERP.
 */
const technicianService = {

    /**
     * Faz upsert em lote de técnicos.
     *
     * @param {string} tenantId - UUID do tenant
     * @param {Array}  technicians - Array de TechnicianDto do Worker
     * @returns {Promise<{ synced: number, skipped: number }>}
     */
    async upsertBatch(tenantId, technicians) {
        const client = await pool.connect();
        let synced = 0;
        let skipped = 0;

        try {
            await client.query('BEGIN');

            for (const t of technicians) {
                // Valida campos obrigatórios
                if (!t.erpId || !t.name) {
                    skipped++;
                    continue;
                }

                await client.query(`
                    INSERT INTO technicians (tenant_id, erp_id, name, active, updated_at)
                    VALUES ($1, $2, $3, $4, NOW())
                    ON CONFLICT (tenant_id, erp_id)
                    DO UPDATE SET
                        name = EXCLUDED.name,
                        active = EXCLUDED.active,
                        updated_at = NOW()
                `, [
                    tenantId,
                    t.erpId,
                    t.name.substring(0, 200),
                    t.active !== false // default true se não informado
                ]);
                synced++;
            }

            await client.query('COMMIT');
            logger.info(`[TechnicianService] Upsert concluído. tenant=${tenantId} synced=${synced} skipped=${skipped}`);
        } catch (err) {
            await client.query('ROLLBACK');
            logger.error('[TechnicianService] Erro no upsertBatch', { error: err.message });
            throw err;
        } finally {
            client.release();
        }

        return { synced, skipped };
    },

    /**
     * Retorna todos os técnicos ativos de um tenant.
     *
     * @param {string} tenantId
     * @returns {Promise<Array>}
     */
    async findAll(tenantId) {
        const { rows } = await pool.query(`
            SELECT erp_id AS "erpId", name, active
            FROM technicians
            WHERE tenant_id = $1 AND active = true
            ORDER BY name
        `, [tenantId]);
        return rows;
    }

};

module.exports = technicianService;
