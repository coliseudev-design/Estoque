namespace Coliseu.Identity.Infrastructure.Notifications;

/// <summary>
/// Opções de configuração para integração com a UAZAPI de WhatsApp.
/// </summary>
public sealed class WhatsAppOptions
{
    public const string Section = "Uazapi";
    public string ServerUrl { get; set; } = string.Empty;
    public string Token { get; set; } = string.Empty;
    public bool Enabled { get; set; } = true;
    public string AdminPhone { get; set; } = string.Empty;
}
