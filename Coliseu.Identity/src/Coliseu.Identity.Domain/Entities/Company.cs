using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Empresa (tenant) registrada no ecossistema Coliseu.
///
/// Cada Company possui seu próprio banco Firebird no ERP local.
/// As credenciais Firebird são armazenadas criptografadas (AES-256-GCM).
/// A CompanyKey é armazenada como SHA-256 — nunca em texto plano.
///
/// Rule-03 (Multi-Tenant): company_id é a fronteira de isolamento.
/// Rule-04 (Secrets): FirebirdPasswordEncrypted cifrado em repouso.
/// </summary>
public sealed class Company
{
    public Guid Id { get; private set; }
    public string Name { get; private set; } = null!;
    public string? ContactEmail { get; private set; }
    public string CompanyKeyHash { get; private set; } = null!;
    public string FirebirdHost { get; private set; } = null!;
    public string FirebirdDatabasePath { get; private set; } = null!;
    public string FirebirdUser { get; private set; } = null!;
    public string FirebirdPasswordEncrypted { get; private set; } = null!;
    public string? CompanyKeyEncrypted { get; private set; }
    public int DeviceLimit { get; private set; }
    public CompanyStatus Status { get; private set; }
    public string? LogoBase64 { get; private set; }
    /// <summary>Controla como a tabela de preços é aplicada no App Mobile.</summary>
    /// <remarks>
    /// Valores permitidos:
    ///   "none"    — Preço base sempre, tabelas ignoradas
    ///   "product" — Tabela vinculada ao cliente é usada automaticamente
    ///   "prompt"  — Vendedor escolhe a tabela manualmente ao criar o pedido
    /// </remarks>
    public string PriceTableMode { get; private set; } = "none";

    /// <summary>
    /// Permite que o App Mobile venda produtos com estoque zero ou negativo.
    /// Quando false (padrão), o app bloqueia visualmente e impede adição ao carrinho.
    /// Quando true, exibe badge de aviso mas mantém o produto selecionável.
    /// </summary>
    public bool AllowNegativeStock { get; private set; } = false;
    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    // Navigation
    private readonly List<Device> _devices = new();
    public IReadOnlyCollection<Device> Devices => _devices.AsReadOnly();

    private readonly List<Branch> _branches = new();
    public IReadOnlyCollection<Branch> Branches => _branches.AsReadOnly();

    // EF Core needs parameterless constructor
    private Company() { }

    /// <summary>
    /// Cria uma nova empresa no ecossistema Coliseu.
    /// </summary>
    /// <param name="name">Nome da empresa.</param>
    /// <param name="companyKeyHash">Hash SHA-256 da CompanyKey (COL-XXXX-XXXX-XXXX).</param>
    /// <param name="firebirdHost">Host do servidor Firebird.</param>
    /// <param name="firebirdDatabasePath">Caminho do arquivo .FDB no servidor.</param>
    /// <param name="firebirdUser">Usuário do Firebird.</param>
    /// <param name="firebirdPasswordEncrypted">Senha do Firebird criptografada via AES-256-GCM.</param>
    /// <param name="deviceLimit">Limite de dispositivos simultâneos.</param>
    /// <param name="companyKeyEncrypted">API Key (CompanyKey) original, criptografada via AES-256-GCM.</param>
    public static Company Create(
        string name,
        string companyKeyHash,
        string firebirdHost,
        string firebirdDatabasePath,
        string firebirdUser,
        string firebirdPasswordEncrypted,
        int deviceLimit,
        string? contactEmail = null,
        string? companyKeyEncrypted = null)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome da empresa é obrigatório.", nameof(name));
        if (string.IsNullOrWhiteSpace(companyKeyHash))
            throw new ArgumentException("Hash da CompanyKey é obrigatório.", nameof(companyKeyHash));
        if (deviceLimit < 1)
            throw new ArgumentException("Limite de dispositivos deve ser pelo menos 1.", nameof(deviceLimit));

        return new Company
        {
            Id = Guid.NewGuid(),
            Name = name.Trim(),
            ContactEmail = contactEmail?.Trim(),
            CompanyKeyHash = companyKeyHash,
            FirebirdHost = firebirdHost.Trim(),
            FirebirdDatabasePath = firebirdDatabasePath.Trim(),
            FirebirdUser = firebirdUser.Trim(),
            FirebirdPasswordEncrypted = firebirdPasswordEncrypted,
            DeviceLimit = deviceLimit,
            Status = CompanyStatus.Active,
            CompanyKeyEncrypted = companyKeyEncrypted,
            CreatedAt = DateTime.UtcNow,
        };
    }

    /// <summary>Suspende a empresa — todos os dispositivos perdem acesso.</summary>
    public void Suspend()
    {
        Status = CompanyStatus.Suspended;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Bloqueia permanentemente a empresa.</summary>
    public void Block()
    {
        Status = CompanyStatus.Blocked;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Reativa a empresa.</summary>
    public void Activate()
    {
        Status = CompanyStatus.Active;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza o limite de dispositivos.</summary>
    public void SetDeviceLimit(int newLimit)
    {
        if (newLimit < 1)
            throw new ArgumentException("Limite deve ser pelo menos 1.", nameof(newLimit));
        DeviceLimit = newLimit;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza dados gerais da empresa (nome, email, limite de dispositivos).</summary>
    public void UpdateDetails(string name, string? contactEmail, int deviceLimit)
    {
        if (!string.IsNullOrWhiteSpace(name))
            Name = name.Trim();
        ContactEmail = contactEmail?.Trim();
        if (deviceLimit >= 1)
            DeviceLimit = deviceLimit;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza as credenciais Firebird (senha criptografada).</summary>
    public void UpdateFirebirdCredentials(
        string host, string databasePath, string user, string passwordEncrypted)
    {
        FirebirdHost = host.Trim();
        FirebirdDatabasePath = databasePath.Trim();
        FirebirdUser = user.Trim();
        FirebirdPasswordEncrypted = passwordEncrypted;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Verifica se a empresa está operacional.</summary>
    public bool IsOperational => Status == CompanyStatus.Active;

    /// <summary>
    /// Atualiza a logo da empresa (Base64-encoded PNG/JPG).
    /// Limite de ~500KB de imagem raw (~670KB em Base64).
    /// </summary>
    /// <param name="logoBase64">String Base64 da imagem (com ou sem prefixo data:image/...).</param>
    public void UpdateLogo(string logoBase64)
    {
        if (string.IsNullOrWhiteSpace(logoBase64))
            throw new ArgumentException("Logo não pode estar vazia.", nameof(logoBase64));
        if (logoBase64.Length > 700_000)
            throw new ArgumentException("Logo excede o limite de 500KB.", nameof(logoBase64));
        LogoBase64 = logoBase64;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Remove a logo da empresa.</summary>
    public void RemoveLogo()
    {
        LogoBase64 = null;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>
    /// Define o modo de aplicação da tabela de preços no App Mobile.
    /// </summary>
    /// <param name="mode">"none" | "product" | "prompt"</param>
    public void SetPriceTableMode(string mode)
    {
        var allowed = new[] { "none", "product", "prompt" };
        if (!allowed.Contains(mode.Trim().ToLower()))
            throw new ArgumentException(
                $"Modo de tabela de preço inválido: '{mode}'. Valores: {string.Join(", ", allowed)}",
                nameof(mode));
        PriceTableMode = mode.Trim().ToLower();
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>
    /// Define se a empresa permite venda com estoque zero ou negativo no App Mobile.
    /// </summary>
    /// <param name="allow">true = venda liberada sem estoque; false = venda bloqueada (padrão).</param>
    public void SetAllowNegativeStock(bool allow)
    {
        AllowNegativeStock = allow;
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>
    /// Re-gera a CompanyKey substituindo o hash e a chave criptografada.
    /// </summary>
    /// <param name="newKeyHash">Novo hash SHA-256 da CompanyKey re-gerada.</param>
    /// <param name="newKeyEncrypted">Nova chave criptografada em AES-256-GCM.</param>
    public void RotateCompanyKey(string newKeyHash, string? newKeyEncrypted = null)
    {
        if (string.IsNullOrWhiteSpace(newKeyHash))
            throw new ArgumentException("Hash da nova CompanyKey é obrigatório.", nameof(newKeyHash));
        CompanyKeyHash = newKeyHash;
        CompanyKeyEncrypted = newKeyEncrypted;
        UpdatedAt = DateTime.UtcNow;
    }


    /// <summary>Verifica se o limite de dispositivos foi atingido.</summary>
    public bool IsDeviceLimitReached => _devices.Count(d => d.Status == DeviceStatus.Active) >= DeviceLimit;
}
