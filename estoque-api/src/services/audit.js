'use strict';

const db = require('../db');

/** Registra uma ação. Aceita um client de transação para gravar junto com a mudança. */
function audit(clientOrNull, { tenantId, documentId = null, userId = null, action, details = {} }) {
    const runner = clientOrNull || db;
    return runner.query(
        'INSERT INTO audit_log (tenant_id, document_id, user_id, action, details) VALUES ($1, $2, $3, $4, $5)',
        [tenantId, documentId, userId, action, JSON.stringify(details)],
    );
}

module.exports = { audit };
