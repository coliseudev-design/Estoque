using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de logs de auditoria.</summary>
public interface IAuditLogRepository
{
    /// <summary>Adiciona um log de auditoria.</summary>
    Task AddAsync(AuditLog log, CancellationToken ct = default);

    /// <summary>Lista logs paginados com filtros opcionais.</summary>
    Task<(List<AuditLog> Items, int TotalCount)> GetAllAsync(
        int page,
        int pageSize,
        Guid? companyId = null,
        string? action = null,
        DateTime? from = null,
        DateTime? to = null,
        CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
