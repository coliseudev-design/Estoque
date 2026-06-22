using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

[ApiController]
[Route("admin/companies/{companyId:guid}/branches")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class BranchesController : ControllerBase
{
    private readonly IBranchRepository _branchRepo;
    private readonly ICompanyRepository _companyRepo;
    private readonly IAuditLogRepository _auditRepo;

    public BranchesController(
        IBranchRepository branchRepo,
        ICompanyRepository companyRepo,
        IAuditLogRepository auditRepo)
    {
        _branchRepo = branchRepo;
        _companyRepo = companyRepo;
        _auditRepo = auditRepo;
    }

    [HttpGet]
    [RequirePermission("companies.read")]
    public async Task<IActionResult> List(Guid companyId, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(companyId, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        var branches = await _branchRepo.GetByCompanyAsync(companyId, ct);
        var dtos = branches.Select(b => new
        {
            b.Id,
            b.Name,
            b.Cnpj,
            b.ErpEmpresaId,
            b.ErpDeptoPadrao,
            b.ErpCentroPadrao,
            b.IsDefault,
            Status = b.Status.ToString(),
            b.CreatedAt
        });

        return Ok(dtos);
    }

    [HttpPost]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> Create(Guid companyId, [FromBody] CreateBranchRequest req, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(companyId, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        if (await _branchRepo.GetByErpIdAsync(companyId, req.ErpEmpresaId, ct) is not null)
            return BadRequest(new { error = "Já existe uma filial com este ID do ERP para esta empresa." });

        // Se for a primeira filial, marca como default obrigatoriamente
        var existingBranches = await _branchRepo.GetByCompanyAsync(companyId, ct);
        var isDefault = existingBranches.Count == 0 || req.IsDefault;

        if (isDefault)
        {
            // Remove o default das outras
            foreach (var b in existingBranches.Where(x => x.IsDefault))
            {
                b.SetDefault(false);
            }
        }

        var branch = Branch.Create(
            companyId, req.Name, req.ErpEmpresaId, req.ErpDeptoPadrao, req.ErpCentroPadrao, isDefault, req.Cnpj);

        await _branchRepo.AddAsync(branch, ct);

        var adminEmail = GetAdminEmail();
        var adminId = GetAdminId();
        await _auditRepo.AddAsync(AuditLog.CreateAdmin("branch.created", adminEmail, companyId, $"AdminId: {adminId} | Name: {req.Name} | ErpId: {req.ErpEmpresaId}"), ct);

        await _branchRepo.SaveChangesAsync(ct);

        return Created($"/admin/companies/{companyId}/branches/{branch.Id}", new
        {
            branch.Id,
            branch.Name,
            branch.IsDefault
        });
    }

    [HttpPut("{branchId:guid}")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> Update(Guid companyId, Guid branchId, [FromBody] UpdateBranchRequest req, CancellationToken ct)
    {
        var branch = await _branchRepo.GetByIdAsync(branchId, ct);
        if (branch is null || branch.CompanyId != companyId)
            return NotFound(new { error = "Filial não encontrada." });

        if (branch.ErpEmpresaId != req.ErpEmpresaId)
        {
            var conflictingBranch = await _branchRepo.GetByErpIdAsync(companyId, req.ErpEmpresaId, ct);
            if (conflictingBranch is not null && conflictingBranch.Id != branchId)
                return BadRequest(new { error = "Já existe outra filial com este ID do ERP." });
        }

        branch.UpdateDetails(req.Name, req.Cnpj, req.ErpEmpresaId, req.ErpDeptoPadrao, req.ErpCentroPadrao);

        if (req.IsDefault && !branch.IsDefault)
        {
            var existingBranches = await _branchRepo.GetByCompanyAsync(companyId, ct);
            foreach (var b in existingBranches.Where(x => x.IsDefault && x.Id != branchId))
            {
                b.SetDefault(false);
            }
            branch.SetDefault(true);
        }

        var adminEmail = GetAdminEmail();
        var adminId = GetAdminId();
        await _auditRepo.AddAsync(AuditLog.CreateAdmin("branch.updated", adminEmail, companyId, $"AdminId: {adminId} | Branch: {req.Name}"), ct);

        await _branchRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Filial atualizada com sucesso." });
    }

    [HttpDelete("{branchId:guid}")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> Delete(Guid companyId, Guid branchId, CancellationToken ct)
    {
        var branch = await _branchRepo.GetByIdAsync(branchId, ct);
        if (branch is null || branch.CompanyId != companyId)
            return NotFound(new { error = "Filial não encontrada." });

        if (branch.IsDefault)
            return BadRequest(new { error = "Não é possível excluir a filial padrão. Defina outra como padrão antes." });

        await _branchRepo.DeleteAsync(branchId, ct);

        var adminEmail = GetAdminEmail();
        var adminId = GetAdminId();
        await _auditRepo.AddAsync(AuditLog.CreateAdmin("branch.deleted", adminEmail, companyId, $"AdminId: {adminId} | Branch: {branch.Name}"), ct);

        await _branchRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Filial excluída com sucesso." });
    }

    private Guid GetAdminId()
        => Guid.TryParse(User.FindFirst("adminId")?.Value, out var id) ? id : Guid.Empty;

    private string GetAdminEmail()
        => User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
           ?? User.FindFirst("email")?.Value
           ?? User.FindFirst("sub")?.Value
           ?? $"admin:{GetAdminId().ToString()[..8]}";
}

public sealed record CreateBranchRequest(
    string Name,
    string? Cnpj,
    int ErpEmpresaId,
    int ErpDeptoPadrao,
    int ErpCentroPadrao,
    bool IsDefault
);

public sealed record UpdateBranchRequest(
    string Name,
    string? Cnpj,
    int ErpEmpresaId,
    int ErpDeptoPadrao,
    int ErpCentroPadrao,
    bool IsDefault
);
