namespace ColiseuSales.Worker.Config;

/// <summary>
/// Opções de configuração para o módulo Controle de Garantias.
/// Mapeado da seção 'GarantiasApi' no appsettings.json ou via .env do Configurador.
/// </summary>
public sealed class GarantiasApiOptions
{
    public const string Section = "GarantiasApi";

    public bool Enabled { get; set; }
    public string BaseUrl { get; set; } = string.Empty;
    public string InternalApiKey { get; set; } = string.Empty;
    public int TimeoutSeconds { get; set; } = 30;
}
