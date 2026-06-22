/**
 * FirebirdManager — Gerenciador multi-tenant de pools Firebird.
 *
 * Responsabilidades:
 * - Criar e reutilizar pools de conexão por empresa (companyId)
 * - Inatividade: destruir pools sem uso por > 10 min (GC automático)
 * - Expor queryFor / executeFor para uso nas rotas de sync
 * - Descriptografar fb_password antes de criar o pool
 *
 * Segurança (Rule-04):
 *   Senhas nunca são logadas. A descriptografia ocorre em memória,
 *   nunca persiste em disco após descriptografar.
 *
 * @module services/firebird.manager
 */
'use strict';

const Firebird = require('node-firebird');
const crypto = require('crypto');
const logger = require('../config/logger');

// ─────────────────────────────────────────────────────────────────────────────
// Criptografia AES-256-GCM (mesma lógica do backend .NET via ENCRYPTION_KEY)
// ─────────────────────────────────────────────────────────────────────────────

const ENCRYPTION_KEY_B64 = process.env.ENCRYPTION_KEY || '';
const ALGO = 'aes-256-gcm';

/**
 * Descriptografa uma string criptografada com AES-256-GCM.
 * Formato: base64(iv[12] + tag[16] + ciphertext)
 *
 * @param {string} encryptedB64
 * @returns {string} texto puro
 */
function decrypt(encryptedB64) {
    if (!encryptedB64) return '';
    try {
        const key = Buffer.from(ENCRYPTION_KEY_B64, 'base64');
        const buf = Buffer.from(encryptedB64, 'base64');
        const iv = buf.subarray(0, 12);
        const tag = buf.subarray(12, 28);
        const data = buf.subarray(28);
        const dec = crypto.createDecipheriv(ALGO, key, iv);
        dec.setAuthTag(tag);
        return Buffer.concat([dec.update(data), dec.final()]).toString('utf8');
    } catch (e) {
        logger.error('[FirebirdManager] Falha ao descriptografar fb_password', { error: e.message });
        return '';
    }
}

/**
 * Criptografa uma string com AES-256-GCM.
 * Retorna base64(iv[12] + tag[16] + ciphertext)
 *
 * @param {string} plaintext
 * @returns {string} base64 cifrado
 */
function encrypt(plaintext) {
    if (!plaintext) return '';
    const key = Buffer.from(ENCRYPTION_KEY_B64, 'base64');
    const iv = crypto.randomBytes(12);
    const enc = crypto.createCipheriv(ALGO, key, iv);
    const data = Buffer.concat([enc.update(plaintext, 'utf8'), enc.final()]);
    const tag = enc.getAuthTag();
    return Buffer.concat([iv, tag, data]).toString('base64');
}

// ─────────────────────────────────────────────────────────────────────────────
// Pool cache
// ─────────────────────────────────────────────────────────────────────────────

// Map<companyId → { pool, lastUsed, options }>
const _pools = new Map();
const IDLE_TTL_MS = 10 * 60 * 1000;   // 10 minutos sem uso
const POOL_MAX = 5;                  // máx conexões por empresa

// GC automático: roda a cada 5 minutos
const _gcInterval = setInterval(_gcPools, 5 * 60 * 1000);
_gcInterval.unref(); // não impede o processo de fechar

function _gcPools() {
    const now = Date.now();
    for (const [id, entry] of _pools.entries()) {
        if (now - entry.lastUsed > IDLE_TTL_MS) {
            logger.info('[FirebirdManager] Pool inativo destruído', { companyId: id });
            try { entry.pool.destroy(() => { }); } catch (_) { }
            _pools.delete(id);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// API pública
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Obtém (ou cria) o pool Firebird de uma empresa.
 *
 * @param {object} company  Objeto req.company com { id, fb_host, fb_port, fb_database, fb_user, fb_password, fb_charset, fb_wire_crypt }
 * @returns {object} pool node-firebird
 * @throws {Error} se credenciais Firebird não estiverem configuradas
 */
function _getPool(company) {
    const id = company.id;

    if (_pools.has(id)) {
        const entry = _pools.get(id);
        entry.lastUsed = Date.now();
        return entry.pool;
    }

    if (!company.fb_host || !company.fb_database) {
        throw new Error(
            `Empresa "${company.name}" não tem conexão Firebird configurada. ` +
            'Configure no painel admin: host, porta, banco, usuário e senha.'
        );
    }

    const password = company.fb_password ? decrypt(company.fb_password) : '';

    const fbOptions = {
        host: company.fb_host,
        port: company.fb_port || 3050,
        database: company.fb_database,
        user: company.fb_user || 'SYSDBA',
        password,
        charset: company.fb_charset || 'WIN1252',
        lowercase_keys: false,
        role: null,
        pageSize: 4096,
        WireCrypt: company.fb_wire_crypt ?? false,
    };

    logger.info('[FirebirdManager] Criando pool', {
        companyId: id,
        host: fbOptions.host,
        database: fbOptions.database,
        user: fbOptions.user,
    });

    const pool = Firebird.pool(POOL_MAX, fbOptions);
    _pools.set(id, { pool, lastUsed: Date.now(), options: fbOptions });
    return pool;
}

/**
 * Obtém uma conexão do pool de uma empresa.
 *
 * @param {object} company
 * @returns {Promise<import('node-firebird').Database>}
 */
function _getConnection(company) {
    const pool = _getPool(company);
    return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
            reject(new Error(`[FirebirdManager] Timeout ao conectar no Firebird da empresa "${company.name}" (1.5s).`));
        }, 1500);

        pool.get((err, db) => {
            clearTimeout(timeout);
            if (err) {
                reject(new Error(`[FirebirdManager] Falha ao conectar: ${err.message}`));
                return;
            }
            resolve(db);
        });
    });
}

/**
 * Executa uma query SELECT no Firebird da empresa.
 *
 * @param {object} company     req.company com credenciais Firebird
 * @param {string} sql
 * @param {Array}  [params=[]]
 * @returns {Promise<Array>}
 */
async function queryFor(company, sql, params = []) {
    const db = await _getConnection(company);
    return new Promise((resolve, reject) => {
        db.query(sql, params, (err, result) => {
            db.detach();
            if (err) {
                logger.error('[FirebirdManager] Erro na query', {
                    companyId: company.id, error: err.message,
                });
                reject(new Error(`Erro na consulta ao banco: ${err.message}`));
                return;
            }
            resolve(result || []);
        });
    });
}

/**
 * Executa uma instrução DML no Firebird da empresa.
 *
 * @param {object} company
 * @param {string} sql
 * @param {Array}  [params=[]]
 * @returns {Promise<void>}
 */
async function executeFor(company, sql, params = []) {
    const db = await _getConnection(company);
    return new Promise((resolve, reject) => {
        db.execute(sql, params, (err) => {
            db.detach();
            if (err) {
                logger.error('[FirebirdManager] Erro no execute', {
                    companyId: company.id, error: err.message,
                });
                reject(new Error(`Erro ao executar no banco: ${err.message}`));
                return;
            }
            resolve();
        });
    });
}

/**
 * Testa a conexão Firebird de uma empresa sem executar query real.
 * Útil para o endpoint de validação no painel admin.
 *
 * @param {object} credentials { fb_host, fb_port, fb_database, fb_user, fb_password_plain, fb_charset }
 * @returns {Promise<{ ok: boolean, error?: string }>}
 */
async function testConnection(credentials) {
    const fbOptions = {
        host: credentials.fb_host,
        port: credentials.fb_port || 3050,
        database: credentials.fb_database,
        user: credentials.fb_user || 'SYSDBA',
        password: credentials.fb_password_plain,
        charset: credentials.fb_charset || 'WIN1252',
        WireCrypt: credentials.fb_wire_crypt ?? false,
    };

    return new Promise((resolve) => {
        const timeout = setTimeout(() => {
            resolve({ ok: false, error: 'Timeout ao conectar (15s). Verifique host, porta e firewall.' });
        }, 15_000);

        Firebird.attach(fbOptions, (err, db) => {
            clearTimeout(timeout);
            if (err) {
                resolve({ ok: false, error: err.message });
                return;
            }
            db.detach(() => resolve({ ok: true }));
        });
    });
}

/**
 * Destroi todos os pools (graceful shutdown).
 * @returns {Promise<void>}
 */
async function destroyAll() {
    clearInterval(_gcInterval);
    const promises = [];
    for (const [, entry] of _pools.entries()) {
        promises.push(new Promise((res) => {
            try { entry.pool.destroy(res); } catch (_) { res(); }
        }));
    }
    _pools.clear();
    await Promise.all(promises);
}

module.exports = {
    queryFor,
    executeFor,
    testConnection,
    encrypt,
    decrypt,
    destroyAll,
};
