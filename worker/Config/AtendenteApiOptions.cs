namespace ColiseuSpeed.Worker.Config;

/// <summary>
/// Configuração de conexão com o backend do Atendente do Futuro.
/// Seção "AtendenteApi" no appsettings.json.
///
/// Quando habilitado (Enabled=true), o Worker sincroniza dados do Firebird
/// para AMBOS os backends: Coliseu Speed (VPS) E Atendente do Futuro.
///
/// Isso permite que pedidos do WhatsApp sejam inseridos no Firebird
/// usando a mesma conexão e stored procedures do Coliseu Speed.
/// </summary>
public sealed class AtendenteApiOptions
{
    public const string Section = "AtendenteApi";

    /// <summary>Se true, o Worker sincroniza com o Atendente do Futuro.</summary>
    public bool Enabled { get; set; } = false;

    /// <summary>URL base do backend (ex: https://atendente.seudominio.com).</summary>
    public string BaseUrl { get; set; } = string.Empty;

    /// <summary>API Key para autenticação com o backend.</summary>
    public string ApiKey { get; set; } = string.Empty;

    /// <summary>Timeout em segundos para chamadas HTTP.</summary>
    public int TimeoutSeconds { get; set; } = 30;
}
