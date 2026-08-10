'use strict';

const { pool } = require('../db/postgres');
const logger = require('../config/logger');

/**
 * SellerService — Gerencia vendedores sincronizados do ERP.
 */
const sellerService = {

    /**
     * Faz upsert em lote de vendedores.
     *
     * @param {string} tenantId - UUID do tenant
     * @param {Array}  sellers - Array de SellerDto do Worker
     * @returns {Promise<{ synced: number, skipped: number }>}
     */
    async upsertBatch(tenantId, sellers) {
        const client = await pool.connect();
        let synced = 0;
        let skipped = 0;

        try {
            await client.query('BEGIN');

            for (const s of sellers) {
                // Valida campos obrigatórios
                if (!s.id || !s.name) {
                    skipped++;
                    continue;
                }

                await client.query(`
                    INSERT INTO sellers (tenant_id, erp_id, name, email, pin, max_discount, commission, active, updated_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
                    ON CONFLICT (tenant_id, erp_id)
                    DO UPDATE SET
                        name = EXCLUDED.name,
                        email = EXCLUDED.email,
                        pin = EXCLUDED.pin,
                        max_discount = EXCLUDED.max_discount,
                        commission = EXCLUDED.commission,
                        active = EXCLUDED.active,
                        updated_at = NOW()
                `, [
                    tenantId,
                    parseInt(s.id, 10),
                    s.name.substring(0, 200),
                    s.email ? s.email.substring(0, 255) : null,
                    s.passwordHash ? s.passwordHash.substring(0, 255) : null, // MOB_SENHA
                    s.maxDiscount !== undefined ? parseFloat(s.maxDiscount) : null,
                    s.commissionRate !== undefined ? parseFloat(s.commissionRate) : null,
                    s.active !== false
                ]);
                synced++;
            }

            await client.query('COMMIT');
            logger.info(`[SellerService] Upsert concluído. tenant=${tenantId} synced=${synced} skipped=${skipped}`);
        } catch (err) {
            await client.query('ROLLBACK');
            logger.error('[SellerService] Erro no upsertBatch', { error: err.message });
            throw err;
        } finally {
            client.release();
        }

        return { synced, skipped };
    },

    /**
     * Retorna todos os vendedores ativos de um tenant.
     *
     * @param {string} tenantId
     * @returns {Promise<Array>}
     */
    async findAll(tenantId) {
        const { rows } = await pool.query(`
            SELECT erp_id AS "id", name, email, pin, max_discount AS "maxDiscount", commission AS "commissionRate", active
            FROM sellers
            WHERE tenant_id = $1 AND active = true
            ORDER BY name
        `, [tenantId]);
        return rows;
    }

};

module.exports = sellerService;
