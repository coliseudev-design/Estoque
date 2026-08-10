'use strict';

const rateLimit = require('express-rate-limit');
const config = require('../config/env');

const defaultLimit = rateLimit({
    windowMs: config.security.rateLimitWindowMs,
    max: config.security.rateLimitMax,
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: (req) => {
        // Usa o Tenant (Empresa) como key se autenticado, senao o IP.
        return req.tenant ? req.tenant.id : req.ip;
    },
    message: { error: 'Muitas requisições. Tente novamente em instantes.', code: 'RATE_LIMITED' },
});

// APIs externas (como APIBrasil) devem ter rate limit mais rigoroso para não estourar a cota
const externalApiLimit = rateLimit({
    windowMs: 60 * 1000, // 1 minuto
    max: 20, // maximo de 20 consultas por minuto por tenant
    standardHeaders: true,
    legacyHeaders: false,
    keyGenerator: (req) => {
        return req.tenant ? req.tenant.id : req.ip;
    },
    message: { error: 'Cota de requisições externas excedida.', code: 'RATE_LIMITED_EXTERNAL' },
});

module.exports = {
    defaultLimit,
    externalApiLimit
};
