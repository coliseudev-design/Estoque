using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Gerencia módulos (produtos) ativos por empresa.
/// Cada módulo tem sua própria API Key, limite de dispositivos e URL de middleware.
/// </summary>
[ApiController]
[Route("admin/companies/{companyId:guid}/modules")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class CompanyModulesController : ControllerBase
{
    private readonly ICompanyRepository _companyRepo;
    private readonly ICompanyModuleRepository _moduleRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly ICompanyKeyGenerator _keyGen;
    private readonly IEncryptionService _encryption;

    public CompanyModulesController(
        ICompanyRepository companyRepo,
        ICompanyModuleRepository moduleRepo,
        IAuditLogRepository auditRepo,
        ICompanyKeyGenerator keyGen,
        IEncryptionService encryption)
    {
        _companyRepo = companyRepo;
        _moduleRepo  = moduleRepo;
        _auditRepo   = auditRepo;
        _keyGen      = keyGen;
        _encryption  = encryption;
    }

    /// <summary>Lista todos os módulos de uma empresa.</summary>
    [HttpGet]
    [RequirePermission("companies.read")]
    public async Task<IActionResult> List(Guid companyId, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(companyId, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        var modules = await _moduleRepo.GetByCompanyAsync(companyId, ct);
        return Ok(modules.Select(m => {
            string? decryptedKey = null;
            if (!string.IsNullOrEmpty(m.ApiKeyEncrypted))
            {
                try { decryptedKey = _encryption.Decrypt(m.ApiKeyEncrypted); }
                catch { /* Ignora */ }
            }
            return new CompanyModuleDto(
                m.Id, m.CompanyId, m.ModuleSlug, m.DeviceLimit,
                m.IsActive, m.MiddlewareBaseUrl, m.CreatedAt, decryptedKey, m.Versions);
        }));
    }

    /// <summary>
    /// Adiciona um módulo a uma empresa, gerando uma API Key automaticamente.
    /// A chave é exibida UMA única vez — o admin deve copiá-la imediatamente.
    /// </summary>
    [HttpPost]
    [RequirePermission("companies.create")]
    public async Task<IActionResult> AddModule(
        Guid companyId,
        [FromBody] AddModuleRequest request,
        CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(companyId, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        // Valida slug
        if (!ModuleSlugs.IsValid(request.ModuleSlug))
            return BadRequest(new { error = $"Slug '{request.ModuleSlug}' inválido. Valores: {string.Join(", ", ModuleSlugs.All)}" });

        // Verifica se o módulo já existe
        var existing = await _moduleRepo.GetByCompanyAndSlugAsync(companyId, request.ModuleSlug, ct);
        if (existing is not null)
            return Conflict(new { error = $"Módulo '{request.ModuleSlug}' já existe para esta empresa." });

        // Gera API Key
        var rawKey  = _keyGen.Generate();
        var keyHash = _keyGen.HashKey(rawKey);
        var encryptedKey = _encryption.Encrypt(rawKey);

        var module = CompanyModule.Create(
            companyId,
            request.ModuleSlug,
            keyHash,
            request.DeviceLimit,
            request.MiddlewareBaseUrl,
            encryptedKey,
            request.Versions);

        await _moduleRepo.AddAsync(module, ct);

        var log = AuditLog.CreateAdmin("module.added",
            GetAdminEmail(), companyId: companyId,
            details: $"Módulo '{request.ModuleSlug}' adicionado. DeviceLimit: {request.DeviceLimit}");
        await _auditRepo.AddAsync(log, ct);
        await _moduleRepo.SaveChangesAsync(ct);

        return Created($"/admin/companies/{companyId}/modules/{module.Id}",
            new AddModuleResponse(
                module.Id, companyId, module.ModuleSlug,
                rawKey,   // ← Exibida uma única vez
                module.DeviceLimit, module.MiddlewareBaseUrl, module.Versions));
    }

    /// <summary>Atualiza configurações do módulo (limit, URL, ativo).</summary>
    [HttpPut("{moduleId:guid}")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> UpdateModule(
        Guid companyId, Guid moduleId,
        [FromBody] UpdateModuleRequest request,
        CancellationToken ct)
    {
        var module = await _moduleRepo.GetByCompanyAndSlugAsync(companyId, request.ModuleSlug ?? string.Empty, ct)
            ?? await FindModuleByIdAsync(companyId, moduleId, ct);

        if (module is null) return NotFound(new { error = "Módulo não encontrado." });

        if (request.DeviceLimit.HasValue)
            module.SetDeviceLimit(request.DeviceLimit.Value);
        if (request.MiddlewareBaseUrl is not null)
            module.SetMiddlewareUrl(request.MiddlewareBaseUrl);
        if (request.IsActive.HasValue)
        {
            if (request.IsActive.Value) module.Activate();
            else module.Deactivate();
        }
        if (request.Versions is not null)
            module.SetVersions(request.Versions);

        var log = AuditLog.CreateAdmin("module.updated",
            GetAdminEmail(), companyId: companyId,
            details: $"Módulo '{module.ModuleSlug}' atualizado.");
        await _auditRepo.AddAsync(log, ct);
        await _moduleRepo.SaveChangesAsync(ct);

        string? decryptedKey = null;
        if (!string.IsNullOrEmpty(module.ApiKeyEncrypted))
        {
            try { decryptedKey = _encryption.Decrypt(module.ApiKeyEncrypted); }
            catch { /* Ignora */ }
        }

        return Ok(new CompanyModuleDto(
            module.Id, module.CompanyId, module.ModuleSlug,
            module.DeviceLimit, module.IsActive, module.MiddlewareBaseUrl, module.CreatedAt, decryptedKey, module.Versions));
    }

    /// <summary>
    /// Rotaciona a API Key do módulo.
    /// A nova chave é exibida UMA vez — inválida imediatamente a anterior.
    /// Apps e Workers precisam ser atualizados.
    /// </summary>
    [HttpPost("{moduleId:guid}/rotate-key")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> RotateKey(
        Guid companyId, Guid moduleId, CancellationToken ct)
    {
        var module = await FindModuleByIdAsync(companyId, moduleId, ct);
        if (module is null) return NotFound(new { error = "Módulo não encontrado." });

        var newKey  = _keyGen.Generate();
        var newHash = _keyGen.HashKey(newKey);
        var newEncrypted = _encryption.Encrypt(newKey);
        module.RotateApiKey(newHash, newEncrypted);

        var log = AuditLog.CreateAdmin("module.key_rotated",
            GetAdminEmail(), companyId: companyId,
            details: $"API Key do módulo '{module.ModuleSlug}' rotacionada.");
        await _auditRepo.AddAsync(log, ct);
        await _moduleRepo.SaveChangesAsync(ct);

        return Ok(new RotateModuleKeyResponse(
            module.Id, module.ModuleSlug, newKey));
    }

    /// <summary>Remove o módulo de uma empresa (SuperAdmin only).</summary>
    [HttpDelete("{moduleId:guid}")]
    [RequirePermission("companies.delete")]
    public async Task<IActionResult> RemoveModule(
        Guid companyId, Guid moduleId, CancellationToken ct)
    {
        var module = await FindModuleByIdAsync(companyId, moduleId, ct);
        if (module is null) return NotFound(new { error = "Módulo não encontrado." });

        var log = AuditLog.CreateAdmin("module.removed",
            GetAdminEmail(), companyId: companyId,
            details: $"Módulo '{module.ModuleSlug}' removido.");
        await _auditRepo.AddAsync(log, ct);

        await _moduleRepo.RemoveAsync(moduleId, ct);
        await _moduleRepo.SaveChangesAsync(ct);

        return Ok(new { message = $"Módulo '{module.ModuleSlug}' removido com sucesso." });
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private async Task<CompanyModule?> FindModuleByIdAsync(Guid companyId, Guid moduleId, CancellationToken ct)
    {
        var modules = await _moduleRepo.GetByCompanyAsync(companyId, ct);
        return modules.FirstOrDefault(m => m.Id == moduleId);
    }

    private string GetAdminEmail()
        => User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
           ?? User.FindFirst("email")?.Value
           ?? User.FindFirst("sub")?.Value
           ?? $"admin:{(User.FindFirst("adminId")?.Value ?? "unknown")[..8]}";
}
