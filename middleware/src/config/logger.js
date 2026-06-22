/**
 * Logger estruturado com Winston.
 * - Produção: JSON em arquivo rotacionado diariamente + console
 * - Desenvolvimento: colorizado e legível no terminal
 *
 * REGRA: Nunca logar dados sensíveis (senhas, API keys, CPF, e-mail).
 */
'use strict';

const path = require('path');
const { createLogger, format, transports } = require('winston');
const { nodeEnv } = require('./env');

const { combine, timestamp, errors, json, colorize, printf } = format;

// Respeita LOG_DIR do .env (ou usa padrão relativo à raiz do app em /app/logs)
const LOG_DIR = process.env.LOG_DIR ? path.resolve(process.env.LOG_DIR)
    : path.resolve(__dirname, '..', '..', 'logs');
const LOG_LEVEL = process.env.LOG_LEVEL || (nodeEnv === 'production' ? 'info' : 'debug');

// Formato amigável para terminal de desenvolvimento
const devFormat = combine(
    colorize({ all: true }),
    timestamp({ format: 'HH:mm:ss' }),
    errors({ stack: true }),
    printf(({ timestamp, level, message, ...meta }) => {
        const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
        return `[${timestamp}] ${level}: ${message}${metaStr}`;
    })
);

// Formato JSON para produção (indexável por ferramentas APM)
const prodFormat = combine(
    timestamp(),
    errors({ stack: true }),
    json()
);

const isProduction = nodeEnv === 'production';

const logTransports = [
    new transports.Console({
        format: isProduction ? prodFormat : devFormat,
    }),
];

// Em produção: persiste logs em arquivo com rotação diária
if (isProduction) {
    logTransports.push(
        new transports.File({
            dirname: LOG_DIR,
            filename: `middleware-${new Date().toISOString().slice(0, 10)}.log`,
            format: prodFormat,
            maxsize: 10 * 1024 * 1024,  // 10 MB por arquivo
            maxFiles: 14,                  // ≈ 2 semanas de histórico
            tailable: true,
        })
    );
}

const logger = createLogger({
    level: LOG_LEVEL,
    format: isProduction ? prodFormat : devFormat,
    transports: logTransports,
    // Captura exceções e rejeições não tratadas
    exceptionHandlers: logTransports,
    rejectionHandlers: logTransports,
    defaultMeta: {
        service: 'coliseu-middleware',
        version: process.env.npm_package_version || '1.0.0',
    },
});

module.exports = logger;
