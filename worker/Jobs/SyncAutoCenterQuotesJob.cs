using System.Text.Json;
using System.Text.Json.Serialization;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using FirebirdSql.Data.FirebirdClient;
using Microsoft.Extensions.Options;
using System.Net.Http.Json;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// DTO provisório para mapeamento dos orçamentos vindos do AutoCenter (Middleware).
/// Adapte as propriedades conforme o Flutter App for evoluindo.
/// </summary>
public record AutoCenterQuoteDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("plate")] string Plate,
    [property: JsonPropertyName("customerName")] string CustomerName,
    [property: JsonPropertyName("customerId")] string CustomerId,
    [property: JsonPropertyName("mechanicId")] string MechanicId,
    [property: JsonPropertyName("paymentSpeciesId")] string PaymentSpeciesId,
    [property: JsonPropertyName("paymentConditionId")] string PaymentConditionId,
    [property: JsonPropertyName("naturezaId")] string NaturezaId,
    [property: JsonPropertyName("totalAmount")] decimal TotalAmount,
    [property: JsonPropertyName("items")] List<AutoCenterQuoteItemDto> Items,
    [property: JsonPropertyName("deptoId")] int? DeptoId,
    [property: JsonPropertyName("empresaErp")] int? EmpresaErp
);

public record AutoCenterQuoteItemDto(
    [property: JsonPropertyName("productCode")] string ProductCode,
    [property: JsonPropertyName("quantity")] decimal Quantity,
    [property: JsonPropertyName("unitPrice")] decimal UnitPrice,
    [property: JsonPropertyName("discount")] decimal Discount
);

/// <summary>
/// SyncAutoCenterQuotesJob — Busca orçamentos mecânicos AUTORIZADOS na VPS e insere na tabela central de pedidos do Firebird.
/// Conforme alinhamento: "mesma tabela, todos usam a mesma". 
/// Portanto usamos as mesmas SPs do Coliseu Sales (MOB_CADASTRAR_PEDIDO e MOB_CADASTRAR_PEDIDO_ITEM).
/// </summary>
public sealed class SyncAutoCenterQuotesJob
{
    private readonly FirebirdService _firebird;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<SyncAutoCenterQuotesJob> _logger;
    private readonly FirebirdOptions _fbOpts;
    private readonly AutoCenterApiOptions _acOpts;
    private readonly StatusStore _status;

    private readonly SemaphoreSlim _lock = new(1, 1);

    public SyncAutoCenterQuotesJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        ILogger<SyncAutoCenterQuotesJob> logger,
        IOptions<FirebirdOptions> fbOpts,
        IOptions<AutoCenterApiOptions> acOpts,
        StatusStore status)
    {
        _firebird = firebird;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
        _fbOpts = fbOpts.Value;
        _acOpts = acOpts.Value;
        _status = status;
    }

    public async Task RunAsync(CancellationToken ct = default)
    {
        if (!await _lock.WaitAsync(0, ct))
        {
            return;
        }

        try
        {
            var client = _httpClientFactory.CreateClient("AutoCenterApiClient");
            
            var request = new HttpRequestMessage(HttpMethod.Get, "/internal/quotes/approved");
            if (!string.IsNullOrEmpty(_acOpts.BranchId))
            {
                request.Headers.Add("X-Branch-Id", _acOpts.BranchId);
            }
            
            var res = await client.SendAsync(request, ct);

            if (!res.IsSuccessStatusCode)
            {
                if (res.StatusCode != System.Net.HttpStatusCode.NotFound)
                {
                    _logger.LogWarning("[AutoCenterSync] Fallback/Aviso na VPS AutoCenter: {Status}", res.StatusCode);
                    _status.Update("AutoCenter_Quotes", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
                else
                {
                    _status.Update("AutoCenter_Quotes", 0, DateTime.Now);
                }
                return;
            }

            var quotes = await res.Content.ReadFromJsonAsync<List<AutoCenterQuoteDto>>(cancellationToken: ct);

            if (quotes == null || quotes.Count == 0)
            {
                _status.Update("AutoCenter_Quotes", 0, DateTime.Now);
                return;
            }

            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] 🚗 [AutoCenter] {quotes.Count} orçamento(s) para integrar");
            
            int successCount = 0;
            foreach (var q in quotes)
            {
                if (await ProcessQuoteAsync(client, q, ct))
                {
                    successCount++;
                }
            }
            _status.Update("AutoCenter_Quotes", successCount, DateTime.Now);
        }
        catch (Exception ex)
        {
            _logger.LogError("[AutoCenterSync] Falha mecânica na rotina API: {Err}", ex.Message);
            _status.Update("AutoCenter_Quotes", 0, DateTime.Now, ex.Message);
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<bool> ProcessQuoteAsync(HttpClient client, AutoCenterQuoteDto quote, CancellationToken ct)
    {
        int erpOrderId = 0;
        try
        {
            // Reutiliza o conceito atômico já provado no Coliseu Sales
            await _firebird.TransactionAsync(async (cmd, innerCt) =>
            {
                var now = DateTime.Now;
                var data = now.ToString("dd.MM.yyyy");
                var hora = now.ToString("HH:mm");

                int.TryParse(quote.MechanicId, out var usuarioInt);
                int.TryParse(quote.CustomerId, out var clienteInt);
                int.TryParse(quote.PaymentSpeciesId, out var pgtoId);
                var obs = $"ATENDIMENTO - PLACA: {quote.Plate} | MECÂNICO: {quote.MechanicId}";

                var spSql = _fbOpts.UseExtendedSpVariant
                    ? "EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(?,?,?,?,?,?,?,?,?,?,?)"
                    : "EXECUTE PROCEDURE MOB_CADASTRAR_PEDIDO(?,?,?,?,?,?,?,?,?,?)";

                cmd.CommandText = spSql;
                cmd.CommandType = System.Data.CommandType.Text;
                cmd.Parameters.Clear();

                // Parâmetros iguais ao SyncOrdersJob para reuso da Tabela e Stored Procedure do Cliente
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Integer, Value = usuarioInt });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Integer, Value = clienteInt });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.VarChar, Value = data });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.VarChar, Value = hora });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.VarChar, Value = obs.Length > 50 ? obs[..50] : obs });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.VarChar, Value = string.IsNullOrWhiteSpace(quote.PaymentConditionId) ? "0" : quote.PaymentConditionId[..Math.Min(20, quote.PaymentConditionId.Length)] });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.VarChar, Value = string.IsNullOrWhiteSpace(quote.NaturezaId) ? "ORCAMENTO" : quote.NaturezaId[..Math.Min(20, quote.NaturezaId.Length)] });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Integer, Value = pgtoId });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Double, Value = 0.0 });
                cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Double, Value = (double)quote.TotalAmount });

                if (_fbOpts.UseExtendedSpVariant)
                {
                    int.TryParse(quote.PaymentConditionId?.Split('_')[0], out var condId);
                    cmd.Parameters.Add(new FbParameter { FbDbType = FbDbType.Integer, Value = condId });
                }

                await cmd.ExecuteNonQueryAsync(innerCt);

                using var genCmd = new FbCommand("SELECT GEN_ID(PEDIDOS, 0) AS ID_PEDIDO FROM RDB$DATABASE", cmd.Connection, cmd.Transaction);
                var result = Convert.ToInt32(await genCmd.ExecuteScalarAsync(innerCt));

                if (quote.Items != null)
                {
                    foreach (var item in quote.Items)
                    {
                        cmd.CommandText = "MOB_CADASTRAR_PEDIDO_ITEM";
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        int.TryParse(item.ProductCode, out var prodInt);

                        cmd.Parameters.Clear();
                        cmd.Parameters.Add(new FbParameter("ID_PEDIDO", FbDbType.Integer) { Value = result });
                        cmd.Parameters.Add(new FbParameter("PRODUTO", FbDbType.Integer) { Value = prodInt });
                        cmd.Parameters.Add(new FbParameter("QUANTIDADE", FbDbType.Float) { Value = (float)item.Quantity });
                        cmd.Parameters.Add(new FbParameter("OBSERVACAO", FbDbType.VarChar) { Value = DBNull.Value });
                        cmd.Parameters.Add(new FbParameter("VALOR_UNITARIO", FbDbType.Decimal) { Value = item.UnitPrice });
                        cmd.Parameters.Add(new FbParameter("VALOR_DESCONTO", FbDbType.Decimal) { Value = item.Discount });
                        cmd.Parameters.Add(new FbParameter("VALOR_TOTAL", FbDbType.Decimal) { Value = item.UnitPrice * item.Quantity });
                        await cmd.ExecuteNonQueryAsync(innerCt);
                    }
                }

                if (quote.DeptoId.HasValue && quote.DeptoId.Value > 0)
                {
                    using var updateCmd = new FbCommand(@"
                        UPDATE PEDIDOS P
                        SET 
                          ID_DEPTO = @DEPTO
                        WHERE P.ID_PEDIDO = @ID_PEDIDO
                    ", cmd.Connection, cmd.Transaction);
                    updateCmd.Parameters.Add(new FbParameter("@DEPTO", FbDbType.Integer) { Value = quote.DeptoId.Value });
                    updateCmd.Parameters.Add(new FbParameter("@ID_PEDIDO", FbDbType.Integer) { Value = result });
                    await updateCmd.ExecuteNonQueryAsync(innerCt);
                    
                    _logger.LogInformation("[AutoCenterSync] Orçamento {QuoteId} roteado para ID_DEPTO={Depto}.", quote.Id, quote.DeptoId.Value);
                }

                erpOrderId = result;
            }, ct);

            _logger.LogInformation("[AutoCenterSync] Orçamento do AutoCenter inserido no Firebird. ERP ID: {Id}", erpOrderId);

            // Avisa o AutoCenter Middleware
            var patchPayload = new { status = "INTEGRATED" };
            var content = JsonContent.Create(patchPayload);
            
            var requestPatch = new HttpRequestMessage(HttpMethod.Patch, $"/internal/quotes/{quote.Id}/status")
            {
                Content = content
            };
            if (!string.IsNullOrEmpty(_acOpts.BranchId))
            {
                requestPatch.Headers.Add("X-Branch-Id", _acOpts.BranchId);
            }
            var ackResponse = await client.SendAsync(requestPatch, ct);

            if (!ackResponse.IsSuccessStatusCode)
            {
                _logger.LogWarning("[AutoCenterSync] Falha no ACK para middleware AutoCenter. O orçamento pode ser duplicado...");
            }
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[AutoCenterSync] Falha ao processar orçamento {Id} no Banco de Dados local", quote.Id);
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [AutoCenter] Erro placa {quote.Plate}: {ex.Message}");
            return false;
        }
    }
}
