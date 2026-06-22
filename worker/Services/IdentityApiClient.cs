using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace ColiseuSales.Worker.Services;

/// <summary>
/// Cliente HTTP para a comunicação com a API de Identidade (Coliseu.Identity).
/// Usado primariamente para buscar as credenciais do Firebird de forma segura (Rule-04).
/// </summary>
public sealed class IdentityApiClient
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<IdentityApiClient> _logger;
    private readonly StatusStore _status;

    public IdentityApiClient(HttpClient httpClient, ILogger<IdentityApiClient> logger, StatusStore status)
    {
        _httpClient = httpClient;
        _logger = logger;
        _status = status;
    }

    /// <summary>
    /// Busca as configurações e credenciais do banco Firebird do tenant atual.
    /// </summary>
    public async Task<FirebirdConfigResponse?> GetFirebirdConfigAsync(Guid tenantId, CancellationToken ct = default)
    {
        try
        {
            var response = await _httpClient.GetAsync($"/internal/companies/{tenantId}/firebird-config", ct);
            
            if (!response.IsSuccessStatusCode)
            {
                var error = await response.Content.ReadAsStringAsync(ct);
                _logger.LogError("[IdentityApi] Falha ao buscar credenciais para o tenant {TenantId}. Status: {StatusCode}. {Error}", 
                    tenantId, response.StatusCode, error);
                return null;
            }

            return await response.Content.ReadFromJsonAsync<FirebirdConfigResponse>(cancellationToken: ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[IdentityApi] Erro de comunicação ao buscar credenciais do tenant {TenantId}.", tenantId);
            return null;
        }
    }

    /// <summary>
    /// Busca a lista de filiais da empresa para enriquecer a integração com ERP.
    /// </summary>
    public async Task<List<BranchDto>> GetBranchesAsync(Guid tenantId, CancellationToken ct = default)
    {
        try
        {
            var response = await _httpClient.GetAsync($"/internal/companies/{tenantId}/branches", ct);
            if (!response.IsSuccessStatusCode)
            {
                var error = await response.Content.ReadAsStringAsync(ct);
                var statusCode = (int)response.StatusCode;
                _logger.LogError("[IdentityApi] Falha ao buscar filiais. Status: {StatusCode}. {Error}", response.StatusCode, error);
                
                // Exibe erro no log da interface para o cliente saber o que ocorreu
                if (statusCode != 404) // 404 significa apenas que n├úo h├í registro, mas outros erros devem ser alertados
                {
                    _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠️ [IdentityApi] Erro HTTP {statusCode} ao buscar filiais: {error}");
                }
                
                return [];
            }
            return await response.Content.ReadFromJsonAsync<List<BranchDto>>(cancellationToken: ct) ?? [];
        }
        catch (TaskCanceledException)
        {
            _logger.LogWarning("[IdentityApi] Timeout ao buscar filiais do tenant {TenantId}.", tenantId);
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠️ [IdentityApi] Timeout de conexão ao buscar filiais.");
            return [];
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[IdentityApi] Erro ao buscar filiais do tenant {TenantId}.", tenantId);
            _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠️ [IdentityApi] Falha de comunicação: {ex.Message}");
            return [];
        }
    }
}

public sealed class FirebirdConfigResponse
{
    [JsonPropertyName("host")]
    public string Host { get; set; } = string.Empty;
    
    [JsonPropertyName("database")]
    public string Database { get; set; } = string.Empty;
    
    [JsonPropertyName("user")]
    public string User { get; set; } = string.Empty;
    
    [JsonPropertyName("password")]
    public string Password { get; set; } = string.Empty;
}

public sealed record BranchDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("cnpj")] string? Cnpj,
    [property: JsonPropertyName("erpEmpresaId")] int ErpEmpresaId,
    [property: JsonPropertyName("erpDeptoPadrao")] int ErpDeptoPadrao,
    [property: JsonPropertyName("erpCentroPadrao")] int ErpCentroPadrao,
    [property: JsonPropertyName("isDefault")] bool IsDefault
);
