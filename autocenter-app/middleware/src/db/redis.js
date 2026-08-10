'use strict';

const Redis = require('ioredis');
const config = require('../config/env');
const logger = require('../config/logger');

function createRedisClient() {
    let client;
    if (config.redis.host) {
        // Usa configurações explícitas (Prioridade para Coolify)
        logger.info('[Redis] Usando REDIS_HOST explícito', { host: config.redis.host, port: config.redis.port });
        client = new Redis({
            host: config.redis.host,
            port: config.redis.port,
            password: config.redis.password,
            maxRetriesPerRequest: 3,
        });
    } else {
        // Fallback para string de conexão (Dev local)
        logger.info('[Redis] Usando REDIS_URL', { url: config.redis.url.split('@').pop() });
        client = new Redis(config.redis.url, {
            maxRetriesPerRequest: 3,
        });
    }

    client.on('error', (err) => {
        logger.error('[Redis] Erro de conexão', { error: err.message });
    });

    client.on('connect', () => {
        logger.info('[Redis] Conectado com sucesso');
    });

    return client;
}

const redis = createRedisClient();

module.exports = redis;
