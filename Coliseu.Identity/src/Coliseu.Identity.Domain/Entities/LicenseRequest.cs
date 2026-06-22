using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Requisição de licença gerada por um parceiro ou administrador.
/// </summary>
public sealed class LicenseRequest
{
    public Guid Id { get; private set; }
    public Guid PartnerId { get; private set; }
    public string CompanyName { get; private set; } = null!;
    public string ClientCnpj { get; private set; } = null!;
    public string ClientCompanyType { get; private set; } = null!;
    public string? CostCenterCode { get; private set; }
    public string? DeptCode { get; private set; }
    public string PriceTableMode { get; private set; } = "none";
    public bool AllowNegativeStock { get; private set; }
    public string FirebirdHost { get; private set; } = null!;
    public string FirebirdDatabasePath { get; private set; } = null!;
    public string FirebirdUser { get; private set; } = null!;
    public string FirebirdPasswordEncrypted { get; private set; } = null!;
    public string? Notes { get; private set; }
    public RequestStatus Status { get; private set; }
    public Guid? RequestedByAdminId { get; private set; }
    public DateTime RequestedAt { get; private set; }
    public Guid? ReviewedByAdminId { get; private set; }
    public DateTime? ReviewedAt { get; private set; }
    public string? RejectReason { get; private set; }
    public string? BranchesJson { get; private set; }
    public Guid? CompanyId { get; private set; }

    // Navigation
    public Partner Partner { get; private set; } = null!;
    public Company? Company { get; private set; }
    
    private readonly List<LicenseRequestModule> _modules = new();
    public IReadOnlyCollection<LicenseRequestModule> Modules => _modules.AsReadOnly();

    // EF Core constructor
    private LicenseRequest() { }

    public LicenseRequest(
        Guid id,
        Guid partnerId,
        string companyName,
        string clientCnpj,
        string clientCompanyType,
        string? costCenterCode,
        string? deptCode,
        string priceTableMode,
        bool allowNegativeStock,
        string firebirdHost,
        string firebirdDatabasePath,
        string firebirdUser,
        string firebirdPasswordEncrypted,
        string? notes,
        Guid? requestedByAdminId,
        string? branchesJson)
    {
        Id = id;
        PartnerId = partnerId;
        CompanyName = companyName;
        ClientCnpj = clientCnpj;
        ClientCompanyType = clientCompanyType;
        CostCenterCode = costCenterCode;
        DeptCode = deptCode;
        PriceTableMode = priceTableMode;
        AllowNegativeStock = allowNegativeStock;
        FirebirdHost = firebirdHost;
        FirebirdDatabasePath = firebirdDatabasePath;
        FirebirdUser = firebirdUser;
        FirebirdPasswordEncrypted = firebirdPasswordEncrypted;
        Notes = notes;
        Status = RequestStatus.Pending;
        RequestedByAdminId = requestedByAdminId;
        RequestedAt = DateTime.UtcNow;
        BranchesJson = branchesJson;
    }

    public void Approve(Guid reviewerAdminId, Guid companyId)
    {
        Status = RequestStatus.Approved;
        ReviewedByAdminId = reviewerAdminId;
        ReviewedAt = DateTime.UtcNow;
        CompanyId = companyId;
    }

    public void Reject(Guid reviewerAdminId, string reason)
    {
        Status = RequestStatus.Rejected;
        ReviewedByAdminId = reviewerAdminId;
        ReviewedAt = DateTime.UtcNow;
        RejectReason = reason;
    }

    public void AddModule(Guid id, string moduleSlug, int deviceLimit)
    {
        _modules.Add(new LicenseRequestModule(id, Id, moduleSlug, deviceLimit));
    }
}
