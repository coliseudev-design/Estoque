'use strict';

const logger = require('../config/logger');

/**
 * Global Error Handler for Express
 * Must be the last middleware in the chain (app.use(errorHandler))
 * 
 * @param {Error} err 
 * @param {import('express').Request} req 
 * @param {import('express').Response} res 
 * @param {import('express').NextFunction} next 
 */
function errorHandler(err, req, res, next) {
    // If headers are already sent, delegate to default express handler
    if (res.headersSent) {
        return next(err);
    }

    // Capture specifics
    const status = err.status || 500;
    const body = {
        error: err.message || 'Erro interno do servidor',
        code: err.code || 'INTERNAL_ERROR'
    };

    // Logging
    if (status >= 500) {
        logger.error(`[ErrorHandler] ${req.method} ${req.path}`, {
            error: err.message,
            stack: err.stack,
            tenantId: req.tenant?.id,
            deviceId: req.device?.id
        });
    } else {
        logger.warn(`[ErrorHandler] ${req.method} ${req.path}`, {
            error: err.message,
            status,
            code: body.code
        });
    }

    res.status(status).json(body);
}

module.exports = { errorHandler };
