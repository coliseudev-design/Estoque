using System.Net.Http.Json;
using System.Text.Json.Serialization;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs;

public record SyncGarantiasCustomerDto(
    [property: JsonPropertyName("erpId")]     int    ErpId,
    [property: JsonPropertyName("nome")]      string Nome,
    [property: JsonPropertyName("telefone")]  string? Telefone,
    [property: JsonPropertyName("email")]     string? Email,
    [property: JsonPropertyName("documento")] string? Documento
);

public sealed class SyncGarantiasCustomersJob
{
    private readonly FirebirdService                       _firebird;
    private readonly IHttpClientFactory                    _httpClientFactory;
    private readonly ILogger<SyncGarantiasCustomersJob>    _logger;
    private readonly GarantiasApiOptions                   _garantiasOpts;
    private readonly IdentityApiOptions                    _identityOpts;
    private readonly StatusStore                           _status;
    private readonly ChangeTrackerService                  _changeTracker;

    private readonly SemaphoreSlim _lock = new(1, 1);

    public SyncGarantiasCustomersJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        ILogger<SyncGarantiasCustomersJob> logger,
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
            _status.Update("Garantias_Customers", 0, DateTime.Now, "Desativado");
            return;
        }

        if (!await _lock.WaitAsync(0, ct)) return;

        var tables = new[] { "CLIENTES" };

        try
        {
            if (!force && !await _changeTracker.HasChangesAsync("GarantiasCustomers", tables))
            {
                _logger.LogDebug("[GarantiasCustomers] Sem alterações pendentes no Firebird. Ignorando este ciclo.");
                return;
            }

            var customers = await ReadCustomersFromFirebirdAsync(ct);

            if (customers.Count == 0)
            {
                _logger.LogInformation("[GarantiasCustomers] Nenhum cliente ativo no Firebird.");
                _status.Update("Garantias_Customers", 0, DateTime.Now, "Nenhum cliente ativo no Firebird");
                await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasCustomers", tables);
                return;
            }

            await PushToApiAsync(customers, ct);
            await _changeTracker.UpdateLastProcessedLogIdAsync("GarantiasCustomers", tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[GarantiasCustomers] Falha na sincronização de clientes.");
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Garantias-Clientes] {ex.Message}");
        }
        finally
        {
            _lock.Release();
        }
    }

    private async Task<List<SyncGarantiasCustomerDto>> ReadCustomersFromFirebirdAsync(CancellationToken ct)
    {
        const string sql = @"
            SELECT
                c.ID_CLIENTE AS IDCLIENTE,
                COALESCE(c.NOME, '')    AS NOME,
                COALESCE(c.CPF_CNPJ, '')  AS DOCUMENTO,
                COALESCE(cd.FONE_RES, cd.FONE_COM, '') AS TELEFONE,
                COALESCE(c.EMAIL, '')   AS EMAIL
            FROM CLIENTES c
            LEFT JOIN CLIENTES_DADOS cd ON cd.ID_CLIENTE = c.ID_CLIENTE
            WHERE c.AN_INATIVO = 0 OR c.AN_INATIVO IS NULL
            ORDER BY c.ID_CLIENTE DESC";

        var rows = await _firebird.QueryAsync(sql, ct: ct);

        var customers = rows.Select(row => new SyncGarantiasCustomerDto(
            ErpId:     Convert.ToInt32(row["IDCLIENTE"] ?? 0),
            Nome:      row["NOME"]?.ToString()?.Trim() ?? "",
            Documento: row["DOCUMENTO"]?.ToString()?.Trim() ?? "",
            Telefone:  row["TELEFONE"]?.ToString()?.Trim() ?? "",
            Email:     row["EMAIL"]?.ToString()?.Trim() ?? ""
        )).ToList();

        _logger.LogInformation("[GarantiasCustomers] {Count} clientes lidos do Firebird.", customers.Count);
        return customers;
    }

    private async Task PushToApiAsync(List<SyncGarantiasCustomerDto> customers, CancellationToken ct)
    {
        var client = _httpClientFactory.CreateClient("GarantiasApiClient");
        var tenantId = _identityOpts.TenantId.ToString();

        // O Garantias API usa ITenantService com X-Tenant-Id header para identificar a qual empresa os dados pertencem.
        // O JWT_KEY da Garantias.API é para autenticação de front-end. O Worker usa X-Internal-Api-Key + X-Tenant-Id.
        if (!client.DefaultRequestHeaders.Contains("X-Tenant-Id"))
            client.DefaultRequestHeaders.Add("X-Tenant-Id", tenantId);

        const int batchSize = 500;
        int totalBatch = (int)Math.Ceiling(customers.Count / (double)batchSize);

        for (int i = 0; i < totalBatch; i++)
        {
            var batch = customers.Skip(i * batchSize).Take(batchSize).ToList();

            var response = await client.PostAsJsonAsync("/api/sync/clientes", batch, ct);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation(
                    "[GarantiasCustomers] Lote {N}/{T} enviado ({C} clientes).",
                    i + 1, totalBatch, batch.Count);
            }
            else
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                _logger.LogWarning(
                    "[GarantiasCustomers] Lote {N} falhou: HTTP {S} — {B}",
                    i + 1, (int)response.StatusCode, body[..Math.Min(200, body.Length)]);
            }
        }

        _status.AppendLog(
            $"[{DateTime.Now:HH:mm:ss}] 👥 [Garantias] {customers.Count} clientes → API");
        _status.Update("Garantias_Customers", customers.Count, DateTime.Now);
    }
}
