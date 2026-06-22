namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Log de auditoria para rastreabilidade de eventos de segurança.
///
/// Registra todas as tentativas de login, bloqueios, suspensões,
/// e operações administrativas para compliance e debugging.
/// </summary>
public sealed class AuditLog
{
    public Guid Id { get; private set; }
    public string Action { get; private set; } = null!;
    public Guid? CompanyId { get; private set; }
    public Guid? DeviceId { get; private set; }
    public string? IpAddress { get; private set; }
    public string? UserAgent { get; private set; }
    public string? Details { get; private set; }
    /// <summary>E-mail do administrador que realizou a ação (null para eventos de sistema/device).</summary>
    public string? AdminEmail { get; private set; }
    public DateTime CreatedAt { get; private set; }

    // EF Core
    private AuditLog() { }

    /// <summary>
    /// Registra um evento de auditoria.
    /// </summary>
    /// <param name="action">Tipo do evento (ex: "device_login_success").</param>
    /// <param name="companyId">ID da empresa envolvida (opcional).</param>
    /// <param name="deviceId">ID do dispositivo envolvido (opcional).</param>
    /// <param name="ipAddress">Endereço IP da requisição.</param>
    /// <param name="userAgent">User-Agent da requisição.</param>
    /// <param name="details">Detalhes adicionais em JSON.</param>
    public static AuditLog Create(
        string action,
        Guid? companyId = null,
        Guid? deviceId = null,
        string? ipAddress = null,
        string? userAgent = null,
        string? details = null)
    {
        if (string.IsNullOrWhiteSpace(action))
            throw new ArgumentException("Action é obrigatória.", nameof(action));

        return new AuditLog
        {
            Id = Guid.NewGuid(),
            Action = action,
            CompanyId = companyId,
            DeviceId = deviceId,
            IpAddress = ipAddress,
            UserAgent = userAgent,
            Details = details,
            CreatedAt = DateTime.UtcNow,
        };
    }

    /// <summary>
    /// Cria um log de auditoria com dados do administrador responsável.
    /// </summary>
    public static AuditLog CreateAdmin(
        string action,
        string adminEmail,
        Guid? companyId = null,
        string? details = null,
        string? ipAddress = null)
    {
        if (string.IsNullOrWhiteSpace(action))
            throw new ArgumentException("Action é obrigatória.", nameof(action));

        return new AuditLog
        {
            Id        = Guid.NewGuid(),
            Action    = action,
            AdminEmail = adminEmail,
            CompanyId  = companyId,
            Details    = details,
            IpAddress  = ipAddress,
            CreatedAt  = DateTime.UtcNow,
        };
    }
}
