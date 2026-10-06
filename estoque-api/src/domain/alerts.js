/**
 * Críticas operacionais de um documento — o que precisa de atenção na fila.
 * Funções puras; a mesma regra existe em SQL (ATTENTION_SQL) para o filtro
 * "somente com críticas" e para as contagens. Mantenha as duas em sincronia.
 */
'use strict';

const OPEN = ['AGUARDANDO', 'EM_CONFERENCIA', 'DIVERGENTE', 'AGUARDANDO_APROVACAO'];

/** Entrada = nota de compra importada (NFE); saída = pedido de venda / nota de saída do ERP. */
const flowOf = (source) => (source === 'NFE' ? 'entrada' : 'saida');

/**
 * @param {object} d  cabeçalho já mapeado (camelCase)
 * @param {object} opts { slaHours, critiques: {erro, alerta, info}, now }
 * @returns {Array<{level:'erro'|'alerta'|'info', code:string, message:string}>}
 */
function documentAlerts(d, { slaHours = 24, critiques, now = new Date() } = {}) {
    const out = [];
    const add = (level, code, message) => out.push({ level, code, message });
    const open = OPEN.includes(d.status);

    if (d.erpCancelled && d.status === 'CONCLUIDO') add('erro', 'CANCELLED_AFTER', 'Cancelado no ERP depois de conferido');
    if (d.invoiceNumber && open) add('erro', 'INVOICED_EARLY', `Faturado (NF ${d.invoiceNumber}) antes de concluir a conferência`);
    if (d.writebackStatus === 'ERRO') add('erro', 'WRITEBACK_ERROR', 'Falha ao gravar o resultado no ERP');
    if (d.erpChanged) add('alerta', 'ERP_CHANGED', 'O ERP alterou o documento durante a conferência');
    if (d.status === 'AGUARDANDO_APROVACAO') add('alerta', 'NEEDS_APPROVAL', 'Divergência aguardando decisão do supervisor');
    if (d.status === 'DIVERGENTE') add('alerta', 'RECOUNT', 'Divergência na contagem — em recontagem');

    const since = d.importedAt || d.issuedAt;
    if (d.status === 'AGUARDANDO' && since) {
        const hours = (now - new Date(since)) / 3_600_000;
        if (hours > slaHours) {
            add('alerta', 'SLA', `Parado na fila há ${hours < 48 ? `${Math.floor(hours)} h` : `${Math.floor(hours / 24)} dias`} (meta: ${slaHours} h)`);
        }
    }
    if (d.status === 'EM_CONFERENCIA' && !d.lock) add('alerta', 'STALLED', 'Conferência iniciada e abandonada (reserva expirou)');

    if (critiques && open) {
        if (critiques.erro) add('erro', 'ENTRY_ERRORS', `${critiques.erro} crítica(s) grave(s) na nota`);
        if (critiques.alerta) add('alerta', 'ENTRY_WARNINGS', `${critiques.alerta} crítica(s) na nota para revisar`);
    }
    return out;
}

/** Mesma regra de documentAlerts em SQL. Um parâmetro: horas do SLA (marcado com ?). */
const ATTENTION_SQL = `(d.erp_changed OR d.writeback_status = 'ERRO'
    OR d.status IN ('DIVERGENTE','AGUARDANDO_APROVACAO')
    OR (d.invoice_number IS NOT NULL AND d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE','AGUARDANDO_APROVACAO'))
    OR (d.erp_cancelled AND d.status = 'CONCLUIDO')
    OR (d.status = 'AGUARDANDO' AND COALESCE(d.imported_at, d.issued_at) < now() - (? || ' hours')::interval)
    OR (d.status = 'EM_CONFERENCIA' AND (d.lock_expires_at IS NULL OR d.lock_expires_at < now()))
    OR (d.status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE','AGUARDANDO_APROVACAO')
        AND COALESCE((d.meta->'critiques'->>'erro')::int, 0) + COALESCE((d.meta->'critiques'->>'alerta')::int, 0) > 0))`;

module.exports = { documentAlerts, flowOf, ATTENTION_SQL, OPEN };
