using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de usuários administradores.</summary>
public interface IAdminUserRepository
{
    /// <summary>Busca admin por e-mail.</summary>
    Task<AdminUser?> GetByEmailAsync(string email, CancellationToken ct = default);

    /// <summary>Busca admin por ID (com PermissionGroup incluso).</summary>
    Task<AdminUser?> GetByIdAsync(Guid id, CancellationToken ct = default);

    /// <summary>Lista todos os admin users (com PermissionGroup incluso).</summary>
    Task<List<AdminUser>> GetAllAsync(CancellationToken ct = default);

    /// <summary>Adiciona um novo admin.</summary>
    Task AddAsync(AdminUser adminUser, CancellationToken ct = default);

    /// <summary>Remove um admin.</summary>
    void Remove(AdminUser adminUser);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
