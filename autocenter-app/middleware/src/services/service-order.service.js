'use strict';

const db = require('../db/postgres');
const logger = require('../config/logger');

const VALID_STATUSES = ['ABERTA', 'EM_EXECUCAO', 'AGUARDANDO_PECAS', 'FINALIZADA', 'ENTREGUE', 'OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'APPROVED', 'INTEGRATED'];

/**
 * Cria uma nova Ordem de Serviço com itens, fotos e checklist.
 * 
 * @param {string} tenantId 
 * @param {string} deviceId 
 * @param {Object} data 
 * @returns {Promise<Object>}
 */
async function createServiceOrder(tenantId, deviceId, data) {
    const {
        id,
        quoteId,
        plate,
        customerId,
        customerName,
        customerPhone,
        observation,
        sellerId,
        seller_id,
        naturezaId,
        paymentConditionId,
        paymentSpeciesId,
        driver,
        motorista,
        odometer,
        km_veiculo,
        fuelLevel,
        fuel_level,
        items = [],
        photos = [],
        checklist = []
    } = data;

    if (!plate) {
        const error = new Error('A placa do veículo é obrigatória.');
        error.status = 400;
        throw error;
    }

    const cleanPlate = plate.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    const client = await db.pool.connect();
    
    try {
        await client.query('BEGIN');

        const soRes = await client.query(
            `INSERT INTO service_orders (
                id, tenant_id, quote_id, device_id, plate, customer_id, customer_name, customer_phone, status, total_amount, observation, seller_id, natureza_id, payment_condition_id, payment_species_id, driver, odometer, fuel_level, created_at, updated_at
            )
            VALUES (COALESCE($1::uuid, uuid_generate_v4()), $2, $3, $4, $5, $6, $7, $8, 'ABERTA', 0, $9, $10, $11, $12, $13, $14, $15, $16, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET
                tenant_id = EXCLUDED.tenant_id,
                quote_id = EXCLUDED.quote_id,
                device_id = EXCLUDED.device_id,
                plate = EXCLUDED.plate,
                customer_id = EXCLUDED.customer_id,
                customer_name = EXCLUDED.customer_name,
                customer_phone = EXCLUDED.customer_phone,
                observation = EXCLUDED.observation,
                seller_id = EXCLUDED.seller_id,
                natureza_id = EXCLUDED.natureza_id,
                payment_condition_id = EXCLUDED.payment_condition_id,
                payment_species_id = EXCLUDED.payment_species_id,
                driver = EXCLUDED.driver,
                odometer = EXCLUDED.odometer,
                fuel_level = EXCLUDED.fuel_level,
                updated_at = NOW()
            RETURNING id`,
            [
                id || null, 
                tenantId, 
                quoteId || null, 
                deviceId, 
                cleanPlate, 
                customerId || null, 
                customerName || null, 
                customerPhone || null, 
                observation || null, 
                sellerId || seller_id || null, 
                naturezaId || null, 
                paymentConditionId || null, 
                paymentSpeciesId || null,
                driver || motorista || null,
                odometer || km_veiculo || null,
                fuelLevel || fuel_level || null
            ]
        );
        const serviceOrderId = soRes.rows[0].id;

        // Limpar itens, fotos e checklist anteriores para evitar duplicidade em caso de reenvio/upsert
        await client.query('DELETE FROM service_order_items WHERE service_order_id = $1', [serviceOrderId]);
        await client.query('DELETE FROM service_order_photos WHERE service_order_id = $1', [serviceOrderId]);
        await client.query('DELETE FROM service_order_checklist WHERE service_order_id = $1', [serviceOrderId]);

        // 1.5. Associar/Inserir o veículo com o cliente no banco de dados local Postgres
        if (customerId) {
            try {
                let vehicleData = null;
                const vRes = await client.query(
                    `SELECT id FROM vehicles WHERE tenant_id = $1 AND plate = $2`,
                    [tenantId, cleanPlate]
                );

                if (vRes.rows.length === 0) {
                    const vehicleService = require('./vehicle.service');
                    vehicleData = await vehicleService.fetchVehicleByPlate(cleanPlate, tenantId).catch(() => null);
                }

                if (vRes.rows.length > 0) {
                    await client.query(
                        `UPDATE vehicles SET id_cliente = $1, updated_at = NOW() WHERE tenant_id = $2 AND plate = $3`,
                        [customerId, tenantId, cleanPlate]
                    );
                } else if (vehicleData) {
                    await client.query(
                        `INSERT INTO vehicles (
                            tenant_id, id_cliente, brand, model, plate, ano_fabrica, ano_modelo, cor, numero_chassi, status, created_at, updated_at
                        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 1, NOW(), NOW())`,
                        [
                            tenantId,
                            customerId,
                            vehicleData.marca || vehicleData.brand || null,
                            vehicleData.modelo || vehicleData.model || null,
                            cleanPlate,
                            parseInt(vehicleData.ano || vehicleData.ano_fabrica, 10) || null,
                            parseInt(vehicleData.ano_modelo, 10) || null,
                            vehicleData.cor || null,
                            vehicleData.chassi || null
                        ]
                    );
                } else {
                    await client.query(
                        `INSERT INTO vehicles (
                            tenant_id, id_cliente, plate, status, created_at, updated_at
                        ) VALUES ($1, $2, $3, 1, NOW(), NOW())
                        ON CONFLICT (tenant_id, plate) DO UPDATE SET id_cliente = EXCLUDED.id_cliente, updated_at = NOW()`,
                        [tenantId, customerId, cleanPlate]
                    );
                }
            } catch (vErr) {
                logger.error('[ServiceOrderService] Falha ao associar veículo ao cliente no Postgres', { error: vErr.message, plate: cleanPlate, customerId });
            }
        }

        // 2. Inserir itens e calcular valor total
        let totalAmount = 0;
        for (const item of items) {
            const { productCode, productDescription, quantity, unitPrice, itemType, technicianId } = item;
            const totalPrice = Number((quantity * unitPrice).toFixed(2));
            totalAmount += totalPrice;

            await client.query(
                `INSERT INTO service_order_items (
                    service_order_id, product_code, product_description, quantity, unit_price, total_price, item_type, technician_id, created_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
                [serviceOrderId, productCode, productDescription, quantity, unitPrice, totalPrice, itemType || 'PART', technicianId || null]
            );
        }

        // 3. Atualizar valor total da OS
        await client.query(
            `UPDATE service_orders SET total_amount = $1 WHERE id = $2`,
            [totalAmount, serviceOrderId]
        );

        // 4. Inserir fotos se houver
        for (const photo of photos) {
            const { photoUrl, photoType } = photo;
            await client.query(
                `INSERT INTO service_order_photos (service_order_id, photo_url, photo_type, created_at)
                 VALUES ($1, $2, $3, NOW())`,
                [serviceOrderId, photoUrl, photoType || null]
            );
        }

        // 5. Inserir itens de checklist
        for (const ch of checklist) {
            const { itemName, status, observation: chObs } = ch;
            await client.query(
                `INSERT INTO service_order_checklist (service_order_id, item_name, status, observation, created_at, updated_at)
                 VALUES ($1, $2, $3, $4, NOW(), NOW())`,
                [serviceOrderId, itemName, status, chObs || null]
            );
        }

        await client.query('COMMIT');
        logger.info('[ServiceOrderService] Ordem de Serviço criada com sucesso', { serviceOrderId, tenantId, deviceId });

        return { id: serviceOrderId, status: 'ABERTA', totalAmount };
    } catch (err) {
        await client.query('ROLLBACK');
        logger.error('[ServiceOrderService] Falha ao criar ordem de serviço', { error: err.message, tenantId });
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Retorna lista paginada e filtrada de Ordens de Serviço.
 * 
 * @param {string} tenantId 
 * @param {Object} filters 
 * @returns {Promise<Object>}
 */
async function listServiceOrders(tenantId, filters = {}) {
    const { page = 1, limit = 50, status, plate } = filters;
    const parsedPage = Math.max(parseInt(page, 10), 1);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10), 1), 200);
    const offset = (parsedPage - 1) * parsedLimit;

    let countQuery = `SELECT COUNT(*) AS total FROM service_orders WHERE tenant_id = $1`;
    let dataQuery = `
        SELECT id, tenant_id AS "tenantId", quote_id AS "quoteId", device_id AS "deviceId",
               plate, customer_id AS "customerId", customer_name AS "customerName",
               customer_phone AS "customerPhone", status, total_amount AS "totalAmount",
               observation, driver, odometer, fuel_level AS "fuelLevel", created_at AS "createdAt", updated_at AS "updatedAt"
        FROM service_orders 
        WHERE tenant_id = $1
    `;
    const params = [tenantId];
    let paramIndex = 2;

    if (status) {
        countQuery += ` AND status = $${paramIndex}`;
        dataQuery += ` AND status = $${paramIndex}`;
        params.push(status.toUpperCase());
        paramIndex++;
    }

    if (plate) {
        const cleanPlate = plate.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
        countQuery += ` AND plate = $${paramIndex}`;
        dataQuery += ` AND plate = $${paramIndex}`;
        params.push(cleanPlate);
        paramIndex++;
    }

    const countRes = await db.query(countQuery, params.slice(0, paramIndex - 1));
    const total = parseInt(countRes.rows[0]?.total || '0', 10);

    dataQuery += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(parsedLimit, offset);

    const { rows } = await db.query(dataQuery, params);

    return {
        total,
        page: parsedPage,
        limit: parsedLimit,
        totalPages: Math.ceil(total / parsedLimit),
        serviceOrders: rows
    };
}

/**
 * Retorna detalhes completos de uma Ordem de Serviço.
 * 
 * @param {string} tenantId 
 * @param {string} id 
 * @returns {Promise<Object|null>}
 */
async function getServiceOrderDetail(tenantId, id) {
    const soRes = await db.query(`
        SELECT id, tenant_id AS "tenantId", quote_id AS "quoteId", device_id AS "deviceId",
               plate, customer_id AS "customerId", customer_name AS "customerName",
               customer_phone AS "customerPhone", status, total_amount AS "totalAmount",
               observation, driver, odometer, fuel_level AS "fuelLevel", created_at AS "createdAt", updated_at AS "updatedAt"
        FROM service_orders
        WHERE tenant_id = $1 AND id = $2
    `, [tenantId, id]);

    if (soRes.rowCount === 0) {
        return null;
    }

    const serviceOrder = soRes.rows[0];

    const itemsRes = await db.query(`
        SELECT id, product_code AS "productCode", product_description AS "productDescription",
               quantity, unit_price AS "unitPrice", total_price AS "totalPrice",
               item_type AS "itemType", technician_id AS "technicianId"
        FROM service_order_items
        WHERE service_order_id = $1
    `, [id]);

    const photosRes = await db.query(`
        SELECT id, photo_url AS "photoUrl", photo_type AS "photoType"
        FROM service_order_photos
        WHERE service_order_id = $1
    `, [id]);

    const checklistRes = await db.query(`
        SELECT id, item_name AS "itemName", status, observation
        FROM service_order_checklist
        WHERE service_order_id = $1
    `, [id]);

    serviceOrder.items = itemsRes.rows;
    serviceOrder.photos = photosRes.rows;
    serviceOrder.checklist = checklistRes.rows;

    return serviceOrder;
}

/**
 * Atualiza o status de uma Ordem de Serviço.
 * 
 * @param {string} tenantId 
 * @param {string} id 
 * @param {string} status 
 * @returns {Promise<Object|null>}
 */
async function updateStatus(tenantId, id, status) {
    const upperStatus = status.toUpperCase();
    if (!VALID_STATUSES.includes(upperStatus)) {
        const error = new Error(`Status inválido. Use um dos seguintes: ${VALID_STATUSES.join(', ')}`);
        error.status = 400;
        throw error;
    }

    const { rowCount } = await db.query(`
        UPDATE service_orders
        SET status = $1, updated_at = NOW()
        WHERE tenant_id = $2 AND id = $3
    `, [upperStatus, tenantId, id]);

    if (rowCount === 0) {
        return null;
    }

    return { id, status: upperStatus };
}

/**
 * Adiciona fotos a uma Ordem de Serviço existente.
 * 
 * @param {string} tenantId 
 * @param {string} id 
 * @param {string[]} photoUrls 
 */
async function addServiceOrderPhotos(tenantId, id, photoUrls) {
    const checkRes = await db.query(
        'SELECT id FROM service_orders WHERE tenant_id = $1 AND id = $2',
        [tenantId, id]
    );
    if (checkRes.rowCount === 0) {
        const err = new Error('Ordem de Serviço não encontrada.');
        err.status = 404;
        throw err;
    }

    for (const url of photoUrls) {
        await db.query(
            `INSERT INTO service_order_photos (service_order_id, photo_url, photo_type, created_at)
             VALUES ($1, $2, 'GENERAL', NOW())`,
            [id, url]
        );
    }
}

/**
 * Busca Ordens de Serviço com status APPROVED para o Worker sincronizar.
 * 
 * @param {string} tenantId 
 * @returns {Promise<Array>}
 */
async function getApprovedServiceOrders(tenantId) {
    const { rows } = await db.query(`
        SELECT id, 
               plate, 
               customer_name AS "customerName", 
               COALESCE(customer_id::text, '') AS "customerId",
               device_id AS "mechanicId", 
               COALESCE(seller_id::text, '') AS "sellerId",
               payment_species_id AS "paymentSpeciesId", 
               payment_condition_id AS "paymentConditionId",
               natureza_id AS "naturezaId", 
               total_amount AS "totalAmount",
               driver,
               odometer,
               fuel_level AS "fuelLevel",
               created_at AS "createdAt"
        FROM service_orders
        WHERE tenant_id = $1 AND status IN ('APPROVED', 'FINALIZADA', 'ENTREGUE', 'ABERTA', 'OPEN')
        ORDER BY created_at ASC
    `, [tenantId]);

    for (const so of rows) {
        const itemsRes = await db.query(`
            SELECT product_code AS "productCode", 
                   quantity, 
                   unit_price AS "unitPrice", 
                   0.0 AS "discount"
            FROM service_order_items
            WHERE service_order_id = $1
        `, [so.id]);

        so.items = itemsRes.rows;
    }

    return rows;
}

module.exports = {
    createServiceOrder,
    listServiceOrders,
    getServiceOrderDetail,
    updateStatus,
    addServiceOrderPhotos,
    getApprovedServiceOrders
};
