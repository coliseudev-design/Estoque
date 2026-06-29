namespace ColiseuSales.Worker.Config;

/// <summary>
/// Configurações de conexão com a ColiseSpeed API.
/// Lidas de appsettings.json > seção "ColiseSpeedApi".
/// </summary>
public sealed class ColiseSpeedApiOptions
{
    public const string Section = "ColiseSpeedApi";

    /// <summary>Habilita a sincronização com o módulo ColiseSpeed.</summary>
    public bool Enabled { get; set; } = false;

    /// <summary>URL base da API ColiseSpeed (ex: https://speed.coliseusistemas.com.br).</summary>
    public string BaseUrl { get; set; } = string.Empty;

    /// <summary>Chave interna de autenticação (Internal API Key do módulo ColiseSpeed).</summary>
    public string InternalApiKey { get; set; } = string.Empty;

    /// <summary>Timeout em segundos para requests HTTP.</summary>
    public int TimeoutSeconds { get; set; } = 30;
}
