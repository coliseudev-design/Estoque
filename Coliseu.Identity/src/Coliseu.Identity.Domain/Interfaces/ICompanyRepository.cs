using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de empresas (tenants).</summary>
public interface ICompanyRepository
{
    /// <summary>Busca empresa pelo hash SHA-256 da CompanyKey.</summary>
    Task<Company?> GetByKeyHashAsync(string companyKeyHash, CancellationToken ct = default);

    /// <summary>Busca empresa por ID com dispositivos carregados.</summary>
    Task<Company?> GetByIdWithDevicesAsync(Guid id, CancellationToken ct = default);

    /// <summary>Busca empresa por ID (sem navegação).</summary>
    Task<Company?> GetByIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Lista todas as empresas (paginação).</summary>
    Task<(List<Company> Items, int TotalCount)> GetAllAsync(
        int page, int pageSize, string? search = null, CancellationToken ct = default);

    /// <summary>Adiciona uma nova empresa.</summary>
    Task AddAsync(Company company, CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);

    /// <summary>Remove uma empresa pelo ID.</summary>
    Task DeleteAsync(Guid id, CancellationToken ct = default);
}
