using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Admin.Handlers;

// ─────────────────────────────────────────────────────────────────────────────
// DTOs
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Request para criar/atualizar grupo de permissões.</summary>
public sealed class UpsertPermissionGroupRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public List<string> Permissions { get; set; } = new();
}

/// <summary>DTO de resposta de um grupo de permissões.</summary>
public sealed record PermissionGroupDto(
    Guid Id,
    string Name,
    string? Description,
    List<string> Permissions,
    int UserCount,
    DateTime CreatedAt,
    DateTime? UpdatedAt);

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Handler para CRUD de grupos de permissões.
/// Requer SuperAdmin para todas as operações.
/// </summary>
public sealed class PermissionGroupHandler
{
    private readonly IPermissionGroupRepository _groupRepo;
    private readonly IAuditLogRepository _auditRepo;

    public PermissionGroupHandler(
        IPermissionGroupRepository groupRepo,
        IAuditLogRepository auditRepo)
    {
        _groupRepo = groupRepo;
        _auditRepo = auditRepo;
    }

    /// <summary>Lista todos os grupos com contagem de usuários.</summary>
    public async Task<Result<List<PermissionGroupDto>>> ListAsync(CancellationToken ct = default)
    {
        var groups = await _groupRepo.GetAllAsync(ct);
        var dtos = new List<PermissionGroupDto>();

        foreach (var g in groups)
        {
            var count = await _groupRepo.CountUsersByGroupAsync(g.Id, ct);
            dtos.Add(new PermissionGroupDto(
                g.Id, g.Name, g.Description,
                g.Permissions, count, g.CreatedAt, g.UpdatedAt));
        }

        return Result<List<PermissionGroupDto>>.Success(dtos);
    }

    /// <summary>Cria um novo grupo de permissões.</summary>
    public async Task<Result<PermissionGroupDto>> CreateAsync(
        UpsertPermissionGroupRequest req, string? ip, string? ua, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(req.Name))
            return Result<PermissionGroupDto>.BadRequest("Nome do grupo é obrigatório.");

        var group = PermissionGroup.Create(req.Name, req.Description, req.Permissions);
        await _groupRepo.AddAsync(group, ct);
        await _groupRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.group.created", ip, ua, $"Group: {group.Name}");

        return Result<PermissionGroupDto>.Success(new PermissionGroupDto(
            group.Id, group.Name, group.Description,
            group.Permissions, 0, group.CreatedAt, group.UpdatedAt));
    }

    /// <summary>Atualiza um grupo existente.</summary>
    public async Task<Result<PermissionGroupDto>> UpdateAsync(
        Guid id, UpsertPermissionGroupRequest req, string? ip, string? ua, CancellationToken ct = default)
    {
        var group = await _groupRepo.GetByIdAsync(id, ct);
        if (group is null)
            return Result<PermissionGroupDto>.NotFound("Grupo não encontrado.");

        group.Update(req.Name, req.Description, req.Permissions);
        await _groupRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.group.updated", ip, ua, $"Group: {group.Name}");

        var count = await _groupRepo.CountUsersByGroupAsync(id, ct);
        return Result<PermissionGroupDto>.Success(new PermissionGroupDto(
            group.Id, group.Name, group.Description,
            group.Permissions, count, group.CreatedAt, group.UpdatedAt));
    }

    /// <summary>Remove um grupo. Falha se houver usuários vinculados.</summary>
    public async Task<Result<bool>> DeleteAsync(
        Guid id, string? ip, string? ua, CancellationToken ct = default)
    {
        var group = await _groupRepo.GetByIdAsync(id, ct);
        if (group is null)
            return Result<bool>.NotFound("Grupo não encontrado.");

        var userCount = await _groupRepo.CountUsersByGroupAsync(id, ct);
        if (userCount > 0)
            return Result<bool>.BadRequest(
                $"Não é possível remover o grupo '{group.Name}' — há {userCount} usuário(s) vinculado(s). Mova-os para outro grupo primeiro.");

        _groupRepo.Remove(group);
        await _groupRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.group.deleted", ip, ua, $"Group: {group.Name}");

        return Result<bool>.Success(true);
    }

    private async Task AuditAsync(string action, string? ip, string? ua, string? details)
    {
        var log = AuditLog.Create(action, ipAddress: ip, userAgent: ua, details: details);
        await _auditRepo.AddAsync(log);
        await _auditRepo.SaveChangesAsync();
    }
}
