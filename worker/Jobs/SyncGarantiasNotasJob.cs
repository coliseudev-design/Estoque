using System.Net.Http.Json;
using System.Text.Json.Serialization;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Jobs;

public record SyncGarantiasItemNotaDto(
    [property: JsonPropertyName("erpProdutoId")]  int     ErpProdutoId,
    [property: JsonPropertyName("produtoNome")]   string  ProdutoNome,
    [property: JsonPropertyName("quantidade")]    decimal Quantidade,
    [property: JsonPropertyName("valorUnitario")] decimal ValorUnitario,
    [property: JsonPropertyName("referencia")]    string? Referencia,
    [property: JsonPropertyName("marca")]         string? Marca
);

public record SyncGarantiasNotaFiscalDto(
    [property: JsonPropertyName("erpId")]        int      ErpId,
    [property: JsonPropertyName("erpClienteId")] int      ErpClienteId,
    [property: JsonPropertyName("numero")]       string   Numero,
    [property: JsonPropertyName("dataEmissao")]  DateTime DataEmissao,
    [property: JsonPropertyName("valorTotal")]   decimal  ValorTotal,
    [property: JsonPropertyName("itens")]        List<SyncGarantiasItemNotaDto> Itens
);

public sealed class SyncGarantiasNotasJob
{
    private readonly FirebirdService                       _firebird;
    private readonly IHttpClientFactory                    _httpClientFactory;
    private readonly ILogger<SyncGarantiasNotasJob>        _logger;
    private readonly GarantiasApiOptions                   _garantiasOpts;
    private readonly IdentityApiOptions                    _identityOpts;
    private readonly StatusStore                           _status;
    private readonly DeltaCacheService                     _deltaCache;
    private readonly ChangeTrackerService                  _changeTracker;

    private readonly SemaphoreSlim _lock = new(1, 1);

    public SyncGarantiasNotasJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        ILogger<SyncGarantiasNotasJob> logger,
        IOptions<GarantiasApiOptions> garantiasOpts,
        IOptions<IdentityApiOptions> identityOpts,
        StatusStore status,
        DeltaCacheService deltaCache,
        ChangeTrackerService changeTracker)
    {
        _firebird          = firebird;
        _httpClientFactory = httpClientFactory;
        _logger            = logger;
        _garantiasOpts     = garantiasOpts.Value;
        _identityOpts      = identityOpts.Value;
        _status            = status;
        _deltaCache        = deltaCache;
        _changeTracker     = changeTracker;
    }

    public async Task RunAsync(bool force = false, CancellationToken ct = default)
    {
        if (!_garantiasOpts.Enabled)
        {
            _status.Update("Garantias_Notas", 0, DateTime.Now, "Desativado");
            return;
        }

        if (!await _lock.WaitAsync(0, ct)) return;

        var tables = new[] { "PEDIDOS" };

        try
        {
            if (!force && !await _changeTracker.HasChangesAsync("GarantiasNotas", tables))
            {
                _logger.LogDebug("[GarantiasNotas] Sem alterações pendentes no Firebird. Ignorando este ciclo.");
                return;
            }

            var notas = await ReadNotasFromFirebirdAsync(ct);

            if (notas.Count == 0)
            {
                _logger.LogInformation("[GarantiasNotas] Nenhuma nota/pedido ativo nos últimos 12 meses.");
                _status.Update("Garantias_Notas", 0, DateTime.Now, "Nenhuma nota nos últimos 12 meses");
                await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasNotas", tables);
                return;
            }

            await PushToApiAsync(notas, ct);
            await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasNotas", tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[GarantiasNotas] Falha na sincronização de notas fiscais.");
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Garantias-Notas] {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<List<SyncGarantiasNotaFiscalDto>> ReadNotasFromFirebirdAsync(CancellationToken ct)
    {
        // Busca os pedidos dos últimos 12 meses
        const string sql = @"
            SELECT 
                p.ID_PEDIDO,
                p.ID_CLIENTE,
                COALESCE(p.PEDIDO, CAST(p.ID_PEDIDO AS VARCHAR(50))) AS NUMERO,
                p.DATA_HORA AS DATA_EMISSAO,
                COALESCE(p.VALOR_PEDIDO, 0) AS VALOR_TOTAL,
                i.ID_PRODUTO,
                pr.DESCRICAO AS NOME_PRODUTO,
                pr.REF AS REFERENCIA,
                l.NOME AS MARCA,
                COALESCE(i.QTDE, 0) AS QUANTIDADE,
                COALESCE(i.VALOR_FINAL_UN, i.VALOR_UNITARIO) AS VALOR_UNITARIO
            FROM PEDIDOS p
            JOIN PEDIDO_ITENS i ON i.ID_PEDIDO = p.ID_PEDIDO
            JOIN PRODUTOS pr ON pr.ID_PRODUTO = i.ID_PRODUTO
            LEFT JOIN LABORATORIOS l ON l.ID_LABORATORIO = pr.ID_MARCA
            WHERE p.DATA_HORA >= DATEADD(-1 YEAR TO CURRENT_DATE)
              AND (p.STATUS <> 9 OR p.STATUS IS NULL)
            ORDER BY p.ID_PEDIDO DESC";

        var rows = await _firebird.QueryAsync(sql, ct: ct);

        // Agrupa por pedido, pois a query retorna uma linha por item
        var grouped = rows.GroupBy(row => Convert.ToInt32(row["ID_PEDIDO"] ?? 0));

        var notas = new List<SyncGarantiasNotaFiscalDto>();

        foreach (var group in grouped)
        {
            var first = group.First();
            var dataEmissaoObj = first["DATA_EMISSAO"];
            DateTime dataEmissao = DateTime.UtcNow;
            
            if (dataEmissaoObj != null && DateTime.TryParse(dataEmissaoObj.ToString(), out var dt))
                dataEmissao = dt.ToUniversalTime();

            var nota = new SyncGarantiasNotaFiscalDto(
                ErpId:        group.Key,
                ErpClienteId: Convert.ToInt32(first["ID_CLIENTE"] ?? 0),
                Numero:       first["NUMERO"]?.ToString()?.Trim() ?? group.Key.ToString(),
                DataEmissao:  dataEmissao,
                ValorTotal:   Convert.ToDecimal(first["VALOR_TOTAL"] ?? 0),
                Itens: group.Select(row => new SyncGarantiasItemNotaDto(
                    ErpProdutoId:  Convert.ToInt32(row["ID_PRODUTO"] ?? 0),
                    ProdutoNome:   row["NOME_PRODUTO"]?.ToString()?.Trim() ?? "Produto Sem Nome",
                    Quantidade:    Convert.ToDecimal(row["QUANTIDADE"] ?? 0),
                    ValorUnitario: Convert.ToDecimal(row["VALOR_UNITARIO"] ?? 0),
                    Referencia:    row["REFERENCIA"]?.ToString()?.Trim(),
                    Marca:         row["MARCA"]?.ToString()?.Trim()
                )).ToList()
            );

            notas.Add(nota);
        }

        _logger.LogInformation("[GarantiasNotas] {Count} pedidos (notas) lidas do Firebird (últimos 12 meses).", notas.Count);
        return notas;
    }

    private async Task PushToApiAsync(List<SyncGarantiasNotaFiscalDto> notas, CancellationToken ct)
    {
        var storeLabel = "Garantias_Notas";
        var rowsToPush = new List<SyncGarantiasNotaFiscalDto>();
        var hashesToSave = new Dictionary<string, string>();

        // Carrega todos os hashes cadastrados para esta entidade na memória
        var cachedHashes = _deltaCache.GetEntityHashes(storeLabel);

        foreach (var nota in notas)
        {
            try
            {
                string idFirebird = nota.ErpId.ToString();
                string hash = _deltaCache.ComputeHash(nota);

                // Compara em memória em vez de fazer query individual no banco
                if (!cachedHashes.TryGetValue(idFirebird, out var savedHash) || savedHash != hash)
                {
                    rowsToPush.Add(nota);
                    hashesToSave[idFirebird] = hash;
                }
            }
            catch (Exception)
            {
                rowsToPush.Add(nota);
            }
        }

        if (rowsToPush.Count == 0)
        {
            _logger.LogInformation("[GarantiasNotas] Tudo atualizado ({Count} verificados, 0 mudanças)", notas.Count);
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [Garantias] Notas Fiscais: Sem mudanças ({notas.Count} analisadas)");
            _status.Update("Garantias_Notas", notas.Count, DateTime.Now);
            return;
        }

        _logger.LogInformation("[GarantiasNotas] Delta: enviando {NewCount} alterações (de {TotalCount} total)", rowsToPush.Count, notas.Count);

        var client = _httpClientFactory.CreateClient("GarantiasApiClient");
        var tenantId = _identityOpts.TenantId.ToString();

        if (!client.DefaultRequestHeaders.Contains("X-Tenant-Id"))
            client.DefaultRequestHeaders.Add("X-Tenant-Id", tenantId);

        const int batchSize = 10; // Lote muito pequeno para evitar 504 Gateway Timeout no bulk insert de itens
        int totalBatch = (int)Math.Ceiling(rowsToPush.Count / (double)batchSize);

        for (int i = 0; i < totalBatch; i++)
        {
            ct.ThrowIfCancellationRequested();
            var batch = rowsToPush.Skip(i * batchSize).Take(batchSize).ToList();

            var response = await client.PostAsJsonAsync("/api/sync/notas-fiscais", batch, ct);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation(
                    "[GarantiasNotas] Lote {N}/{T} enviado ({C} notas).",
                    i + 1, totalBatch, batch.Count);
                
                // Coleta hashes do lote atual sincronizado e salva em lote (transação única) no SQLite
                var batchHashes = new Dictionary<string, string>();
                foreach (var nota in batch)
                {
                    string idFirebird = nota.ErpId.ToString();
                    if (hashesToSave.TryGetValue(idFirebird, out var hash))
                    {
                        batchHashes[idFirebird] = hash;
                    }
                }
                _deltaCache.SaveHashes(storeLabel, batchHashes);
            }
            else
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning(
                    "[GarantiasNotas] Lote {N} falhou: HTTP {S} — {B}",
                    i + 1, (int)response.StatusCode, body[..Math.Min(200, body.Length)]);
            }
        }

        _status.AppendLog(
            $"[{DateTime.Now:HH:mm:ss}] 🧾 [Garantias] {rowsToPush.Count} notas novas/alteradas → API");
        _status.Update("Garantias_Notas", notas.Count, DateTime.Now);
    }
}
