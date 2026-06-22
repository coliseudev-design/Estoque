using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Usuário administrativo do painel Coliseu.Identity.Admin.
///
/// Possui JWT de autenticação separado dos dispositivos.
/// Senha armazenada como bcrypt com custo 12 (Rule-07).
/// </summary>
public sealed class AdminUser
{
    public Guid Id { get; private set; }
    public string Email { get; private set; } = null!;
    public string? Name { get; private set; }
    public string PasswordHash { get; private set; } = null!;
    public AdminRole Role { get; private set; }
    public bool IsActive { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime? LastLoginAt { get; private set; }

    // ── RBAC: vínculo com grupo de permissões ──────────────────────────────
    public Guid? PermissionGroupId { get; private set; }
    public PermissionGroup? PermissionGroup { get; private set; }

    // ── 2FA TOTP (Rule-04: secret armazenado criptografado pelo EncryptionService) ──
    /// <summary>Secret TOTP em Base32, criptografado antes do armazenamento.</summary>
    public string? TotpSecretEncrypted { get; private set; }
    /// <summary>True quando o 2FA foi ativado e verificado pelo admin.</summary>
    public bool TotpEnabled { get; private set; }

    // EF Core
    private AdminUser() { }

    /// <summary>
    /// Cria um novo usuário administrador.
    /// </summary>
    /// <param name="email">E-mail do administrador (único).</param>
    /// <param name="passwordHash">Hash bcrypt da senha (custo 12).</param>
    /// <param name="role">Papel: SuperAdmin ou Operator.</param>
    public static AdminUser Create(string email, string name, string passwordHash, AdminRole role, Guid? permissionGroupId = null)
    {
        if (string.IsNullOrWhiteSpace(email))
            throw new ArgumentException("E-mail é obrigatório.", nameof(email));
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome é obrigatório.", nameof(name));
        if (string.IsNullOrWhiteSpace(passwordHash))
            throw new ArgumentException("PasswordHash é obrigatório.", nameof(passwordHash));

        return new AdminUser
        {
            Id = Guid.NewGuid(),
            Email = email.Trim().ToLowerInvariant(),
            Name = name.Trim(),
            PasswordHash = passwordHash,
            Role = role,
            PermissionGroupId = permissionGroupId,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
        };
    }

    /// <summary>Registra o timestamp do último login.</summary>
    public void RecordLogin()
    {
        LastLoginAt = DateTime.UtcNow;
    }

    /// <summary>Atualiza o hash da senha (para reset/mudança).</summary>
    public void UpdatePassword(string newPasswordHash)
    {
        if (string.IsNullOrWhiteSpace(newPasswordHash))
            throw new ArgumentException("PasswordHash é obrigatório.", nameof(newPasswordHash));
        PasswordHash = newPasswordHash;
    }

    /// <summary>Desativa o administrador.</summary>
    public void Deactivate() => IsActive = false;

    /// <summary>Reativa o administrador.</summary>
    public void Activate() => IsActive = true;

    /// <summary>Verifica se é SuperAdmin.</summary>
    public bool IsSuperAdmin => Role == AdminRole.SuperAdmin;

    /// <summary>Atualiza perfil do usuário (nome, email, grupo).</summary>
    public void UpdateProfile(string name, string email, Guid? permissionGroupId)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome é obrigatório.", nameof(name));
        if (string.IsNullOrWhiteSpace(email))
            throw new ArgumentException("E-mail é obrigatório.", nameof(email));

        Name = name.Trim();
        Email = email.Trim().ToLowerInvariant();
        PermissionGroupId = permissionGroupId;
    }

    /// <summary>
    /// Verifica se o usuário tem determinada permissão.
    /// SuperAdmin sempre retorna true (bypass total).
    /// </summary>
    public bool HasPermission(string key)
    {
        if (IsSuperAdmin) return true;
        return PermissionGroup?.HasPermission(key) ?? false;
    }

    // ── 2FA TOTP Methods ──────────────────────────────────────────────────────

    /// <summary>
    /// Armazena o secret TOTP criptografado e ativa o 2FA.
    /// Chamar apenas após verificar que o usuário validou um código correto.
    /// </summary>
    public void EnableTotp(string encryptedSecret)
    {
        if (string.IsNullOrWhiteSpace(encryptedSecret))
            throw new ArgumentException("Secret é obrigatório para ativar 2FA.");
        TotpSecretEncrypted = encryptedSecret;
        TotpEnabled = true;
    }

    /// <summary>Desativa o 2FA e remove o secret.</summary>
    public void DisableTotp()
    {
        TotpSecretEncrypted = null;
        TotpEnabled = false;
    }
}
