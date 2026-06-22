using Coliseu.Identity.Application.Auth.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Auth.Handlers;

/// <summary>
/// Handler para refresh de JWT via Refresh Token rotativo.
///
/// Fluxo:
/// 1. Busca sessão pelo refresh token
/// 2. Valida sessão (não expirada, não revogada)
/// 3. Verifica status do dispositivo e empresa
/// 4. Revoga sessão atual
/// 5. Gera nova sessão com novos tokens
/// </summary>
public sealed class RefreshTokenHandler
{
    private readonly ISessionRepository _sessionRepo;
    private readonly IDeviceRepository _deviceRepo;
    private readonly ICompanyRepository _companyRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly IJwtService _jwt;

    /// <summary>Dias de validade do Refresh Token — configurado em appsettings Jwt:RefreshTokenDays.</summary>
    private readonly int _refreshTokenDays;

    public RefreshTokenHandler(
        ISessionRepository sessionRepo,
        IDeviceRepository deviceRepo,
        ICompanyRepository companyRepo,
        IAuditLogRepository auditRepo,
        IJwtService jwt,
        int refreshTokenDays = 30)
    {
        _sessionRepo = sessionRepo;
        _deviceRepo = deviceRepo;
        _companyRepo = companyRepo;
        _auditRepo = auditRepo;
        _jwt = jwt;
        _refreshTokenDays = refreshTokenDays;
    }

    /// <summary>
    /// Processa refresh de token.
    /// </summary>
    public async Task<Result<RefreshResponse>> HandleAsync(
        RefreshRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        // 1. Buscar sessão
        var session = await _sessionRepo.GetByRefreshTokenAsync(request.RefreshToken, ct);
        if (session is null || !session.IsValid)
        {
            return Result<RefreshResponse>.Forbidden("Refresh token inválido ou expirado.");
        }

        // 2. Verificar dispositivo
        var device = await _deviceRepo.GetByIdAsync(session.DeviceId, ct);
        if (device is null || !device.CanAuthenticate)
        {
            return Result<RefreshResponse>.Forbidden("Dispositivo bloqueado ou revogado.");
        }

        // 3. Verificar empresa
        var company = await _companyRepo.GetByIdAsync(device.CompanyId, ct);
        if (company is null || !company.IsOperational)
        {
            return Result<RefreshResponse>.Forbidden("Empresa suspensa ou bloqueada.");
        }

        // 4. Revogar sessão atual (rotação)
        session.Revoke();

        // 5. Gerar novos tokens
        var (accessToken, expiresIn) = _jwt.GenerateDeviceToken(
            company.Id, device.Id, company.Name);

        var newRefreshToken = TokenGenerator.GenerateRefreshToken();
        var newSession = Session.Create(
            device.Id, newRefreshToken, DateTime.UtcNow.AddDays(_refreshTokenDays));
        await _sessionRepo.AddAsync(newSession, ct);

        // Atualizar último acesso
        device.RecordAccess(null, null, null);

        // Auditoria
        var log = AuditLog.Create("refresh_token_used",
            company.Id, device.Id, ipAddress, userAgent);
        await _auditRepo.AddAsync(log, ct);

        await _sessionRepo.SaveChangesAsync(ct);

        return Result<RefreshResponse>.Success(new RefreshResponse(
            AccessToken: accessToken,
            RefreshToken: newRefreshToken,
            ExpiresInSeconds: expiresIn));
    }


}
