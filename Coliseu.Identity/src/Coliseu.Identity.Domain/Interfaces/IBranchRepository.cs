using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de filiais (branches).</summary>
public interface IBranchRepository
{
    Task<Branch?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<Branch?> GetByErpIdAsync(Guid companyId, int erpEmpresaId, CancellationToken ct = default);
    Task<List<Branch>> GetByCompanyAsync(Guid companyId, CancellationToken ct = default);
    Task AddAsync(Branch branch, CancellationToken ct = default);
    Task DeleteAsync(Guid id, CancellationToken ct = default);
    Task SaveChangesAsync(CancellationToken ct = default);
}
