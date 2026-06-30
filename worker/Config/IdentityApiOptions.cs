namespace ColiseuSpeed.Worker.Config;

/// <summary>
/// Configuração de conexão com a API Central de Identidade.
/// Usada para buscar credenciais dinamicamente.
/// </summary>
public sealed class IdentityApiOptions
{
    public const string Section = "IdentityApi";

    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public Guid   TenantId { get; set; }
}
