namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Módulo ativo para uma empresa (tenant) no ecossistema Coliseu.
///
/// Cada módulo é um produto independente (ex: "coliseu-sales", "autocenter")
/// com sua própria API Key, limite de dispositivos e URL de middleware.
///
/// Rule-03 (Multi-Tenant): o isolamento se dá por (company_id + module_slug).
/// Rule-04 (Secrets): ApiKeyHash armazenado como SHA-256 — nunca em texto plano.
/// </summary>
public sealed class CompanyModule
{
    public Guid Id { get; private set; }
    public Guid CompanyId { get; private set; }

    /// <summary>Identificador do produto. Exemplos: "coliseu-sales", "autocenter".</summary>
    public string ModuleSlug { get; private set; } = null!;

    /// <summary>Hash SHA-256 da API Key do módulo (nunca armazenada em texto plano).</summary>
    public string ApiKeyHash { get; private set; } = null!;

    /// <summary>API Key do módulo criptografada via AES-256-GCM.</summary>
    public string? ApiKeyEncrypted { get; private set; }

    /// <summary>Limite de dispositivos simultâneos para este módulo nesta empresa.</summary>
    public int DeviceLimit { get; private set; }

    /// <summary>Indica se o módulo está ativo para a empresa.</summary>
    public bool IsActive { get; private set; }

    /// <summary>
    /// URL base do Middleware retornada ao app mobile após ativação.
    /// Ex: "https://licencas.coliseusistemas.com.br" ou "https://autocenter.coliseusistemas.com.br".
    /// </summary>
    public string? MiddlewareBaseUrl { get; private set; }

    /// <summary>Versões contratadas/disponibilizadas para o módulo (usado principalmente pelo coliseu-dash).</summary>
    public List<string> Versions { get; private set; } = new();

    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    // Navigation
    public Company Company { get; private set; } = null!;

    // EF Core needs parameterless constructor
    private CompanyModule() { }

    /// <summary>
    /// Registra um módulo para uma empresa.
    /// </summary>
    public static CompanyModule Create(
        Guid companyId,
        string moduleSlug,
        string apiKeyHash,
        int deviceLimit,
        string? middlewareBaseUrl = null,
        string? apiKeyEncrypted = null,
        List<string>? versions = null)
    {
        if (companyId == Guid.Empty)
            throw new ArgumentException("CompanyId é obrigatório.", nameof(companyId));
        if (string.IsNullOrWhiteSpace(moduleSlug))
            throw new ArgumentException("ModuleSlug é obrigatório.", nameof(moduleSlug));
        if (string.IsNullOrWhiteSpace(apiKeyHash))
            throw new ArgumentException("ApiKeyHash é obrigatório.", nameof(apiKeyHash));
        if (deviceLimit < 1)
            throw new ArgumentException("Limite de dispositivos deve ser pelo menos 1.", nameof(deviceLimit));

        return new CompanyModule
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            ModuleSlug = moduleSlug.Trim().ToLowerInvariant(),
            ApiKeyHash = apiKeyHash,
            ApiKeyEncrypted = apiKeyEncrypted,
            DeviceLimit = deviceLimit,
            IsActive = true,
            MiddlewareBaseUrl = middlewareBaseUrl?.Trim(),
            CreatedAt = DateTime.UtcNow,
            Versions = versions ?? new List<string>(),
        };
    }

    /// <summary>Ativa o módulo.</summary>
    public void Activate()
    {
        IsActive = true;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Desativa o módulo (dispositivos perdem acesso na renovação do JWT).</summary>
    public void Deactivate()
    {
        IsActive = false;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza o limite de dispositivos do módulo.</summary>
    public void SetDeviceLimit(int newLimit)
    {
        if (newLimit < 1)
            throw new ArgumentException("Limite deve ser pelo menos 1.", nameof(newLimit));
        DeviceLimit = newLimit;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza a URL do Middleware retornada ao app.</summary>
    public void SetMiddlewareUrl(string? url)
    {
        MiddlewareBaseUrl = url?.Trim();
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza as versões contratadas/disponíveis do módulo.</summary>
    public void SetVersions(List<string>? versions)
    {
        Versions = versions ?? new List<string>();
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Rotaciona a API Key do módulo.</summary>
    public void RotateApiKey(string newApiKeyHash, string? newApiKeyEncrypted = null)
    {
        if (string.IsNullOrWhiteSpace(newApiKeyHash))
            throw new ArgumentException("Hash da nova API Key é obrigatório.", nameof(newApiKeyHash));
        ApiKeyHash = newApiKeyHash;
        ApiKeyEncrypted = newApiKeyEncrypted;
        UpdatedAt = DateTime.UtcNow;
    }
}
