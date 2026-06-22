using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Admin.Handlers;

// ─────────────────────────────────────────────────────────────────────────────
// DTOs
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>Request para criação de usuário admin.</summary>
public sealed class CreateAdminUserRequest
{
    public string Email { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public Guid? PermissionGroupId { get; set; }
}

/// <summary>Request para atualização de usuário admin.</summary>
public sealed class UpdateAdminUserRequest
{
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public Guid? PermissionGroupId { get; set; }
    public bool IsActive { get; set; } = true;
}

/// <summary>Request para reset de senha.</summary>
public sealed class ResetPasswordRequest
{
    public string NewPassword { get; set; } = string.Empty;
}

/// <summary>DTO de resposta de um admin user.</summary>
public sealed record AdminUserDto(
    Guid Id,
    string Email,
    string Name,
    string Role,
    bool IsActive,
    bool TotpEnabled,
    Guid? PermissionGroupId,
    string? PermissionGroupName,
    DateTime CreatedAt,
    DateTime? LastLoginAt);

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Handler para CRUD de usuários administradores.
/// Requer SuperAdmin para todas as operações.
/// </summary>
public sealed class AdminUsersHandler
{
    private readonly IAdminUserRepository _userRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly IPasswordHasher _hasher;

    public AdminUsersHandler(
        IAdminUserRepository userRepo,
        IAuditLogRepository auditRepo,
        IPasswordHasher hasher)
    {
        _userRepo = userRepo;
        _auditRepo = auditRepo;
        _hasher = hasher;
    }

    /// <summary>Lista todos os admin users.</summary>
    public async Task<Result<List<AdminUserDto>>> ListAsync(CancellationToken ct = default)
    {
        var users = await _userRepo.GetAllAsync(ct);
        var dtos = users.Select(u => new AdminUserDto(
            u.Id, u.Email, u.Name ?? "", u.Role.ToString(), u.IsActive,
            u.TotpEnabled, u.PermissionGroupId,
            u.PermissionGroup?.Name, u.CreatedAt, u.LastLoginAt)).ToList();
        return Result<List<AdminUserDto>>.Success(dtos);
    }

    /// <summary>Cria um novo admin user.</summary>
    public async Task<Result<AdminUserDto>> CreateAsync(
        CreateAdminUserRequest req, string? ip, string? ua, CancellationToken ct = default)
    {
        // Validação de senha (Rule-07)
        var (isValid, passError) = PasswordPolicy.Validate(req.Password);
        if (!isValid)
            return Result<AdminUserDto>.BadRequest(passError!);

        // Email duplicado
        var existing = await _userRepo.GetByEmailAsync(req.Email.Trim().ToLowerInvariant(), ct);
        if (existing is not null)
            return Result<AdminUserDto>.BadRequest("E-mail já cadastrado.");

        var user = AdminUser.Create(
            req.Email, req.Name, _hasher.Hash(req.Password),
            AdminRole.Operator, req.PermissionGroupId);

        await _userRepo.AddAsync(user, ct);
        await _userRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.user.created", ip, ua, $"User: {user.Email} ({user.Name})");

        // Recarrega com PermissionGroup
        var saved = await _userRepo.GetByIdAsync(user.Id, ct);
        return Result<AdminUserDto>.Success(ToDto(saved!));
    }

    /// <summary>Atualiza um admin user existente.</summary>
    public async Task<Result<AdminUserDto>> UpdateAsync(
        Guid id, UpdateAdminUserRequest req, string? ip, string? ua, CancellationToken ct = default)
    {
        var user = await _userRepo.GetByIdAsync(id, ct);
        if (user is null)
            return Result<AdminUserDto>.NotFound("Usuário não encontrado.");

        // Verifica email duplicado (se mudou)
        if (!string.Equals(user.Email, req.Email, StringComparison.OrdinalIgnoreCase))
        {
            var dup = await _userRepo.GetByEmailAsync(req.Email.Trim().ToLowerInvariant(), ct);
            if (dup is not null)
                return Result<AdminUserDto>.BadRequest("E-mail já cadastrado por outro usuário.");
        }

        user.UpdateProfile(req.Name, req.Email, req.PermissionGroupId);
        if (req.IsActive) user.Activate(); else user.Deactivate();

        await _userRepo.SaveChangesAsync(ct);
        await AuditAsync("admin.user.updated", ip, ua, $"User: {user.Email} ({user.Name})");

        var updated = await _userRepo.GetByIdAsync(id, ct);
        return Result<AdminUserDto>.Success(ToDto(updated!));
    }

    /// <summary>Desativa (soft delete) um admin user.</summary>
    public async Task<Result<bool>> DeleteAsync(
        Guid id, string? ip, string? ua, CancellationToken ct = default)
    {
        var user = await _userRepo.GetByIdAsync(id, ct);
        if (user is null)
            return Result<bool>.NotFound("Usuário não encontrado.");

        user.Deactivate();
        await _userRepo.SaveChangesAsync(ct);
        await AuditAsync("admin.user.deactivated", ip, ua, $"User: {user.Email}");

        return Result<bool>.Success(true);
    }

    /// <summary>Reset de senha de um admin user.</summary>
    public async Task<Result<bool>> ResetPasswordAsync(
        Guid id, ResetPasswordRequest req, string? ip, string? ua, CancellationToken ct = default)
    {
        var (isValid, passError) = PasswordPolicy.Validate(req.NewPassword);
        if (!isValid)
            return Result<bool>.BadRequest(passError!);

        var user = await _userRepo.GetByIdAsync(id, ct);
        if (user is null)
            return Result<bool>.NotFound("Usuário não encontrado.");

        user.UpdatePassword(_hasher.Hash(req.NewPassword));
        await _userRepo.SaveChangesAsync(ct);
        await AuditAsync("admin.user.password_reset", ip, ua, $"User: {user.Email}");

        return Result<bool>.Success(true);
    }

    private static AdminUserDto ToDto(AdminUser u) => new(
        u.Id, u.Email, u.Name ?? "", u.Role.ToString(), u.IsActive,
        u.TotpEnabled, u.PermissionGroupId,
        u.PermissionGroup?.Name, u.CreatedAt, u.LastLoginAt);

    private async Task AuditAsync(string action, string? ip, string? ua, string? details)
    {
        var log = AuditLog.Create(action, ipAddress: ip, userAgent: ua, details: details);
        await _auditRepo.AddAsync(log);
        await _auditRepo.SaveChangesAsync();
    }
}
