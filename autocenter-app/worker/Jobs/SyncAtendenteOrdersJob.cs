using FirebirdSql.Data.FirebirdClient;
using ColiseuSales.Shared.Dtos;
using ColiseuSales.Worker.Services;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// SyncAtendenteOrdersJob — Busca pedidos do WhatsApp (Atendente do Futuro)
/// e os insere no Firebird usando as mesmas stored procedures do Coliseu Sales.
///
/// Fluxo:
/// 1. GET /api/sync/orders/pending → pedidos criados pelo AI Agent do WhatsApp
/// 2. Para cada pedido: transação Firebird (MOB_CADASTRAR_PEDIDO + ITENS)
/// 3. Confirma no backend Atendente (3 tentativas com backoff)
/// 4. Em caso de erro: reporta no backend para retry
///
/// Usa exatamente as mesmas SPs do SyncOrdersJob — os pedidos do WhatsApp
/// entram no ERP pelo mesmo caminho dos pedidos do app mobile.
///
/// Cadência: configurável (padrão 1 minuto) — compartilha timer com SyncOrdersJob.
/// Rule-02: totalmente async.
/// </summary>
public sealed class SyncAtendenteOrdersJob
{
    private readonly FirebirdService            _firebird;
    private readonly AtendenteApiClient         _atendente;
    private readonly ILogger<SyncAtendenteOrdersJob> _logger;

    private const int MaxConfirmRetries = 3;

    public SyncAtendenteOrdersJob(
        FirebirdService            firebird,
        AtendenteApiClient         atendente,
        ILogger<SyncAtendenteOrdersJob> logger)
    {
        _firebird  = firebird;
        _atendente = atendente;
        _logger    = logger;
    }

    /// <summary>Executa um ciclo de processamento de pedidos do WhatsApp.</summary>
    public async Task RunAsync(CancellationToken ct = default)
    {
        if (!_atendente.IsEnabled)
            return; // Atendente não configurado — noop

        List<PendingOrderDto> orders;
        try
        {
            orders = await _atendente.GetPendingOrdersAsync(ct);
        }
        catch (Exception ex)
        {
            _logger.LogError("[AtendenteOrderSync] Falha ao buscar pedidos: {Error}", ex.Message);
            return;
        }

        if (orders.Count == 0)
            return;

        _logger.LogInformation("[AtendenteOrderSync] {Count} pedido(s) WhatsApp pendentes.", orders.Count);

        foreach (var order in orders)
        {
            try
            {
                var erpOrderId = await InsertOrderInFirebird(order, ct);
                _logger.LogInformation(
                    "[AtendenteOrderSync] Pedido {OrderId} inserido no ERP (ID={ErpId}).",
                    order.Id, erpOrderId);

                // Confirma no backend (fora da transação Firebird)
                await ConfirmWithRetry(order.Id, erpOrderId, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(
                    "[AtendenteOrderSync] Erro ao processar pedido {OrderId}: {Error}",
                    order.Id, ex.Message);

                try
                {
                    await _atendente.ReportOrderErrorAsync(order.Id, ex.Message, ct);
                }
                catch (Exception reportEx)
                {
                    _logger.LogWarning(
                        "[AtendenteOrderSync] Falha ao reportar erro do pedido {OrderId}: {Error}",
                        order.Id, reportEx.Message);
                }
            }
        }
    }

    /// <summary>
    /// Insere o pedido no Firebird via MOB_CADASTRAR_PEDIDO + MOB_CADASTRAR_PEDIDO_ITEM.
    /// Usa exatamente as mesmas stored procedures do Coliseu Sales.
    /// </summary>
    private async Task<int> InsertOrderInFirebird(PendingOrderDto order, CancellationToken ct)
    {
        var now = DateTime.Now;

        return await _firebird.ExecuteInTransactionAsync(async conn =>
        {
            // ── Cabeçalho ───────────────────────────────────────────────
            using var cmdHeader = new FbCommand(@"
                EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(
                    @USUARIO, @CLIENTE, @DATA, @HORA, @OBSERVACAO,
                    @PRAZO_PEDIDO, @TIPO_OPERACAO, @PAGAMENTO,
                    @VALOR_DESCONTO, @TOTAL_PEDIDO
                )", conn);

            // Vendedor: usa ID do vendedor ou 1 como fallback
            var sellerId = 1;
            if (!string.IsNullOrEmpty(order.SellerId) && int.TryParse(order.SellerId, out var sid))
                sellerId = sid;

            // Cliente: usa ID do cliente ou 1 como fallback
            var clienteId = 1;
            if (!string.IsNullOrEmpty(order.CustomerId) && int.TryParse(order.CustomerId, out var cid))
                clienteId = cid;

            cmdHeader.Parameters.AddWithValue("@USUARIO",        sellerId);
            cmdHeader.Parameters.AddWithValue("@CLIENTE",        clienteId);
            cmdHeader.Parameters.AddWithValue("@DATA",           now.ToString("dd.MM.yyyy"));
            cmdHeader.Parameters.AddWithValue("@HORA",           now.ToString("HH:mm"));
            cmdHeader.Parameters.AddWithValue("@OBSERVACAO",     TruncateString($"[WhatsApp] {order.Notes}", 50));
            cmdHeader.Parameters.AddWithValue("@PRAZO_PEDIDO",   TruncateString(order.PaymentConditionId ?? "", 20));
            cmdHeader.Parameters.AddWithValue("@TIPO_OPERACAO",  TruncateString(order.NaturezaId ?? "", 20));
            cmdHeader.Parameters.AddWithValue("@PAGAMENTO",      int.TryParse(order.PaymentSpeciesId, out var pid) ? pid : 0);
            // DISCOUNT-FIX (definitivo): passa o desconto absoluto para o ERP calcular bruto/líquido corretamente.
            cmdHeader.Parameters.AddWithValue("@VALOR_DESCONTO", (double)order.DiscountValue);
            cmdHeader.Parameters.AddWithValue("@TOTAL_PEDIDO",   order.TotalAmount);

            var erpOrderId = Convert.ToInt32(await cmdHeader.ExecuteScalarAsync(ct));

            // ── Itens ──────────────────────────────────────────────────
            foreach (var item in order.Items)
            {
                using var cmdItem = new FbCommand(@"
                    EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO_ITEM(
                        @ID_PEDIDO, @PRODUTO, @QUANTIDADE,
                        @OBSERVACAO, @VALOR_UNITARIO,
                        @VALOR_DESCONTO, @VALOR_TOTAL
                    )", conn);

                var productId = int.TryParse(item.ProductCode, out var prodId) ? prodId : 0;
                var itemTotalPrice = item.UnitPrice * item.Quantity - item.Discount;

                cmdItem.Parameters.AddWithValue("@ID_PEDIDO",      erpOrderId);
                cmdItem.Parameters.AddWithValue("@PRODUTO",        productId);
                cmdItem.Parameters.AddWithValue("@QUANTIDADE",     item.Quantity);
                cmdItem.Parameters.AddWithValue("@OBSERVACAO",     "");
                cmdItem.Parameters.AddWithValue("@VALOR_UNITARIO", item.UnitPrice);
                cmdItem.Parameters.AddWithValue("@VALOR_DESCONTO", item.Discount);
                // Passa BRUTO p/ VALOR_TOTAL — ERP calcula Total Produtos = bruto; Total Pedido = líquido.
                var itemGrossTotal = item.UnitPrice * item.Quantity;
                cmdItem.Parameters.AddWithValue("@VALOR_TOTAL",    itemGrossTotal);

                await cmdItem.ExecuteNonQueryAsync(ct);

                // GRID-FIX: Atualiza VALOR_FINAL_UN (preço unit. líquido) e DESCONTO (% p/ coluna Valor Desc).
                // PEDIDOS.VALOR_PEDIDO = net → Total Produtos = Total Pedido sem Troco negativo.
                if (item.Discount > 0 && item.Quantity > 0m)
                {
                    var grossSubtotal = item.UnitPrice * item.Quantity;
                    var unitPriceLiq  = Math.Round(itemTotalPrice / item.Quantity, 4);
                    var discountPct   = grossSubtotal > 0m
                        ? Math.Round(item.Discount / grossSubtotal * 100m, 4)
                        : 0m;

                    using var updateCmd = new FbCommand(
                        "UPDATE PEDIDO_ITENS" +
                        "  SET VALOR_FINAL_UN = @VFU," +
                        "      DESCONTO       = @DISC" +
                        " WHERE ID_PEDIDO    = @PEDIDO" +
                        "   AND ID_PRODUTO   = @PROD" +
                        "   AND VALOR_UNITARIO = @VU",
                        conn);

                    updateCmd.Parameters.AddWithValue("@VFU",    unitPriceLiq);
                    updateCmd.Parameters.AddWithValue("@DISC",   discountPct);
                    updateCmd.Parameters.AddWithValue("@PEDIDO", erpOrderId);
                    updateCmd.Parameters.AddWithValue("@PROD",   productId);
                    updateCmd.Parameters.AddWithValue("@VU",     item.UnitPrice);

                    await updateCmd.ExecuteNonQueryAsync(ct);
                }
            }

            return erpOrderId;
        }, ct);
    }

    /// <summary>Confirma no backend com retry exponencial.</summary>
    private async Task ConfirmWithRetry(string orderId, int erpOrderId, CancellationToken ct)
    {
        for (int attempt = 1; attempt <= MaxConfirmRetries; attempt++)
        {
            try
            {
                var ok = await _atendente.ConfirmOrderAsync(orderId, erpOrderId, ct);
                if (ok)
                {
                    _logger.LogInformation(
                        "[AtendenteOrderSync] Pedido {OrderId} confirmado no backend (tentativa {Attempt}).",
                        orderId, attempt);
                    return;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    "[AtendenteOrderSync] Tentativa {Attempt}/{Max} de confirmar pedido {OrderId} falhou: {Error}",
                    attempt, MaxConfirmRetries, orderId, ex.Message);
            }

            if (attempt < MaxConfirmRetries)
                await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)), ct);
        }

        _logger.LogError(
            "[AtendenteOrderSync] Pedido {OrderId} inserido no ERP (ID={ErpId}) mas NÃO confirmado no backend após {Max} tentativas.",
            orderId, erpOrderId, MaxConfirmRetries);
    }

    private static string TruncateString(string value, int maxLength)
        => string.IsNullOrEmpty(value) ? "" : value.Length <= maxLength ? value : value[..maxLength];
}
