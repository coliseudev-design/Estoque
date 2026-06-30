using System.Net.Http.Json;
using System.Text.Json.Serialization;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Jobs;

public record SyncGarantiasSupplierDto(
    [property: JsonPropertyName("erpId")]    int    ErpId,
    [property: JsonPropertyName("nome")]     string Nome,
    [property: JsonPropertyName("telefone")] string? Telefone,
    [property: JsonPropertyName("cnpj")]     string? Cnpj
);

public sealed class SyncGarantiasSuppliersJob
{
    private readonly FirebirdService                       _firebird;
    private readonly IHttpClientFactory                    _httpClientFactory;
    private readonly ILogger<SyncGarantiasSuppliersJob>    _logger;
    private readonly GarantiasApiOptions                   _garantiasOpts;
    private readonly IdentityApiOptions                    _identityOpts;
    private readonly StatusStore                           _status;
    private readonly ChangeTrackerService                  _changeTracker;

    private readonly SemaphoreSlim _lock = new(1, 1);

    public SyncGarantiasSuppliersJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        ILogger<SyncGarantiasSuppliersJob> logger,
        IOptions<GarantiasApiOptions> garantiasOpts,
        IOptions<IdentityApiOptions> identityOpts,
        StatusStore status,
        ChangeTrackerService changeTracker)
    {
        _firebird          = firebird;
        _httpClientFactory = httpClientFactory;
        _logger            = logger;
        _garantiasOpts     = garantiasOpts.Value;
        _identityOpts      = identityOpts.Value;
        _status            = status;
        _changeTracker     = changeTracker;
    }

    public async Task RunAsync(bool force = false, CancellationToken ct = default)
    {
        if (!_garantiasOpts.Enabled)
        {
            _status.Update("Garantias_Suppliers", 0, DateTime.Now, "Desativado");
            return;
        }

        if (!await _lock.WaitAsync(0, ct)) return;

        var tables = new[] { "CLIENTES" };

        try
        {
            if (!force && !await _changeTracker.HasChangesAsync("GarantiasSuppliers", tables))
            {
                _logger.LogDebug("[GarantiasSuppliers] Sem alterações pendentes no Firebird. Ignorando este ciclo.");
                return;
            }

            var suppliers = await ReadSuppliersFromFirebirdAsync(ct);

            if (suppliers.Count == 0)
            {
                _logger.LogInformation("[GarantiasSuppliers] Nenhum fornecedor encontrado no Firebird.");
                _status.Update("Garantias_Suppliers", 0, DateTime.Now, "Nenhum fornecedor encontrado");
                await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasSuppliers", tables);
                return;
            }

            await PushToApiAsync(suppliers, ct);
            await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasSuppliers", tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[GarantiasSuppliers] Falha na sincronização de fornecedores.");
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Garantias-Fornecedores] {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<List<SyncGarantiasSupplierDto>> ReadSuppliersFromFirebirdAsync(CancellationToken ct)
    {
        const string sql = @"
            SELECT 
                c.ID_CLIENTE AS IDFORNECEDOR,
                COALESCE(c.NOME, '') AS NOME,
                COALESCE(c.CPF_CNPJ, '') AS CNPJ,
                COALESCE(cd.FONE_RES, cd.FONE_COM, '') AS TELEFONE
            FROM CLIENTES c
            LEFT JOIN CLIENTES_DADOS cd ON cd.ID_CLIENTE = c.ID_CLIENTE
            WHERE c.TIPO = 2
            ORDER BY c.ID_CLIENTE DESC";

        var rows = await _firebird.QueryAsync(sql, ct: ct);

        var suppliers = rows.Select(row => new SyncGarantiasSupplierDto(
            ErpId:    Convert.ToInt32(row["IDFORNECEDOR"] ?? 0),
            Nome:     row["NOME"]?.ToString()?.Trim() ?? "",
            Cnpj:     row["CNPJ"]?.ToString()?.Trim() ?? "",
            Telefone: row["TELEFONE"]?.ToString()?.Trim() ?? ""
        )).ToList();

        _logger.LogInformation("[GarantiasSuppliers] {Count} fornecedores lidos do Firebird.", suppliers.Count);
        return suppliers;
    }

    private async Task PushToApiAsync(List<SyncGarantiasSupplierDto> suppliers, CancellationToken ct)
    {
        var client = _httpClientFactory.CreateClient("GarantiasApiClient");
        var tenantId = _identityOpts.TenantId.ToString();

        if (!client.DefaultRequestHeaders.Contains("X-Tenant-Id"))
            client.DefaultRequestHeaders.Add("X-Tenant-Id", tenantId);

        const int batchSize = 500;
        int totalBatch = (int)Math.Ceiling(suppliers.Count / (double)batchSize);

        for (int i = 0; i < totalBatch; i++)
        {
            var batch = suppliers.Skip(i * batchSize).Take(batchSize).ToList();

            var response = await client.PostAsJsonAsync("/api/sync/fornecedores", batch, ct);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation(
                    "[GarantiasSuppliers] Lote {N}/{T} enviado ({C} fornecedores).",
                    i + 1, totalBatch, batch.Count);
            }
            else
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning(
                    "[GarantiasSuppliers] Lote {N} falhou: HTTP {S} — {B}",
                    i + 1, (int)response.StatusCode, body[..Math.Min(200, body.Length)]);
            }
        }

        _status.AppendLog(
            $"[{DateTime.Now:HH:mm:ss}] 🚚 [Garantias] {suppliers.Count} fornecedores → API");
        _status.Update("Garantias_Suppliers", suppliers.Count, DateTime.Now);
    }
}
