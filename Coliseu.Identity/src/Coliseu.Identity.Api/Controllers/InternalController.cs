using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Endpoints internos protegidos por API Key para a comunicação de backend (Worker Service).
/// Uso estritamente restrito a infraestrutura interna confiável.
/// </summary>
[ApiController]
[Route("internal")]
[TypeFilter(typeof(InternalApiKeyFilter))]
public class InternalController : ControllerBase
{
    private readonly ICompanyRepository _companyRepo;
    private readonly IEncryptionService _encryption;
    private readonly ILogger<InternalController> _logger;

    public InternalController(
        ICompanyRepository companyRepo,
        IEncryptionService encryption,
        ILogger<InternalController> logger)
    {
        _companyRepo = companyRepo;
        _encryption = encryption;
        _logger = logger;
    }

    /// <summary>
    /// Retorna as credenciais decifradas do Firebird para a configuração do Worker local da empresa.
    /// O Worker chama este endpoint no startup para plugar no ERP correto.
    /// </summary>
    [HttpGet("companies/{id:guid}/firebird-config")]
    public async Task<IActionResult> GetFirebirdConfig(Guid id, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null) return NotFound(new { error = "Empresa não encontrada." });
        
        if (company.Status != Coliseu.Identity.Domain.Enums.CompanyStatus.Active)
            return StatusCode(StatusCodes.Status403Forbidden, new { error = $"Acesso bloqueado: o status da empresa é {company.Status}." });

        if (string.IsNullOrWhiteSpace(company.FirebirdHost) || string.IsNullOrWhiteSpace(company.FirebirdDatabasePath))
            return BadRequest(new { error = "Configuração Firebird incompleta para esta empresa. Um administrador precisa configurá-la no painel." });

        try 
        {
            var password = _encryption.Decrypt(company.FirebirdPasswordEncrypted);

            return Ok(new
            {
                host = company.FirebirdHost,
                database = company.FirebirdDatabasePath,
                user = company.FirebirdUser,
                password = password
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Internal] Falha ao decifrar credenciais Firebird para empresa {CompanyId}", id);
            return StatusCode(StatusCodes.Status500InternalServerError, new { error = "Falha ao decifrar credenciais Firebird. Verifique a chave de encriptação (ENCRYPTION_KEY)." });
        }
    }

    /// <summary>
    /// Retorna as filiais ativas da empresa para uso do Worker (isolamento multi-tenant).
    /// </summary>
    [HttpGet("companies/{id:guid}/branches")]
    public async Task<IActionResult> GetBranches([FromServices] IBranchRepository branchRepo, Guid id, CancellationToken ct)
    {
        var branches = await branchRepo.GetByCompanyAsync(id, ct);
        var dtos = branches.Select(b => new
        {
            id = b.Id,
            name = b.Name,
            cnpj = b.Cnpj,
            erpEmpresaId = b.ErpEmpresaId,
            erpDeptoPadrao = b.ErpDeptoPadrao,
            erpCentroPadrao = b.ErpCentroPadrao,
            isDefault = b.IsDefault
        });
        return Ok(dtos);
    }

    /// <summary>
    /// Valida dinamicamente se uma API Key provida por um middleware/worker
    /// corresponde à chave gerada para o módulo daquela empresa e se ela está ativa.
    /// Chamado pelos middlewares Node.js para travar inadimplentes instântaneamente.
    /// </summary>
    [HttpPost("companies/{id:guid}/modules/{moduleSlug}/validate-key")]
    public async Task<IActionResult> ValidateModuleKey(
        [FromServices] ICompanyModuleRepository moduleRepo,
        [FromServices] ICompanyKeyGenerator keyGen,
        Guid id, string moduleSlug, [FromBody] ValidateKeyRequest req, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.ApiKey))
            return BadRequest(new { valid = false, reason = "API Key é obrigatória no body." });

        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null || company.Status != Coliseu.Identity.Domain.Enums.CompanyStatus.Active)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = "Empresa não encontrada ou inativa." });

        var module = await moduleRepo.GetByCompanyAndSlugAsync(id, moduleSlug.ToLowerInvariant().Trim(), ct);
        if (module is null)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = $"Módulo '{moduleSlug}' não ativado para esta empresa." });

        if (!module.IsActive)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = $"Módulo '{moduleSlug}' está suspenso/desativado." });

        var hash = keyGen.HashKey(req.ApiKey.Trim());
        if (hash != module.ApiKeyHash)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = "API Key do módulo inválida." });

        return Ok(new { valid = true });
    }

    /// <summary>
    /// Retorna as informações do módulo, como o limite de dispositivos, para a comunicação de backend.
    /// Utilizado pelo Dashboard para travar a criação de contas excedentes.
    /// </summary>
    [HttpGet("companies/{id:guid}/modules/{moduleSlug}/info")]
    public async Task<IActionResult> GetModuleInfo(
        [FromServices] ICompanyModuleRepository moduleRepo,
        Guid id, string moduleSlug, CancellationToken ct)
    {
        var company = await _companyRepo.GetByIdAsync(id, ct);
        if (company is null || company.Status != Coliseu.Identity.Domain.Enums.CompanyStatus.Active)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = "Empresa não encontrada ou inativa." });

        var module = await moduleRepo.GetByCompanyAndSlugAsync(id, moduleSlug.ToLowerInvariant().Trim(), ct);
        if (module is null)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = $"Módulo '{moduleSlug}' não ativado para esta empresa." });

        if (!module.IsActive)
            return StatusCode(StatusCodes.Status403Forbidden, new { valid = false, reason = $"Módulo '{moduleSlug}' está suspenso/desativado." });

        return Ok(new { valid = true, deviceLimit = module.DeviceLimit, nomeDaEmpresa = company.Name, versions = module.Versions });
    }
}

public record ValidateKeyRequest(string ApiKey);
