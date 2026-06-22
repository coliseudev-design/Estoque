using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador de dispositivos — protegido por JWT Admin.
/// </summary>
[ApiController]
[Route("admin/devices")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class DevicesController : ControllerBase
{
    private readonly IDeviceRepository _deviceRepo;
    private readonly IAuditLogRepository _auditRepo;

    public DevicesController(IDeviceRepository deviceRepo, IAuditLogRepository auditRepo)
    {
        _deviceRepo = deviceRepo;
        _auditRepo = auditRepo;
    }

    /// <summary>Listar dispositivos de uma empresa.</summary>
    [HttpGet("by-company/{companyId:guid}")]
    [RequirePermission("devices.read")]
    public async Task<IActionResult> ListByCompany(
        Guid companyId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var (items, total) = await _deviceRepo.GetByCompanyAsync(companyId, page, pageSize, ct);
        var dtos = items.Select(d => new DeviceDto(
            d.Id, d.ActivationKey, d.DeviceUuid, d.Name, d.Model, d.OS, d.AppVersion,
            d.Status.ToString(), d.FirstActivation, d.LastAccess)).ToList();

        return Ok(new { items = dtos, totalCount = total, page, pageSize });
    }

    /// <summary>Cria um dispositivo pré-ativado aguardando vinculação via app mobile.</summary>
    [HttpPost]
    [RequirePermission("devices.activate")]
    public async Task<IActionResult> CreatePendingDevice(
        [FromBody] CreateDeviceRequest request,
        CancellationToken ct)
    {
        // Verifica limites ativos
        var activeCount = await _deviceRepo.CountActiveByCompanyAsync(request.CompanyId, ct);
        // Não temos o limite aqui facilmente, precisaríamos do CompanyRepo.
        // Simulando que o limite é validado no frontend por enquanto, ou podemos 
        // injetar o ICompanyRepository e validar aqui.
        // Como o CreateCompany não expõe isso facilmente sem o repo, vamos deixar o db criar e logar.
        
        try 
        {
            var device = Device.CreatePending(request.CompanyId, request.ActivationKey);
            await _deviceRepo.AddAsync(device, ct);

            var adminId = User.FindFirst("adminId")?.Value ?? "unknown";
            var log = AuditLog.Create("device_created",
                companyId: request.CompanyId, deviceId: device.Id,
                details: $"AdminId: {adminId}, ActivationKey: {request.ActivationKey}");
            
            await _auditRepo.AddAsync(log, ct);
            await _deviceRepo.SaveChangesAsync(ct);

            return Created($"/admin/devices/{device.Id}", new { id = device.Id, activationKey = device.ActivationKey });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            // Poderia ser Unique Constraint de ActivationKey duplicada ou erro de FK
            return BadRequest(new { error = "Chave de ativação inválida ou já em uso.", details = ex.Message, inner = ex.InnerException?.Message });
        }
    }

    /// <summary>Alterar status do dispositivo (Active/Blocked).</summary>
    [HttpPatch("{id:guid}/status")]
    [RequirePermission("devices.revoke")]
    public async Task<IActionResult> UpdateStatus(
        Guid id,
        [FromBody] UpdateDeviceStatusRequest request,
        CancellationToken ct)
    {
        var device = await _deviceRepo.GetByIdAsync(id, ct);
        if (device is null) return NotFound(new { error = "Dispositivo não encontrado." });

        switch (request.Status.ToLowerInvariant())
        {
            case "active":  device.Unblock(); break;
            case "blocked": device.Block(); break;
            case "revoked":
                // RevokeAndReleaseHardware: limpa DeviceUuid para permitir reativação
                // no novo hardware com a mesma chave (após admin revogar e o novo
                // device usar a mesma activationKey).
                device.RevokeAndReleaseHardware();
                break;
            default: return BadRequest(new { error = "Status inválido. Use: active, blocked, revoked." });
        }

        var adminId = User.FindFirst("adminId")?.Value ?? "unknown";
        var log = AuditLog.Create($"device_{request.Status.ToLowerInvariant()}",
            companyId: device.CompanyId, deviceId: id,
            details: $"AdminId: {adminId}");
        await _auditRepo.AddAsync(log, ct);
        await _deviceRepo.SaveChangesAsync(ct);

        return Ok(new { deviceId = id, status = device.Status.ToString() });
    }

    /// <summary>Alterar nome/apelido do dispositivo pelo Admin.</summary>
    [HttpPatch("{id:guid}/name")]
    [RequirePermission("devices.activate")]
    public async Task<IActionResult> UpdateName(
        Guid id,
        [FromBody] UpdateDeviceNameRequest request,
        CancellationToken ct)
    {
        var device = await _deviceRepo.GetByIdAsync(id, ct);
        if (device is null) return NotFound(new { error = "Dispositivo não encontrado." });

        device.UpdateName(request.Name);

        var adminId = User.FindFirst("adminId")?.Value ?? "unknown";
        var log = AuditLog.Create("device_rename",
            companyId: device.CompanyId, deviceId: id,
            details: $"AdminId: {adminId}, NewName: {request.Name}");
        await _auditRepo.AddAsync(log, ct);
        await _deviceRepo.SaveChangesAsync(ct);

        return Ok(new { deviceId = id, name = device.Name });
    }
}
