'use strict';

require('dotenv').config();

function required(key) {
    const val = process.env[key];
    if (!val) throw new Error(`[Config] Variável de ambiente obrigatória ausente: ${key}`);
    return val;
}

function optional(key, defaultValue = '') {
    return process.env[key] ?? defaultValue;
}

const config = {
    server: {
        port: parseInt(optional('PORT', '3100'), 10),
        nodeEnv: optional('NODE_ENV', 'development'),
        isProduction: optional('NODE_ENV', 'development') === 'production',
    },

    security: {
        jwtDeviceKey: required('JWT_DEVICE_KEY'),
        expectedModuleSlug: optional('EXPECTED_MODULE_SLUG', 'autocenter'),
        allowedOrigins: optional('ALLOWED_ORIGINS', '')
            .split(',')
            .map(s => s.trim())
            .filter(Boolean),
        rateLimitWindowMs: parseInt(optional('RATE_LIMIT_WINDOW_MS', '60000'), 10),
        rateLimitMax: parseInt(optional('RATE_LIMIT_MAX', '200'), 10),
        identityApiUrl: optional('IDENTITY_API_URL') || 'https://adminlicencas.coliseusistemas.com.br',
        identityInternalKey: optional('IDENTITY_INTERNAL_KEY') || 'Coliseu2026!IdentitySuperSecretKeyOauth20',
    },

    postgres: {
        host: optional('PG_HOST', 'localhost'),
        port: parseInt(optional('PG_PORT', '5432'), 10),
        database: optional('PG_DATABASE', 'autocenter_db'),
        user: optional('PG_USER', 'coliseu_admin'),
        password: optional('PG_PASSWORD', ''),
        ssl: optional('PG_SSL', 'false') === 'true',
    },

    redis: {
        host: optional('REDIS_HOST', ''),
        port: parseInt(optional('REDIS_PORT', '6379'), 10),
        password: optional('REDIS_PASSWORD', ''),
        url: optional('REDIS_URL', 'redis://localhost:6379'),
    },

    vehicle: {
        cacheTtlSeconds: parseInt(optional('VEHICLE_CACHE_TTL_SECONDS', '86400'), 10),
        apibrasilToken: optional('APIBRASIL_TOKEN', 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwczovL2dhdGV3YXkuYXBpYnJhc2lsLmlvL2FwaS92Mi9hdXRoL2tleWNsb2FrL2V4Y2hhbmdlIiwiaWF0IjoxNzc2Mzc0OTAxLCJleHAiOjE4MDc5MTA5MDEsIm5iZiI6MTc3NjM3NDkwMSwianRpIjoiT1Nxb0NtTk16TjVHaXNwYyIsInN1YiI6IjQxMTg1In0.1ejqxDV-BZfAvP_YZqyTat5HvhaJEHywQ08Pjgawl6c'),
        apibrasilDeviceToken: optional('APIBRASIL_DEVICE_TOKEN', ''),
    },
};

module.exports = config;
