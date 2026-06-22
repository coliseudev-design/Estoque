/**
 * Serviço de acesso ao Firebird com pool de conexões.
 *
 * Responsabilidades:
 * - Gerenciar pool de conexões reutilizáveis
 * - Expor métodos seguros de query, execute e transaction
 * - Modo mock para desenvolvimento sem banco real (FB_MOCK=true)
 * - Nunca expor detalhes de conexão em erros propagados
 *
 * @module services/firebird.service
 */
'use strict';

const Firebird = require('node-firebird');
const config = require('../config/env');
const logger = require('../config/logger');

// ─────────────────────────────────────────────────────────────────────────────
// Pool e Configuração — REAL
// ─────────────────────────────────────────────────────────────────────────────

let pool = null;

// ─────────────────────────────────────────────────────────────────────────────
// MOCK — Dados simulados para desenvolvimento sem banco Firebird
// ─────────────────────────────────────────────────────────────────────────────

const MOCK_ORDERS = new Map();

const mockDb = {
    /**
     * Simula SELECT — retorna sempre array vazio para queries genéricas.
     * @param {string} sql
     * @param {Array} params
     * @returns {Promise<Array>}
     */
    query: async (sql, params = []) => {
        logger.debug('[MOCK] Query executada', { sql: sql.substring(0, 80), params });
        // Idempotência: SELECT de UUID de pedido
        if (sql.includes('SALES_ORDERS') && sql.includes('WHERE') && params[0]) {
            const found = MOCK_ORDERS.has(params[0]);
            return found ? [{ ID: params[0] }] : [];
        }
        return [];
    },

    /**
     * Simula INSERT/UPDATE — armazena em memória para testes de idempotência.
     * @param {string} sql
     * @param {Array} params
     * @returns {Promise<void>}
     */
    execute: async (sql, params = []) => {
        logger.debug('[MOCK] Execute executado', { sql: sql.substring(0, 80) });
        if (sql.includes('INSERT INTO SALES_ORDERS') && params[0]) {
            MOCK_ORDERS.set(params[0], { id: params[0], createdAt: new Date() });
        }
    },

    /**
     * Simula uma transação — executa função de callback com mock db.
     * @param {Function} fn
     * @returns {Promise<any>}
     */
    transaction: async (fn) => fn(mockDb),
};

// ─────────────────────────────────────────────────────────────────────────────
// POOL REAL
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Inicializa o pool de conexões Firebird.
 * Deve ser chamado uma única vez no startup da aplicação.
 *
 * Em desenvolvimento: se o Firebird não estiver disponível, ativa mock automático
 * e o middleware continua funcionando (degraded mode).
 * Em produção: falha fatalmente se não conseguir conectar.
 *
 * @returns {Promise<void>}
 */
async function initPool() {
    if (config.firebird.mock) {
        logger.warn('[FirebirdService] Modo MOCK ativo. Nenhuma conexão real ao banco será feita.');
        return;
    }

    return new Promise((resolve, reject) => {
        // Opções de conexão para o node-firebird
        const fbOptions = {
            host: config.firebird.host,
            port: config.firebird.port,
            database: config.firebird.database,
            user: config.firebird.user,
            password: config.firebird.password,
            lowercase_keys: config.firebird.lowercase_keys,
            role: config.firebird.role,
            pageSize: config.firebird.pageSize,
            charset: config.firebird.charset,
            WireCrypt: config.firebird.wireCrypt ?? true,
        };

        logger.debug('[FirebirdService] Criando pool...', {
            host: fbOptions.host,
            database: fbOptions.database,
            user: fbOptions.user ? 'DEFINED' : 'MISSING',
            port: fbOptions.port
        });

        pool = Firebird.pool(config.firebird.poolMax, fbOptions);
        // Teste de conectividade imediato
        pool.get((err, db) => {
            if (err) {
                const isDev = config.nodeEnv !== 'production';
                const isAsync = process.env.SYNC_MODE === 'async';

                // Em dev OU em async mode (VPS): ativa mock automático.
                // No VPS com SYNC_MODE=async, o Worker é quem conecta ao Firebird.
                // O middleware nunca precisa de conexão direta — não crasha.
                if (isDev || isAsync) {
                    logger.warn('[FirebirdService] ⚠️ Firebird indisponível — ativando modo MOCK automático.', {
                        host: config.firebird.host,
                        database: config.firebird.database,
                        error: err.message,
                        mode: isAsync ? 'async (VPS — Worker faz push)' : 'dev',
                    });
                    config.firebird.mock = true;
                    pool = null;
                    resolve();
                } else {
                    // direct-mode em produção: Firebird é obrigatório
                    reject(new Error(`[FirebirdService] Falha ao conectar ao banco: ${err.message}`));
                }
                return;
            }
            db.detach();
            logger.info('[FirebirdService] Pool iniciado com sucesso.', {
                host: config.firebird.host,
                poolMax: config.firebird.poolMax,
            });
            resolve();
        });
    });
}

/**
 * Obtém uma conexão do pool.
 * @returns {Promise<import('node-firebird').Database>}
 */
function getConnection() {
    return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
            reject(new Error('[FirebirdService] Timeout ao obter conexão do pool (1.5s).'));
        }, 1500);

        pool.get((err, db) => {
            clearTimeout(timeout);
            if (err) {
                reject(new Error(`[FirebirdService] Falha ao obter conexão: ${err.message}`));
                return;
            }
            resolve(db);
        });
    });
}

/**
 * Executa uma query SELECT e retorna as linhas resultantes.
 *
 * @param {string} sql - Instrução SQL parametrizada.
 * @param {Array} [params=[]] - Parâmetros posicionais da query.
 * @returns {Promise<Array<Object>>} Linhas retornadas pelo banco.
 * @throws {Error} Se a query falhar.
 *
 * @example
 * const rows = await query('SELECT ID FROM SALES_ORDERS WHERE ID = ?', [uuid]);
 */
async function query(sql, params = []) {
    if (config.firebird.mock) return mockDb.query(sql, params);

    const db = await getConnection();
    return new Promise((resolve, reject) => {
        db.query(sql, params, (err, result) => {
            db.detach();
            if (err) {
                logger.error('[FirebirdService] Erro na query', { error: err.message });
                reject(new Error(`Erro na consulta ao banco: ${err.message}`));
                return;
            }
            resolve(result || []);
        });
    });
}

/**
 * Executa uma stored procedure e retorna as linhas resultantes.
 * Necessário para procedures com cláusula RETURNING, ex: MOB_CADASTRAR_PEDIDO → ID_PEDIDO.
 *
 * @param {string} sql    - EXECUTE PROCEDURE nome(?,?,...)
 * @param {Array}  params - Parâmetros posicionais.
 * @returns {Promise<Array<Object>>} Linhas retornadas (OUT params).
 */
async function queryProc(sql, params = []) {
    if (config.firebird.mock) return mockDb.query(sql, params);

    const db = await getConnection();
    return new Promise((resolve, reject) => {
        db.query(sql, params, (err, result) => {
            db.detach();
            if (err) {
                logger.error('[FirebirdService] Erro na stored procedure', { error: err.message });
                reject(new Error(`Erro ao executar procedure: ${err.message}`));
                return;
            }
            resolve(result || []);
        });
    });
}

/**
 * Executa uma instrução DML (INSERT, UPDATE, DELETE).
 *
 * @param {string} sql - Instrução SQL parametrizada.
 * @param {Array} [params=[]] - Parâmetros posicionais.
 * @returns {Promise<void>}
 * @throws {Error} Se a execução falhar.
 */
async function execute(sql, params = []) {
    if (config.firebird.mock) return mockDb.execute(sql, params);

    const db = await getConnection();
    return new Promise((resolve, reject) => {
        db.execute(sql, params, (err) => {
            db.detach();
            if (err) {
                logger.error('[FirebirdService] Erro no execute', { error: err.message });
                reject(new Error(`Erro ao executar instrução no banco: ${err.message}`));
                return;
            }
            resolve();
        });
    });
}

/**
 * Executa uma função dentro de uma transação ACID.
 * Faz commit se a função resolver, rollback se rejeitar.
 *
 * @param {Function} fn - Função assíncrona que recebe o objeto db.
 * @returns {Promise<any>} Valor retornado por fn.
 * @throws {Error} Se a transação falhar ou fn lançar exceção.
 *
 * @example
 * await transaction(async (db) => {
 *   await executeInTx(db, 'INSERT INTO SALES_ORDERS ...', [...]);
 *   await executeInTx(db, 'INSERT INTO SALES_ORDER_ITEMS ...', [...]);
 * });
 */
async function transaction(fn) {
    if (config.firebird.mock) return mockDb.transaction(fn);

    const db = await getConnection();
    return new Promise((resolve, reject) => {
        db.transaction(Firebird.ISOLATION_READ_COMMITTED, async (err, tx) => {
            if (err) {
                db.detach();
                reject(new Error(`[FirebirdService] Falha ao iniciar transação: ${err.message}`));
                return;
            }

            try {
                const result = await fn(tx);
                tx.commit((commitErr) => {
                    db.detach();
                    if (commitErr) {
                        reject(new Error(`[FirebirdService] Falha no commit: ${commitErr.message}`));
                        return;
                    }
                    resolve(result);
                });
            } catch (fnErr) {
                tx.rollback((rollbackErr) => {
                    db.detach();
                    if (rollbackErr) {
                        logger.error('[FirebirdService] Falha no rollback', { error: rollbackErr.message });
                    }
                    reject(fnErr);
                });
            }
        });
    });
}

/**
 * Executa uma instrução DML dentro de uma transação existente.
 *
 * @param {import('node-firebird').Transaction} tx - Transação ativa.
 * @param {string} sql - Instrução SQL parametrizada.
 * @param {Array} [params=[]] - Parâmetros posicionais.
 * @returns {Promise<void>}
 */
async function executeInTx(tx, sql, params = []) {
    return new Promise((resolve, reject) => {
        tx.execute(sql, params, (err) => {
            if (err) {
                reject(new Error(`Erro na instrução da transação: ${err.message}`));
                return;
            }
            resolve();
        });
    });
}

/**
 * Retorna o status atual do pool de conexões.
 * Usado pelo health check.
 * @returns {{ connected: boolean, mode: string }}
 */
function getPoolStatus() {
    if (config.firebird.mock) return { connected: true, mode: 'mock' };
    return { connected: pool !== null, mode: 'live' };
}

/**
 * Destrói o pool e libera todas as conexões.
 * Usar no graceful shutdown.
 * @returns {Promise<void>}
 */
async function destroyPool() {
    if (pool) {
        const p = pool;
        pool = null;           // zera o ponteiro antes de iniciar o destroy
        return new Promise((resolve) => {
            p.destroy(resolve);
        });
    }
}

module.exports = {
    initPool,
    query,
    queryProc,
    execute,
    executeInTx,
    transaction,
    getPoolStatus,
    destroyPool,
};
