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
    [property: JsonPropertyName("sellerId")] string SellerId,
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
    private readonly VpsApiClient _vps;
    private readonly ILogger<SyncAutoCenterQuotesJob> _logger;
    private readonly FirebirdOptions _fbOpts;
    private readonly AutoCenterApiOptions _acOpts;
    private readonly StatusStore _status;

    private readonly SemaphoreSlim _lock = new(1, 1);

    public SyncAutoCenterQuotesJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        VpsApiClient vps,
        ILogger<SyncAutoCenterQuotesJob> logger,
        IOptions<FirebirdOptions> fbOpts,
        IOptions<AutoCenterApiOptions> acOpts,
        StatusStore status)
    {
        _firebird = firebird;
        _httpClientFactory = httpClientFactory;
        _vps = vps;
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
            
            var request = new HttpRequestMessage(HttpMethod.Get, "/internal/service-orders/approved");
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
            
            int integratedCount = 0;
            foreach (var q in quotes)
            {
                if (await ProcessQuoteAsync(client, q, ct))
                {
                    integratedCount++;
                }
            }

            _status.Update("AutoCenter_Quotes", integratedCount, DateTime.Now);
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
        // Resolve cliente local se necessário antes de abrir transação no Firebird
        if (quote.CustomerId?.StartsWith("local_", StringComparison.OrdinalIgnoreCase) == true)
        {
            var erpCustomerId = await _vps.ResolveLocalCustomerAsync(quote.CustomerId, ct);
            if (erpCustomerId is null)
            {
                _logger.LogWarning("[AutoCenterSync] Cliente local {CustomerId} ainda não confirmado no ERP. Orçamento {QuoteId} aguardando próximo ciclo.",
                    quote.CustomerId, quote.Id);
                return false;
            }
            _logger.LogInformation("[AutoCenterSync] Cliente local {LocalId} resolvido para ERP ID {ErpId} no orçamento {QuoteId}",
                quote.CustomerId, erpCustomerId, quote.Id);
            quote = quote with { CustomerId = erpCustomerId };
        }

        // Consulta o veículo na VPS antes de iniciar a transação do Firebird para evitar manter conexões abertas
        string brand = "GENERICA";
        string model = "GENERICO";
        int? anoFabrica = null;
        int? anoModelo = null;
        string cor = "PRETA";
        string chassi = "";

        try
        {
            var vehicleRes = await client.GetAsync($"/internal/vehicles/{quote.Plate}", ct);
            if (vehicleRes.IsSuccessStatusCode)
            {
                var vData = await vehicleRes.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
                if (vData.ValueKind != JsonValueKind.Null)
                {
                    brand = vData.TryGetProperty("brand", out var bProp) ? bProp.GetString() ?? "GENERICA" : "GENERICA";
                    model = vData.TryGetProperty("model", out var mProp) ? mProp.GetString() ?? "GENERICO" : "GENERICO";
                    cor = vData.TryGetProperty("cor", out var cProp) ? cProp.GetString() ?? "PRETA" : "PRETA";
                    chassi = vData.TryGetProperty("chassi", out var chProp) ? chProp.GetString() ?? "" : "";
                    
                    if (vData.TryGetProperty("ano_fabrica", out var afProp) && afProp.ValueKind == JsonValueKind.Number)
                    {
                        anoFabrica = afProp.GetInt32();
                    }
                    else if (vData.TryGetProperty("ano", out var aProp) && aProp.ValueKind == JsonValueKind.String)
                    {
                        int.TryParse(aProp.GetString(), out var af);
                        anoFabrica = af > 0 ? af : null;
                    }

                    if (vData.TryGetProperty("ano_modelo", out var amProp) && amProp.ValueKind == JsonValueKind.Number)
                    {
                        anoModelo = amProp.GetInt32();
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[AutoCenterSync] Não foi possível consultar detalhes do veículo {Plate} na VPS: {Msg}. Usando valores padrão.", quote.Plate, ex.Message);
        }

        int erpOrderId = 0;
        try
        {
            await _firebird.TransactionAsync(async (cmd, innerCt) =>
            {
                var now = DateTime.Now;
                var data = now.ToString("dd.MM.yyyy");
                var hora = now.ToString("HH:mm");

                var sellerCode = string.IsNullOrWhiteSpace(quote.SellerId) ? quote.MechanicId : quote.SellerId;
                int.TryParse(sellerCode, out var usuarioInt);
                int.TryParse(quote.CustomerId, out var clienteInt);
                int.TryParse(quote.PaymentSpeciesId, out var pgtoId);
                var obs = $"ATENDIMENTO - PLACA: {quote.Plate} | VENDEDOR: {sellerCode}";

                // 1. Verifica se o veículo já existe no cadastro de veículos do Firebird (tabela CLIENTES_VEICULOS)
                int? existingVehicleId = null;
                int? existingClientId = null;

                cmd.CommandText = "SELECT ID_VEICULO, ID_CLIENTE FROM CLIENTES_VEICULOS WHERE PLACA = @PLACA";
                cmd.CommandType = System.Data.CommandType.Text;
                cmd.Parameters.Clear();
                cmd.Parameters.Add(new FbParameter("@PLACA", FbDbType.VarChar) { Value = quote.Plate });

                using (var reader = await cmd.ExecuteReaderAsync(innerCt))
                {
                    if (await reader.ReadAsync(innerCt))
                    {
                        existingVehicleId = reader.GetInt32(0);
                        existingClientId = reader.GetInt32(1);
                    }
                }

                int targetVehicleId;

                if (existingVehicleId.HasValue)
                {
                    targetVehicleId = existingVehicleId.Value;

                    // Se estiver associado a outro cliente no ERP, re-associa para o cliente atual
                    if (existingClientId != clienteInt)
                    {
                        cmd.CommandText = "UPDATE CLIENTES_VEICULOS SET ID_CLIENTE = @NEW_CLIENT WHERE ID_VEICULO = @ID_VEICULO AND ID_CLIENTE = @OLD_CLIENT";
                        cmd.Parameters.Clear();
                        cmd.Parameters.Add(new FbParameter("@NEW_CLIENT", FbDbType.Integer) { Value = clienteInt });
                        cmd.Parameters.Add(new FbParameter("@ID_VEICULO", FbDbType.Integer) { Value = targetVehicleId });
                        cmd.Parameters.Add(new FbParameter("@OLD_CLIENT", FbDbType.Integer) { Value = existingClientId.Value });
                        await cmd.ExecuteNonQueryAsync(innerCt);

                        _logger.LogInformation("[AutoCenterSync] Veículo placa {Plate} reassociado do cliente {OldClient} para o cliente {NewClient} no ERP", 
                            quote.Plate, existingClientId, clienteInt);
                    }
                }
                else
                {
                    // Obtém novo ID_VEICULO do generator do ERP
                    cmd.CommandText = "SELECT GEN_ID(VEICULOS, 1) FROM RDB$DATABASE";
                    cmd.Parameters.Clear();
                    targetVehicleId = Convert.ToInt32(await cmd.ExecuteScalarAsync(innerCt));

                    // Insere o veículo na ficha do cliente no ERP
                    cmd.CommandText = @"
                        INSERT INTO CLIENTES_VEICULOS (
                            ID_CLIENTE, ID_VEICULO, PLACA, MARCA, MODELO, ANO_FABRICA, ANO_MODELO, COR, NUMERO_CHASSI, STATUS
                        ) VALUES (
                            @ID_CLIENTE, @ID_VEICULO, @PLACA, @MARCA, @MODELO, @ANO_FABRICA, @ANO_MODELO, @COR, @NUMERO_CHASSI, 1
                        )";
                    cmd.Parameters.Clear();
                    cmd.Parameters.Add(new FbParameter("@ID_CLIENTE", FbDbType.Integer) { Value = clienteInt });
                    cmd.Parameters.Add(new FbParameter("@ID_VEICULO", FbDbType.Integer) { Value = targetVehicleId });
                    cmd.Parameters.Add(new FbParameter("@PLACA", FbDbType.VarChar) { Value = quote.Plate });
                    cmd.Parameters.Add(new FbParameter("@MARCA", FbDbType.VarChar) { Value = brand.Length > 50 ? brand[..50] : brand });
                    cmd.Parameters.Add(new FbParameter("@MODELO", FbDbType.VarChar) { Value = model.Length > 50 ? model[..50] : model });
                    cmd.Parameters.Add(new FbParameter("@ANO_FABRICA", FbDbType.SmallInt) { Value = (object)anoFabrica ?? DBNull.Value });
                    cmd.Parameters.Add(new FbParameter("@ANO_MODELO", FbDbType.SmallInt) { Value = (object)anoModelo ?? DBNull.Value });
                    cmd.Parameters.Add(new FbParameter("@COR", FbDbType.VarChar) { Value = cor.Length > 30 ? cor[..30] : cor });
                    cmd.Parameters.Add(new FbParameter("@NUMERO_CHASSI", FbDbType.VarChar) { Value = chassi.Length > 20 ? chassi[..20] : chassi });
                    await cmd.ExecuteNonQueryAsync(innerCt);

                    _logger.LogInformation("[AutoCenterSync] Novo veículo cadastrado na ficha do cliente {ClienteId} no ERP. Placa: {Plate}", 
                        clienteInt, quote.Plate);
                }

                // 2. Executa stored procedure de cadastro do pedido/orçamento no ERP
                // Descobre dinamicamente a assinatura da SP para compatibilidade em qualquer banco de dados
                using (var countCmd = new FbCommand(
                    "SELECT count(*) FROM RDB$PROCEDURE_PARAMETERS WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO' AND RDB$PARAMETER_TYPE = 0",
                    cmd.Connection, cmd.Transaction))
                {
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

                    cmd.Parameters.AddWithValue("@USUARIO", usuarioInt);
                    cmd.Parameters.AddWithValue("@CLIENTE", clienteInt);
                    cmd.Parameters.AddWithValue("@DATA", data);
                    cmd.Parameters.AddWithValue("@HORA", hora);
                    cmd.Parameters.AddWithValue("@OBSERVACAO", obs.Length > 50 ? obs[..50] : obs);

                    var condStr = quote.PaymentConditionId ?? "0";
                    var prazoPedido = condStr.Length > 20 ? condStr[..20] : condStr;
                    cmd.Parameters.AddWithValue("@PRAZO_PEDIDO", prazoPedido);

                    var tipoOperacao = (quote.NaturezaId == "null" || 
                                        quote.NaturezaId == "ORCAMENTO" || 
                                        string.IsNullOrWhiteSpace(quote.NaturezaId) || 
                                        !int.TryParse(quote.NaturezaId, out _)) 
                                        ? null 
                                        : quote.NaturezaId;
                    cmd.Parameters.AddWithValue("@TIPO_OPERACAO", (object?)tipoOperacao ?? DBNull.Value);

                    cmd.Parameters.AddWithValue("@PAGAMENTO", pgtoId);
                    cmd.Parameters.AddWithValue("@VALOR_DESCONTO", 0.0);
                    cmd.Parameters.AddWithValue("@TOTAL_PEDIDO", (double)quote.TotalAmount);

                    if (isExtended)
                    {
                        int.TryParse(quote.PaymentConditionId?.Split('_')[0], out var condId);
                        cmd.Parameters.AddWithValue("@CONDICAO_PAGAMENTO", condId);
                    }

                    if (hasMultiTenant)
                    {
                        int nativeDepto = 1;
                        if (quote.DeptoId.HasValue && quote.DeptoId.Value > 0)
                        {
                            nativeDepto = quote.DeptoId.Value;
                        }
                        cmd.Parameters.AddWithValue("@DEPTO", nativeDepto);
                        cmd.Parameters.AddWithValue("@EMPRESA", 1);
                    }
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

                // 3. Atualiza os campos de veículo, placa e departamento na tabela central PEDIDOS do ERP
                string descVeiculo = $"{brand} {model}";
                if (descVeiculo.Length > 20) descVeiculo = descVeiculo[..20];

                var updateSql = @"
                    UPDATE PEDIDOS P
                    SET 
                      P.ID_VEICULO = @ID_VEICULO,
                      P.PLACA_VEICULO = @PLACA_VEICULO,
                      P.VEICULO = @VEICULO";

                if (quote.DeptoId.HasValue && quote.DeptoId.Value > 0)
                {
                    updateSql += ", P.ID_DEPTO = @DEPTO";
                }

                updateSql += " WHERE P.ID_PEDIDO = @ID_PEDIDO";

                using var updatePedCmd = new FbCommand(updateSql, cmd.Connection, cmd.Transaction);
                updatePedCmd.Parameters.Add(new FbParameter("@ID_VEICULO", FbDbType.Integer) { Value = targetVehicleId });
                updatePedCmd.Parameters.Add(new FbParameter("@PLACA_VEICULO", FbDbType.VarChar) { Value = quote.Plate });
                updatePedCmd.Parameters.Add(new FbParameter("@VEICULO", FbDbType.VarChar) { Value = descVeiculo });
                if (quote.DeptoId.HasValue && quote.DeptoId.Value > 0)
                {
                    updatePedCmd.Parameters.Add(new FbParameter("@DEPTO", FbDbType.Integer) { Value = quote.DeptoId.Value });
                }
                updatePedCmd.Parameters.Add(new FbParameter("@ID_PEDIDO", FbDbType.Integer) { Value = result });
                await updatePedCmd.ExecuteNonQueryAsync(innerCt);

                erpOrderId = result;
            }, ct);

            _logger.LogInformation("[AutoCenterSync] Orçamento do AutoCenter inserido no Firebird. ERP ID: {Id}", erpOrderId);

            // Avisa o AutoCenter Middleware
            var patchPayload = new { status = "INTEGRATED" };
            var content = JsonContent.Create(patchPayload);
            
            var requestPatch = new HttpRequestMessage(HttpMethod.Patch, $"/internal/service-orders/{quote.Id}/status")
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
