using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de grupos de permissões.</summary>
public interface IPermissionGroupRepository
{
    /// <summary>Lista todos os grupos.</summary>
    Task<List<PermissionGroup>> GetAllAsync(CancellationToken ct = default);

    /// <summary>Busca grupo por ID.</summary>
    Task<PermissionGroup?> GetByIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Adiciona um novo grupo.</summary>
    Task AddAsync(PermissionGroup group, CancellationToken ct = default);

    /// <summary>Remove um grupo.</summary>
    void Remove(PermissionGroup group);

    /// <summary>Conta quantos usuários estão vinculados a um grupo.</summary>
    Task<int> CountUsersByGroupAsync(Guid groupId, CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
