using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Dispositivo móvel registrado para uma empresa.
///
/// Cada dispositivo é identificado por um UUID de hardware único.
/// O primeiro acesso registra o dispositivo; acessos subsequentes atualizam LastAccess.
/// Dispositivos podem ser bloqueados remotamente pelo painel Admin.
/// </summary>
public sealed class Device
{
    public Guid Id { get; private set; }
    public Guid CompanyId { get; private set; }
    public string? DeviceUuid { get; private set; }
    public string ActivationKey { get; private set; } = null!;
    public string? Name { get; private set; } // Apelido personalizado pelo Admin
    public string? Model { get; private set; }
    public string? OS { get; private set; }
    public string? AppVersion { get; private set; }
    public DeviceStatus Status { get; private set; }
    /// <summary>
    /// Identifica o módulo/produto a que este dispositivo pertence.
    /// Ex: "coliseu-speed" | "autocenter"
    /// Padrão "coliseu-speed" garante backward compatibility com devices existentes.
    /// </summary>
    public string ModuleSlug { get; private set; } = ModuleSlugs.ColiseuSpeed;
    public DateTime FirstActivation { get; private set; }
    public DateTime LastAccess { get; private set; }

    // Navigation
    public Company Company { get; private set; } = null!;
    private readonly List<Session> _sessions = new();
    public IReadOnlyCollection<Session> Sessions => _sessions.AsReadOnly();

    // EF Core
    private Device() { }

    /// <summary>
    /// Registra um novo dispositivo para uma empresa aguardando sincronização.
    /// </summary>
    /// <param name="companyId">ID da empresa proprietária.</param>
    /// <param name="activationKey">Chave de 10 dígitos para ativação no mobile.</param>
    /// <param name="moduleSlug">Módulo ao qual o device pertence (default: coliseu-speed).</param>
    public static Device CreatePending(Guid companyId, string activationKey,
        string moduleSlug = ModuleSlugs.ColiseuSpeed)
    {
        if (companyId == Guid.Empty)
            throw new ArgumentException("CompanyId é obrigatório.", nameof(companyId));
        if (string.IsNullOrWhiteSpace(activationKey) || activationKey.Length > 10)
            throw new ArgumentException("ActivationKey inválida.", nameof(activationKey));

        var now = DateTime.UtcNow;
        return new Device
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            ActivationKey = activationKey.Trim().ToUpperInvariant(),
            ModuleSlug = moduleSlug.Trim().ToLowerInvariant(),
            DeviceUuid = null,
            Model = "Aguardando Sinc. - Desconhecido",
            OS = null,
            AppVersion = null,
            Status = DeviceStatus.Active,
            FirstActivation = now,
            LastAccess = now,
        };
    }

    /// <summary>Víncula o dispositivo ao hardware UUID quando o app sincroniza pela primeira vez.</summary>
    public void LinkHardware(string deviceUuid, string? model, string? os, string? appVersion)
    {
        if (string.IsNullOrWhiteSpace(deviceUuid))
            throw new ArgumentException("DeviceUuid é obrigatório.", nameof(deviceUuid));

        DeviceUuid = deviceUuid.Trim();
        Model = model?.Trim() ?? Model;
        OS = os?.Trim() ?? OS;
        AppVersion = appVersion?.Trim() ?? AppVersion;
        LastAccess = DateTime.UtcNow;
    }

    /// <summary>Atualiza metadados do dispositivo e marca último acesso.</summary>
    public void RecordAccess(string? model, string? os, string? appVersion)
    {
        Model = model?.Trim() ?? Model;
        OS = os?.Trim() ?? OS;
        AppVersion = appVersion?.Trim() ?? AppVersion;
        LastAccess = DateTime.UtcNow;
    }

    /// <summary>Atualiza manualmente o nome/apelido do dispositivo pelo Admin.</summary>
    public void UpdateName(string? name)
    {
        Name = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
    }

    /// <summary>Bloqueia o dispositivo — impede novos logins.</summary>
    public void Block()
    {
        Status = DeviceStatus.Blocked;
    }

    /// <summary>Desbloqueia o dispositivo — permite logins novamente.</summary>
    public void Unblock()
    {
        Status = DeviceStatus.Active;
    }

    /// <summary>Revoga permanentemente o dispositivo.</summary>
    public void Revoke()
    {
        Status = DeviceStatus.Revoked;
    }

    /// <summary>
    /// Revoga o dispositivo E limpa o vínculo de hardware (DeviceUuid).
    /// Usar quando o admin quer transferir a chave para um novo dispositivo:
    /// o status Revoked bloqueia o device antigo, o UUID nulo permite que
    /// o mesmo ActivationKey seja ativado no novo hardware.
    /// </summary>
    public void RevokeAndReleaseHardware()
    {
        Status = DeviceStatus.Revoked;
        DeviceUuid = null; // Libera vínculo para reativação em novo hardware
    }

    /// <summary>Verifica se o dispositivo pode autenticar.</summary>
    public bool CanAuthenticate => Status == DeviceStatus.Active;
}
