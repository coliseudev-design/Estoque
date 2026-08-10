'use strict';

const winston = require('winston');
const config = require('./env');

const { combine, timestamp, printf, colorize, errors } = winston.format;

const customFormat = printf(({ level, message, timestamp, stack, ...meta }) => {
    let log = `${timestamp} [${level}]: ${message}`;
    if (Object.keys(meta).length) {
        log += ` | ${JSON.stringify(meta)}`;
    }
    if (stack) {
        log += `\n${stack}`;
    }
    return log;
});

const logger = winston.createLogger({
    level: config.server.isProduction ? 'info' : 'debug',
    format: combine(
        errors({ stack: true }),
        timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        config.server.isProduction ? winston.format.json() : combine(colorize(), customFormat)
    ),
    transports: [
        new winston.transports.Console()
    ]
});

module.exports = logger;
