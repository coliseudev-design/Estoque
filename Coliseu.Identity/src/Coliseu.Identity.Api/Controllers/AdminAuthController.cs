using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Admin.Handlers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador de autenticação de administradores.
/// Gera JWT Admin (issuer separado do Device JWT).
/// </summary>
[ApiController]
[Route("admin/auth")]
public sealed class AdminAuthController : ControllerBase
{
    private readonly AdminLoginHandler _loginHandler;

    public AdminAuthController(AdminLoginHandler loginHandler)
    {
        _loginHandler = loginHandler;
    }

    /// <summary>Login de administrador via e-mail + senha.</summary>
    [HttpPost("login")]
    [EnableRateLimiting("AdminLogin")]
    public async Task<IActionResult> Login(
        [FromBody] AdminLoginRequest request,
        CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _loginHandler.HandleAsync(request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2FA — TOTP Real (Google Authenticator compatível)
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Segundo fator: valida código TOTP após login com senha.
    /// Chamado quando o login retorna requiresTwoFactor = true.
    /// Retorna o JWT completo se o código for válido.
    /// </summary>
    [HttpPost("2fa/verify")]
    [EnableRateLimiting("AdminLogin")]
    public async Task<IActionResult> Verify2fa(
        [FromBody] TotpVerifyRequest request,
        CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _loginHandler.VerifyTotpAsync(
            request.Email, request.TotpCode, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>
    /// Inicia o setup de 2FA para o admin autenticado.
    ///
    /// Fluxo:
    /// 1. Chamada inicial sem totpCode: retorna a URI otpauth:// para exibir o QR Code
    /// 2. Admin escaneia com Google Authenticator
    /// 3. Segunda chamada com totpCode: ativa o 2FA se o código estiver correto
    /// </summary>
    [HttpPost("2fa/setup")]
    [Authorize(AuthenticationSchemes = "AdminJwt")]
    public async Task<IActionResult> Setup2fa(
        [FromBody] TotpSetupRequest request,
        CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();

        var result = await _loginHandler.SetupTotpAsync(
            request.Email, request.TotpCode, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>Desativa o 2FA do admin autenticado (requer confirmação por senha no front).</summary>
    [HttpPost("2fa/disable")]
    [Authorize(AuthenticationSchemes = "AdminJwt")]
    public async Task<IActionResult> Disable2fa(CancellationToken ct)
    {
        // O e-mail é extraído do JWT — não aceito do body (Rule-03 segurança)
        var email = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
                 ?? User.FindFirst("email")?.Value;

        if (string.IsNullOrWhiteSpace(email))
            return Unauthorized(new { error = "Sessão inválida." });

        var result = await _loginHandler.DisableTotpAsync(email, ct: ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(new { message = "2FA desativado com sucesso." });
    }
}

