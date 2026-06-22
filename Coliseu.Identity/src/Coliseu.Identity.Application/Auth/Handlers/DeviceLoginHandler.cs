using Coliseu.Identity.Application.Auth.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Auth.Handlers;

/// <summary>
/// Handler para login de dispositivo via CompanyKey + DeviceUUID ou ActivationKey.
///
/// Fluxo:
/// 1. Determina o módulo solicitado (padrão: "coliseu-sales" para backward compat)
/// 2. Hash da CompanyKey → busca empresa / ou busca por ActivationKey
/// 3. Valida status da empresa (ativa?)
/// 4. Valida se o módulo está ativo para a empresa
/// 5. Busca ou registra dispositivo no módulo correto
/// 6. Verifica limite de dispositivos do módulo
/// 7. Valida status do dispositivo
/// 8. Gera JWT + Refresh Token (JWT inclui module_slug no claim)
/// 9. Registra sessão + auditoria
/// </summary>
public sealed class DeviceLoginHandler
{
    private readonly ICompanyRepository _companyRepo;
    private readonly IDeviceRepository _deviceRepo;
    private readonly ISessionRepository _sessionRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly ICompanyModuleRepository _moduleRepo;
    private readonly IJwtService _jwt;
    private readonly ICompanyKeyGenerator _keyGen;

    /// <summary>
    /// URL de fallback para o módulo coliseu-sales quando não há CompanyModule configurado.
    /// Garante backward compatibility com devices existentes.
    /// </summary>
    private readonly string _salesApiBaseUrl;

    /// <summary>Dias de validade do Refresh Token — configurado em appsettings Jwt:RefreshTokenDays.</summary>
    private readonly int _refreshTokenDays;

    public DeviceLoginHandler(
        ICompanyRepository companyRepo,
        IDeviceRepository deviceRepo,
        ISessionRepository sessionRepo,
        IAuditLogRepository auditRepo,
        IJwtService jwt,
        ICompanyKeyGenerator keyGen,
        string salesApiBaseUrl,
        int refreshTokenDays = 30,
        ICompanyModuleRepository? moduleRepo = null)
    {
        _companyRepo = companyRepo;
        _deviceRepo = deviceRepo;
        _sessionRepo = sessionRepo;
        _auditRepo = auditRepo;
        _jwt = jwt;
        _keyGen = keyGen;
        _salesApiBaseUrl = salesApiBaseUrl;
        _refreshTokenDays = refreshTokenDays;
        // moduleRepo pode ser null em ambientes de teste (backward compat)
        _moduleRepo = moduleRepo!;
    }

    /// <summary>Processa login de dispositivo com suporte a múltiplos módulos.</summary>
    public async Task<Result<DeviceLoginResponse>> HandleAsync(
        DeviceLoginRequest request,
        string? ipAddress,
        string? userAgent,
        CancellationToken ct = default)
    {
        // Determina o módulo: se não informado, assume coliseu-sales (backward compat)
        var moduleSlug = string.IsNullOrWhiteSpace(request.ModuleSlug)
            ? ModuleSlugs.ColiseuSales
            : request.ModuleSlug.Trim().ToLowerInvariant();

        Device? device = null;
        Company? company = null;

        // 1. Busca por ActivationKey (Primeiro acesso / LinkHardware)
        if (!string.IsNullOrWhiteSpace(request.ActivationKey))
        {
            device = await _deviceRepo.GetByActivationKeyAsync(request.ActivationKey, ct);
            if (device is null)
            {
                await AuditAsync("device_login_failed", ipAddress: ipAddress,
                    userAgent: userAgent, details: "ActivationKey inválida");
                return Result<DeviceLoginResponse>.Forbidden("Chave de ativação inválida ou não encontrada.");
            }

            company = await _companyRepo.GetByIdAsync(device.CompanyId, ct);

            // NOVO: Validação em Camada Dupla (API Key + Activation Key)
            if (!string.IsNullOrWhiteSpace(request.CompanyKey))
            {
                var keyHash = _keyGen.HashKey(request.CompanyKey);
                bool isValidKey = company?.CompanyKeyHash == keyHash;
                
                if (!isValidKey && _moduleRepo is not null && company is not null)
                {
                    var module = await _moduleRepo.GetByApiKeyHashAsync(keyHash, ct);
                    if (module is not null && module.CompanyId == company.Id)
                    {
                        isValidKey = true;
                        moduleSlug = module.ModuleSlug; // Alinha o fluxo com a chave do módulo
                    }
                }

                if (!isValidKey)
                {
                    await AuditAsync("device_login_failed", companyId: company?.Id,
                        deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                        details: "Chave de API (CompanyKey) da ativação é inválida ou incompatível.");
                    return Result<DeviceLoginResponse>.Forbidden("A Chave de API não corresponde a esta empresa/dispositivo.");
                }
            }

            // Realiza o vínculo do UUID (primeiro acesso, reinstalação, ou troca de dispositivo)
            if (string.IsNullOrWhiteSpace(device.DeviceUuid))
            {
                // ── Primeiro vínculo: verifica se outro device já usa este UUID neste módulo ──
                var existingByUuid = await _deviceRepo.GetByUuidAndCompanyAsync(
                    request.DeviceUuid, device.CompanyId, ct);

                if (existingByUuid is not null && existingByUuid.Id != device.Id)
                {
                    await AuditAsync("device_login_failed", companyId: company?.Id,
                        deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                        details: $"UUID {request.DeviceUuid} já está vinculado a outro device nesta empresa");
                    return Result<DeviceLoginResponse>.Forbidden(
                        "Este dispositivo já está registrado com outra chave de ativação. " +
                        "Contate o administrador para revogar o dispositivo anterior.");
                }

                device.LinkHardware(request.DeviceUuid, request.Model, request.OS, request.AppVersion);
                await AuditAsync("device_hardware_linked", companyId: company?.Id,
                    deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                    details: $"Hardware {request.DeviceUuid} vinculado via ActivationKey. Módulo: {moduleSlug}");
            }
            else if (device.DeviceUuid != request.DeviceUuid)
            {
                // ── SEGURANÇA: Re-bind bloqueado ────────────────────────────────────────
                // O hardware já está vinculado a outro ANDROID_ID/UUID.
                // Admin deve clicar "Revogar" → DeviceUuid é limpo → novo device pode ativar.
                await AuditAsync("device_rebind_blocked", companyId: company?.Id,
                    deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                    details: $"Re-bind bloqueado: hardware existente={device.DeviceUuid} | " +
                             $"tentativa={request.DeviceUuid}");
                return Result<DeviceLoginResponse>.Forbidden(
                    "Esta chave de ativação já está vinculada ao hardware de outro dispositivo. " +
                    "Solicite ao administrador que revogue este dispositivo para transferi-lo.");
            }
            else
            {
                device.RecordAccess(request.Model, request.OS, request.AppVersion);
            }
        }
        // 2. Busca tradicional por CompanyKey + DeviceUuid (Acessos subsequentes)
        else if (!string.IsNullOrWhiteSpace(request.CompanyKey))
        {
            var keyHash = _keyGen.HashKey(request.CompanyKey);
            company = await _companyRepo.GetByKeyHashAsync(keyHash, ct);

            if (company is null && _moduleRepo is not null)
            {
                var module = await _moduleRepo.GetByApiKeyHashAsync(keyHash, ct);
                if (module is not null)
                {
                    company = module.Company;
                    moduleSlug = module.ModuleSlug; // Força slug
                }
            }

            if (company is null)
            {
                await AuditAsync("device_login_failed", ipAddress: ipAddress,
                    userAgent: userAgent, details: "CompanyKey inválida (nem no mestre, nem nos módulos)");
                return Result<DeviceLoginResponse>.Forbidden("Chave de API inválida.");
            }

            device = await _deviceRepo.GetByUuidAndCompanyAsync(request.DeviceUuid, company.Id, ct);

            if (device is null)
            {
                await AuditAsync("device_login_failed", companyId: company.Id,
                    ipAddress: ipAddress, userAgent: userAgent,
                    details: "UUID não encontrado/autorizado nesta empresa.");
                return Result<DeviceLoginResponse>.Forbidden("Dispositivo não encontrado ou não autorizado.");
            }

            device.RecordAccess(request.Model, request.OS, request.AppVersion);
        }
        else
        {
             return Result<DeviceLoginResponse>.Forbidden("É necessário informar CompanyKey ou Chave de Ativação.");
        }

        // 3. Valida status da empresa
        if (company is null || !company.IsOperational)
        {
            await AuditAsync("device_login_failed", companyId: company?.Id,
                ipAddress: ipAddress, userAgent: userAgent,
                details: $"Empresa {company?.Status}");
            return Result<DeviceLoginResponse>.Forbidden(
                $"Empresa '{company?.Name}' não está operacional no momento.");
        }

        // 4. Valida módulo e obtém URL do middleware correspondente
        // Se o repositório de módulos não estiver disponível (legacy) ou o módulo for coliseu-sales
        // e não houver registro de CompanyModule, usa o _salesApiBaseUrl como fallback.
        string middlewareUrl = _salesApiBaseUrl;
        if (_moduleRepo is not null)
        {
            var companyModule = await _moduleRepo.GetByCompanyAndSlugAsync(company.Id, moduleSlug, ct);

            if (companyModule is null)
            {
                // Módulo não está habilitado para esta empresa — exceto para coliseu-sales sem CompanyModules
                // (empresas migradas do sistema legado ainda não têm registros em company_modules)
                if (moduleSlug != ModuleSlugs.ColiseuSales)
                {
                    await AuditAsync("device_login_failed", companyId: company.Id,
                        deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                        details: $"Módulo '{moduleSlug}' não habilitado para esta empresa.");
                    return Result<DeviceLoginResponse>.Forbidden(
                        $"O módulo '{moduleSlug}' não está habilitado para esta empresa. " +
                        "Contate o administrador.");
                }
                // coliseu-sales sem CompanyModule: usa URL de fallback (backward compat)
            }
            else
            {
                if (!companyModule.IsActive)
                {
                    await AuditAsync("device_login_failed", companyId: company.Id,
                        deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                        details: $"Módulo '{moduleSlug}' desativado.");
                    return Result<DeviceLoginResponse>.Forbidden(
                        $"O módulo '{moduleSlug}' está desativado para esta empresa.");
                }

                // Usa a URL configurada no módulo (pode sobrescrever o fallback)
                if (!string.IsNullOrWhiteSpace(companyModule.MiddlewareBaseUrl))
                    middlewareUrl = companyModule.MiddlewareBaseUrl;
            }
        }

        // 5. Valida status do dispositivo
        if (!device.CanAuthenticate)
        {
            await AuditAsync("device_login_failed", companyId: company.Id,
                deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
                details: $"Dispositivo {device.Status}");
            return Result<DeviceLoginResponse>.Forbidden(
                $"Dispositivo '{device.DeviceUuid}' está {device.Status.ToString().ToLower()}.");
        }

        // 6. Gerar JWT (inclui module_slug no payload para validação no middleware)
        var (accessToken, expiresIn) = _jwt.GenerateDeviceToken(
            company.Id, device.Id, company.Name, moduleSlug);

        // 7. Gerar Refresh Token (rotativo: revoga anteriores)
        await _sessionRepo.RevokeAllByDeviceAsync(device.Id, ct);
        var refreshToken = TokenGenerator.GenerateRefreshToken();
        var session = Session.Create(
            device.Id, refreshToken, DateTime.UtcNow.AddDays(_refreshTokenDays));
        await _sessionRepo.AddAsync(session, ct);

        // 8. Auditoria de sucesso
        await AuditAsync("device_login_success", companyId: company.Id,
            deviceId: device.Id, ipAddress: ipAddress, userAgent: userAgent,
            details: $"Módulo: {moduleSlug}");

        // Persistir todas as alterações
        await _deviceRepo.SaveChangesAsync(ct);

        return Result<DeviceLoginResponse>.Success(new DeviceLoginResponse(
            AccessToken: accessToken,
            RefreshToken: refreshToken,
            ExpiresInSeconds: expiresIn,
            BaseUrl: middlewareUrl,
            CompanyName: company.Name,
            TenantId: company.Id,
            DeviceId: device.Id));
    }

    private async Task AuditAsync(
        string action, Guid? companyId = null, Guid? deviceId = null,
        string? ipAddress = null, string? userAgent = null, string? details = null)
    {
        var log = AuditLog.Create(action, companyId, deviceId, ipAddress, userAgent, details);
        await _auditRepo.AddAsync(log);
    }
}
