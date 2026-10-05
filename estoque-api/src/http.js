/**
 * Utilitários HTTP: erro tipado, wrapper async e validação com zod.
 */
'use strict';

class HttpError extends Error {
    constructor(status, code, message, extra) {
        super(message);
        this.status = status;
        this.code = code;
        this.extra = extra;
    }
}

const badRequest = (msg, extra) => new HttpError(400, 'BAD_REQUEST', msg, extra);
const unauthorized = (msg = 'Não autorizado', code = 'UNAUTHORIZED') => new HttpError(401, code, msg);
const forbidden = (msg = 'Sem permissão para esta ação', code = 'FORBIDDEN') => new HttpError(403, code, msg);
const notFound = (msg = 'Não encontrado') => new HttpError(404, 'NOT_FOUND', msg);
const conflict = (msg, code = 'CONFLICT', extra) => new HttpError(409, code, msg, extra);

/** Encaminha rejeições de handlers async para o errorHandler do Express. */
const route = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Valida `data` com um schema zod; lança 400 com os campos inválidos. */
function parse(schema, data) {
    const result = schema.safeParse(data);
    if (result.success) return result.data;
    const fields = result.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
    throw badRequest('Dados inválidos', { fields });
}

module.exports = { HttpError, badRequest, unauthorized, forbidden, notFound, conflict, route, parse };
