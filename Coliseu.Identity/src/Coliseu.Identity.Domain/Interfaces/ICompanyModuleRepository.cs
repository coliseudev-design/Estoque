using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de módulos ativos por empresa.</summary>
public interface ICompanyModuleRepository
{
    /// <summary>Busca módulo pelo hash da API Key.</summary>
    Task<CompanyModule?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken ct = default);

    /// <summary>Busca módulo por empresa e slug.</summary>
    Task<CompanyModule?> GetByCompanyAndSlugAsync(Guid companyId, string moduleSlug, CancellationToken ct = default);

    /// <summary>Lista todos os módulos de uma empresa.</summary>
    Task<List<CompanyModule>> GetByCompanyAsync(Guid companyId, CancellationToken ct = default);

    /// <summary>Verifica se um módulo está ativo para a empresa.</summary>
    Task<bool> IsActiveAsync(Guid companyId, string moduleSlug, CancellationToken ct = default);

    /// <summary>Adiciona novo módulo.</summary>
    Task AddAsync(CompanyModule module, CancellationToken ct = default);

    /// <summary>Remove módulo.</summary>
    Task RemoveAsync(Guid moduleId, CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
