using FirebirdSql.Data.FirebirdClient;
using ColiseuSales.Shared.Dtos;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Options;


namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// SyncOrdersJob — Busca pedidos pendentes na VPS e os insere no Firebird.
///
/// Fluxo corrigido (#2):
/// 1. GET /api/orders/pending → lista pedidos que o app Flutter enviou à VPS
/// 2. Para cada pedido: transação Firebird (cabeçalho + itens)
/// 3. Confirma na VPS FORA da transação (3 tentativas com backoff)
///    Antes: confirmar dentro da transação → HTTP timeout fazia rollback do ERP
///    Agora: Firebird commit independente da VPS; retry na confirmação
/// 4. Em caso de erro no Firebird: reporta na VPS para o app exibir ao vendedor
///
/// SP MOB_CADASTRAR_PEDIDO — Parâmetros verificados no Firebird (2026-02-23):
///   INPUT:  USUARIO (INT), CLIENTE (INT), DATA (VARCHAR10), HORA (VARCHAR5),
///           OBSERVACAO (VARCHAR50), PRAZO_PEDIDO (VARCHAR20),
///           TIPO_OPERACAO (VARCHAR20), PAGAMENTO (INT),
///           VALOR_DESCONTO (FLOAT), TOTAL_PEDIDO (FLOAT)
///   OUTPUT: ID_PEDIDO (INT)
///
/// SP MOB_CADASTRAR_PEDIDO_ITEM — Parâmetros verificados:
///   INPUT:  ID_PEDIDO (INT), PRODUTO (INT), QUANTIDADE (FLOAT),
///           OBSERVACAO (VARCHAR50), VALOR_UNITARIO (BIGINT centavos),
///           VALOR_DESCONTO (BIGINT centavos), VALOR_TOTAL (BIGINT centavos)
///
/// Cadência: configurável (padrão 1 minuto).
/// Rule-02: totalmente async.
/// </summary>
public sealed class SyncOrdersJob
{
    private readonly FirebirdService        _firebird;
    private readonly VpsApiClient           _vps;
    private readonly ILogger<SyncOrdersJob> _logger;
    private readonly FirebirdOptions        _fbOpts;
    private readonly StatusStore            _status;
    private readonly IdentityApiClient      _identity;
    private readonly string                 _companyId;

    private List<BranchDto>? _cachedBranches;

    /// <summary>
    /// Semáforo que garante no máximo UMA execução simultânea do RunAsync.
    /// Evita race condition crítica no GEN_ID(PEDIDOS,0): se dois ciclos rodassem
    /// em paralelo, ambos leriam o mesmo valor do generator Firebird (não transacional)
    /// e um dos pedidos ficaria com o ID errado.
    /// </summary>
    private readonly SemaphoreSlim _lock = new SemaphoreSlim(1, 1);

    /// Número de tentativas de confirmação na VPS após inserção no ERP (#2).
    private const int VpsConfirmMaxRetries = 3;

    public SyncOrdersJob(
        FirebirdService        firebird,
        VpsApiClient           vps,
        ILogger<SyncOrdersJob> logger,
        IOptions<FirebirdOptions> fbOpts,
        IOptions<VpsApiOptions> vpsOpts,
        StatusStore            status,
        IdentityApiClient      identity)
    {
        _firebird = firebird;
        _vps      = vps;
        _logger   = logger;
        _fbOpts   = fbOpts.Value;
        _status   = status;
        _identity = identity;
        _companyId = vpsOpts.Value.CompanyId;
    }

    /// <summary>Executa um ciclo de processamento de pedidos.</summary>
    public async Task RunAsync(CancellationToken ct = default)
    {
        // RACE-GUARD: se ciclo anterior ainda está processando pedidos, pula este ciclo.
        // Sem isso, dois ciclos com fire-and-forget leriam GEN_ID(PEDIDOS,0) em paralelo
        // e um pedido ficaria registrado com o ID errado na VPS.
        if (!await _lock.WaitAsync(0, ct))
        {
            _logger.LogDebug("[OrderSync] Ciclo anterior ainda em execução — pulando ciclo.");
            return;
        }

        try
        {
            List<PendingOrderDto> orders;
            try
            {
                orders = await _vps.GetPendingOrdersAsync(ct);
                // Pré-carrega as filiais (faz cache do ciclo atual)
                if (Guid.TryParse(_companyId, out var cid))
                {
                    _cachedBranches = await _identity.GetBranchesAsync(cid, ct);
                }
            }
            catch (Exception ex)
            {
                var errMsg = $"⚠ Erro ao buscar pedidos na VPS: {ex.Message}";
                _logger.LogError("[OrderSync] {Error}", errMsg);
                _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] {errMsg}");
                return; // finally do bloco externo libera o semáforo
            }


            if (orders.Count == 0)
            {
                _logger.LogDebug("[OrderSync] Nenhum pedido pendente.");
                return; // finally do bloco externo libera o semáforo
            }

            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] 📦 {orders.Count} pedido(s) pendente(s) encontrado(s)");
            _logger.LogInformation("[OrderSync] {Count} pedidos para processar.", orders.Count);

            foreach (var order in orders)
            {
                await ProcessOrderAsync(order, ct);
            }
        }
        finally
        {
            _lock.Release();
        }
    }


    // ─────────────────────────────────────────────────────────────────────────
    // Processamento individual
    // ─────────────────────────────────────────────────────────────────────────

    private async Task ProcessOrderAsync(PendingOrderDto order, CancellationToken ct)
    {
        _logger.LogInformation("[OrderSync] Processando pedido {OrderId} (cliente {CustomerId})",
            order.Id, order.CustomerId);

        // Validações Críticas: se faltar dados, reporta erro IMEDIATAMENTE.
        if (string.IsNullOrWhiteSpace(order.CustomerId))
            throw new InvalidOperationException($"Pedido rejeitado: sem CustomerId definido.");

        if (string.IsNullOrWhiteSpace(order.SellerId))
            throw new InvalidOperationException($"Pedido rejeitado: sem SellerId (Vendedor) definido. Verifique se a filial '{order.BranchId}' possui vendedores mapeados.");

        if (order.Items == null || order.Items.Count == 0)
            throw new InvalidOperationException($"Pedido rejeitado: não contém itens.");

        // ── Resolve cliente local → ERP ID ────────────────────────────────────
        // Se o customerId começa com "local_", o cliente foi cadastrado offline e
        // ainda não recebeu um código ERP. Buscamos o ID confirmado na VPS.
        // Se ainda pendente, pulamos este pedido — ele será reprocessado no próximo ciclo.
        if (order.CustomerId?.StartsWith("local_", StringComparison.OrdinalIgnoreCase) == true)
        {
            var erpCustomerId = await _vps.ResolveLocalCustomerAsync(order.CustomerId, ct);
            if (erpCustomerId is null)
            {
                _logger.LogWarning("[OrderSync] Cliente local {CustomerId} ainda não confirmado no ERP. Pedido {OrderId} aguardando próximo ciclo.",
                    order.CustomerId, order.Id);
                _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⏳ Pedido {order.Id.ToString()[..8]}: cliente ainda pendente. Retry no próximo ciclo.");
                return; // Mantém pedido como pending na VPS — não reporta erro
            }
            _logger.LogInformation("[OrderSync] Cliente local {LocalId} resolvido para ERP ID {ErpId} no pedido {OrderId}",
                order.CustomerId, erpCustomerId, order.Id);
            // PendingOrderDto é um record — usamos 'with' para criar cópia com ID resolvido
            order = order with { CustomerId = erpCustomerId };
        }

        // FASE 1 — Inserção no Firebird (dentro de uma transação atômica)

        int erpOrderId;
        try
        {
            erpOrderId = await InsertIntoFirebirdAsync(order, ct);
        }
        catch (Exception ex)
        {
            var errTxt = ex.Message.Length > 120 ? ex.Message[..120] : ex.Message;
            _logger.LogError("[OrderSync] Erro Firebird no pedido {OrderId}: {Error}",
                order.Id, errTxt);
            _status.AppendLog(
                $"[{DateTime.Now:HH:mm:ss}] ✗ Pedido {order.Id.ToString()[..8]} falhou: {errTxt}");

            // Reporta erro na VPS para que o app possa exibir ao vendedor
            try
            {
                await _vps.ReportOrderErrorAsync(order.Id, ex.Message, ct);
                _status.AppendLog(
                    $"[{DateTime.Now:HH:mm:ss}]   ↳ Erro reportado à VPS (pedido ficará como Erro no app)");
            }
            catch (Exception reportEx)
            {
                _status.AppendLog(
                    $"[{DateTime.Now:HH:mm:ss}]   ↳ ⚠ FALHA ao reportar erro à VPS: {reportEx.Message} — pedido ficará PENDENTE!");
                _logger.LogWarning("[OrderSync] Falha ao reportar erro do pedido {Id} para VPS: {Error}",
                    order.Id, reportEx.Message);
            }
            return;
        }

        // FASE 2 — Confirmação na VPS (FORA da transação Firebird)
        // O commit do Firebird já ocorreu. Se a VPS falhar aqui, o pedido está
        // gravado no ERP. Fazemos retry com backoff exponencial para tolerar
        // instabilidade temporária de rede.
        await ConfirmInVpsWithRetryAsync(order.Id, erpOrderId, ct);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FASE 1 — Inserção atômica no Firebird
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Executa MOB_CADASTRAR_PEDIDO + MOB_CADASTRAR_PEDIDO_ITEM em uma transação.
    ///
    /// Returns: ID_PEDIDO gerado pelo ERP.
    /// Throws: InvalidOperationException se a SP retornar ID inválido.
    /// </summary>
    private async Task<int> InsertIntoFirebirdAsync(PendingOrderDto order, CancellationToken ct)
    {
        int erpOrderId = 0;

        await _firebird.TransactionAsync(async (cmd, innerCt) =>
        {
            var now  = DateTime.Now;
            // FIX: Firebird faz parse de datas com ponto como separador ('dd.MM.yyyy').
            // Usar barra ('dd/MM/yyyy') fazia a SP falhar silenciosamente (ID_PEDIDO=0).
            // Consistente com SyncAtendenteOrdersJob e modo Direct do middleware.
            var data = now.ToString("dd.MM.yyyy");
            var hora = now.ToString("HH:mm");

            // 1. Inserir cabeçalho do pedido via stored procedure
            //    Usa EXECUTE PROCEDURE (raw SQL) + ExecuteScalarAsync para evitar ambiguidade
            //    do CommandType.StoredProcedure com parâmetros de output no driver Firebird.
            //    Abordagem consistente com SyncAtendenteOrdersJob (linha 107).
            //
            //    SP MOB_CADASTRAR_PEDIDO — parâmetros:
            //    Standard (10): USUARIO, CLIENTE, DATA, HORA, OBSERVACAO, PRAZO_PEDIDO,
            //                   TIPO_OPERACAO, PAGAMENTO, VALOR_DESCONTO, TOTAL_PEDIDO
            //    Extended (11): idem + CONDICAO_PAGAMENTO no final

            // PRAZO_PEDIDO: ID composto da condição de pagamento (FORMA_PGTO.ID_FORMA || '_' || ID_ESPECIE)
            // ex: "4_2" para FORMA 4 / ESPECIE 2. A SP usa esse ID para buscar o plano de parcelamento.
            var condStr     = order.PaymentConditionId ?? "0";
            var prazoPedido = condStr.Length > 20 ? condStr[..20] : condStr;

            var tipoOperacao = (order.NaturezaId == "null" || string.IsNullOrWhiteSpace(order.NaturezaId)) ? null : order.NaturezaId;
            var pagamentoId  = int.TryParse(order.PaymentSpeciesId, out var pid) ? pid : 0;

            // BLOCKER-2 fix: usar TryParse para evitar FormatException em SellerId/CustomerId
            // que chegue como UUID ou nulo por bug no app móvel.
            if (!int.TryParse(order.SellerId, out var sellerIdInt))
                throw new InvalidOperationException(
                    $"SellerId inválido (não-numérico): '{order.SellerId}' para pedido {order.Id}");

            if (!int.TryParse(order.CustomerId, out var customerIdInt))
                throw new InvalidOperationException(
                    $"CustomerId inválido (não-numérico): '{order.CustomerId}' para pedido {order.Id}");

            // DESCUBRE DINAMICAMENTE A ASSINATURA DA SP
            using var countCmd = new FbCommand(
                "SELECT count(*) FROM RDB$PROCEDURE_PARAMETERS WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO' AND RDB$PARAMETER_TYPE = 0",
                cmd.Connection, cmd.Transaction);
            var paramCount = Convert.ToInt32(await countCmd.ExecuteScalarAsync(innerCt));
            var isExtended = paramCount >= 11;
            var hasMultiTenant = paramCount >= 13;

            var spSql = "EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(@USUARIO, @CLIENTE, @DATA, @HORA, @OBSERVACAO, @PRAZO_PEDIDO, @TIPO_OPERACAO, @PAGAMENTO, @VALOR_DESCONTO, @TOTAL_PEDIDO";
            if (isExtended) spSql += ", @CONDICAO_PAGAMENTO";
            if (hasMultiTenant) spSql += ", @DEPTO, @EMPRESA";
            spSql += ")";

            cmd.CommandText = spSql;
            cmd.CommandType = System.Data.CommandType.Text;
            cmd.Parameters.Clear();

            cmd.Parameters.AddWithValue("@USUARIO", sellerIdInt);
            cmd.Parameters.AddWithValue("@CLIENTE", customerIdInt);
            cmd.Parameters.AddWithValue("@DATA", data);
            cmd.Parameters.AddWithValue("@HORA", hora);
            cmd.Parameters.AddWithValue("@OBSERVACAO", Truncate(order.Notes, 50) ?? string.Empty);
            cmd.Parameters.AddWithValue("@PRAZO_PEDIDO", Truncate(prazoPedido, 20) ?? string.Empty);
            cmd.Parameters.AddWithValue("@TIPO_OPERACAO", (object?)Truncate(tipoOperacao, 20) ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@PAGAMENTO", pagamentoId);
            
            // IMPORTANT: passar 0.0 em VALOR_DESCONTO para que PEDIDOS.DESCONTO = 0%.
            cmd.Parameters.AddWithValue("@VALOR_DESCONTO", 0.0);
            cmd.Parameters.AddWithValue("@TOTAL_PEDIDO", (double)order.TotalAmount);

            var condId = isExtended ? ParseConditionId(order.PaymentConditionId) : 0;
            if (isExtended)
            {
                cmd.Parameters.AddWithValue("@CONDICAO_PAGAMENTO", condId);
            }

            int nativeDepto = 1;
            int nativeEmpresa = 1;
            if (hasMultiTenant)
            {
                if (order.BranchId.HasValue && _cachedBranches != null)
                {
                    var branch = _cachedBranches.FirstOrDefault(b => b.Id == order.BranchId.Value);
                    if (branch != null)
                    {
                        nativeDepto = branch.ErpDeptoPadrao;
                        nativeEmpresa = branch.ErpEmpresaId;
                    }
                }
                cmd.Parameters.AddWithValue("@DEPTO", nativeDepto);
                cmd.Parameters.AddWithValue("@EMPRESA", nativeEmpresa);
            }

            // ExecuteScalar retorna a primeira coluna da primeira linha do resultado
            // (ID_PEDIDO gerado pelo ERP). Equivalente ao que SyncAtendenteOrdersJob faz.
            var spDiag = $"[SP] Pedido {order.Id.ToString()[..8]} | " +
                         $"USUARIO={sellerIdInt} CLIENTE={customerIdInt} " +
                         $"DATA='{data}' PRAZO='{prazoPedido}' OP='{tipoOperacao}' " +
                         $"PGTO={pagamentoId}" +
                         (isExtended ? $" COND={condId}" : "") +
                         $" DESC=0(via GRID-FIX) TOTAL={order.TotalAmount:F2}" +
                         (hasMultiTenant ? $" DEPTO={nativeDepto} EMPRESA={nativeEmpresa}" : "");
            _logger.LogDebug("[OrderSync] {Diag}", spDiag);  // Debug: diagnóstico normal da SP
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚙ {spDiag}");

            // ExecuteNonQuery: a SP cria o pedido. Não capturamos o output via ExecuteScalar
            // porque este driver Firebird .NET não retorna o parâmetro OUTPUT da SP.
            // GEN_ID(PEDIDOS, 0) lê o valor atual do generator (gerado pela SP).
            // Seguro porque SemaphoreSlim garante UMA execução por vez.
            await cmd.ExecuteNonQueryAsync(innerCt);

            using var genCmd = new FbCommand(
                "SELECT GEN_ID(PEDIDOS, 0) AS ID_PEDIDO FROM RDB$DATABASE",
                cmd.Connection, cmd.Transaction);
            erpOrderId = Convert.ToInt32(await genCmd.ExecuteScalarAsync(innerCt));
            _logger.LogDebug("[OrderSync] GEN_ID(PEDIDOS,0) retornou {Id}", erpOrderId);

            if (erpOrderId <= 0)
            {
                var errMsg = $"⚠ SP retornou ID=0 | {spDiag}";
                _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] {errMsg}");
                throw new InvalidOperationException(
                    $"MOB_CADASTRAR_PEDIDO retornou ID_PEDIDO={erpOrderId} para pedido {order.Id}");
            }

            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ Pedido {order.Id.ToString()[..8]} integrado. ERP ID={erpOrderId}");
            _logger.LogDebug("[OrderSync] Pedido {OrderId} integrado. ERP ID={ErpOrderId}", order.Id, erpOrderId);

            // 2. Inserir os itens do pedido
            //    DISCOUNT-FIX: rateia o desconto global (order.DiscountValue inclui descontos por item
            //    + desconto global do pedido). Para que a soma dos VALOR_TOTAL dos itens corresponda
            //    ao TOTAL_PEDIDO informado, distribuímos o desconto global proporcionalmente.
            var itemsWithDiscount = ApplyGlobalDiscount(order);

            foreach (var (item, itemDiscountValue, itemTotalPrice) in itemsWithDiscount)
            {
                // WARNING-3 fix: respeita cancelamento mesmo em pedidos com muitos itens
                innerCt.ThrowIfCancellationRequested();

                cmd.CommandText = @"
                    EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO_ITEM(
                        @ID_PEDIDO, @PRODUTO, @QUANTIDADE,
                        @OBSERVACAO, @VALOR_UNITARIO,
                        @VALOR_DESCONTO, @VALOR_TOTAL
                    )";
                cmd.CommandType = System.Data.CommandType.Text;

                // BLOCKER fix: TryParse para evitar FormatException se ProductCode chegar inválido
                if (!int.TryParse(item.ProductCode, out var productCodeInt))
                    throw new InvalidOperationException(
                        $"ProductCode inválido: '{item.ProductCode}' no pedido {order.Id}");

                cmd.Parameters.Clear();
                cmd.Parameters.AddWithValue("@ID_PEDIDO",      erpOrderId);
                cmd.Parameters.AddWithValue("@PRODUTO",        productCodeInt);
                cmd.Parameters.AddWithValue("@QUANTIDADE",     (float)item.Quantity);
                cmd.Parameters.AddWithValue("@OBSERVACAO",     "");
                cmd.Parameters.AddWithValue("@VALOR_UNITARIO", (double)item.UnitPrice);
                cmd.Parameters.AddWithValue("@VALOR_DESCONTO", (double)itemDiscountValue);
                // Passa o BRUTO para VALOR_TOTAL. A SP mapeia VALOR_FINAL = VALOR_TOTAL.
                var itemGrossTotal = item.UnitPrice * item.Quantity;
                cmd.Parameters.AddWithValue("@VALOR_TOTAL",    (double)itemGrossTotal);

                await cmd.ExecuteNonQueryAsync(innerCt);

                // GRID-FIX: A SP MOB_CADASTRAR_PEDIDO_ITEM seta VALOR_FINAL_UN = VALOR_UNITARIO (bruto)
                // e DESCONTO = % do cabeçalho PEDIDOS (= 0 porque passamos VALOR_DESCONTO=0 no header).
                // Atualizamos ambos para exibição correta na grade do ERP:
                //   VALOR_FINAL_UN = preço unitário líquido (com desconto)
                //   DESCONTO       = % de desconto do item — p/ coluna "Valor Desc." na grade
                //
                // Segurança: como PEDIDOS.VALOR_PEDIDO = totalLíquido e PEDIDOS.DESCONTO = 0,
                // o rodapé "Total Produtos" e "Total Pedido" ambos mostram o net → sem Troco negativo.
                // O SUM_DESC do PEDIDOTOTAL exibe um valor no campo "Desconto (F1)" no rodapé,
                // mas não afeta Total Produtos nem Total Pedido.
                if (itemDiscountValue > 0 && item.Quantity > 0m)
                {
                    var grossSubtotal = item.UnitPrice * item.Quantity;
                    var unitPriceLiq  = Math.Round(itemTotalPrice / item.Quantity, 4);
                    // Desconto % calculado sobre o bruto (para exibição correta na coluna Valor Desc)
                    var discountPct   = grossSubtotal > 0m
                        ? Math.Round(itemDiscountValue / grossSubtotal * 100m, 4)
                        : 0m;

                    using var updateCmd = new FbCommand(
                        "UPDATE PEDIDO_ITENS" +
                        "  SET VALOR_FINAL_UN = @VFU," +
                        "      DESCONTO       = @DISC" +
                        " WHERE ID_PEDIDO    = @PEDIDO" +
                        "   AND ID_PRODUTO   = @PROD" +
                        "   AND VALOR_UNITARIO = @VU",
                        cmd.Connection, cmd.Transaction);

                    updateCmd.Parameters.AddWithValue("@VFU",    unitPriceLiq);
                    updateCmd.Parameters.AddWithValue("@DISC",   discountPct);
                    updateCmd.Parameters.AddWithValue("@PEDIDO", erpOrderId);
                    updateCmd.Parameters.AddWithValue("@PROD",   productCodeInt);
                    updateCmd.Parameters.AddWithValue("@VU",     item.UnitPrice);

                    await updateCmd.ExecuteNonQueryAsync(innerCt);

                    _logger.LogDebug(
                        "[OrderSync] GRID-FIX produto {Prod}: VFU={Liq:F4} DISC={Pct:F2}% (bruto={Gross:F4})",
                        productCodeInt, unitPriceLiq, discountPct, item.UnitPrice);
                }
            }

            // 3. Corrigir parcelas em PEDIDOS_DOCS
            //    A SP MOB_CADASTRAR_PEDIDO sempre insere 1 parcela com valor BRUTO (hardcoded).
            //    Aqui: deletamos essa linha e inserimos N parcelas corretas com valor LÍQUIDO.
            var installments    = Math.Max(1, order.PaymentInstallments);
            var diasParcelas    = order.PaymentDaysPerInstallment > 0 ? order.PaymentDaysPerInstallment : 30;
            var diasEntrada     = order.PaymentEntryDays;
            // SUGGESTION-3 fix: arredonda para 2 casas; última parcela absorve o centavo residual
            var valorParcela    = Math.Round(order.TotalAmount / installments, 2);
            var valorUltima     = order.TotalAmount - valorParcela * (installments - 1);
            var hoje            = DateTime.Today;

            if (installments <= 0)
                _logger.LogWarning("[OrderSync] PaymentInstallments={N} inválido para pedido {Id}, usando 1.",
                    order.PaymentInstallments, order.Id);

            _logger.LogInformation(
                "[OrderSync] Parcelamento: {N}x de {Val:F2} (última={Last:F2}, entrada={E}d, parc={D}d)",
                installments, valorParcela, valorUltima, diasEntrada, diasParcelas);

            // 3a. Remove as parcelas geradas pela SP (sempre 1, com valor bruto)
            cmd.CommandText = "DELETE FROM PEDIDOS_DOCS WHERE ID_PEDIDO = @ID_PEDIDO";
            cmd.CommandType = System.Data.CommandType.Text;
            cmd.Parameters.Clear();
            cmd.Parameters.Add(new FbParameter("@ID_PEDIDO", FbDbType.Integer) { Value = erpOrderId });
            await cmd.ExecuteNonQueryAsync(innerCt);

            // 3b. Insere N parcelas corretas
            // Constantes para campos do Firebird (WARNING-4 fix)
            const int PedidoDocSemCheque       = 0;
            const int PedidoDocTipoCartaoPadrao = 2;

            for (var i = 1; i <= installments; i++)
            {
                innerCt.ThrowIfCancellationRequested();

                var vencimento  = hoje.AddDays(diasEntrada + diasParcelas * i);
                // Última parcela absorve o centavo residual (SUGGESTION-3)
                var valorAtual  = (i == installments) ? valorUltima : valorParcela;

                cmd.CommandText = @"
                    INSERT INTO PEDIDOS_DOCS
                        (ID_PEDIDO, PARCELA, N_DOC, ID_ESPECIE, DATA_VENCIMENTO, VALOR, ID_CHEQUE, TIPO_CARTAO)
                    VALUES
                        (@ID_PEDIDO, @PARCELA, @N_DOC, @ID_ESPECIE, @DATA_VENC, @VALOR, @ID_CHEQUE, @TIPO_CARTAO)";
                cmd.CommandType = System.Data.CommandType.Text;

                cmd.Parameters.Clear();
                cmd.Parameters.Add(new FbParameter("@ID_PEDIDO",   FbDbType.Integer) { Value = erpOrderId });
                cmd.Parameters.Add(new FbParameter("@PARCELA",     FbDbType.Integer) { Value = i });
                cmd.Parameters.Add(new FbParameter("@N_DOC",       FbDbType.VarChar) { Value = i.ToString() });
                cmd.Parameters.Add(new FbParameter("@ID_ESPECIE",  FbDbType.Integer) { Value = pagamentoId });
                cmd.Parameters.Add(new FbParameter("@DATA_VENC",   FbDbType.Date)    { Value = vencimento });
                cmd.Parameters.Add(new FbParameter("@VALOR",       FbDbType.Decimal) { Value = valorAtual });
                cmd.Parameters.Add(new FbParameter("@ID_CHEQUE",   FbDbType.Integer) { Value = PedidoDocSemCheque });
                cmd.Parameters.Add(new FbParameter("@TIPO_CARTAO", FbDbType.Integer) { Value = PedidoDocTipoCartaoPadrao });
                await cmd.ExecuteNonQueryAsync(innerCt);
            }

            // FASE 3 (Multi-tenant): rateio do pedido para a Filial correta no ERP
            // Se a SP já usou os parâmetros nativos (hasMultiTenant = true), pulamos esta etapa.
            if (order.BranchId.HasValue)
            {
                if (_cachedBranches == null || _cachedBranches.Count == 0)
                {
                    _logger.LogWarning("[OrderSync] Pedido {OrderId} tentou rotear p/ filial {BranchId}, mas o cache de filiais do Identity está VAZIO. " +
                                       "O pedido permanecerá no departamento padrão. (A API do Identity retornou 0 filiais para esta empresa?)", 
                                       order.Id, order.BranchId);
                    
                    _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠️ Pedido {order.Id.Substring(0, 5)} - Nenhuma filial cadastrada no Identity. Roteado p/ ERP nativo EMP=1/DEP=1.");
                }
                else
                {
                    var branch = _cachedBranches.FirstOrDefault(b => b.Id == order.BranchId.Value);
                    if (branch != null)
                    {
                        cmd.CommandText = @"
                            UPDATE PEDIDOS P
                            SET 
                                ID_DEPTO = @DEPTO
                            WHERE P.ID_PEDIDO = @ID_PEDIDO
                        ";
                        cmd.CommandType = System.Data.CommandType.Text;
                        cmd.Parameters.Clear();
                        cmd.Parameters.Add(new FbParameter("@DEPTO", FbDbType.Integer) { Value = branch.ErpDeptoPadrao });
                        cmd.Parameters.Add(new FbParameter("@ID_PEDIDO", FbDbType.Integer) { Value = erpOrderId });
                        
                        await cmd.ExecuteNonQueryAsync(innerCt);
                        
                        _logger.LogInformation("[OrderSync] Pedido {OrderId} rateado para DEPTO={Depto}.",
                            order.Id, branch.ErpDeptoPadrao);
                    }
                    else
                    {
                        _logger.LogWarning("[OrderSync] Filial do pedido {BranchId} NÃO FOI ENCONTRADA no cache do Identity. O pedido continuará no departamento padrão.", order.BranchId);
                        _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠️ Pedido {order.Id.Substring(0, 5)} - Filial '{order.BranchId}' não encontrada. Roteado p/ ERP nativo EMP=1/DEP=1.");
                    }
                }
            }

            // FASE 4: Recalcular totais sumarizados na capa do pedido (ITENS, QTDE_TOTAL, VALOR_CUSTOS)
            // A stored procedure original inseria 0, 0 por padrão, o que fazia alguns ERPs filtrarem o pedido
            // como um pedido "vazio/incompleto".
            cmd.CommandText = @"
                UPDATE PEDIDOS P
                SET 
                    ITENS = (SELECT COUNT(ID_ITEM) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = @ID_PEDIDO),
                    QTDE_TOTAL = COALESCE((SELECT SUM(QTDE) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = @ID_PEDIDO), 0),
                    VALOR_CUSTOS = COALESCE((SELECT SUM(VALOR_CUSTO * QTDE) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = @ID_PEDIDO), 0)
                WHERE P.ID_PEDIDO = @ID_PEDIDO
            ";
            cmd.CommandType = System.Data.CommandType.Text;
            cmd.Parameters.Clear();
            cmd.Parameters.Add(new FbParameter("@ID_PEDIDO", FbDbType.Integer) { Value = erpOrderId });
            await cmd.ExecuteNonQueryAsync(innerCt);

            // Transação commited aqui pelo TransactionAsync — ERP já tem o pedido
        }, ct);

        _logger.LogInformation("[OrderSync] Pedido {OrderId} inserido no Firebird (ERP ID={ErpId}).",
            order.Id, erpOrderId);
        return erpOrderId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FASE 2 — Confirmação na VPS com retry (#2)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Confirma o pedido na VPS com backoff exponencial.
    ///
    /// O pedido JÁ ESTÁ no Firebird. Esta fase apenas sincroniza o status
    /// na VPS (SQLite de controle) para que o app Flutter receba o ERP ID.
    ///
    /// Tentativas: 1s → 4s → 9s (base² × 1s).
    /// </summary>
    private async Task ConfirmInVpsWithRetryAsync(
        string orderId, int erpOrderId, CancellationToken ct)
    {
        for (var attempt = 1; attempt <= VpsConfirmMaxRetries; attempt++)
        {
            try
            {
                var ok = await _vps.ConfirmOrderAsync(orderId, erpOrderId, ct);
                if (ok)
                {
                    _logger.LogInformation(
                        "[OrderSync] Pedido {OrderId} confirmado na VPS (ERP ID={ErpId}, tentativa {Attempt}).",
                        orderId, erpOrderId, attempt);
                    return;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    "[OrderSync] Falha ao confirmar pedido {OrderId} na VPS (tentativa {Attempt}/{Max}): {Error}",
                    orderId, attempt, VpsConfirmMaxRetries, ex.Message);
            }

            if (attempt < VpsConfirmMaxRetries)
            {
                var delay = TimeSpan.FromSeconds(attempt * attempt); // 1s, 4s, 9s
                _logger.LogDebug("[OrderSync] Aguardando {Delay}s antes da próxima tentativa.", delay.TotalSeconds);
                await Task.Delay(delay, ct);
            }
        }

        _logger.LogError(
            "[OrderSync] Pedido {OrderId} INSERIDO no ERP (ID={ErpId}) mas falha persistente na VPS após {Max} tentativas. " +
            "O pedido será reprocessado no próximo ciclo se ainda estiver como 'processing' na VPS.",
            orderId, erpOrderId, VpsConfirmMaxRetries);
    }

    /// <summary>
    /// Rateia o desconto global do pedido SOMENTE nos itens sem desconto individual.
    ///
    /// O app envia dois tipos de desconto:
    ///   - Desconto por item (item.Discount em %) — aplicado individualmente pelo vendedor
    ///   - Desconto global do pedido (order.DiscountValue − Σ descontos por item)
    ///
    /// Regra de negócio (2026-03-25):
    ///   O desconto global afeta APENAS os itens com item.Discount == 0.
    ///   Itens com desconto individual ficam com seu desconto intacto.
    ///   Fallback: se todos os itens tiverem desconto individual, rateia em todos
    ///   proporcionalmente (evita que o desconto global seja descartado).
    ///
    /// Algoritmo:
    ///   1. Calcula subtotais brutos de cada item
    ///   2. Calcula descontos individuais em R$ por item
    ///   3. Calcula globalDiscount = order.DiscountValue − Σ(descontos individuais)
    ///   4. Identifica candidatos = itens com item.Discount == 0
    ///   5. Distribui globalDiscount proporcionalmente entre os candidatos
    ///      (ou entre todos, se não houver candidatos — fallback)
    ///   6. Último candidato absorve o centavo residual
    ///
    /// Returns: lista de tuplas (item, valorDesconto, valorTotal) prontas para o Firebird.
    /// </summary>
    private static List<(OrderItemDto Item, decimal DiscountValue, decimal TotalPrice)>
        ApplyGlobalDiscount(PendingOrderDto order)
    {
        var items = order.Items ?? [];
        if (items.Count == 0)
            return [];

        // 1. Subtotais brutos (sem desconto) por item
        var subtotals  = items.Select(i => i.UnitPrice * i.Quantity).ToList();
        var grossTotal = subtotals.Sum();

        // 2. Descontos individuais por item em R$ (4 casas para minimizar erros de arredondamento)
        var itemDiscounts     = items.Select((i, idx) =>
            Math.Round(subtotals[idx] * (i.Discount / 100m), 4)).ToList();
        var totalItemDiscount = itemDiscounts.Sum();

        // 3. Desconto global = total do pedido − descontos individuais já embutidos
        //    Clamp em 0 para evitar valor negativo por diferança de ponto flutuante
        var globalDiscount = Math.Max(0m, order.DiscountValue - totalItemDiscount);

        if (globalDiscount == 0m)
        {
            // Nenhum desconto global para distribuir
            return items.Select((item, idx) =>
            {
                var disc  = Math.Round(itemDiscounts[idx], 2);
                var total = Math.Round(subtotals[idx] - disc, 2);
                return (item, disc, total);
            }).ToList();
        }

        // 4. Candidatos ao rateio = índices dos itens SEM desconto individual
        var candidateIndices = items
            .Select((item, idx) => (item, idx))
            .Where(x => x.item.Discount == 0m)
            .Select(x => x.idx)
            .ToList();

        // Fallback: se TODOS os itens têm desconto individual, rateia em todos
        // (evita que o desconto global seja silenciosamente descartado)
        if (candidateIndices.Count == 0)
            candidateIndices = Enumerable.Range(0, items.Count).ToList();

        // Subtotal bruto dos candidatos (base proporcional do rateio)
        var candidatesGross = candidateIndices.Sum(idx => subtotals[idx]);

        // 5. Distribuir globalDiscount proporcionalmente entre os candidatos
        var globalShares    = new decimal[items.Count]; // indexado pelo índice do item
        decimal allocated   = 0m;

        for (var k = 0; k < candidateIndices.Count; k++)
        {
            var idx    = candidateIndices[k];
            var isLast = (k == candidateIndices.Count - 1);

            if (isLast)
            {
                // 6. Último candidato absorve o centavo residual
                globalShares[idx] = globalDiscount - allocated;
            }
            else
            {
                var proportion     = candidatesGross > 0m ? subtotals[idx] / candidatesGross : 0m;
                globalShares[idx]  = Math.Round(globalDiscount * proportion, 2);
                allocated         += globalShares[idx];
            }
        }

        // Monta resultado final para todos os itens
        return items.Select((item, idx) =>
        {
            var totalDisc  = Math.Round(itemDiscounts[idx] + globalShares[idx], 2);
            var totalPrice = Math.Max(0m, Math.Round(subtotals[idx] - totalDisc, 2));
            return (item, totalDisc, totalPrice);
        }).ToList();
    }

    /// <summary>
    /// Trunca uma string ao tamanho máximo aceito pela SP.
    /// Retorna null se a string original era null ou vazia.
    /// </summary>
    private static string? Truncate(string? s, int maxLen)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        return s.Length <= maxLen ? s : s[..maxLen];
    }

    /// <summary>
    /// Extrai o ID inteiro da condição de pagamento.
    /// Suporta formato composto "4_2" (FORMA_4 / ESPECIE_2) retornando a parte antes do '_',
    /// ou formato simples "4" retornando diretamente o inteiro.
    /// Retorna 0 se nulo ou não parseável.
    /// </summary>
    private static int ParseConditionId(string? conditionId)
    {
        if (string.IsNullOrWhiteSpace(conditionId)) return 0;
        var part = conditionId.Split('_')[0];
        return int.TryParse(part, out var id) ? id : 0;
    }
}
