/**
 * Handler centralizado de erros da aplicação.
 *
 * Captura todos os erros não tratados nas rotas e middleware.
 * Em produção, nunca expõe stack traces ou mensagens internas detalhadas.
 */
'use strict';

const logger = require('../config/logger');
const { isProduction } = require('../config/env');

/**
 * Middleware de tratamento de erros do Express (4 parâmetros obrigatórios).
 *
 * @param {Error} err
 * @param {import('express').Request} req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} _next - Obrigatório mesmo sem uso.
 */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
    const statusCode = err.statusCode || 500;

    logger.error('[ErrorHandler] Erro não tratado', {
        message: err.message,
        path: req.path,
        method: req.method,
        statusCode,
        stack: isProduction ? undefined : err.stack,
    });

    const response = {
        error: statusCode === 500 ? 'Erro interno do servidor' : err.message,
        code: err.code || 'INTERNAL_ERROR',
    };

    // Em dev, inclui stack para facilitar debug
    if (!isProduction && err.stack) {
        response.debug_stack = err.stack;
    }

    res.status(statusCode).json(response);
}

/**
 * Cria um erro com statusCode customizado.
 *
 * @param {string} message - Mensagem descritiva do erro.
 * @param {number} statusCode - HTTP status code.
 * @param {string} [code] - Código interno do erro.
 * @returns {Error}
 */
function createError(message, statusCode, code) {
    const err = new Error(message);
    err.statusCode = statusCode;
    err.code = code;
    return err;
}

module.exports = { errorHandler, createError };
