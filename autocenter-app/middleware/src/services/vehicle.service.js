'use strict';

const fetch = globalThis.fetch || require('node-fetch');
const redis = require('../db/redis');
const { pool } = require('../db/postgres');
const config = require('../config/env');
const logger = require('../config/logger');

// Cache prefix
const CACHE_PREFIX = 'plate_v1:';

/**
 * Consulta a placa na APIBrasil e usa Redis como cache.
 * 
 * @param {string} plate - Placa do veículo
 * @param {string} tenantId - Usado para logs e rastrear cotas
 * @returns {Promise<Object>} Dados do veículo formatados
 */
async function fetchVehicleByPlate(plate, tenantId) {
    const cleanPlate = plate.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    
    // RegEx estrito para placas brasileiras (antiga: AAA-0000 e Mercosul: AAA-0A00)
    const regexPlate = /^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$/;
    
    if (!regexPlate.test(cleanPlate)) {
        const error = new Error('Placa no formato inválido. Use AAA-0000 ou AAA-0A00.');
        error.status = 400;
        throw error;
    }

    // 0. Consulta a tabela local `vehicles` primeiro
    try {
        const pgResult = await pool.query(`
            SELECT 
                v.id_cliente,
                v.id_veiculo,
                v.brand,
                v.model,
                v.plate,
                v.ano_fabrica,
                v.ano_modelo,
                v.cor,
                v.obs,
                v.numero,
                v.numero_chassi,
                v.id_seguradora,
                v.status,
                v.numero_1,
                v.numero_2,
                v.combustivel,
                c.name AS "customerName"
            FROM vehicles v
            LEFT JOIN customers c ON v.tenant_id = c.tenant_id AND v.id_cliente = c.erp_id
            WHERE v.tenant_id = $1 AND v.plate = $2
        `, [tenantId, cleanPlate]);

        if (pgResult.rows.length > 0) {
            const row = pgResult.rows[0];
            logger.info('[VehicleService] Placa encontrada no banco de dados local', { plate: cleanPlate, tenantId });
            return {
                id_cliente: row.id_cliente,
                id_veiculo: row.id_veiculo,
                marca: row.brand,
                brand: row.brand,
                modelo: row.model,
                model: row.model,
                placa: row.plate,
                plate: row.plate,
                ano_fabrica: row.ano_fabrica,
                ano_modelo: row.ano_modelo,
                cor: row.cor,
                obs: row.obs,
                numero: row.numero,
                numero_chassi: row.numero_chassi,
                id_seguradora: row.id_seguradora,
                status: row.status,
                numero_1: row.numero_1,
                numero_2: row.numero_2,
                combustivel: row.combustivel,
                customerName: row.customerName
            };
        }
    } catch (err) {
        logger.error('[VehicleService] Falha ao consultar tabela local de veículos', { error: err.message, plate: cleanPlate, tenantId });
    }

    const cacheKey = `${CACHE_PREFIX}${cleanPlate}`;

    // 1. Tenta no Redis
    try {
        const cached = await redis.get(cacheKey);
        if (cached) {
            logger.debug('[VehicleService] Cache hit para placa', { plate: cleanPlate, tenantId });
            return JSON.parse(cached);
        }
    } catch (err) {
        logger.warn('[VehicleService] Falha ao ler do Redis, caindo para API', { error: err.message });
    }

    // 2. Busca na APIBrasil
    if (!config.vehicle.apibrasilToken) {
         logger.warn('[VehicleService] Credenciais da APIBrasil não configuradas! Simulando dados para placa', { plate: cleanPlate });
         // Retorna dados mockados em caso de falta de config (para dev não travar)
         return {
             placa: cleanPlate,
             marca: 'HONDA',
             modelo: 'CIVIC EXL',
             ano: '2020',
             ano_modelo: '2020',
             cor: 'PRETA',
             chassi: '***1234***'
         };
    }

    try {
        const response = await fetch('https://gateway.apibrasil.io/api/v2/consulta/veiculos/credits', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${config.vehicle.apibrasilToken}`
            },
            body: JSON.stringify({
                tipo: 'fipe-chassi',
                placa: cleanPlate
            })
        });

        if (!response.ok) {
            const result = await response.json().catch(() => ({}));
            logger.error('[VehicleService] Erro da APIBrasil', { status: response.status, body: result });
            
            if (response.status === 404) {
                const err = new Error('Veículo não encontrado');
                err.status = 404;
                throw err;
            }
            
            const err = new Error('Falha ao consultar parceiro de dados veiculares');
            err.status = 502;
            throw err;
        }

        const body = await response.json();

        if (body.error) {
            const msg = body.message || 'Erro ao processar consulta na APIBrasil';
            logger.error('[VehicleService] Erro retornado pela APIBrasil', { message: msg });
            if (msg.toLowerCase().includes('não encontrado') || msg.toLowerCase().includes('not found')) {
                const err = new Error('Veículo não encontrado');
                err.status = 404;
                throw err;
            }
            const err = new Error(msg);
            err.status = 502;
            throw err;
        }

        const resultados = body.data?.resultados || [];
        if (resultados.length === 0) {
            const err = new Error('Veículo não encontrado');
            err.status = 404;
            throw err;
        }

        const principal = resultados.find(r => r.principal === true) || resultados[0];
        
        // Mapear campos da APIBrasil para nosso padrão interno
        const result = {
            placa: cleanPlate,
            marca: (principal.marca || 'GENERICA').toUpperCase(),
            modelo: (principal.modelo || 'GENERICO').toUpperCase(),
            ano: String(principal.anoFabricacao || principal.anoModelo || '2020'),
            ano_modelo: String(principal.anoModelo || principal.anoFabricacao || '2020'),
            cor: (principal.cor || 'PRETA').toUpperCase(),
            chassi: principal.chassi || '***1234***',
            motor: principal.motor
        };

        // 3. Salva no Redis
        try {
            await redis.setex(cacheKey, config.vehicle.cacheTtlSeconds, JSON.stringify(result));
            logger.info('[VehicleService] Placa consultada na API e salva no cache', { plate: cleanPlate, tenantId });
        } catch (err) {
            logger.error('[VehicleService] Falha ao salvar no Redis', { error: err.message });
        }

        // 4. Salva no Postgres para termos persistência local
        try {
            await pool.query(`
                INSERT INTO vehicles (
                    tenant_id, brand, model, plate, ano_fabrica, ano_modelo, cor, numero_chassi, status
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 1)
                ON CONFLICT (tenant_id, plate) DO UPDATE SET
                    brand = EXCLUDED.brand,
                    model = EXCLUDED.model,
                    ano_fabrica = EXCLUDED.ano_fabrica,
                    ano_modelo = EXCLUDED.ano_modelo,
                    cor = EXCLUDED.cor,
                    numero_chassi = EXCLUDED.numero_chassi,
                    updated_at = NOW()
            `, [
                tenantId,
                result.marca,
                result.modelo,
                result.placa,
                parseInt(result.ano, 10) || null,
                parseInt(result.ano_modelo, 10) || null,
                result.cor,
                result.chassi
            ]);
            logger.info('[VehicleService] Veículo persistido no banco de dados local Postgres', { plate: cleanPlate, tenantId });
        } catch (err) {
            logger.error('[VehicleService] Falha ao salvar veículo no Postgres', { error: err.message, plate: cleanPlate });
        }

        return result;

    } catch (err) {
        if (!err.status) {
            logger.error('[VehicleService] Falha de rede ao contatar APIBrasil', { error: err.message });
            err.status = 500;
        }
        throw err;
    }
}

/**
 * Upsert de lote de veículos vindos do ERP Firebird.
 * 
 * @param {string} tenantId 
 * @param {Array} vehicles 
 * @returns {Promise<Object>}
 */
async function upsertBatch(tenantId, vehicles) {
    if (!vehicles || vehicles.length === 0) return { synced: 0 };

    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        let synced = 0;
        for (const item of vehicles) {
            const cleanPlate = item.plate?.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
            if (!cleanPlate) continue;

            const query = `
                INSERT INTO vehicles (
                    tenant_id, id_cliente, id_veiculo, brand, model, plate, 
                    ano_fabrica, ano_modelo, cor, obs, numero, numero_chassi, 
                    id_seguradora, status, numero_1, numero_2, combustivel, updated_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, NOW())
                ON CONFLICT (tenant_id, plate)
                DO UPDATE SET
                    id_cliente = EXCLUDED.id_cliente,
                    id_veiculo = EXCLUDED.id_veiculo,
                    brand = EXCLUDED.brand,
                    model = EXCLUDED.model,
                    ano_fabrica = EXCLUDED.ano_fabrica,
                    ano_modelo = EXCLUDED.ano_modelo,
                    cor = EXCLUDED.cor,
                    obs = EXCLUDED.obs,
                    numero = EXCLUDED.numero,
                    numero_chassi = EXCLUDED.numero_chassi,
                    id_seguradora = EXCLUDED.id_seguradora,
                    status = EXCLUDED.status,
                    numero_1 = EXCLUDED.numero_1,
                    numero_2 = EXCLUDED.numero_2,
                    combustivel = EXCLUDED.combustivel,
                    updated_at = NOW()
            `;

            const values = [
                tenantId,
                item.id_cliente || null,
                item.id_veiculo || null,
                item.brand || null,
                item.model || null,
                cleanPlate,
                item.ano_fabrica || null,
                item.ano_modelo || null,
                item.cor || null,
                item.obs || null,
                item.numero || null,
                item.numero_chassi || null,
                item.id_seguradora || null,
                item.status || null,
                item.numero_1 || null,
                item.numero_2 || null,
                item.combustivel || null
            ];

            await client.query(query, values);
            synced++;
        }

        await client.query('COMMIT');
        return { synced };
    } catch (err) {
        await client.query('ROLLBACK');
        logger.error('[VehicleService] Erro ao sincronizar lote de veículos', { error: err.message, tenantId });
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Busca todos os veículos associados a um cliente.
 * 
 * @param {number} customerId - ERP ID do cliente
 * @param {string} tenantId 
 * @returns {Promise<Array>} Lista de veículos do cliente
 */
async function getVehiclesByCustomer(customerId, tenantId) {
    const pgResult = await pool.query(`
        SELECT 
            id_cliente,
            id_veiculo,
            brand,
            model,
            plate,
            ano_fabrica,
            ano_modelo,
            cor,
            obs,
            numero,
            numero_chassi,
            id_seguradora,
            status,
            numero_1,
            numero_2,
            combustivel
        FROM vehicles
        WHERE tenant_id = $1 AND id_cliente = $2
        ORDER BY brand ASC, model ASC
    `, [tenantId, customerId]);

    return pgResult.rows.map(row => ({
        id_cliente: row.id_cliente,
        id_veiculo: row.id_veiculo,
        marca: row.brand,
        brand: row.brand,
        modelo: row.model,
        model: row.model,
        placa: row.plate,
        plate: row.plate,
        ano_fabrica: row.ano_fabrica,
        ano_modelo: row.ano_modelo,
        cor: row.cor,
        obs: row.obs,
        numero: row.numero,
        numero_chassi: row.numero_chassi,
        id_seguradora: row.id_seguradora,
        status: row.status,
        numero_1: row.numero_1,
        numero_2: row.numero_2,
        combustivel: row.combustivel
    }));
}

module.exports = {
    fetchVehicleByPlate,
    upsertBatch,
    getVehiclesByCustomer
};
