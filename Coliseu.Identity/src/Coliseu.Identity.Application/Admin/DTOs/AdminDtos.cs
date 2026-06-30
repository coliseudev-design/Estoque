namespace Coliseu.Identity.Application.Admin.DTOs;

/// <summary>Request para login de administrador.</summary>
public sealed class AdminLoginRequest
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;

    public AdminLoginRequest() { }
    public AdminLoginRequest(string email, string password) { Email = email; Password = password; }
}

/// <summary>Response de login de administrador.</summary>
public sealed record AdminLoginResponse(
    string? AccessToken,
    string? RefreshToken,
    int ExpiresInSeconds,
    string Email,
    string? Name,
    string Role,
    bool RequiresTwoFactor = false);

/// <summary>Request para verificar código TOTP no segundo fator.</summary>
public sealed class TotpVerifyRequest
{
    public string Email    { get; set; } = string.Empty;
    public string TotpCode { get; set; } = string.Empty;
}

/// <summary>Request para iniciar o setup de 2FA (envia QR Code e valida o primeiro código).</summary>
public sealed class TotpSetupRequest
{
    public string Email    { get; set; } = string.Empty;
    public string TotpCode { get; set; } = string.Empty;
}

/// <summary>Response do setup de 2FA — contém a URI otpauth:// para exibir o QR Code.</summary>
public sealed record TotpSetupResponse(
    string OtpAuthUri,
    bool IsVerified,
    string Message);

public sealed class CreateCompanyBranchRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Cnpj { get; set; }
    public int ErpEmpresaId { get; set; }
    public int ErpDeptoPadrao { get; set; }
    public int ErpCentroPadrao { get; set; }
    public bool IsDefault { get; set; }
}

/// <summary>Request para criação de empresa.</summary>
public sealed class CreateCompanyRequest
{
    public string Name { get; set; } = string.Empty;
    public string? ContactEmail { get; set; }
    public int DeviceLimit { get; set; } = 5;
    public string FirebirdHost { get; set; } = "localhost";
    public string FirebirdDatabasePath { get; set; } = string.Empty;
    public string FirebirdUser { get; set; } = "SYSDBA";
    public string FirebirdPassword { get; set; } = "masterkey";
    public List<CreateCompanyBranchRequest> Branches { get; set; } = new();

    public CreateCompanyRequest() { }
    public CreateCompanyRequest(string name, int deviceLimit, string firebirdHost, string firebirdDatabasePath, string firebirdUser, string firebirdPassword, string? contactEmail = null)
    {
        Name = name;
        ContactEmail = contactEmail;
        DeviceLimit = deviceLimit;
        FirebirdHost = firebirdHost;
        FirebirdDatabasePath = firebirdDatabasePath;
        FirebirdUser = firebirdUser;
        FirebirdPassword = firebirdPassword;
    }
}

/// <summary>Response de criação de empresa — inclui CompanyKey em texto (exibido UMA vez).</summary>
public sealed record CreateCompanyResponse(
    Guid CompanyId,
    string CompanyName,
    string? ContactEmail,
    string CompanyKey,
    int DeviceLimit);

/// <summary>DTO para listagem de empresas.</summary>
public sealed record CompanyDto(
    Guid Id,
    string Name,
    string? ContactEmail,
    string Status,
    int DeviceLimit,
    int ActiveDevices,
    DateTime CreatedAt,
    bool HasLogo = false,
    string PriceTableMode = "none",
    bool AllowNegativeStock = false,
    string? CompanyKey = null);

/// <summary>DTO para listagem de dispositivos.</summary>
public sealed record DeviceDto(
    Guid Id,
    string ActivationKey,
    string? DeviceUuid,
    string? Name,
    string? Model,
    string? OS,
    string? AppVersion,
    string Status,
    DateTime FirstActivation,
    DateTime LastAccess);

/// <summary>Request para criação de dispositivo pendente via painel admin.</summary>
public sealed class CreateDeviceRequest
{
    public Guid CompanyId { get; set; }
    public string ActivationKey { get; set; } = string.Empty;
}

/// <summary>DTO para logs de auditoria.</summary>
public sealed record AuditLogDto(
    Guid Id,
    string Action,
    Guid? CompanyId,
    Guid? DeviceId,
    string? IpAddress,
    string? Details,
    DateTime CreatedAt,
    string? AdminEmail = null);

/// <summary>Request para alterar status de empresa.</summary>
public sealed record UpdateCompanyStatusRequest(string Status);

/// <summary>Request para alterar status de dispositivo.</summary>
public sealed record UpdateDeviceStatusRequest(string Status);

/// <summary>Request para atualizar credenciais Firebird.</summary>
public sealed record UpdateFirebirdRequest(
    string Host,
    string DatabasePath,
    string User,
    string Password);

/// <summary>Request para atualizar dados gerais da empresa (nome, email, limite, status).</summary>
public sealed class UpdateCompanyRequest
{
    public string Name { get; set; } = string.Empty;
    public string? ContactEmail { get; set; }
    public int DeviceLimit { get; set; } = 1;
    public string? Status { get; set; }
    /// <summary>Modo de tabela de preços: "none" | "product" | "prompt"</summary>
    public string? PriceTableMode { get; set; }
    /// <summary>Permite venda com estoque zero/negativo no App Mobile.</summary>
    public bool? AllowNegativeStock { get; set; }
}

/// <summary>Request para upload de logo da empresa (Base64-encoded PNG/JPG, max 500KB).</summary>
public sealed class UpdateLogoRequest
{
    public string LogoBase64 { get; set; } = string.Empty;
}

/// <summary>
/// Response de rotação de CompanyKey — inclui a nova chave em texto (exibida UMA vez).
/// A chave é usada como API Key no app mobile e no Worker Configurator.
/// </summary>
public sealed record RotateKeyResponse(
    Guid CompanyId,
    string CompanyName,
    string NewCompanyKey);

// ── Module DTOs ──────────────────────────────────────────────────────────────

/// <summary>DTO para exibição de módulo ativo por empresa.</summary>
public sealed record CompanyModuleDto(
    Guid Id,
    Guid CompanyId,
    string ModuleSlug,
    int DeviceLimit,
    bool IsActive,
    string? MiddlewareBaseUrl,
    DateTime CreatedAt,
    string? ApiKey = null,
    List<string>? Versions = null);

/// <summary>Request para adicionar um módulo a uma empresa.</summary>
public sealed class AddModuleRequest
{
    /// <summary>Slug do módulo. Ex: "coliseu-speed" | "autocenter"</summary>
    public string ModuleSlug { get; set; } = string.Empty;
    public int DeviceLimit { get; set; } = 5;
    public string? MiddlewareBaseUrl { get; set; }
    public List<string>? Versions { get; set; }
}

/// <summary>Response de criação de módulo — inclui a API Key em texto (exibida UMA vez).</summary>
public sealed record AddModuleResponse(
    Guid ModuleId,
    Guid CompanyId,
    string ModuleSlug,
    string ApiKey,         // ← Exibida uma única vez
    int DeviceLimit,
    string? MiddlewareBaseUrl,
    List<string>? Versions = null);

/// <summary>Request para atualizar configurações de um módulo.</summary>
public sealed class UpdateModuleRequest
{
    public string? ModuleSlug { get; set; }
    public int? DeviceLimit { get; set; }
    public string? MiddlewareBaseUrl { get; set; }
    public bool? IsActive { get; set; }
    public List<string>? Versions { get; set; }
}

/// <summary>Response de rotação de API Key do módulo (exibida UMA vez).</summary>
public sealed record RotateModuleKeyResponse(
    Guid ModuleId,
    string ModuleSlug,
    string NewApiKey);   // ← Exibida uma única vez

/// <summary>Request para atualizar o nome/apelido do dispositivo.</summary>
public sealed class UpdateDeviceNameRequest
{
    public string? Name { get; set; }
}

// ── Partner & Request DTOs ──────────────────────────────────────────────────

public sealed class CreatePartnerRequest
{
    public string Name { get; set; } = string.Empty;
    public string Cnpj { get; set; } = string.Empty;
    public string ContactName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
}

public sealed record PartnerDto(
    Guid Id,
    string Name,
    string Cnpj,
    string ContactName,
    string Email,
    string Phone,
    DateTime CreatedAt,
    DateTime? UpdatedAt);

public sealed class RequestModuleDto
{
    public string ModuleSlug { get; set; } = string.Empty;
    public int DeviceLimit { get; set; } = 1;
}

public sealed class CreateLicenseRequest
{
    public Guid PartnerId { get; set; }
    public string CompanyName { get; set; } = string.Empty;
    public string ClientCnpj { get; set; } = string.Empty;
    public string ClientCompanyType { get; set; } = "Empresa Individual"; // Empresa Individual | MultiEmpresa
    public string? CostCenterCode { get; set; }
    public string? DeptCode { get; set; }
    public string PriceTableMode { get; set; } = "none";
    public bool AllowNegativeStock { get; set; }
    public string FirebirdHost { get; set; } = "localhost";
    public string FirebirdDatabasePath { get; set; } = string.Empty;
    public string FirebirdUser { get; set; } = "SYSDBA";
    public string FirebirdPassword { get; set; } = "masterkey";
    public string? Notes { get; set; }
    public List<RequestModuleDto> Modules { get; set; } = new();
    public string? BranchesJson { get; set; }
}

public sealed class LicenseRequestModuleDto
{
    public Guid Id { get; set; }
    public string ModuleSlug { get; set; } = string.Empty;
    public int DeviceLimit { get; set; }
}

public sealed record LicenseRequestDto(
    Guid Id,
    Guid PartnerId,
    string PartnerName,
    string CompanyName,
    string ClientCnpj,
    string ClientCompanyType,
    string? CostCenterCode,
    string? DeptCode,
    string PriceTableMode,
    bool AllowNegativeStock,
    string FirebirdHost,
    string FirebirdDatabasePath,
    string FirebirdUser,
    string? Notes,
    string Status,
    Guid? RequestedByAdminId,
    string? RequestorEmail,
    DateTime RequestedAt,
    Guid? ReviewedByAdminId,
    string? ReviewerEmail,
    DateTime? ReviewedAt,
    string? RejectReason,
    string? BranchesJson,
    Guid? CompanyId,
    List<LicenseRequestModuleDto> Modules);

public sealed class ApproveRequestReview
{
    public string? ReviewNotes { get; set; }
}

public sealed class RejectRequestReview
{
    public string ReviewNotes { get; set; } = string.Empty;
}

