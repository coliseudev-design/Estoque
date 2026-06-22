using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Admin.Handlers;

/// <summary>
/// Handler para login de administrador no painel Admin.
///
/// Gera JWT Admin (issuer separado do JWT de dispositivos).
/// Valida e-mail + senha bcrypt (custo 12).
/// </summary>
public sealed class AdminLoginHandler
{
    private readonly IAdminUserRepository _adminRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly IJwtService _jwt;
    private readonly IPasswordHasher _hasher;
    private readonly TotpService _totp;
    private readonly IEncryptionService _encryption;

    public AdminLoginHandler(
        IAdminUserRepository adminRepo,
        IAuditLogRepository auditRepo,
        IJwtService jwt,
        IPasswordHasher hasher,
        TotpService totp,
        IEncryptionService encryption)
    {
        _adminRepo  = adminRepo;
        _auditRepo  = auditRepo;
        _jwt        = jwt;
        _hasher     = hasher;
        _totp       = totp;
        _encryption = encryption;
    }

    /// <summary>Processa login do administrador.</summary>
    public async Task<Result<AdminLoginResponse>> HandleAsync(
        AdminLoginRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        var admin = await _adminRepo.GetByEmailAsync(request.Email.Trim().ToLowerInvariant(), ct);

        if (admin is null || !admin.IsActive)
        {
            await AuditAsync("admin_login_failed", ipAddress, userAgent,
                $"E-mail: {request.Email} — não encontrado ou inativo");
            return Result<AdminLoginResponse>.Forbidden("Credenciais inválidas.");
        }

        if (!_hasher.Verify(request.Password, admin.PasswordHash))
        {
            await AuditAsync("admin_login_failed", ipAddress, userAgent,
                $"E-mail: {request.Email} — senha incorreta");
            return Result<AdminLoginResponse>.Forbidden("Credenciais inválidas.");
        }

        // Se 2FA estiver ativado: exige código TOTP antes de emitir JWT
        if (admin.TotpEnabled)
        {
            await AuditAsync("admin.login.2fa_required", ipAddress, userAgent,
                $"E-mail: {admin.Email}");
            await _adminRepo.SaveChangesAsync(ct);

            // Retorna uma resposta parcial — o front-end deve pedir o código TOTP
            return Result<AdminLoginResponse>.Success(new AdminLoginResponse(
                AccessToken: null,
                RefreshToken: null,
                ExpiresInSeconds: 0,
                Email: admin.Email,
                Name: admin.Name,
                Role: admin.Role.ToString(),
                RequiresTwoFactor: true));
        }

        return await IssueTokenAsync(admin, ipAddress, userAgent, ct);
    }

    /// <summary>
    /// Segundo fator: valida código TOTP e emite JWT se correto.
    /// </summary>
    public async Task<Result<AdminLoginResponse>> VerifyTotpAsync(
        string email,
        string totpCode,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        var admin = await _adminRepo.GetByEmailAsync(email.Trim().ToLowerInvariant(), ct);

        if (admin is null || !admin.IsActive || !admin.TotpEnabled || admin.TotpSecretEncrypted is null)
            return Result<AdminLoginResponse>.Forbidden("Credenciais inválidas.");

        var secret = _encryption.Decrypt(admin.TotpSecretEncrypted);

        if (!_totp.Validate(secret, totpCode))
        {
            await AuditAsync("admin.login.2fa_failed", ipAddress, userAgent,
                $"E-mail: {admin.Email} — código TOTP incorreto");
            await _adminRepo.SaveChangesAsync(ct);
            return Result<AdminLoginResponse>.Forbidden("Código 2FA inválido.");
        }

        return await IssueTokenAsync(admin, ipAddress, userAgent, ct);
    }

    /// <summary>Configura o 2FA para um admin. Retorna a URI otpauth para QR Code.</summary>
    public async Task<Result<TotpSetupResponse>> SetupTotpAsync(
        string email,
        string totpCode,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        var admin = await _adminRepo.GetByEmailAsync(email.Trim().ToLowerInvariant(), ct);
        if (admin is null || !admin.IsActive)
            return Result<TotpSetupResponse>.Forbidden("Acesso negado.");

        // Gera novo secret se ainda não tiver ou se desejar regenerar
        var rawSecret = _totp.GenerateSecret();

        // Verifica que o código enviado é válido com o secret recém-gerado
        if (!_totp.Validate(rawSecret, totpCode))
        {
            // Durante o setup a verificação confirma que o app foi configurado corretamente.
            // Se inválido, retorna a URI para o front-end mostrar o QR novamente.
            var otpUri = _totp.GetOtpAuthUri(admin.Email, rawSecret);
            return Result<TotpSetupResponse>.Success(new TotpSetupResponse(
                OtpAuthUri: otpUri,
                IsVerified: false,
                Message: "Escaneie o QR Code e confirme com o código gerado."));
        }

        // Código correto: salva secret criptografado e ativa 2FA
        var encryptedSecret = _encryption.Encrypt(rawSecret);
        admin.EnableTotp(encryptedSecret);
        await _adminRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.2fa.enabled", ipAddress, userAgent, $"E-mail: {admin.Email}");
        await _adminRepo.SaveChangesAsync(ct);

        return Result<TotpSetupResponse>.Success(new TotpSetupResponse(
            OtpAuthUri: _totp.GetOtpAuthUri(admin.Email, rawSecret),
            IsVerified: true,
            Message: "2FA ativado com sucesso!"));
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Helpers privados
    // ─────────────────────────────────────────────────────────────────────────────

    private async Task<Result<AdminLoginResponse>> IssueTokenAsync(
        AdminUser admin, string? ip, string? ua, CancellationToken ct)
    {
        // SuperAdmin recebe wildcard — bypassa qualquer RequirePermission
        IEnumerable<string> permissions;
        if (admin.Role == AdminRole.SuperAdmin)
        {
            permissions = new[] { "*" };
        }
        else if (admin.PermissionGroupId.HasValue)
        {
            // Carrega o grupo para obter as permissões (já eager-load via GetByIdAsync)
            var withGroup = await _adminRepo.GetByIdAsync(admin.Id, ct);
            var groupPerms = withGroup?.PermissionGroup?.Permissions;
            permissions = groupPerms != null ? (IEnumerable<string>)groupPerms : Array.Empty<string>();
        }
        else
        {
            permissions = Array.Empty<string>();
        }

        var (accessToken, expiresIn) = _jwt.GenerateAdminToken(
            admin.Id, admin.Email, admin.Role.ToString(), permissions);

        var refreshToken = Convert.ToBase64String(
            System.Security.Cryptography.RandomNumberGenerator.GetBytes(64));

        admin.RecordLogin();

        await AuditAsync("admin.login", ip, ua,
            $"E-mail: {admin.Email}, Role: {admin.Role}");

        await _adminRepo.SaveChangesAsync(ct);

        return Result<AdminLoginResponse>.Success(new AdminLoginResponse(
            AccessToken: accessToken,
            RefreshToken: refreshToken,
            ExpiresInSeconds: expiresIn,
            Email: admin.Email,
            Name: admin.Name,
            Role: admin.Role.ToString(),
            RequiresTwoFactor: false));
    }

    private async Task AuditAsync(
        string action, string? ipAddress, string? userAgent, string? details)
    {
        var log = AuditLog.Create(action, ipAddress: ipAddress,
            userAgent: userAgent, details: details);
        await _auditRepo.AddAsync(log);
    }

    /// <summary>Desativa o 2FA do admin pelo e-mail extraído do JWT.</summary>
    public async Task<Result<bool>> DisableTotpAsync(
        string email, string? ipAddress = null, string? userAgent = null,
        CancellationToken ct = default)
    {
        var admin = await _adminRepo.GetByEmailAsync(email.Trim().ToLowerInvariant(), ct);
        if (admin is null || !admin.IsActive)
            return Result<bool>.Forbidden("Acesso negado.");

        admin.DisableTotp();
        await _adminRepo.SaveChangesAsync(ct);

        await AuditAsync("admin.2fa.disabled", ipAddress, userAgent, $"E-mail: {admin.Email}");
        await _adminRepo.SaveChangesAsync(ct);

        return Result<bool>.Success(true);
    }
}
