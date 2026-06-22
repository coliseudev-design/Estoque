using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using ColiseuSales.Shared.Dtos;
using ColiseuSales.Worker.Config;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Services;

/// <summary>
/// Cliente HTTP para comunicação com o backend do Atendente do Futuro.
///
/// Espelha a API do VpsApiClient, mas com endpoints adaptados (/api/sync/*).
/// Só ativado quando AtendenteApi:Enabled = true no appsettings.json.
///
/// Responsabilidades:
/// - PUSH: enviar catálogo, vendedores, clientes para o backend Atendente
/// - PULL: buscar pedidos do WhatsApp para processar no Firebird
///
/// Rule-02 (Async): todas as chamadas HTTP são async.
/// Rule-04 (Secrets): API Key não é logada.
/// </summary>
public sealed class AtendenteApiClient
{
    private readonly HttpClient                   _http;
    private readonly ILogger<AtendenteApiClient>   _logger;
    private readonly AtendenteApiOptions           _opts;

    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNamingPolicy        = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented               = false,
    };

    public AtendenteApiClient(
        HttpClient http,
        ILogger<AtendenteApiClient> logger,
        IOptions<AtendenteApiOptions> opts)
    {
        _http   = http;
        _logger = logger;
        _opts   = opts.Value;
    }

    /// <summary>Se false, todas as chamadas retornam imediatamente sem fazer nada.</summary>
    public bool IsEnabled => _opts.Enabled
                             && !string.IsNullOrWhiteSpace(_opts.BaseUrl);

    // ─────────────────────────────────────────────────────────────────────────
    // PUSH — Worker → Atendente do Futuro (envio de dados do ERP)
    // ─────────────────────────────────────────────────────────────────────────

    public async Task<bool> PushCatalogAsync(IReadOnlyList<object> products, CancellationToken ct = default)
        => await PostAsync("/api/sync/catalog", new { products }, ct);

    public async Task<bool> PushCustomersAsync(IReadOnlyList<object> customers, CancellationToken ct = default)
        => await PostAsync("/api/sync/customers", new { customers }, ct);

    public async Task<bool> PushSellersAsync(IReadOnlyList<object> sellers, CancellationToken ct = default)
        => await PostAsync("/api/sync/sellers", new { sellers }, ct);

    public async Task<bool> PushPaymentSpeciesAsync(IReadOnlyList<object> species, CancellationToken ct = default)
        => await PostAsync("/api/sync/payment-species", new { species }, ct);

    public async Task<bool> PushPaymentConditionsAsync(IReadOnlyList<object> conditions, CancellationToken ct = default)
        => await PostAsync("/api/sync/payment-conditions", new { conditions }, ct);

    public async Task<bool> PushNaturezaAsync(IReadOnlyList<object> naturezas, CancellationToken ct = default)
        => await PostAsync("/api/sync/natureza", new { naturezas }, ct);

    public async Task<bool> PushFinancialsAsync(IReadOnlyList<object> financials, CancellationToken ct = default)
        => await PostAsync("/api/sync/financials", new { financials }, ct);

    public async Task<bool> PushPriceTablesAsync(IReadOnlyList<object> tables, CancellationToken ct = default)
        => await PostAsync("/api/sync/price-tables", new { tables }, ct);


    public async Task<bool> PushProductPricesAsync(IReadOnlyList<object> prices, CancellationToken ct = default)
        => await PostAsync("/api/sync/product-prices", new { prices }, ct);

    // ─────────────────────────────────────────────────────────────────────────
    // PULL — Atendente do Futuro → Worker (pedidos do WhatsApp)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>Busca pedidos WhatsApp pendentes no backend.</summary>
    public async Task<List<PendingOrderDto>> GetPendingOrdersAsync(CancellationToken ct = default)
    {
        if (!IsEnabled) return [];

        try
        {
            var response = await _http.GetAsync("/api/sync/orders/pending", ct);
            response.EnsureSuccessStatusCode();

            var result = await response.Content.ReadFromJsonAsync<PendingOrdersResponse>(_jsonOpts, ct);
            return result?.Orders ?? [];
        }
        catch (Exception ex)
        {
            _logger.LogError("[AtendenteApi] Erro ao buscar pedidos WhatsApp: {Error}", ex.Message);
            return [];
        }
    }

    /// <summary>Confirma inserção do pedido no Firebird.</summary>
    public async Task<bool> ConfirmOrderAsync(string orderId, int erpOrderId, CancellationToken ct = default)
        => await PostAsync($"/api/sync/orders/{orderId}/confirm", new { erpOrderId = erpOrderId.ToString() }, ct);

    /// <summary>Reporta erro na inserção do pedido.</summary>
    public async Task<bool> ReportOrderErrorAsync(string orderId, string errorMessage, CancellationToken ct = default)
        => await PostAsync($"/api/sync/orders/{orderId}/error", new { errorMessage }, ct);

    // ─────────────────────────────────────────────────────────────────────────
    // Health Check
    // ─────────────────────────────────────────────────────────────────────────

    public async Task<bool> IsAvailableAsync(CancellationToken ct = default)
    {
        if (!IsEnabled) return false;
        try
        {
            var response = await _http.GetAsync("/api/health", ct);
            return response.IsSuccessStatusCode;
        }
        catch { return false; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers privados
    // ─────────────────────────────────────────────────────────────────────────

    private async Task<bool> PostAsync(string path, object payload, CancellationToken ct)
    {
        if (!IsEnabled) return true; // noop when disabled

        try
        {
            var json    = JsonSerializer.Serialize(payload, _jsonOpts);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = content };

            var response = await _http.SendAsync(request, ct);

            if (!response.IsSuccessStatusCode)
            {
                var body    = await response.Content.ReadAsStringAsync(ct);
                var snippet = body.Length > 200 ? body[..200] : body;
                _logger.LogWarning(
                    "[AtendenteApi] HTTP {Status} em {Path}: {Body}",
                    (int)response.StatusCode, path, snippet);
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            // Falhas do Atendente não devem derrubar o sync do Coliseu Sales
            _logger.LogWarning("[AtendenteApi] Erro em {Path}: {Error}", path, ex.Message);
            return false;
        }
    }
}
