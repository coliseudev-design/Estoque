using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de requisições de licenças.</summary>
public interface ILicenseRequestRepository
{
    Task<LicenseRequest?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<LicenseRequest?> GetByIdWithoutIncludesAsync(Guid id, CancellationToken ct = default);
    Task<(List<LicenseRequest> Items, int TotalCount)> GetAllAsync(
        int page, 
        int pageSize, 
        string? search = null, 
        RequestStatus? status = null, 
        Guid? partnerId = null, 
        CancellationToken ct = default);
    Task AddAsync(LicenseRequest request, CancellationToken ct = default);
    Task DeleteAsync(Guid id, CancellationToken ct = default);
    Task SaveChangesAsync(CancellationToken ct = default);
}
