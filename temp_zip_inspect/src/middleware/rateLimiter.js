/**
 * rateLimiter.js — Rate limiting por empresa (P1-B).
 *
 * Problema: o rate limiting global permite que uma empresa monopolize
 * o servidor e afete todas as outras.
 *
 * Solução: cada empresa tem sua própria janela de rate limiting,
 * usando Redis como store distribuído (funciona com múltiplas instâncias).
 *
 * Limites configuráveis por rota:
 *   - Sync de catálogo (push Worker): 120 req/min
 *   - Sync de pedidos (push Flutter):  60 req/min
 *   - Geral (default):                 200 req/min
 *
 * @module middleware/rateLimiter
 */
'use strict';

const { client: redisClient } = require('../db/redis');
const { createError } = require('./errorHandler');
const logger = require('../config/logger');

/**
 * Cria um middleware de rate limit por empresa usando Redis (sliding window).
 *
 * @param {object} options
 * @param {number} options.windowMs     Janela em ms (default: 60_000 = 1 min)
 * @param {number} options.max          Máx de requisições por janela (default: 200)
 * @param {string} [options.keyPrefix]  Prefixo para diferenciar limites por rota
 * @returns {import('express').RequestHandler}
 */
function companyRateLimit({ windowMs = 60_000, max = 200, keyPrefix = 'rl' } = {}) {
    const windowSec = Math.ceil(windowMs / 1000);

    return async function rateLimiter(req, res, next) {
        // Se empresa não está autenticada ainda, deixa o auth.js rejeitar
        if (!req.company) return next();

        const key = `${keyPrefix}:${req.company.id}`;

        try {
            const count = await redisClient.incr(key);
            if (count === 1) {
                await redisClient.expire(key, windowSec);
            }

            res.setHeader('X-RateLimit-Limit', max);
            res.setHeader('X-RateLimit-Remaining', Math.max(0, max - count));
            res.setHeader('X-RateLimit-Company', req.company.id);

            if (count > max) {
                logger.warn('[RateLimit] Empresa excedeu o limite', {
                    companyId: req.company.id,
                    name: req.company.name,
                    count, max, key,
                });
                return next(createError(
                    `Limite de requisições excedido para empresa "${req.company.name}". Tente novamente em instantes.`,
                    429,
                    'RATE_LIMITED_COMPANY'
                ));
            }
        } catch (redisErr) {
            // Redis offline — não bloqueia, apenas loga (fail open)
            logger.warn('[RateLimit] Redis indisponível — rate limit ignorado', {
                error: redisErr.message,
            });
        }

        next();
    };
}

// Limites pré-configurados por tipo de rota
const syncCatalogLimit = companyRateLimit({ windowMs: 60_000, max: 120, keyPrefix: 'rl:catalog' });
const syncOrdersLimit = companyRateLimit({ windowMs: 60_000, max: 60, keyPrefix: 'rl:orders' });
const defaultLimit = companyRateLimit({ windowMs: 60_000, max: 200, keyPrefix: 'rl:default' });

module.exports = { companyRateLimit, syncCatalogLimit, syncOrdersLimit, defaultLimit };
