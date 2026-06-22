using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de parceiros integradores comercializadores.</summary>
public interface IPartnerRepository
{
    Task<Partner?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<Partner?> GetByCnpjAsync(string cnpj, CancellationToken ct = default);
    Task<(List<Partner> Items, int TotalCount)> GetAllAsync(
        int page, int pageSize, string? search = null, CancellationToken ct = default);
    Task AddAsync(Partner partner, CancellationToken ct = default);
    Task DeleteAsync(Guid id, CancellationToken ct = default);
    Task SaveChangesAsync(CancellationToken ct = default);
}
