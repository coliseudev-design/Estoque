using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador CRUD de parceiros integradores.
/// </summary>
[ApiController]
[Route("admin/partners")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class PartnersController : ControllerBase
{
    private readonly IPartnerRepository _partnerRepo;
    private readonly IAuditLogRepository _auditRepo;

    public PartnersController(
        IPartnerRepository partnerRepo,
        IAuditLogRepository auditRepo)
    {
        _partnerRepo = partnerRepo;
        _auditRepo = auditRepo;
    }

    /// <summary>Listar parceiros paginados.</summary>
    [HttpGet]
    [RequirePermission("partners.read")]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        CancellationToken ct = default)
    {
        var (items, total) = await _partnerRepo.GetAllAsync(page, pageSize, search, ct);
        var dtos = items.Select(p => new PartnerDto(
            p.Id, p.Name, p.Cnpj, p.ContactName, p.Email, p.Phone, p.CreatedAt, p.UpdatedAt
        )).ToList();

        return Ok(new PagedResult<PartnerDto>(dtos, total, page, pageSize));
    }

    /// <summary>Criar novo parceiro integrador.</summary>
    [HttpPost]
    [RequirePermission("partners.create")]
    public async Task<IActionResult> Create([FromBody] CreatePartnerRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Cnpj))
        {
            return BadRequest(new { error = "Nome e CNPJ são obrigatórios." });
        }

        var existing = await _partnerRepo.GetByCnpjAsync(request.Cnpj, ct);
        if (existing is not null)
        {
            return BadRequest(new { error = "Este CNPJ já está cadastrado para outro parceiro comercial." });
        }

        var partner = new Partner(
            Guid.NewGuid(),
            request.Name,
            request.Cnpj,
            request.ContactName,
            request.Email,
            request.Phone
        );

        await _partnerRepo.AddAsync(partner, ct);
        
        var log = AuditLog.CreateAdmin("partner_created", 
            adminEmail: GetAdminEmail(),
            details: $"Partner: {partner.Name} (CNPJ: {partner.Cnpj}) | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);
        
        await _partnerRepo.SaveChangesAsync(ct);

        var dto = new PartnerDto(
            partner.Id, partner.Name, partner.Cnpj, partner.ContactName, partner.Email, partner.Phone, partner.CreatedAt, partner.UpdatedAt
        );

        return CreatedAtAction(nameof(List), new { id = partner.Id }, dto);
    }

    /// <summary>Atualizar dados do parceiro integrador.</summary>
    [HttpPut("{id:guid}")]
    [RequirePermission("partners.update")]
    public async Task<IActionResult> Update(Guid id, [FromBody] CreatePartnerRequest request, CancellationToken ct)
    {
        var partner = await _partnerRepo.GetByIdAsync(id, ct);
        if (partner is null)
        {
            return NotFound(new { error = "Parceiro comercial não encontrado." });
        }

        var existingWithCnpj = await _partnerRepo.GetByCnpjAsync(request.Cnpj, ct);
        if (existingWithCnpj is not null && existingWithCnpj.Id != id)
        {
            return BadRequest(new { error = "Este CNPJ já está cadastrado para outro parceiro comercial." });
        }

        partner.Update(
            request.Name,
            request.Cnpj,
            request.ContactName,
            request.Email,
            request.Phone
        );

        var log = AuditLog.CreateAdmin("partner_updated", 
            adminEmail: GetAdminEmail(),
            details: $"PartnerId: {id} | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _partnerRepo.SaveChangesAsync(ct);

        var dto = new PartnerDto(
            partner.Id, partner.Name, partner.Cnpj, partner.ContactName, partner.Email, partner.Phone, partner.CreatedAt, partner.UpdatedAt
        );

        return Ok(dto);
    }

    /// <summary>Excluir parceiro integrador.</summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("partners.delete")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var partner = await _partnerRepo.GetByIdAsync(id, ct);
        if (partner is null)
        {
            return NotFound(new { error = "Parceiro comercial não encontrado." });
        }

        await _partnerRepo.DeleteAsync(id, ct);

        var log = AuditLog.CreateAdmin("partner_deleted", 
            adminEmail: GetAdminEmail(),
            details: $"PartnerId: {id} ({partner.Name}) | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _partnerRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Parceiro removido com sucesso." });
    }

    private Guid GetAdminId()
        => Guid.TryParse(User.FindFirst("adminId")?.Value, out var id) ? id : Guid.Empty;

    private string GetAdminEmail()
        => User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
           ?? User.FindFirst("email")?.Value
           ?? User.FindFirst("sub")?.Value
           ?? $"admin:{GetAdminId().ToString()[..8]}";
}
