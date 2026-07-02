using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Services;

/// <summary>
/// Cliente HTTP para comunicação com a ColiseSpeed API (PDV Web Middleware).
/// </summary>
public sealed class ColiseSpeedApiClient
{
    private readonly HttpClient _http;
    private readonly ILogger<ColiseSpeedApiClient> _logger;
    
    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = false,
    };

    public ColiseSpeedApiClient(
        HttpClient http,
        ILogger<ColiseSpeedApiClient> logger)
    {
        _http = http;
        _logger = logger;
    }

    /// <summary>Envia catálogo para o Speed PDV</summary>
    public async Task<bool> PushCatalogAsync(IReadOnlyList<object> products, CancellationToken ct = default)
        => await PostAsync("/api/sync/catalog", new { products }, ct);

    /// <summary>Envia clientes para o Speed PDV</summary>
    public async Task<bool> PushCustomersAsync(IReadOnlyList<object> customers, CancellationToken ct = default)
        => await PostAsync("/api/sync/customers", new { customers }, ct);

    /// <summary>Envia vendedores/usuários para o Speed PDV</summary>
    public async Task<bool> PushSellersAsync(IReadOnlyList<object> sellers, CancellationToken ct = default)
        => await PostAsync("/api/sync/sellers", new { sellers }, ct);

    /// <summary>Envia naturezas de operação para o Speed PDV</summary>
    public async Task<bool> PushNaturezaAsync(IReadOnlyList<object> naturezas, CancellationToken ct = default)
        => await PostAsync("/api/sync/natureza", new { naturezas }, ct);

    private async Task<bool> PostAsync<T>(string url, T payload, CancellationToken ct)
    {
        try
        {
            var content = JsonContent.Create(payload, options: _jsonOpts);
            var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };

            var resp = await _http.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                var err = await resp.Content.ReadAsStringAsync(ct);
                _logger.LogWarning("[ColiseSpeed API] Falha em {Url}: {Status} - {Error}", url, resp.StatusCode, err);
                return false;
            }
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[ColiseSpeed API] Exceção em {Url}", url);
            return false;
        }
    }
}
