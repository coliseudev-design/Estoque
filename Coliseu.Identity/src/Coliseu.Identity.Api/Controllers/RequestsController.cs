using Coliseu.Identity.Api.Filters;
using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Coliseu.Identity.Domain.Interfaces;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;

namespace Coliseu.Identity.Api.Controllers;

/// <summary>
/// Controlador para gerenciamento do fluxo de Requisições de Módulos (Licenças).
/// </summary>
[ApiController]
[Route("admin/requests")]
[Authorize(AuthenticationSchemes = "AdminJwt")]
public sealed class RequestsController : ControllerBase
{
    private readonly ILicenseRequestRepository _requestRepo;
    private readonly IPartnerRepository _partnerRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly IWhatsAppService _whatsAppService;
    private readonly CreateCompanyHandler _createCompanyHandler;
    private readonly ICompanyModuleRepository _moduleRepo;
    private readonly ICompanyRepository _companyRepo;
    private readonly ICompanyKeyGenerator _keyGen;
    private readonly IEncryptionService _encryption;

    public RequestsController(
        ILicenseRequestRepository requestRepo,
        IPartnerRepository partnerRepo,
        IAuditLogRepository auditRepo,
        IWhatsAppService whatsAppService,
        CreateCompanyHandler createCompanyHandler,
        ICompanyModuleRepository moduleRepo,
        ICompanyRepository companyRepo,
        ICompanyKeyGenerator keyGen,
        IEncryptionService encryption)
    {
        _requestRepo = requestRepo;
        _partnerRepo = partnerRepo;
        _auditRepo = auditRepo;
        _whatsAppService = whatsAppService;
        _createCompanyHandler = createCompanyHandler;
        _moduleRepo = moduleRepo;
        _companyRepo = companyRepo;
        _keyGen = keyGen;
        _encryption = encryption;
    }

    /// <summary>Listar requisições paginadas com filtros opcionais.</summary>
    [HttpGet]
    [RequirePermission("requests.read")]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? status = null,
        [FromQuery] Guid? partnerId = null,
        CancellationToken ct = default)
    {
        RequestStatus? statusEnum = null;
        if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<RequestStatus>(status, true, out var parsedStatus))
        {
            statusEnum = parsedStatus;
        }

        var (items, total) = await _requestRepo.GetAllAsync(page, pageSize, search, statusEnum, partnerId, ct);

        var dtos = items.Select(r => new LicenseRequestDto(
            r.Id,
            r.PartnerId,
            r.Partner?.Name ?? "Parceiro não identificado",
            r.CompanyName,
            r.ClientCnpj,
            r.ClientCompanyType,
            r.CostCenterCode,
            r.DeptCode,
            r.PriceTableMode,
            r.AllowNegativeStock,
            r.FirebirdHost,
            r.FirebirdDatabasePath,
            r.FirebirdUser,
            r.Notes,
            r.Status.ToString(),
            r.RequestedByAdminId,
            null, // Email do solicitante pode ser resolvido se necessário, ou mantido simplificado
            r.RequestedAt,
            r.ReviewedByAdminId,
            null,
            r.ReviewedAt,
            r.RejectReason,
            r.BranchesJson,
            r.CompanyId,
            r.Modules.Select(m => new LicenseRequestModuleDto
            {
                Id = m.Id,
                ModuleSlug = m.ModuleSlug,
                DeviceLimit = m.DeviceLimit
            }).ToList()
        )).ToList();

        return Ok(new PagedResult<LicenseRequestDto>(dtos, total, page, pageSize));
    }

    /// <summary>Obter detalhes de uma requisição pelo ID.</summary>
    [HttpGet("{id:guid}")]
    [RequirePermission("requests.read")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var r = await _requestRepo.GetByIdAsync(id, ct);
        if (r is null) return NotFound(new { error = "Requisição não encontrada." });

        var dto = new LicenseRequestDto(
            r.Id,
            r.PartnerId,
            r.Partner?.Name ?? "Parceiro não identificado",
            r.CompanyName,
            r.ClientCnpj,
            r.ClientCompanyType,
            r.CostCenterCode,
            r.DeptCode,
            r.PriceTableMode,
            r.AllowNegativeStock,
            r.FirebirdHost,
            r.FirebirdDatabasePath,
            r.FirebirdUser,
            r.Notes,
            r.Status.ToString(),
            r.RequestedByAdminId,
            null,
            r.RequestedAt,
            r.ReviewedByAdminId,
            null,
            r.ReviewedAt,
            r.RejectReason,
            r.BranchesJson,
            r.CompanyId,
            r.Modules.Select(m => new LicenseRequestModuleDto
            {
                Id = m.Id,
                ModuleSlug = m.ModuleSlug,
                DeviceLimit = m.DeviceLimit
            }).ToList()
        );

        return Ok(dto);
    }

    /// <summary>Criar uma nova requisição de licença.</summary>
    [HttpPost]
    [RequirePermission("requests.create")]
    public async Task<IActionResult> Create([FromBody] CreateLicenseRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.ClientCnpj))
            return BadRequest(new { error = "CNPJ do cliente é obrigatório." });

        var partner = await _partnerRepo.GetByIdAsync(request.PartnerId, ct);
        if (partner is null)
            return BadRequest(new { error = "Parceiro comercial não encontrado." });

        // Rule-04 (Secrets): FirebirdPassword cifrado em repouso
        var encryptedPassword = _encryption.Encrypt(request.FirebirdPassword);

        var licenseRequest = new LicenseRequest(
            Guid.NewGuid(),
            request.PartnerId,
            request.CompanyName,
            request.ClientCnpj,
            request.ClientCompanyType,
            request.CostCenterCode,
            request.DeptCode,
            request.PriceTableMode,
            request.AllowNegativeStock,
            request.FirebirdHost,
            request.FirebirdDatabasePath,
            request.FirebirdUser,
            encryptedPassword,
            request.Notes,
            GetAdminId(),
            request.BranchesJson
        );

        if (request.Modules != null)
        {
            foreach (var m in request.Modules)
            {
                if (!ModuleSlugs.IsValid(m.ModuleSlug))
                {
                    return BadRequest(new { error = $"Slug do módulo '{m.ModuleSlug}' inválido." });
                }
                licenseRequest.AddModule(Guid.NewGuid(), m.ModuleSlug, m.DeviceLimit);
            }
        }

        await _requestRepo.AddAsync(licenseRequest, ct);

        var log = AuditLog.CreateAdmin("request_created", 
            adminEmail: GetAdminEmail(),
            details: $"RequestId: {licenseRequest.Id} | CNPJ: {request.ClientCnpj} | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _requestRepo.SaveChangesAsync(ct);

        // Recarregar com navegações carregadas para WhatsApp
        var savedRequest = await _requestRepo.GetByIdAsync(licenseRequest.Id, ct);
        if (savedRequest != null)
        {
            // Disparar notificação de WhatsApp (Criação) de forma assíncrona
            await _whatsAppService.NotifyRequestCreatedAsync(savedRequest, ct);
        }

        return CreatedAtAction(nameof(GetById), new { id = licenseRequest.Id }, new { id = licenseRequest.Id });
    }

    /// <summary>Aprovar requisição, executando onboarding automático da empresa e disparando licença.</summary>
    [HttpPost("{id:guid}/approve")]
    [RequirePermission("requests.approve")]
    public async Task<IActionResult> Approve(Guid id, [FromBody] ApproveRequestReview review, CancellationToken ct)
    {
        var licenseRequest = await _requestRepo.GetByIdAsync(id, ct);
        if (licenseRequest is null)
            return NotFound(new { error = "Requisição não encontrada." });

        if (licenseRequest.Status != RequestStatus.Pending)
            return BadRequest(new { error = $"Apenas requisições pendentes podem ser aprovadas. Status atual: {licenseRequest.Status}" });

        // 1. Desserializar as filiais salvas no BranchesJson da requisição
        var branches = new List<CreateCompanyBranchRequest>();
        if (!string.IsNullOrWhiteSpace(licenseRequest.BranchesJson))
        {
            try
            {
                branches = JsonSerializer.Deserialize<List<CreateCompanyBranchRequest>>(
                    licenseRequest.BranchesJson, 
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true }
                ) ?? new List<CreateCompanyBranchRequest>();
            }
            catch (Exception ex)
            {
                return BadRequest(new { error = $"Erro ao interpretar dados de filiais da requisição: {ex.Message}" });
            }
        }

        if (branches.Count == 0)
        {
            // Garantir que exista ao menos uma filial padrão para a empresa individual ou multi
            branches.Add(new CreateCompanyBranchRequest
            {
                Name = "Matriz",
                Cnpj = licenseRequest.ClientCnpj,
                ErpEmpresaId = 1,
                ErpDeptoPadrao = int.TryParse(licenseRequest.DeptCode, out var dp) ? dp : 0,
                ErpCentroPadrao = int.TryParse(licenseRequest.CostCenterCode, out var cp) ? cp : 0,
                IsDefault = true
            });
        }

        // Descriptografar a senha do Firebird para a criação
        string decryptedFirebirdPassword = "masterkey";
        try
        {
            decryptedFirebirdPassword = _encryption.Decrypt(licenseRequest.FirebirdPasswordEncrypted);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = $"Erro ao descriptografar senha de banco Firebird para aprovação: {ex.Message}" });
        }

        // Definir o nome fantasia ou razão com base no CNPJ/configuração (usando o CNPJ como fallback ou o nome da requisição se houver)
        // No formulário o admin insere o nome da empresa na criação. Vamos passar o nome da empresa
        // Como o LicenseRequest não possui campo Name direto (o clientCnpj é chave, e o nome fica no JSON do form ou no notes).
        // Vamos extrair o nome do parceiro ou das notas como fallback, mas o ideal é obter a empresa
        // Vamos usar "Empresa " + CNPJ como nome padrão. No frontend, o parceiro envia o nome do cliente.
        // O frontend envia `companyName` no payload de criação.
        // Vamos checar se temos o nome fantasia no payload da requisição. Deixe-me ver se adicionamos no LicenseRequest.
        // Ah, no LicenseRequest.cs criamos com: `ClientCnpj`. Onde fica o nome da empresa?
        // No localStorage/mock ficava `companyName`. Para não termos perda, vamos usar o Notes como nome se contiver dados estruturados,
        // ou criar um campo na tabela para Name.
        // Espera! O LicenseRequest.cs que criei tem `Notes`, mas não tem `CompanyName`?
        // Sim, o frontend Mock envia `companyName`. Vamos adicionar o campo `CompanyName` em `LicenseRequest` para ficar perfeito!
        // Deixe-me adicionar CompanyName em LicenseRequest.cs e na configuração do EF Core. Isso é importante!
        // Deixe-me ver se posso colocar um fallback para "Empresa CNPJ" agora e atualizar a classe LicenseRequest.cs em seguida.
        // Sim, farei a atualização de LicenseRequest.cs em seguida. Vamos assumir que a propriedade existe ou será adicionada.
        // Vamos usar "Empresa CNPJ" por enquanto ou request.Notes.

        var companyName = licenseRequest.CompanyName;

        // 2. Chamar o CreateCompanyHandler para criar a empresa real
        var createCompanyRequest = new CreateCompanyRequest
        {
            Name = companyName,
            ContactEmail = licenseRequest.Partner?.Email, // Usa email do parceiro como contato
            DeviceLimit = licenseRequest.Modules.Sum(m => m.DeviceLimit), // Limite de disp total ou padrão
            FirebirdHost = licenseRequest.FirebirdHost,
            FirebirdDatabasePath = licenseRequest.FirebirdDatabasePath,
            FirebirdUser = licenseRequest.FirebirdUser,
            FirebirdPassword = decryptedFirebirdPassword,
            Branches = branches
        };

        var companyResult = await _createCompanyHandler.HandleAsync(createCompanyRequest, GetAdminId(), ct);
        if (!companyResult.IsSuccess)
        {
            return BadRequest(new { error = $"Erro no onboarding automático da empresa: {companyResult.Error}" });
        }

        var companyResponse = companyResult.Value!;
        var companyId = companyResponse.CompanyId;
        var companyKey = companyResponse.CompanyKey;

        // 3. Cadastrar os módulos da requisição na empresa criada
        foreach (var reqModule in licenseRequest.Modules)
        {
            // Gerar chaves de modulo API Key
            var rawKey = _keyGen.Generate();
            var keyHash = _keyGen.HashKey(rawKey);
            var encryptedKey = _encryption.Encrypt(rawKey);

            var module = CompanyModule.Create(
                companyId,
                reqModule.ModuleSlug,
                keyHash,
                reqModule.DeviceLimit,
                null, // Middleware Url nulo inicialmente
                encryptedKey);

            await _moduleRepo.AddAsync(module, ct);
        }

        // 4. Salvar estado da aprovação
        licenseRequest.Approve(GetAdminId(), companyId);

        var log = AuditLog.CreateAdmin("request_approved", 
            adminEmail: GetAdminEmail(),
            details: $"RequestId: {id} | CompanyId: {companyId} | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _requestRepo.SaveChangesAsync(ct);

        // 5. Enviar notificação WhatsApp com a chave de ativação gerada
        await _whatsAppService.NotifyRequestApprovedAsync(licenseRequest, companyKey, ct);

        return Ok(new { message = "Requisição aprovada com sucesso. Empresa criada.", companyId, companyKey });
    }

    /// <summary>Recusar requisição de licença.</summary>
    [HttpPost("{id:guid}/reject")]
    [RequirePermission("requests.approve")]
    public async Task<IActionResult> Reject(Guid id, [FromBody] RejectRequestReview review, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(review.ReviewNotes))
        {
            return BadRequest(new { error = "É necessário fornecer um motivo para a recusa." });
        }

        var licenseRequest = await _requestRepo.GetByIdAsync(id, ct);
        if (licenseRequest is null)
            return NotFound(new { error = "Requisição não encontrada." });

        if (licenseRequest.Status != RequestStatus.Pending)
            return BadRequest(new { error = $"Apenas requisições pendentes podem ser recusadas. Status atual: {licenseRequest.Status}" });

        licenseRequest.Reject(GetAdminId(), review.ReviewNotes);

        var log = AuditLog.CreateAdmin("request_rejected", 
            adminEmail: GetAdminEmail(),
            details: $"RequestId: {id} | Reason: {review.ReviewNotes} | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _requestRepo.SaveChangesAsync(ct);

        // Enviar notificação de WhatsApp (Recusa)
        await _whatsAppService.NotifyRequestRejectedAsync(licenseRequest, review.ReviewNotes, ct);

        return Ok(new { message = "Requisição recusada com sucesso." });
    }

    /// <summary>Remover uma requisição de licença (apenas pendentes).</summary>
    [HttpDelete("{id:guid}")]
    [RequirePermission("requests.create")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var licenseRequest = await _requestRepo.GetByIdWithoutIncludesAsync(id, ct);
        if (licenseRequest is null) return NotFound(new { error = "Requisição não encontrada." });

        if (licenseRequest.Status != RequestStatus.Pending)
            return BadRequest(new { error = "Apenas requisições com status 'Pendente' podem ser excluídas." });

        await _requestRepo.DeleteAsync(id, ct);

        var log = AuditLog.CreateAdmin("request_deleted", 
            adminEmail: GetAdminEmail(),
            details: $"RequestId: {id} | AdminId: {GetAdminId()}");
        await _auditRepo.AddAsync(log, ct);

        await _requestRepo.SaveChangesAsync(ct);

        return Ok(new { message = "Requisição removida com sucesso." });
    }

    private Guid GetAdminId()
        => Guid.TryParse(User.FindFirst("adminId")?.Value, out var id) ? id : Guid.Empty;

    private string GetAdminEmail()
        => User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value
           ?? User.FindFirst("email")?.Value
           ?? User.FindFirst("sub")?.Value
           ?? $"admin:{GetAdminId().ToString()[..8]}";
}
