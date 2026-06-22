using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Auth.Handlers;

public sealed record SelectBranchRequest(Guid BranchId);

public sealed record SelectBranchResponse(
    string AccessToken,
    string RefreshToken,
    int ExpiresInSeconds,
    string BaseUrl,
    string CompanyName,
    Guid TenantId,
    Guid DeviceId,
    Guid BranchId,
    string BranchName,
    int ErpEmpresaId
);

/// <summary>
/// Handler para selecionar uma filial. 
/// Requer que o dispositivo já tenha um JWT inicial (genérico da empresa).
/// Retorna um novo JWT restrito àquela Branch, contendo os claims da filial.
/// </summary>
public sealed class SelectBranchHandler
{
    private readonly IBranchRepository _branchRepo;
    private readonly ICompanyRepository _companyRepo;
    private readonly IDeviceRepository _deviceRepo;
    private readonly ISessionRepository _sessionRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly ICompanyModuleRepository _moduleRepo;
    private readonly IJwtService _jwt;

    private readonly string _salesApiBaseUrl;
    private readonly int _refreshTokenDays;

    public SelectBranchHandler(
        IBranchRepository branchRepo,
        ICompanyRepository companyRepo,
        IDeviceRepository deviceRepo,
        ISessionRepository sessionRepo,
        IAuditLogRepository auditRepo,
        IJwtService jwt,
        string salesApiBaseUrl,
        int refreshTokenDays = 30,
        ICompanyModuleRepository? moduleRepo = null)
    {
        _branchRepo = branchRepo;
        _companyRepo = companyRepo;
        _deviceRepo = deviceRepo;
        _sessionRepo = sessionRepo;
        _auditRepo = auditRepo;
        _jwt = jwt;
        _salesApiBaseUrl = salesApiBaseUrl;
        _refreshTokenDays = refreshTokenDays;
        _moduleRepo = moduleRepo!;
    }

    public async Task<Result<SelectBranchResponse>> HandleAsync(
        Guid companyId,
        Guid deviceId,
        string moduleSlug,
        SelectBranchRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        var company = await _companyRepo.GetByIdAsync(companyId, ct);
        if (company is null || !company.IsOperational)
        {
            return Result<SelectBranchResponse>.Forbidden("Empresa não encontrada ou inativa.");
        }

        var device = await _deviceRepo.GetByIdAsync(deviceId, ct);
        if (device is null || device.CompanyId != companyId || !device.CanAuthenticate)
        {
            return Result<SelectBranchResponse>.Forbidden("Dispositivo não encontrado ou não autorizado.");
        }

        var branch = await _branchRepo.GetByIdAsync(request.BranchId, ct);
        if (branch is null || branch.CompanyId != companyId)
        {
            return Result<SelectBranchResponse>.NotFound("Filial não encontrada para esta empresa.");
        }

        string middlewareUrl = _salesApiBaseUrl;
        if (_moduleRepo is not null)
        {
            var companyModule = await _moduleRepo.GetByCompanyAndSlugAsync(company.Id, moduleSlug, ct);
            if (companyModule is not null && companyModule.IsActive && !string.IsNullOrWhiteSpace(companyModule.MiddlewareBaseUrl))
            {
                middlewareUrl = companyModule.MiddlewareBaseUrl;
            }
        }

        var (accessToken, expiresIn) = _jwt.GenerateDeviceTokenWithBranch(
            company.Id, device.Id, company.Name, branch.Id, branch.ErpEmpresaId, moduleSlug);

        // Gerar novo refresh token e invalidar o anterior
        await _sessionRepo.RevokeAllByDeviceAsync(device.Id, ct);
        var refreshToken = TokenGenerator.GenerateRefreshToken();
        var session = Session.Create(device.Id, refreshToken, DateTime.UtcNow.AddDays(_refreshTokenDays));
        await _sessionRepo.AddAsync(session, ct);

        // Audit
        var log = AuditLog.Create("device_branch_selected", company.Id, device.Id, ipAddress, userAgent, $"BranchId: {branch.Id} | Name: {branch.Name}");
        await _auditRepo.AddAsync(log, ct);

        device.RecordAccess(device.Model ?? "Unknown", device.OS ?? "Unknown", device.AppVersion ?? "Unknown");

        // Save
        await _sessionRepo.SaveChangesAsync(ct);
        await _auditRepo.SaveChangesAsync(ct);
        await _deviceRepo.SaveChangesAsync(ct);

        return Result<SelectBranchResponse>.Success(new SelectBranchResponse(
            AccessToken: accessToken,
            RefreshToken: refreshToken,
            ExpiresInSeconds: expiresIn,
            BaseUrl: middlewareUrl,
            CompanyName: company.Name,
            TenantId: company.Id,
            DeviceId: device.Id,
            BranchId: branch.Id,
            BranchName: branch.Name,
            ErpEmpresaId: branch.ErpEmpresaId
        ));
    }
}
