using Coliseu.Identity.Application.Auth.DTOs;
using Coliseu.Identity.Application.Auth.Handlers;
using Coliseu.Identity.Application.Auth.Handlers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador de autenticação de dispositivos.
///
/// Endpoints públicos (sem JWT), protegidos por Rate Limiting.
/// </summary>
[ApiController]
[Route("auth")]
public sealed class AuthController : ControllerBase
{
    private readonly DeviceLoginHandler _loginHandler;
    private readonly RefreshTokenHandler _refreshHandler;
    private readonly SelectBranchHandler _selectBranchHandler;

    public AuthController(DeviceLoginHandler loginHandler, RefreshTokenHandler refreshHandler, SelectBranchHandler selectBranchHandler)
    {
        _loginHandler = loginHandler;
        _refreshHandler = refreshHandler;
        _selectBranchHandler = selectBranchHandler;
    }

    /// <summary>
    /// Login de dispositivo via CompanyKey + DeviceUUID.
    /// Retorna JWT + Refresh Token + BaseUrl da Sales API.
    /// </summary>
    [HttpPost("device-login")]
    [EnableRateLimiting("DeviceLogin")]
    public async Task<IActionResult> DeviceLogin(
        [FromBody] DeviceLoginRequest request,
        CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _loginHandler.HandleAsync(request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>
    /// Refresh de JWT via Refresh Token rotativo.
    /// </summary>
    [HttpPost("refresh")]
    [EnableRateLimiting("DeviceLogin")]
    public async Task<IActionResult> Refresh(
        [FromBody] RefreshRequest request,
        CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _refreshHandler.HandleAsync(request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>
    /// Seleciona uma filial e gera um novo JWT restrito para ela.
    /// Requer que o dispositivo já esteja autenticado genéricamente com a empresa (DeviceJwt).
    /// </summary>
    [HttpPost("select-branch")]
    [Authorize(AuthenticationSchemes = "DeviceJwt")]
    [EnableRateLimiting("DeviceLogin")]
    public async Task<IActionResult> SelectBranch(
        [FromBody] SelectBranchRequest request,
        CancellationToken ct)
    {
        var tenantIdClaim = User.FindFirst("tenantId")?.Value;
        var deviceIdClaim = User.FindFirst("deviceId")?.Value;
        var moduleSlug = User.FindFirst("module")?.Value ?? "coliseu-sales";

        if (!Guid.TryParse(tenantIdClaim, out var companyId) || !Guid.TryParse(deviceIdClaim, out var deviceId))
            return Unauthorized(new { error = "Token inválido ou sem identificação de dispositivo." });

        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _selectBranchHandler.HandleAsync(
            companyId, deviceId, moduleSlug, request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }
}
