using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Common;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Interfaces;

namespace Coliseu.Identity.Application.Admin.Handlers;

/// <summary>
/// Handler para criação de empresa via painel Admin.
///
/// Gera CompanyKey (COL-XXXX-XXXX-XXXX) automaticamente.
/// Armazena hash SHA-256 da key e criptografa a senha Firebird.
/// </summary>
public sealed class CreateCompanyHandler
{
    private readonly ICompanyRepository _companyRepo;
    private readonly IAuditLogRepository _auditRepo;
    private readonly ICompanyKeyGenerator _keyGen;
    private readonly IEncryptionService _encryption;
    private readonly IBranchRepository _branchRepo;

    public CreateCompanyHandler(
        ICompanyRepository companyRepo,
        IAuditLogRepository auditRepo,
        ICompanyKeyGenerator keyGen,
        IEncryptionService encryption,
        IBranchRepository branchRepo)
    {
        _companyRepo = companyRepo;
        _auditRepo = auditRepo;
        _keyGen = keyGen;
        _encryption = encryption;
        _branchRepo = branchRepo;
    }

    /// <summary>Cria uma nova empresa.</summary>
    public async Task<Result<CreateCompanyResponse>> HandleAsync(
        CreateCompanyRequest request,
        Guid adminId,
        CancellationToken ct = default)
    {
        // 0. Validar filiais obrigatórias
        if (request.Branches == null || request.Branches.Count == 0)
        {
            return Result<CreateCompanyResponse>.Failure("A criação de pelo menos uma filial é obrigatória.", 400);
        }

        // Validar duplicidade de ErpEmpresaId no payload
        var erpEmpresaIds = new HashSet<int>();
        foreach (var branchReq in request.Branches)
        {
            if (branchReq.ErpEmpresaId <= 0)
            {
                return Result<CreateCompanyResponse>.Failure("ID Empresa (ERP) da filial deve ser maior que zero.", 400);
            }
            if (string.IsNullOrWhiteSpace(branchReq.Name))
            {
                return Result<CreateCompanyResponse>.Failure("Nome da filial é obrigatório.", 400);
            }
            if (!erpEmpresaIds.Add(branchReq.ErpEmpresaId))
            {
                return Result<CreateCompanyResponse>.Failure($"Não é permitido cadastrar filiais duplicadas com a mesma Empresa ERP ({branchReq.ErpEmpresaId}) no mesmo cadastro.", 400);
            }
        }

        // Garantir que pelo menos uma é padrão. Se nenhuma for default, marcar a primeira
        if (!request.Branches.Any(b => b.IsDefault))
        {
            request.Branches[0].IsDefault = true;
        }
        else
        {
            // Se houver mais de uma default, manter apenas a primeira
            bool foundDefault = false;
            foreach (var branchReq in request.Branches)
            {
                if (branchReq.IsDefault)
                {
                    if (foundDefault)
                    {
                        branchReq.IsDefault = false;
                    }
                    else
                    {
                        foundDefault = true;
                    }
                }
            }
        }

        // 1. Gerar CompanyKey
        var companyKey = _keyGen.Generate();
        var keyHash = _keyGen.HashKey(companyKey);

        // 2. Criptografar senha Firebird e a CompanyKey original
        var encryptedPassword = _encryption.Encrypt(request.FirebirdPassword);
        var encryptedKey = _encryption.Encrypt(companyKey);

        // 3. Criar entidade
        var company = Company.Create(
            name: request.Name,
            companyKeyHash: keyHash,
            firebirdHost: request.FirebirdHost,
            firebirdDatabasePath: request.FirebirdDatabasePath,
            firebirdUser: request.FirebirdUser,
            firebirdPasswordEncrypted: encryptedPassword,
            deviceLimit: request.DeviceLimit,
            contactEmail: request.ContactEmail,
            companyKeyEncrypted: encryptedKey);

        await _companyRepo.AddAsync(company, ct);

        // Criar as filiais associadas
        foreach (var branchReq in request.Branches)
        {
            var branch = Branch.Create(
                companyId: company.Id,
                name: branchReq.Name,
                erpEmpresaId: branchReq.ErpEmpresaId,
                erpDeptoPadrao: branchReq.ErpDeptoPadrao,
                erpCentroPadrao: branchReq.ErpCentroPadrao,
                isDefault: branchReq.IsDefault,
                cnpj: branchReq.Cnpj
            );
            await _branchRepo.AddAsync(branch, ct);
        }

        // 4. Auditoria
        var log = AuditLog.Create("company_created", companyId: company.Id,
            details: $"AdminId: {adminId}, Name: {request.Name}");
        await _auditRepo.AddAsync(log, ct);

        await _companyRepo.SaveChangesAsync(ct);

        // Retorna CompanyKey em texto — exibida UMA VEZ ao admin
        return Result<CreateCompanyResponse>.Success(new CreateCompanyResponse(
            CompanyId: company.Id,
            CompanyName: company.Name,
            ContactEmail: company.ContactEmail,
            CompanyKey: companyKey,
            DeviceLimit: company.DeviceLimit));
    }
}
