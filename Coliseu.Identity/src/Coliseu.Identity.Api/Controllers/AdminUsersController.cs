using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Api.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// CRUD de usuários administradores do painel.
/// Requer autenticação AdminJwt + role SuperAdmin.
/// </summary>
[ApiController]
[Route("admin/users")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class AdminUsersController : ControllerBase
{
    private readonly AdminUsersHandler _handler;

    public AdminUsersController(AdminUsersHandler handler)
    {
        _handler = handler;
    }

    /// <summary>Lista todos os admin users.</summary>
    [HttpGet]
    [RequirePermission("users.manage")]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await _handler.ListAsync(ct);
        return Ok(result.Value);
    }

    /// <summary>Cria um novo admin user.</summary>
    [HttpPost]
    [RequirePermission("users.manage")]
    public async Task<IActionResult> Create(
        [FromBody] CreateAdminUserRequest request, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.CreateAsync(request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Created($"/admin/users/{result.Value!.Id}", result.Value);
    }

    /// <summary>Atualiza um admin user.</summary>
    [HttpPut("{id:guid}")]
    [RequirePermission("users.manage")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdateAdminUserRequest request, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.UpdateAsync(id, request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>Desativa (soft delete) um admin user.</summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("users.manage")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.DeleteAsync(id, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(new { message = "Usuário desativado." });
    }

    /// <summary>Reset de senha de um admin user.</summary>
    [HttpPost("{id:guid}/reset-password")]
    [RequirePermission("users.manage")]
    public async Task<IActionResult> ResetPassword(
        Guid id, [FromBody] ResetPasswordRequest request, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.ResetPasswordAsync(id, request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(new { message = "Senha alterada com sucesso." });
    }
}
