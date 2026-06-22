namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Módulos e limites de dispositivos solicitados em uma requisição de licença.
/// </summary>
public sealed class LicenseRequestModule
{
    public Guid Id { get; private set; }
    public Guid LicenseRequestId { get; private set; }
    public string ModuleSlug { get; private set; } = null!;
    public int DeviceLimit { get; private set; }

    // EF Core constructor
    private LicenseRequestModule() { }

    public LicenseRequestModule(Guid id, Guid licenseRequestId, string moduleSlug, int deviceLimit)
    {
        Id = id;
        LicenseRequestId = licenseRequestId;
        ModuleSlug = moduleSlug;
        DeviceLimit = deviceLimit;
    }
}
