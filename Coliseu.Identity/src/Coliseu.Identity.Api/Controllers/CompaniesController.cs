using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text;
using System.Text.Json;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador CRUD de empresas — protegido por JWT Admin.
/// </summary>
[ApiController]
[Route("admin/companies")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class CompaniesController : ControllerBase
{
    private readonly ICompanyRepository _companyRepo;
    private readonly IDeviceRepository _deviceRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly CreateCompanyHandler _createHandler;
    private readonly IEncryptionService _encryption;
    private readonly ICompanyKeyGenerator _keyGen;
    private readonly IHttpClientFactory _httpFactory;
    private readonly IConfiguration _config;

    public CompaniesController(
        ICompanyRepository companyRepo,
        IDeviceRepository deviceRepo,
        IAuditLogRepository auditRepo,
        CreateCompanyHandler createHandler,
        IEncryptionService encryption,
        ICompanyKeyGenerator keyGen,
        IHttpClientFactory httpFactory,
        IConfiguration config)
    {
        _companyRepo    = companyRepo;
        _deviceRepo     = deviceRepo;
        _auditRepo      = auditRepo;
        _createHandler  = createHandler;
        _encryption     = encryption;
        _keyGen         = keyGen;
        _httpFactory    = httpFactory;
        _config         = config;
    }

    /// <summary>Listar empresas paginadas.</summary>
    [HttpGet]
    [RequirePermission("companies.read")]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        CancellationToken ct = default)
    {
        var (items, total) = await _companyRepo.GetAllAsync(page, pageSize, search, ct);
        var dtos = new List<CompanyDto>();
        foreach (var c in items)
        {
            var activeDevices = await _deviceRepo.CountActiveByCompanyAsync(c.Id, ct);
            dtos.Add(new CompanyDto(c.Id, c.Name, c.ContactEmail, c.Status.ToString(), c.DeviceLimit, activeDevices, c.CreatedAt, c.LogoBase64 != null));
        }
        return Ok(new PagedResult<CompanyDto>(dtos, total, page, pageSize));
    }

    /// <summary>Detalhes da empresa.</summary>
    [HttpGet("{id:guid}")]
    [RequirePermission("companies.read")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        var activeDevices = await _deviceRepo.CountActiveByCompanyAsync(id, ct);
        
        string? decryptedKey = null;
        if (!string.IsNullOrEmpty(company.CompanyKeyEncrypted))
        {
            try { decryptedKey = _encryption.Decrypt(company.CompanyKeyEncrypted); }
            catch { /* Ignora erro de descriptografia e retorna null */ }
        }

        return Ok(new CompanyDto(company.Id, company.Name, company.ContactEmail, company.Status.ToString(),
            company.DeviceLimit, activeDevices, company.CreatedAt, company.LogoBase64 != null, company.PriceTableMode, company.AllowNegativeStock, decryptedKey));
    }

    /// <summary>Cadastrar nova empresa (requer permissão companies.create).</summary>
    [HttpPost]
    [RequirePermission("companies.create")]
    public async Task<IActionResult> Create(
        [FromBody] CreateCompanyRequest request,
        CancellationToken ct)
    {
        var adminId = GetAdminId();
        var result = await _createHandler.HandleAsync(request, adminId, ct);

        if (!result.IsSuccess)
            return StatusCode(result.StatusCode ?? 400, new { error = result.Error });

        return Created($"/admin/companies/{result.Value!.CompanyId}", result.Value);
    }

    /// <summary>Alterar status da empresa (SuperAdmin only).</summary>
    [HttpPatch("{id:guid}/status")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> UpdateStatus(
        Guid id,
        [FromBody] UpdateCompanyStatusRequest request,
        CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        switch (request.Status.ToLowerInvariant())
        {
            case "active": company.Activate(); break;
            case "suspended": company.Suspend(); break;
            case "blocked": company.Block(); break;
            default: return BadRequest(new { error = "Status inválido. Use: active, suspended, blocked." });
        }

        var log = AuditLog.CreateAdmin($"company_{request.Status.ToLowerInvariant()}",
            GetAdminEmail(), companyId: id,
            details: $"Status alterado para '{request.Status}'");
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        return Ok(new { status = company.Status.ToString() });
    }

    /// <summary>Atualizar dados gerais da empresa (nome, email, limite, status).</summary>
    [HttpPut("{id:guid}")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> Update(
        Guid id,
        [FromBody] UpdateCompanyRequest request,
        CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        // Monta detalhes do diff para auditoria
        var diffParts = new List<string>();
        if (company.Name != request.Name && request.Name is not null)
            diffParts.Add($"Nome: '{company.Name}' → '{request.Name}'");
        if (company.DeviceLimit != request.DeviceLimit)
            diffParts.Add($"Dispositivos: {company.DeviceLimit} → {request.DeviceLimit}");
        if (company.ContactEmail != request.ContactEmail && request.ContactEmail is not null)
            diffParts.Add($"Email: '{company.ContactEmail ?? "-"}' → '{request.ContactEmail}'");
        if (request.Status is not null)
            diffParts.Add($"Status: → '{request.Status}'");
        if (request.PriceTableMode is not null)
            diffParts.Add($"TabelaPreco: → '{request.PriceTableMode}'");
        if (request.AllowNegativeStock.HasValue)
            diffParts.Add($"EstoqueNegativo: → {request.AllowNegativeStock.Value}");
        var diffDetails = diffParts.Count > 0 ? string.Join(" | ", diffParts) : "Sem alterações detectadas";

        company.UpdateDetails(request.Name, request.ContactEmail, request.DeviceLimit);

        if (!string.IsNullOrWhiteSpace(request.Status))
        {
            switch (request.Status.ToLowerInvariant())
            {
                case "active": company.Activate(); break;
                case "suspended": company.Suspend(); break;
                case "blocked": company.Block(); break;
            }
        }

        if (!string.IsNullOrWhiteSpace(request.PriceTableMode))
        {
            try { company.SetPriceTableMode(request.PriceTableMode); }
            catch (ArgumentException ex) { return BadRequest(new { error = ex.Message }); }
        }

        if (request.AllowNegativeStock.HasValue)
            company.SetAllowNegativeStock(request.AllowNegativeStock.Value);

        var log = AuditLog.CreateAdmin("company.updated",
            GetAdminEmail(), companyId: id, details: diffDetails);
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        string? decryptedKey = null;
        if (!string.IsNullOrEmpty(company.CompanyKeyEncrypted))
        {
            try { decryptedKey = _encryption.Decrypt(company.CompanyKeyEncrypted); }
            catch { /* Ignora erro de descriptografia e retorna null */ }
        }

        var activeDevices2 = await _deviceRepo.CountActiveByCompanyAsync(id, ct);
        return Ok(new CompanyDto(company.Id, company.Name, company.ContactEmail,
            company.Status.ToString(), company.DeviceLimit, activeDevices2, company.CreatedAt, company.LogoBase64 != null, company.PriceTableMode, company.AllowNegativeStock, decryptedKey));
    }

    /// <summary>Upload de logo da empresa (Base64-encoded PNG/JPG, max 500KB).</summary>
    [HttpPut("{id:guid}/logo")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> UploadLogo(
        Guid id,
        [FromBody] UpdateLogoRequest request,
        CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        try
        {
            company.UpdateLogo(request.LogoBase64);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }

        var log = AuditLog.Create("company_logo_updated",
            companyId: id, details: $"AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Logo atualizada com sucesso." });
    }

    /// <summary>Retorna a logo da empresa como imagem (bytes).</summary>
    [HttpGet("{id:guid}/logo")]
    [AllowAnonymous]
    public async Task<IActionResult> GetLogo(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });
        if (string.IsNullOrEmpty(company.LogoBase64)) return NotFound(new { error = "Nenhuma logo cadastrada." });

        // Remove prefixo data:image/... se presente
        var base64 = company.LogoBase64;
        var contentType = "image/png";
        if (base64.StartsWith("data:"))
        {
            var commaIdx = base64.IndexOf(',');
            if (commaIdx > 0)
            {
                var header = base64[..commaIdx];
                if (header.Contains("jpeg") || header.Contains("jpg")) contentType = "image/jpeg";
                base64 = base64[(commaIdx + 1)..];
            }
        }

        var bytes = Convert.FromBase64String(base64);
        return File(bytes, contentType);
    }

    /// <summary>Remove a logo da empresa.</summary>
    [HttpDelete("{id:guid}/logo")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> DeleteLogo(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        company.RemoveLogo();

        var log = AuditLog.Create("company_logo_removed",
            companyId: id, details: $"AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Logo removida com sucesso." });
    }

    /// <summary>Excluir empresa permanentemente (SuperAdmin only).</summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("companies.delete")]
    public async Task<IActionResult> DeleteCompany(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        var log = AuditLog.CreateAdmin("company.deleted",
            GetAdminEmail(), companyId: id,
            details: $"Empresa '{company.Name}' excluída permanentemente");
        await _auditRepo.AddAsync(log, ct);

        await _companyRepo.DeleteAsync(id, ct);
        await _companyRepo.SaveChangesAsync(ct);

        // Notifica o middleware Sales API para excluir todos os dados do tenant no PostgreSQL
        // Best-effort: falha de sync não cancela a exclusão na Identity DB
        await SyncDeleteWithMiddlewareAsync(id);

        return Ok(new { message = "Empresa excluída com sucesso.", companyId = id });
    }

    /// <summary>Atualizar credenciais Firebird (SuperAdmin only).</summary>
    [HttpPut("{id:guid}/firebird")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> UpdateFirebird(
        Guid id,
        [FromBody] UpdateFirebirdRequest request,
        CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        var encryptedPassword = _encryption.Encrypt(request.Password);
        company.UpdateFirebirdCredentials(
            request.Host, request.DatabasePath, request.User, encryptedPassword);

        var log = AuditLog.Create("company_firebird_updated",
            companyId: id, details: $"AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Credenciais Firebird atualizadas." });
    }

    /// <summary>
    /// Re-gera a CompanyKey (API Key) da empresa.
    ///
    /// A nova chave é exibida UMA VEZ na resposta.
    /// O admin deve copiá-la imediatamente e configurar no app mobile e no Worker.
    /// SuperAdmin only — ação irreversível que invalida a chave anterior.
    ///
    /// Além de salvar na Identity DB, notifica o middleware Sales API
    /// para atualizar o SHA-256 na tabela companies do PostgreSQL do middleware.
    /// </summary>
    [HttpPost("{id:guid}/rotate-key")]
    [RequirePermission("companies.update")]
    public async Task<IActionResult> RotateKey(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });

        // Gera nova chave e hash usando o mesmo generator do CreateCompany
        var newKey  = _keyGen.Generate();
        var newHash = _keyGen.HashKey(newKey);
        var newEncrypted = _encryption.Encrypt(newKey);

        company.RotateCompanyKey(newHash, newEncrypted);

        var log = AuditLog.Create("company_key_rotated",
            companyId: id, details: $"AdminId: {GetAdminId()} — chave anterior invalidada");
        await _auditRepo.AddAsync(log, ct);
        await _companyRepo.SaveChangesAsync(ct);

        // Notifica o middleware Sales API para sincronizar o hash no seu PostgreSQL.
        // Best-effort: falha de sync não cancela a rotação na Identity DB.
        await SyncKeyWithMiddlewareAsync(id, newKey);

        return Ok(new RotateKeyResponse(company.Id, company.Name, newKey));
    }

    /// <summary>
    /// Envia a nova rawKey ao middleware para sincronizar o SHA-256 no seu PG.
    /// POST {SalesApi:BaseUrl}/api/admin/companies/by-external/{companyId}/rotate-key
    /// Header: Admin-Api-Key: {SalesApi:InternalAdminKey}
    /// Body:   { "rawKey": "COL-XXXX-YYYY-ZZZZ" }
    /// </summary>
    private async Task SyncKeyWithMiddlewareAsync(Guid companyId, string rawKey)
    {
        var baseUrl    = _config["SalesApi:BaseUrl"];
        var adminKey   = _config["SalesApi:InternalAdminKey"];

        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(adminKey))
        {
            // Não configurado — ignora silenciosamente (ex: dev sem middleware)
            return;
        }

        try
        {
            using var client  = _httpFactory.CreateClient();
            client.Timeout    = TimeSpan.FromSeconds(10);

            var url     = $"{baseUrl.TrimEnd('/')}/api/admin/companies/by-external/{companyId}/rotate-key";
            var payload = JsonSerializer.Serialize(new { rawKey });
            var content = new StringContent(payload, Encoding.UTF8, "application/json");
            
            // FIX: Adicionar no header da requisição, e não do conteúdo
            var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
            request.Headers.Add("Admin-Api-Key", adminKey);

            var resp = await client.SendAsync(request);

            if (!resp.IsSuccessStatusCode)
            {
                var body = await resp.Content.ReadAsStringAsync();
                // Loga mas não falha — a chave foi trocada na Identity mesmo assim
                Console.Error.WriteLine(
                    $"[RotateKey] Middleware não atualizou a empresa {companyId}: " +
                    $"HTTP {(int)resp.StatusCode} — {body}");
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                $"[RotateKey] Falha ao notificar middleware para empresa {companyId}: {ex.Message}");
        }
    }

    /// <summary>
    /// Notifica o middleware Sales API para excluir todos os dados do tenant permanentemente.
    /// DELETE {SalesApi:BaseUrl}/api/admin/companies/by-external/{companyId}
    /// Header: Admin-Api-Key: {SalesApi:InternalAdminKey}
    /// </summary>
    private async Task SyncDeleteWithMiddlewareAsync(Guid companyId)
    {
        var baseUrl    = _config["SalesApi:BaseUrl"];
        var adminKey   = _config["SalesApi:InternalAdminKey"];

        if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(adminKey))
        {
            // Não configurado — ignora silenciosamente
            return;
        }

        try
        {
            using var client  = _httpFactory.CreateClient();
            client.Timeout    = TimeSpan.FromSeconds(15);

            var url     = $"{baseUrl.TrimEnd('/')}/api/admin/companies/by-external/{companyId}";
            
            var request = new HttpRequestMessage(HttpMethod.Delete, url);
            request.Headers.Add("Admin-Api-Key", adminKey);

            var resp = await client.SendAsync(request);

            if (!resp.IsSuccessStatusCode)
            {
                var body = await resp.Content.ReadAsStringAsync();
                Console.Error.WriteLine(
                    $"[DeleteCompany] Middleware não excluiu os dados do tenant {companyId}: " +
                    $"HTTP {(int)resp.StatusCode} — {body}");
            }
            else
            {
                Console.WriteLine($"[DeleteCompany] Middleware excluiu com sucesso os dados do tenant {companyId}");
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                $"[DeleteCompany] Falha ao notificar middleware para exclusão da empresa {companyId}: {ex.Message}");
        }
    }

    private Guid GetAdminId()
        => Guid.TryParse(User.FindFirst("adminId")?.Value, out var id) ? id : Guid.Empty;

    private string GetAdminEmail()
        => User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
           ?? User.FindFirst("email")?.Value
           ?? User.FindFirst("sub")?.Value
           ?? $"admin:{GetAdminId().ToString()[..8]}";
}
