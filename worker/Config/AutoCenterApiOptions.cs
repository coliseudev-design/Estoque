namespace ColiseuSpeed.Worker.Config;

/// <summary>
/// Mapeia a seção "AutoCenterApi" do appsettings.json.
/// Armazena credenciais e rotas para comunicação com o Middleware do AutoCenter.
/// </summary>
public class AutoCenterApiOptions
{
    public const string Section = "AutoCenterApi";

    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 30;
    public bool Enabled { get; set; } = false;
    public string? BranchId { get; set; }
}

