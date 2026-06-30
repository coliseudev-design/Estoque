namespace Coliseu.Identity.Application.Auth.DTOs;

/// <summary>Request para login de dispositivo via CompanyKey ou ActivationKey.</summary>
public sealed record DeviceLoginRequest(
    string? CompanyKey,
    string? ActivationKey,
    string DeviceUuid,
    string? Model,
    string? OS,
    string? AppVersion,
    /// <summary>
    /// Slug do módulo/produto. Ex: "coliseu-speed" | "autocenter".
    /// Campo opcional — ausência ou null assume "coliseu-speed" (backward compatible).
    /// </summary>
    string? ModuleSlug = null);

/// <summary>Response de login de dispositivo com tokens JWT.</summary>
public sealed record DeviceLoginResponse(
    string AccessToken,
    string RefreshToken,
    int ExpiresInSeconds,
    string BaseUrl,
    string CompanyName,
    Guid TenantId,
    Guid DeviceId);

/// <summary>Request para refresh de token.</summary>
public sealed record RefreshRequest(string RefreshToken);

/// <summary>Response de refresh de token.</summary>
public sealed record RefreshResponse(
    string AccessToken,
    string RefreshToken,
    int ExpiresInSeconds);
