using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador de logs de auditoria — protegido por JWT Admin.
/// </summary>
[ApiController]
[Route("admin/audit-logs")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class AuditController : ControllerBase
{
    private readonly IAuditLogRepository _auditRepo;

    public AuditController(IAuditLogRepository auditRepo) => _auditRepo = auditRepo;

    /// <summary>Listar logs de auditoria paginados com filtros.</summary>
    [HttpGet]
    [RequirePermission("audit.read")]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] Guid? companyId = null,
        [FromQuery] string? action = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? adminEmail = null,
        CancellationToken ct = default)
    {
        var (items, total) = await _auditRepo.GetAllAsync(
            page, pageSize, companyId, action, from, to, ct);

        // Filtro client-side por adminEmail (simples, sem adicionar param no repo agora)
        var filtered = string.IsNullOrWhiteSpace(adminEmail)
            ? items
            : items.Where(l => l.AdminEmail != null &&
                               l.AdminEmail.Contains(adminEmail, StringComparison.OrdinalIgnoreCase)).ToList();

        var dtos = filtered.Select(l => new AuditLogDto(
            l.Id, l.Action, l.CompanyId, l.DeviceId,
            l.IpAddress, l.Details, l.CreatedAt, l.AdminEmail)).ToList();

        return Ok(new PagedResult<AuditLogDto>(dtos, total, page, pageSize));
    }
}
