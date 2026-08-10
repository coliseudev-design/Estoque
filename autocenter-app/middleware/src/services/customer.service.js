'use strict';

const { pool } = require('../db/postgres');
const logger   = require('../config/logger');

/**
 * CustomerService — Gerencia clientes sincronizados do Firebird ERP.
 * Padrão offline-first: o Worker envia, o app baixa e salva no SQLite local.
 */
const customerService = {

    /**
     * Faz upsert em lote de clientes (INSERT ON CONFLICT DO UPDATE).
     * Seguro para reenvios — o Worker pode enviar o mesmo lote várias vezes.
     *
     * @param {string} tenantId - UUID do tenant
     * @param {Array}  customers - Array de CustomerDto do Worker
     * @returns {{ synced: number, skipped: number }}
     */
    async upsertBatch(tenantId, customers) {
        const client = await pool.connect();
        let   synced = 0;
        let   skipped = 0;

        try {
            await client.query('BEGIN');

            for (const c of customers) {
                // Valida campos obrigatórios
                if (!c.erpId || !c.name) {
                    skipped++;
                    continue;
                }

                await client.query(`
                    INSERT INTO customers
                        (tenant_id, erp_id, name, fantasy_name, cpf_cnpj, phone, phone2, email, city, address, active, updated_at)
                    VALUES
                        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
                    ON CONFLICT (tenant_id, erp_id)
                    DO UPDATE SET
                        name         = EXCLUDED.name,
                        fantasy_name = EXCLUDED.fantasy_name,
                        cpf_cnpj     = EXCLUDED.cpf_cnpj,
                        phone        = EXCLUDED.phone,
                        phone2       = EXCLUDED.phone2,
                        email        = EXCLUDED.email,
                        city         = EXCLUDED.city,
                        address      = EXCLUDED.address,
                        active       = EXCLUDED.active,
                        updated_at   = NOW(),
                        synced_at    = NOW()
                `, [
                    tenantId,
                    c.erpId,
                    c.name?.substring(0, 200)    || '',
                    c.fantasyName?.substring(0, 200) || '',
                    c.cpfCnpj?.substring(0, 20)  || '',
                    c.phone?.substring(0, 25)    || '',
                    c.phone2?.substring(0, 25)   || '',
                    c.email?.substring(0, 150)   || '',
                    c.city?.substring(0, 100)    || '',
                    c.address?.substring(0, 255) || '',
                    c.active !== false, // default true se não informado
                ]);
                synced++;
            }

            await client.query('COMMIT');
            logger.info(`[CustomerService] Upsert concluído. tenant=${tenantId} synced=${synced} skipped=${skipped}`);
        } catch (err) {
            await client.query('ROLLBACK');
            logger.error('[CustomerService] Erro no upsertBatch', { error: err.message });
            throw err;
        } finally {
            client.release();
        }

        return { synced, skipped };
    },

    /**
     * Retorna todos os clientes ativos de um tenant.
     * Suporta busca por nome, CPF/CNPJ ou telefone.
     *
     * @param {string} tenantId
     * @param {{ search: string, limit: number }} opts
     */
    async findAll(tenantId, { search = '', limit = 500 } = {}) {
        let query;
        let params;

        if (search) {
            const pattern = `%${search.toLowerCase()}%`;
            query = `
                SELECT erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                       cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
                FROM customers
                WHERE tenant_id = $1
                  AND active = true
                  AND (
                      LOWER(name)     LIKE $2 OR
                      cpf_cnpj        LIKE $2 OR
                      phone           LIKE $2 OR
                      phone2          LIKE $2
                  )
                ORDER BY name
                LIMIT $3
            `;
            params = [tenantId, pattern, limit];
        } else {
            query = `
                SELECT erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                       cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
                FROM customers
                WHERE tenant_id = $1 AND active = true
                ORDER BY name
                LIMIT $2
            `;
            params = [tenantId, limit];
        }

        const { rows } = await pool.query(query, params);
        return rows;
    },

    /**
     * Busca um cliente específico pelo ID do ERP.
     *
     * @param {string} tenantId
     * @param {number} erpId
     */
    async findByErpId(tenantId, erpId) {
        const { rows } = await pool.query(`
            SELECT erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                   cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
            FROM customers
            WHERE tenant_id = $1 AND erp_id = $2
        `, [tenantId, erpId]);

        return rows[0] || null;
    },

    /**
     * Cria um cliente individual e gera um erpId de contingência.
     */
    async createCustomer(tenantId, customer) {
        let erpId = customer.erpId;
        if (!erpId) {
            const { rows } = await pool.query(
                'SELECT COALESCE(MAX(erp_id), 0) + 1 AS next_id FROM customers WHERE tenant_id = $1',
                [tenantId]
            );
            erpId = parseInt(rows[0].next_id, 10);
            if (erpId < 9000000) {
                erpId = 9000000 + erpId;
            }
        }

        const { rows } = await pool.query(`
            INSERT INTO customers
                (tenant_id, erp_id, name, fantasy_name, cpf_cnpj, phone, phone2, email, city, address, active, updated_at, synced_at)
            VALUES
                ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())
            RETURNING erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                      cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
        `, [
            tenantId,
            erpId,
            customer.name || '',
            customer.fantasyName || customer.fantasy_name || null,
            customer.cpfCnpj || customer.cpf_cnpj || null,
            customer.phone || null,
            customer.phone2 || null,
            customer.email || null,
            customer.city || null,
            customer.address || null,
            customer.active !== false
        ]);

        const localId = customer.local_id || customer.localId;
        if (localId) {
            await pool.query(`
                INSERT INTO pending_customers (
                    tenant_id, local_id, name, fantasy_name, cpf_cnpj, phone, phone2,
                    email, city, address, street, number, complement, neighborhood,
                    zip, state, status, erp_id, created_at, updated_at
                )
                VALUES (
                    $1, $2, $3, $4, $5, $6, $7,
                    $8, $9, $10, $11, $12, $13, $14,
                    $15, $16, 'PENDING', $17, NOW(), NOW()
                )
                ON CONFLICT (tenant_id, local_id)
                DO UPDATE SET
                    status = 'PENDING',
                    erp_id = EXCLUDED.erp_id,
                    updated_at = NOW()
            `, [
                tenantId,
                localId,
                customer.name || '',
                customer.fantasyName || customer.fantasy_name || null,
                customer.cpfCnpj || customer.cpf_cnpj || null,
                customer.phone || null,
                customer.phone2 || null,
                customer.email || null,
                customer.city || null,
                customer.address || null,
                customer.street || customer.logradouro || null,
                customer.number || customer.numero || null,
                customer.complement || customer.complemento || null,
                customer.neighborhood || customer.bairro || null,
                customer.zip || customer.zipCode || customer.cep || null,
                customer.state || customer.uf || null,
                erpId
            ]);
        }

        return rows[0];
    },

    /**
     * Cadastra um cliente offline na tabela pending_customers.
     *
     * @param {string} tenantId - UUID do tenant
     * @param {Object} data - Dados do cliente
     * @returns {Promise<Object>} Cliente cadastrado
     */
    async createPending(tenantId, data) {
        const localId = data.local_id || data.localId;
        const name = data.name;
        const fantasyName = data.fantasy_name || data.fantasyName;
        const cpfCnpj = data.cpf_cnpj || data.cpfCnpj;
        const phone = data.phone;
        const phone2 = data.phone2;
        const email = data.email;
        const city = data.city;
        const address = data.address;
        const street = data.street;
        const number = data.number;
        const complement = data.complement;
        const neighborhood = data.neighborhood;
        const zip = data.zip || data.zipCode || data.cep;
        const state = data.state;

        const { rows } = await pool.query(`
            INSERT INTO pending_customers (
                tenant_id, local_id, name, fantasy_name, cpf_cnpj, phone, phone2,
                email, city, address, street, number, complement, neighborhood,
                zip, state, status, created_at, updated_at
            )
            VALUES (
                $1, $2, $3, $4, $5, $6, $7,
                $8, $9, $10, $11, $12, $13, $14,
                $15, $16, 'PENDING', NOW(), NOW()
            )
            ON CONFLICT (tenant_id, local_id)
            DO UPDATE SET
                name = EXCLUDED.name,
                fantasy_name = EXCLUDED.fantasy_name,
                cpf_cnpj = EXCLUDED.cpf_cnpj,
                phone = EXCLUDED.phone,
                phone2 = EXCLUDED.phone2,
                email = EXCLUDED.email,
                city = EXCLUDED.city,
                address = EXCLUDED.address,
                street = EXCLUDED.street,
                number = EXCLUDED.number,
                complement = EXCLUDED.complement,
                neighborhood = EXCLUDED.neighborhood,
                zip = EXCLUDED.zip,
                state = EXCLUDED.state,
                status = 'PENDING',
                updated_at = NOW()
            RETURNING id, tenant_id AS "tenantId", local_id AS "localId", name, status, created_at AS "createdAt"
        `, [
            tenantId,
            localId,
            name,
            fantasyName || null,
            cpfCnpj || null,
            phone || null,
            phone2 || null,
            email || null,
            city || null,
            address || null,
            street || null,
            number || null,
            complement || null,
            neighborhood || null,
            zip || null,
            state || null
        ]);

        return rows[0];
    },

    /**
     * Retorna lista paginada de clientes ativos de um tenant.
     *
     * @param {string} tenantId
     * @param {{ search: string, limit: number, offset: number }} opts
     * @returns {Promise<{ total: number, rows: Array }>}
     */
    async findPaginated(tenantId, { search = '', limit = 100, offset = 0 } = {}) {
        let countQuery;
        let dataQuery;
        let params;

        if (search) {
            const pattern = `%${search.toLowerCase()}%`;
            countQuery = `
                SELECT COUNT(*) AS total
                FROM customers
                WHERE tenant_id = $1 AND active = true
                  AND (
                      LOWER(name)     LIKE $2 OR
                      cpf_cnpj        LIKE $2 OR
                      phone           LIKE $2 OR
                      phone2          LIKE $2
                  )
            `;
            dataQuery = `
                SELECT erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                       cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
                FROM customers
                WHERE tenant_id = $1 AND active = true
                  AND (
                      LOWER(name)     LIKE $2 OR
                      cpf_cnpj        LIKE $2 OR
                      phone           LIKE $2 OR
                      phone2          LIKE $2
                  )
                ORDER BY name
                LIMIT $3 OFFSET $4
            `;
            params = [tenantId, pattern, limit, offset];
        } else {
            countQuery = `
                SELECT COUNT(*) AS total
                FROM customers
                WHERE tenant_id = $1 AND active = true
            `;
            dataQuery = `
                SELECT erp_id AS "erpId", name, fantasy_name AS "fantasyName",
                       cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address, active
                FROM customers
                WHERE tenant_id = $1 AND active = true
                ORDER BY name
                LIMIT $2 OFFSET $3
            `;
            params = [tenantId, limit, offset];
        }

        const countResult = await pool.query(countQuery, search ? [tenantId, params[1]] : [tenantId]);
        const total = parseInt(countResult.rows[0]?.total || '0', 10);

        const { rows } = await pool.query(dataQuery, params);

        return { total, rows };
    },

    async getPendingCustomers(tenantId) {
        const { rows } = await pool.query(
            `SELECT local_id AS "localId", name, fantasy_name AS "fantasyName",
                    cpf_cnpj AS "cpfCnpj", phone, phone2, email, city, address,
                    street, number, complement, neighborhood, zip, state
             FROM pending_customers
             WHERE tenant_id = $1 AND status = 'PENDING'
             ORDER BY created_at ASC`,
            [tenantId]
        );
        return rows;
    },

    async confirmCustomer(tenantId, pendingId, erpId) {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const pRes = await client.query(
                `SELECT erp_id FROM pending_customers WHERE tenant_id = $1 AND local_id = $2`,
                [tenantId, pendingId]
            );

            let mockErpId = null;
            if (pRes.rows.length > 0) {
                mockErpId = pRes.rows[0].erp_id;
            }

            await client.query(
                `UPDATE pending_customers 
                 SET status = 'SYNCHRONIZED', erp_id = $1, updated_at = NOW() 
                 WHERE tenant_id = $2 AND local_id = $3`,
                [erpId, tenantId, pendingId]
            );

            if (mockErpId) {
                await client.query(
                    `UPDATE customers SET erp_id = $1, updated_at = NOW() WHERE tenant_id = $2 AND erp_id = $3`,
                    [erpId, tenantId, mockErpId]
                );

                await client.query(
                    `UPDATE service_orders SET customer_id = $1, updated_at = NOW() WHERE tenant_id = $2 AND customer_id = $3`,
                    [erpId, tenantId, mockErpId]
                );

                await client.query(
                    `UPDATE vehicles SET id_cliente = $1, updated_at = NOW() WHERE tenant_id = $2 AND id_cliente = $3`,
                    [erpId, tenantId, mockErpId]
                );
            } else {
                await client.query(
                    `UPDATE customers SET erp_id = $1, updated_at = NOW() WHERE tenant_id = $2 AND name = (
                        SELECT name FROM pending_customers WHERE tenant_id = $2 AND local_id = $3
                    )`,
                    [erpId, tenantId, pendingId]
                );
            }

            await client.query('COMMIT');
            return { success: true };
        } catch (err) {
            await client.query('ROLLBACK');
            throw err;
        } finally {
            client.release();
        }
    },

    async errorCustomer(tenantId, pendingId, errorMessage) {
        await pool.query(
            `UPDATE pending_customers 
             SET status = 'ERROR', error_message = $1, updated_at = NOW() 
             WHERE tenant_id = $2 AND local_id = $3`,
            [errorMessage, tenantId, pendingId]
        );
        return { success: true };
    }

};

module.exports = customerService;
