using Coliseu.Identity.Application.Admin.Handlers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// CRUD de grupos de permissões RBAC.
/// Requer autenticação AdminJwt + role SuperAdmin.
/// </summary>
[ApiController]
[Route("admin/permission-groups")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class PermissionGroupsController : ControllerBase
{
    private readonly PermissionGroupHandler _handler;

    public PermissionGroupsController(PermissionGroupHandler handler)
    {
        _handler = handler;
    }

    /// <summary>Lista todos os grupos de permissões.</summary>
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await _handler.ListAsync(ct);
        return Ok(result.Value);
    }

    /// <summary>Cria um novo grupo de permissões.</summary>
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] UpsertPermissionGroupRequest request, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.CreateAsync(request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Created($"/admin/permission-groups/{result.Value!.Id}", result.Value);
    }

    /// <summary>Atualiza um grupo de permissões.</summary>
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpsertPermissionGroupRequest request, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.UpdateAsync(id, request, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(result.Value);
    }

    /// <summary>Remove um grupo de permissões.</summary>
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var ip = HttpContext.Connection.RemoteIpAddress?.ToString();
        var ua = Request.Headers.UserAgent.ToString();
        var result = await _handler.DeleteAsync(id, ip, ua, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Ok(new { message = "Grupo removido." });
    }

    /// <summary>Lista todas as permissões disponíveis no sistema.</summary>
    [HttpGet("available-permissions")]
    public IActionResult GetAvailablePermissions()
    {
        var permissions = new[]
        {
            new { Key = "companies.create", Label = "Cadastrar empresa", Module = "Empresas" },
            new { Key = "companies.read", Label = "Visualizar empresas", Module = "Empresas" },
            new { Key = "companies.update", Label = "Editar empresa", Module = "Empresas" },
            new { Key = "companies.delete", Label = "Remover empresa", Module = "Empresas" },
            new { Key = "devices.read", Label = "Visualizar dispositivos", Module = "Dispositivos" },
            new { Key = "devices.revoke", Label = "Revogar/bloquear licença", Module = "Dispositivos" },
            new { Key = "devices.activate", Label = "Ativar dispositivo", Module = "Dispositivos" },
            new { Key = "users.manage", Label = "Gerenciar usuários", Module = "Usuários" },
            new { Key = "audit.read", Label = "Visualizar audit trail", Module = "Auditoria" },
            new { Key = "settings.read", Label = "Visualizar configurações", Module = "Configurações" },
            new { Key = "webhooks.manage", Label = "Gerenciar webhooks", Module = "Webhooks" },
            new { Key = "kpi.read", Label = "Acessar KPI Dashboard", Module = "Analytics" },
            new { Key = "reports.read", Label = "Acessar relatórios", Module = "Analytics" },
            new { Key = "partners.create", Label = "Cadastrar parceiro", Module = "Parceiros" },
            new { Key = "partners.read", Label = "Visualizar parceiros", Module = "Parceiros" },
            new { Key = "partners.update", Label = "Editar parceiro", Module = "Parceiros" },
            new { Key = "partners.delete", Label = "Remover parceiro", Module = "Parceiros" },
            new { Key = "requests.create", Label = "Criar nova requisição", Module = "Requisições" },
            new { Key = "requests.read", Label = "Visualizar histórico de requisições", Module = "Requisições" },
            new { Key = "requests.approve", Label = "Aprovar / Recusar requisições (Apenas para Super Admins)", Module = "Requisições" },
        };

        return Ok(permissions);
    }
}
