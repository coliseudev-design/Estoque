'use strict';
/**
 * Rotas de performance, rankings de vendas e logo da empresa.
 *
 * @module routes/sync/performance
 * @route POST /api/sync/performance      — Worker push de KPIs
 * @route GET  /api/sync/performance      — App leitura (store → fallback Firebird)
 * @route POST /api/sync/sales-rankings   — Worker push de rankings
 * @route GET  /api/sync/sales-rankings   — App leitura (store only)
 * @route GET  /api/sync/company-logo     — Logo da empresa em bytes
 */

const express = require('express');
const { fbQuery } = require('./helpers');
const { pgQuery } = require('../../db/postgres');
const { createError } = require('../../middleware/errorHandler');
const store  = require('../../services/dataStore');
const logger = require('../../config/logger');

const router = express.Router();

// ── performance ───────────────────────────────────────────────────────────────

/** @route POST /api/sync/performance */
router.post('/performance', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const branchId  = req.branch?.id || null;
        const data = req.body.performance;
        if (!Array.isArray(data)) {
            return next(createError('Campo "performance" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }
        // [FIX] Passa branchId para isolar dados por filial no Redis
        await store.upsert(companyId, 'performance', data, branchId);
        logger.info(`[Sync/Performance] ${data.length} KPIs recebidos do Worker`, { companyId, branchId });
        res.json({ received: data.length, entity: 'performance', syncedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

/**
 * KPIs de performance do vendedor.
 * Store primeiro (Worker push) → fallback Firebird (MINHASVENDAS + MINHASVENDASR).
 * @route GET /api/sync/performance?sellerId=<id>&month=<m>&year=<y>
 */
router.get('/performance', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now   = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year  = parseInt(req.query.year)  || now.getFullYear();

        const jwtBranchId = req.branch?.id || null;
        let empresaId = parseInt(req.query.empresaId);
        let deptoId = parseInt(req.query.deptoId);
        if (jwtBranchId) {
            const { rows } = await pgQuery('SELECT "ErpEmpresaId" AS erp_empresa_id, "ErpDeptoPadrao" AS erp_depto_padrao FROM branches WHERE "Id" = $1', [jwtBranchId]);
            if (rows.length > 0) {
                if (!empresaId) empresaId = rows[0].erp_empresa_id;
                if (!deptoId) deptoId = rows[0].erp_depto_padrao;
            }
        }
        empresaId = empresaId || 1;
        deptoId = deptoId || 1;

        const forceRefresh = req.query.forceRefresh === 'true';

        // 1. Store (dados do Worker — caminho principal)
        if (!forceRefresh) {
            const cached = await store.get(companyId, 'performance', jwtBranchId);
            if (cached && cached.data.length > 0) {
                // Match exato: sellerId + month + year + deptoId (filial correta)
                // O Worker envia um push por filial, portanto o dado correto sempre existe
                // sob a chave desta filial. Sem fallback permissivo para não cruzar dados.
                const sellerKpis = cached.data.find(
                    k => String(k.sellerId) === String(sellerId) && k.month === month && k.year === year &&
                         String(k.deptoId) === String(deptoId)
                );
                if (sellerKpis) {
                    logger.info('[Sync/Performance] KPIs retornados', { sellerId, month, year, deptoId, branchId: jwtBranchId, source: 'dataStore' });
                    return res.json({ data: sellerKpis, source: 'dataStore' });
                }
                logger.warn('[Sync/Performance] KPI não encontrado no cache para deptoId', { sellerId, deptoId, branchId: jwtBranchId });
            }
        }

        // 2. Fallback: Firebird direto isolado por EMPRESA
        const today    = now.toISOString().split('T')[0];
        const firstDay = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay  = new Date(year, month, 0).toISOString().split('T')[0];

        const mobMinhasVendasSql = `
EXECUTE BLOCK ( VENDEDOR INTEGER = ?, MES INTEGER = ?, ANO INTEGER = ?, DATA DATE = ?, EMPRESA INTEGER = ? )
RETURNS ( VENDA_DIARIA NUMERIC(15,2), VENDA_MENSAL NUMERIC(15,2), COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2), META_DIARIA NUMERIC(15,2), META_MENSAL NUMERIC(15,2), SERVICO_MENSAL NUMERIC(15,2), COMISSAO_SV_MENSAL NUMERIC(15,2) )
AS
declare variable MT_D numeric(15,2); declare variable MT_M numeric(15,2);
declare variable VEND_D numeric(15,2); declare variable VEND_M numeric(15,2);
declare variable COM_D numeric(15,2); declare variable COM_M numeric(15,2);
declare variable SERV_M numeric(15,2); declare variable COM_SV_M numeric(15,2);
BEGIN
    select FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL,
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and (extract(month from PEDIDOS.data_vencimento) = :MES) and (extract(year from PEDIDOS.data_vencimento) = :ANO)
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    group by FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL into :MT_D, :MT_M, :VEND_M, :COM_M;

    select sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO) left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((PEDIDOS.data_vencimento >= :DATA) and (PEDIDOS.data_vencimento <= :DATA))
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    into :VEND_D, :COM_D;

    select sum(LISTAPEDIDOS_ITENS.VALOR_TOTAL), sum(((LISTAPEDIDOS_ITENS.VALOR_TOTAL*(case when PRODUTOS.forca_comissao = 1 then PRODUTOS.comissao else FUNCIONARIOS.comissao end))/100))
    from LISTAPEDIDOS_ITENS left join PRODUTOS on (PRODUTOS.ID_PRODUTO = LISTAPEDIDOS_ITENS.ID_PRODUTO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = LISTAPEDIDOS_ITENS.id_tecnico) left join NATUREZA_OPERACAO on (natureza_operacao.id_natureza = LISTAPEDIDOS_ITENS.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((LISTAPEDIDOS_ITENS.tipo_item = 3) or (LISTAPEDIDOS_ITENS.tipo_item = 6)) and (extract(month from LISTAPEDIDOS_ITENS.data_vencimento) = :MES) and (extract(year from LISTAPEDIDOS_ITENS.data_vencimento) = :ANO)
    and (LISTAPEDIDOS_ITENS.id_tecnico = :VENDEDOR) and (LISTAPEDIDOS_ITENS.ID_DEPTO = :EMPRESA) and (LISTAPEDIDOS_ITENS.TIPO = 1) and (LISTAPEDIDOS_ITENS.STATUS = 2)
    into :SERV_M, :COM_SV_M;

    VENDA_DIARIA = coalesce(:VEND_D, 0); VENDA_MENSAL = coalesce(:VEND_M, 0);
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    META_DIARIA = coalesce(:MT_D, 0); META_MENSAL = coalesce(:MT_M, 0);
    SERVICO_MENSAL = coalesce(:SERV_M, 0); COMISSAO_SV_MENSAL = coalesce(:COM_SV_M, 0);
    SUSPEND;
END`;

        const mobMinhasVendasRSql = `
EXECUTE BLOCK ( VENDEDOR INTEGER = ?, DATAI DATE = ?, DATAF DATE = ?, DIA DATE = ?, EMPRESA INTEGER = ?, DEPTO INTEGER = ? )
RETURNS ( TOTAL_DIARIO NUMERIC(15,2), TOTAL_MENSAL NUMERIC(15,2), COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2) )
AS
declare variable COM_D decimal(15,2); declare variable COM_M decimal(15,2);
declare variable TOT_V_D decimal(15,2); declare variable TOT_V_M decimal(15,2);
declare variable TP_COM smallint;
BEGIN
    select COMISSAO_TIPO from config where ID_EMPRESA = :EMPRESA into :TP_COM;
    if (TP_COM = 1) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 2) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 3) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    TOTAL_DIARIO = coalesce(:TOT_V_D, 0); TOTAL_MENSAL = coalesce(:TOT_V_M, 0);
    SUSPEND;
END`;

        const [mainRows, rangeRows] = await Promise.all([
            fbQuery(req, mobMinhasVendasSql,
                [parseInt(sellerId), month, year, today, deptoId]),
            fbQuery(req, mobMinhasVendasRSql,
                [parseInt(sellerId), firstDay, lastDay, today, empresaId, deptoId]),
        ]);

        const main  = mainRows[0]  || {};
        const range = rangeRows[0] || {};

        const performance = {
            sellerId: parseInt(sellerId), month, year,
            deptoId,   // [VPS-FIRST] App usa deptoId como chave SQLite estável
            empresaId, // informação de auditoria
            syncedAt:           now.toISOString(),
            vendaDiaria:        parseFloat(main.VENDA_DIARIA)     || 0,
            vendaMensal:        parseFloat(main.VENDA_MENSAL)     || 0,
            comissaoDiaria:     parseFloat(main.COMISSAO_DIARIA)  || 0,
            comissaoMensal:     parseFloat(main.COMISSAO_MENSAL)  || 0,
            metaDiaria:         parseFloat(main.META_DIARIA)      || 0,
            metaMensal:         parseFloat(main.META_MENSAL)      || 0,
            servicoMensal:      parseFloat(main.SERVICO_MENSAL)   || 0,
            comissaoSvMensal:   parseFloat(main.COMISSAO_SV_MENSAL)  || 0,
            totalDiario:        parseFloat(range.TOTAL_DIARIO)    || 0,
            totalMensal:        parseFloat(range.TOTAL_MENSAL)    || 0,
            comissaoDiariaR:    parseFloat(range.COMISSAO_DIARIA) || 0,
            comissaoMensalR:    parseFloat(range.COMISSAO_MENSAL) || 0,
        };

        const source = mainRows.length > 0 ? 'firebird' : 'empty';
        logger.info('[Sync/Performance] KPIs retornados', { sellerId, month, year, deptoId, source });
        if (source === 'empty') return res.json({ data: null, source });
        res.json({ data: performance, source });
    } catch (err) {
        logger.error('[Sync/Performance] Erro', { error: err.message });
        next(err);
    }
});

// ── sales-rankings ────────────────────────────────────────────────────────────

/** @route POST /api/sync/sales-rankings */
router.post('/sales-rankings', async (req, res, next) => {
    try {
        const companyId = req.company.id;
        const branchId  = req.branch?.id || null;
        const data = req.body.rankings;
        if (!Array.isArray(data)) {
            return next(createError('Campo "rankings" deve ser um array.', 400, 'INVALID_PAYLOAD'));
        }
        // [FIX] Passa branchId para isolar rankings por filial no Redis
        await store.upsert(companyId, 'sales-rankings', data, branchId);
        logger.info(`[Sync/SalesRankings] ${data.length} vendedores recebidos do Worker`, { companyId, branchId });
        res.json({ received: data.length, entity: 'sales-rankings', syncedAt: new Date().toISOString() });
    } catch (err) { next(err); }
});

/**
 * Rankings de vendas do vendedor (store only — sem fallback Firebird).
 * @route GET /api/sync/sales-rankings?sellerId=<id>&month=<m>&year=<y>&period=<p>
 */
router.get('/sales-rankings', async (req, res, next) => {
    try {
        const { sellerId } = req.query;
        if (!sellerId) {
            return next(createError('sellerId é obrigatório', 400, 'MISSING_SELLER_ID'));
        }

        const companyId = req.company.id;
        const now   = new Date();
        const month = parseInt(req.query.month) || (now.getMonth() + 1);
        const year  = parseInt(req.query.year)  || now.getFullYear();
        const period = req.query.period || 'month';

        // [FIX] Resolve branchId do JWT para isolar dados da filial
        const jwtBranchId = req.branch?.id || null;
        let empresaId = parseInt(req.query.empresaId);
        let deptoId = parseInt(req.query.deptoId);
        if (jwtBranchId) {
            const { rows } = await pgQuery('SELECT "ErpEmpresaId" AS erp_empresa_id, "ErpDeptoPadrao" AS erp_depto_padrao FROM branches WHERE "Id" = $1', [jwtBranchId]);
            if (rows.length > 0) {
                if (!empresaId) empresaId = rows[0].erp_empresa_id;
                if (!deptoId) deptoId = rows[0].erp_depto_padrao;
            }
        }
        empresaId = empresaId || 1;
        deptoId = deptoId || 1;

        // [FIX Multi-Filial] Mesma lógica do /performance:
        // 1º match exato por deptoId, 2º fallback sem filtro de depto
        const cached = await store.get(companyId, 'sales-rankings', jwtBranchId);
        if (cached && cached.data && cached.data.length > 0) {
            let sellerRankings = cached.data.find(
                k => String(k.sellerId) === String(sellerId)
                    && k.month === month && k.year === year
                    && (k.period || 'month') === period
                    && String(k.deptoId) === String(deptoId)
            );
            if (!sellerRankings) {
                sellerRankings = cached.data.find(
                    k => String(k.sellerId) === String(sellerId)
                        && k.month === month && k.year === year
                        && (k.period || 'month') === period
                );
            }
            if (sellerRankings) {
                logger.info('[Sync/SalesRankings] Rankings retornados', { sellerId, month, year, period, deptoId, branchId: jwtBranchId, source: 'dataStore' });
                return res.json({ data: sellerRankings, source: 'dataStore' });
            }
        }

        logger.info('[Sync/SalesRankings] Sem rankings para vendedor', { sellerId, month, year, period });
        res.json({ data: null, source: 'empty' });
    } catch (err) {
        logger.error('[Sync/SalesRankings] Erro', { error: err.message });
        next(err);
    }
});

/**
 * Rankings on-demand para período personalizado.
 * Consulta Firebird diretamente sem cache.
 * @route GET /api/sync/rankings-ondemand?sellerId=<id>&dateFrom=YYYY-MM-DD&dateTo=YYYY-MM-DD
 */
router.get('/rankings-ondemand', async (req, res, next) => {
    try {
        const { sellerId, dateFrom, dateTo } = req.query;
        if (!sellerId || !dateFrom || !dateTo) {
            return next(createError('sellerId, dateFrom e dateTo são obrigatórios', 400, 'MISSING_PARAMS'));
        }

        // Valida formato ISO YYYY-MM-DD
        const isoRe = /^\d{4}-\d{2}-\d{2}$/;
        if (!isoRe.test(dateFrom) || !isoRe.test(dateTo)) {
            return next(createError('dateFrom e dateTo devem ser YYYY-MM-DD', 400, 'INVALID_DATE'));
        }

        // Firebird trata 'yyyy-MM-dd' como '00:00:00.000' em TIMESTAMP.
        // Adiciona hora explícita para capturar todos os registros do intervalo.
        const dateFromTs = `${dateFrom} 00:00:00`;
        const dateToTs   = `${dateTo} 23:59:59`;

        let empresaId = parseInt(req.query.empresaId);
        let deptoId = parseInt(req.query.deptoId);
        if (req.branch && req.branch.id) {
            const { rows } = await pgQuery('SELECT "ErpEmpresaId" AS erp_empresa_id, "ErpDeptoPadrao" AS erp_depto_padrao FROM branches WHERE "Id" = $1', [req.branch.id]);
            if (rows.length > 0) {
                if (!empresaId) empresaId = rows[0].erp_empresa_id;
                if (!deptoId) deptoId = rows[0].erp_depto_padrao;
            }
        }
        empresaId = empresaId || 1;
        deptoId = deptoId || 1;

        const [topProducts, topClients, revenueByDay, byRegion, categoryMix, clientHealth] =
            await Promise.all([
                fbQuery(req, `
                    SELECT FIRST 10
                           DESCRICAO, ID_PRODUTO,
                           SUM(TOTAL_QTDE) AS TOTAL_QTD,
                           SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                           COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
                    FROM L_VENDAS_PRODUTO
                    WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                      AND DATA_HORA >= ?
                      AND DATA_HORA <= ?
                    GROUP BY DESCRICAO, ID_PRODUTO
                    ORDER BY TOTAL_VALOR DESC`,
                    [parseInt(sellerId), deptoId, dateFromTs, dateToTs]),

                fbQuery(req, `
                    SELECT FIRST 10
                           NOME, ID_CLIENTE,
                           SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                           COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
                    FROM L_VENDAS_CLIENTE
                    WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                      AND DATA_HORA >= ?
                      AND DATA_HORA <= ?
                    GROUP BY NOME, ID_CLIENTE
                    ORDER BY TOTAL_VALOR DESC`,
                    [parseInt(sellerId), deptoId, dateFromTs, dateToTs]),

                fbQuery(req, `
                    SELECT CAST(DATA_HORA AS DATE) AS DIA,
                           SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                           COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
                    FROM L_VENDAS_CLIENTE
                    WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                      AND DATA_HORA >= ?
                      AND DATA_HORA <= ?
                    GROUP BY CAST(DATA_HORA AS DATE)
                    ORDER BY DIA ASC`,
                    [parseInt(sellerId), deptoId, dateFromTs, dateToTs]),

                fbQuery(req, `
                    SELECT FIRST 20
                           CIDADE, UF,
                           SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                           COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
                    FROM L_VENDAS_REGIAO
                    WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                      AND DATA_HORA >= ?
                      AND DATA_HORA <= ?
                    GROUP BY CIDADE, UF
                    ORDER BY TOTAL_VALOR DESC`,
                    [parseInt(sellerId), deptoId, dateFromTs, dateToTs]),

                fbQuery(req, `
                    SELECT FIRST 6
                           ID_DEPTO,
                           SUM(TOTAL_VALOR) AS TOTAL_VALOR
                    FROM L_VENDAS_PRODUTO
                    WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                      AND DATA_HORA >= ?
                      AND DATA_HORA <= ?
                    GROUP BY ID_DEPTO
                    ORDER BY TOTAL_VALOR DESC`,
                    [parseInt(sellerId), deptoId, dateFromTs, dateToTs]),

                fbQuery(req, `
                    SELECT
                        SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) <= 30 THEN 1 ELSE 0 END) AS ATIVOS,
                        SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) > 30 AND DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) <= 90 THEN 1 ELSE 0 END) AS INATIVOS,
                        SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) > 90 THEN 1 ELSE 0 END) AS PERDIDOS,
                        COUNT(ID_CLIENTE) AS TOTAL
                    FROM (
                        SELECT ID_CLIENTE, MAX(CAST(DATA_HORA AS DATE)) AS ULTIMA_VENDA
                        FROM L_VENDAS_CLIENTE
                        WHERE ID_VENDEDOR = ? AND ID_DEPTO = ?
                        GROUP BY ID_CLIENTE
                    )`,
                    [parseInt(sellerId), deptoId]),
            ]);

        const data = {
            sellerId: parseInt(sellerId),
            period: 'custom',
            dateFrom,
            dateTo,
            syncedAt: new Date().toISOString(),
            topProducts: topProducts.map(r => ({
                name: r.DESCRICAO || '',
                productId: r.ID_PRODUTO,
                totalQty: parseFloat(r.TOTAL_QTD) || 0,
                totalValue: parseFloat(r.TOTAL_VALOR) || 0,
                numOrders: parseInt(r.NUM_PEDIDOS) || 0,
            })),
            topClients: topClients.map(r => ({
                name: r.NOME || '',
                clientId: r.ID_CLIENTE,
                totalValue: parseFloat(r.TOTAL_VALOR) || 0,
                numOrders: parseInt(r.NUM_PEDIDOS) || 0,
            })),
            revenueByDay: revenueByDay.map(r => ({
                date: r.DIA ? String(r.DIA).split('T')[0] : '',
                totalAmount: parseFloat(r.TOTAL_VALOR) || 0,
                numOrders: parseInt(r.NUM_PEDIDOS) || 0,
            })),
            byRegion: byRegion.map(r => ({
                region: r.CIDADE || '',
                uf: r.UF || '',
                totalValue: parseFloat(r.TOTAL_VALOR) || 0,
                numOrders: parseInt(r.NUM_PEDIDOS) || 0,
            })),
            categoryMix: categoryMix.map(r => ({
                name: 'Depto ' + (r.ID_DEPTO || '0'),
                total: parseFloat(r.TOTAL_VALOR) || 0,
            })),
            clientHealth: clientHealth.length > 0 ? {
                actives:   parseInt(clientHealth[0].ATIVOS)   || 0,
                inactives: parseInt(clientHealth[0].INATIVOS) || 0,
                lost:      parseInt(clientHealth[0].PERDIDOS)  || 0,
                total:     parseInt(clientHealth[0].TOTAL)     || 0,
            } : { actives: 0, inactives: 0, lost: 0, total: 0 },
            heatmapStats: [],
        };

        logger.info('[Sync/RankingsOnDemand] Rankings retornados', { sellerId, dateFrom, dateTo });
        res.json({ data, source: 'firebird' });
    } catch (err) {
        logger.error('[Sync/RankingsOnDemand] Erro', { error: err.message });
        next(err);
    }
});

// ── company-logo ──────────────────────────────────────────────────────────────

/**
 * Serve a logo da empresa como imagem binária (PNG/JPEG).
 * Lê LogoBase64 da tabela companies no PostgreSQL Identity.
 * @route GET /api/sync/company-logo
 */
router.get('/company-logo', async (req, res, next) => {
    try {
        const companyId = req.company?.id;
        if (!companyId) {
            return res.status(401).json({ error: 'Empresa não identificada.' });
        }

        const { rows } = await pgQuery(
            `SELECT "LogoBase64" AS logo_base64 FROM companies WHERE "Id" = $1 LIMIT 1`,
            [companyId]
        );

        if (!rows.length || !rows[0].logo_base64) {
            return res.status(404).json({ error: 'Nenhuma logo cadastrada.' });
        }

        let base64 = rows[0].logo_base64;
        let contentType = 'image/png';

        if (base64.startsWith('data:')) {
            const commaIdx = base64.indexOf(',');
            if (commaIdx > 0) {
                const header = base64.substring(0, commaIdx);
                if (header.includes('jpeg') || header.includes('jpg')) contentType = 'image/jpeg';
                base64 = base64.substring(commaIdx + 1);
            }
        }

        const buffer = Buffer.from(base64, 'base64');
        res.set('Content-Type', contentType);
        res.set('Content-Length', buffer.length);
        res.set('Cache-Control', 'public, max-age=3600');
        res.send(buffer);

        logger.info('[Sync/CompanyLogo] Logo servida', { companyId, bytes: buffer.length });
    } catch (err) {
        logger.error('[Sync/CompanyLogo] Erro', { error: err.message });
        next(err);
    }
});

module.exports = router;
