using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using ColiseuSales.Shared.Dtos;
using ColiseuSales.Worker.Config;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Services;

/// <summary>
/// Cliente HTTP para comunicação com a VPS API.
///
/// Responsabilidades:
/// - PUSH: enviar catálogo, vendedores, clientes, financeiros para a VPS
/// - PULL: buscar pedidos pendentes da VPS para processar no Firebird
/// - Retry automático via Polly (configurado no DI)
///
/// Rule-02 (Async): todas as chamadas HTTP são async.
/// Rule-04 (Secrets): API Key não é logada.
/// </summary>
public sealed class VpsApiClient
{
    private readonly HttpClient           _http;
    private readonly ILogger<VpsApiClient> _logger;
    private readonly string               _companyId;

    // Opções de serialização alinhadas com o Node.js middleware (camelCase)
    private static readonly JsonSerializerOptions _jsonOpts = new()
    {
        PropertyNamingPolicy        = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented               = false,
    };

    public VpsApiClient(
        HttpClient http,
        ILogger<VpsApiClient> logger,
        IOptions<VpsApiOptions> vpsOpts)
    {
        _http      = http;
        _logger    = logger;
        _companyId = vpsOpts.Value.CompanyId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PUSH — Worker → VPS (envio de dados do ERP)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Envia lista de produtos para a VPS (POST /api/sync/catalog).
    ///
    /// @param products  Lista de produtos mapeados do Firebird.
    /// @param branchId  UUID da filial (Identity) para isolar dados no Redis por filial.
    /// @returns true se aceito com sucesso pela VPS.
    /// </summary>
    public async Task<bool> PushCatalogAsync(
        IReadOnlyList<object> products,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/catalog", new { products }, branchId, ct);

    /// <summary>Envia lista de clientes para a VPS (POST /api/sync/customers).</summary>
    public async Task<bool> PushCustomersAsync(
        IReadOnlyList<object> customers,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/customers", new { customers }, branchId, ct);

    /// <summary>Envia lista de vendedores para a VPS (POST /api/sync/sellers).</summary>
    public async Task<bool> PushSellersAsync(
        IReadOnlyList<object> sellers,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/sellers", new { sellers }, branchId, ct);

    /// <summary>Envia lista de formas de pagamento para a VPS.</summary>
    public async Task<bool> PushPaymentSpeciesAsync(
        IReadOnlyList<object> species,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/payment-species", new { species }, branchId, ct);

    /// <summary>Envia lista de condições de pagamento para a VPS.</summary>
    public async Task<bool> PushPaymentConditionsAsync(
        IReadOnlyList<object> conditions,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/payment-conditions", new { conditions }, branchId, ct);

    /// <summary>Envia naturezas de operação para a VPS (filtradas por MOB_ACESSO='S').</summary>
    public async Task<bool> PushNaturezaAsync(
        IReadOnlyList<object> naturezas,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/natureza", new { naturezas }, branchId, ct);

    /// <summary>Envia títulos financeiros para a VPS.</summary>
    public async Task<bool> PushFinancialsAsync(
        IReadOnlyList<object> financials,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/financials", new { financials }, branchId, ct);

    /// <summary>Envia KPIs de desempenho (MINHASVENDAS) para a VPS.</summary>
    public async Task<bool> PushPerformanceAsync(
        IReadOnlyList<object> performance,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/performance", new { performance }, branchId, ct);

    /// <summary>Envia rankings de vendas (L_VENDAS_*) para a VPS.</summary>
    public async Task<bool> PushSalesRankingsAsync(
        IReadOnlyList<object> rankings,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/sales-rankings", new { rankings }, branchId, ct);

    /// <summary>Envia cabeçalhos das tabelas de preço para a VPS (POST /api/sync/price-tables).</summary>
    public async Task<bool> PushPriceTablesAsync(
        IReadOnlyList<object> tables,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/price-tables", new { tables }, branchId, ct);

    /// <summary>Envia dados da tabela EMPRESA para a VPS.</summary>
    public async Task<bool> PushCompanyDataAsync(
        IReadOnlyList<object> company,
        CancellationToken ct = default)
        => await PostAsync("/api/sync/company-data", new { company }, ct);

    /// <summary>
    /// Envia preços por produto x tabela para a VPS (POST /api/sync/product-prices).
    /// Baseado na procedure MOB_TABELAPRECO: PRECO = BASE + (BASE x PRECOT_P%).
    /// </summary>
    public async Task<bool> PushProductPricesAsync(
        IReadOnlyList<object> prices,
        Guid? branchId = null,
        CancellationToken ct = default)
        => await PostWithBranchAsync("/api/sync/product-prices", new { prices }, branchId, ct);

    // ─────────────────────────────────────────────────────────────────────────
    // PULL — VPS → Worker (busca pedidos para inserir no Firebird)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Busca pedidos pendentes na VPS (GET /api/orders/pending).
    ///
    /// Retorna uma lista de pedidos que ainda não foram processados
    /// no Firebird. Cada pedido será inserido via MOB_CADASTRAR_PEDIDO.
    /// </summary>
    public async Task<List<PendingOrderDto>> GetPendingOrdersAsync(CancellationToken ct = default)
    {
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, "/api/orders/pending");
            request.Headers.Add("X-Company-Id", _companyId);

            var response = await _http.SendAsync(request, ct);
            response.EnsureSuccessStatusCode();

            var result = await response.Content.ReadFromJsonAsync<PendingOrdersResponse>(_jsonOpts, ct);
            return result?.Orders ?? [];
        }
        catch (Exception ex)
        {
            _logger.LogError("[VpsApi] Erro ao buscar pedidos pendentes: {Error}", ex.Message);
            return [];
        }
    }

    /// <summary>
    /// Confirma que um pedido foi processado com sucesso no Firebird.
    /// Isso marca o pedido como "synced" na VPS.
    /// </summary>
    public async Task<bool> ConfirmOrderAsync(string orderId, int erpOrderId, CancellationToken ct = default)
        => await PostAsync($"/api/orders/{orderId}/confirm", new { erpOrderId = erpOrderId.ToString() }, ct);

    /// <summary>
    /// Reporta falha ao processar um pedido (para retry pela VPS).
    /// </summary>
    public async Task<bool> ReportOrderErrorAsync(string orderId, string errorMessage, CancellationToken ct = default)
        => await PostAsync($"/api/orders/{orderId}/error", new { errorMessage }, ct);

    // ─────────────────────────────────────────────────────────────────────────
    // PULL — VPS → Worker (busca clientes pendentes para cadastrar no ERP)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Busca clientes pendentes de cadastro no ERP (GET /api/sync/pending-customers).
    /// </summary>
    public async Task<List<Dictionary<string, object?>>> GetPendingCustomersAsync(CancellationToken ct = default)
    {
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, "/api/sync/pending-customers");
            request.Headers.Add("X-Company-Id", _companyId);

            var response = await _http.SendAsync(request, ct);
            response.EnsureSuccessStatusCode();

            var json = await response.Content.ReadAsStringAsync(ct);
            var doc = System.Text.Json.JsonDocument.Parse(json);
            var customers = new List<Dictionary<string, object?>>();

            if (doc.RootElement.TryGetProperty("customers", out var arr))
            {
                foreach (var item in arr.EnumerateArray())
                {
                    var dict = new Dictionary<string, object?>();
                    foreach (var prop in item.EnumerateObject())
                    {
                        dict[prop.Name] = prop.Value.ValueKind switch
                        {
                            System.Text.Json.JsonValueKind.String => prop.Value.GetString(),
                            System.Text.Json.JsonValueKind.Number => prop.Value.GetDecimal(),
                            System.Text.Json.JsonValueKind.True   => true,
                            System.Text.Json.JsonValueKind.False  => false,
                            System.Text.Json.JsonValueKind.Null   => null,
                            _ => prop.Value.ToString()
                        };
                    }
                    customers.Add(dict);
                }
            }

            return customers;
        }
        catch (Exception ex)
        {
            _logger.LogError("[VpsApi] Erro ao buscar clientes pendentes: {Error}", ex.Message);
            return [];
        }
    }

    /// <summary>Confirma que um cliente foi cadastrado no ERP.</summary>
    public async Task<bool> ConfirmCustomerAsync(string pendingId, string erpCustomerId, CancellationToken ct = default)
        => await PostAsync($"/api/sync/confirm-customer/{pendingId}", new { erpCustomerId }, ct);

    /// <summary>
    /// Resolve um ID local de cliente (prefixo "local_") para o ID numérico do ERP.
    /// Retorna null se o cliente ainda não foi confirmado no Firebird.
    /// </summary>
    public async Task<string?> ResolveLocalCustomerAsync(string localId, CancellationToken ct = default)
    {
        try
        {
            var request = new HttpRequestMessage(
                HttpMethod.Get,
                $"/api/sync/resolve-local-customer?localId={Uri.EscapeDataString(localId)}");
            request.Headers.Add("X-Company-Id", _companyId);

            var response = await _http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode) return null;

            var json = await response.Content.ReadAsStringAsync(ct);
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.TryGetProperty("found", out var found) && found.GetBoolean()
                && root.TryGetProperty("erpCustomerId", out var erpId)
                && erpId.ValueKind == System.Text.Json.JsonValueKind.String)
            {
                return erpId.GetString();
            }
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[VpsApi] Falha ao resolver cliente local {LocalId}: {Error}", localId, ex.Message);
            return null;
        }
    }

    /// <summary>Reporta erro no cadastro de um cliente.</summary>
    public async Task<bool> ReportCustomerErrorAsync(string pendingId, string errorMessage, CancellationToken ct = default)
        => await PostAsync($"/api/sync/error-customer/{pendingId}", new { errorMessage }, ct);

    // ─────────────────────────────────────────────────────────────────────────
    // Health Check
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>Verifica se a VPS está acessível.</summary>
    public async Task<bool> IsAvailableAsync(CancellationToken ct = default)
    {
        try
        {
            var response = await _http.GetAsync("/health", ct);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers privados
    // ─────────────────────────────────────────────────────────────────────────

    private async Task<bool> PostAsync(string path, object payload, CancellationToken ct)
        => await PostWithBranchAsync(path, payload, null, ct);

    /// <summary>
    /// Envia POST com suporte opcional a X-Branch-Id para isolar dados por filial no Redis.
    /// [FIX] Sem o branchId, todos os tenants compartilham a mesma chave Redis.
    /// </summary>
    private async Task<bool> PostWithBranchAsync(string path, object payload, Guid? branchId, CancellationToken ct)
    {
        try
        {
            var json     = JsonSerializer.Serialize(payload, _jsonOpts);
            var content  = new StringContent(json, Encoding.UTF8, "application/json");

            var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = content };
            request.Headers.Add("X-Company-Id", _companyId);

            // [FIX] Inclui X-Branch-Id para que o middleware salve na chave Redis correta da filial
            if (branchId.HasValue)
            {
                request.Headers.Add("X-Branch-Id", branchId.Value.ToString());
            }

            var response = await _http.SendAsync(request, ct);

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                var snippet = body.Length > 200 ? body[..200] : body;
                // Lança para que o caller possa logar o status HTTP real no SSE
                throw new HttpRequestException(
                    $"HTTP {(int)response.StatusCode} {response.StatusCode} — {snippet}");
            }

            return true;
        }
        catch (HttpRequestException)
        {
            throw; // re-propaga para SyncCatalogJob logar no SSE
        }
        catch (TaskCanceledException)
        {
            throw new HttpRequestException("Timeout ao conectar na VPS");
        }
        catch (Exception ex)
        {
            throw new HttpRequestException($"Erro de rede: {ex.Message}");
        }
    }
}
