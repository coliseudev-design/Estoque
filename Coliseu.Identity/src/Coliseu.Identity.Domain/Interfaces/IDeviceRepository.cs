using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de dispositivos.</summary>
public interface IDeviceRepository
{
    /// <summary>Busca dispositivo pelo UUID e empresa.</summary>
    Task<Device?> GetByUuidAndCompanyAsync(
        string deviceUuid, Guid companyId, CancellationToken ct = default);

    /// <summary>Busca dispositivo pendente pela sua chave de ativação.</summary>
    Task<Device?> GetByActivationKeyAsync(string activationKey, CancellationToken ct = default);

    /// <summary>Busca dispositivo por ID.</summary>
    Task<Device?> GetByIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Conta dispositivos ativos de uma empresa.</summary>
    Task<int> CountActiveByCompanyAsync(Guid companyId, CancellationToken ct = default);

    /// <summary>Lista dispositivos de uma empresa (paginação).</summary>
    Task<(List<Device> Items, int TotalCount)> GetByCompanyAsync(
        Guid companyId, int page, int pageSize, CancellationToken ct = default);

    /// <summary>Adiciona um novo dispositivo.</summary>
    Task AddAsync(Device device, CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
