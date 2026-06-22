using Coliseu.Identity.Domain.Enums;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Filial de uma empresa (Branch).
/// Representa a granularidade fina de acesso de estoque e financeiro do ERP.
/// </summary>
public sealed class Branch
{
    public Guid Id { get; private set; }
    public Guid CompanyId { get; private set; }
    public Company Company { get; private set; } = null!;
    
    public string Name { get; private set; } = null!;
    public string? Cnpj { get; private set; }
    
    /// <summary>
    /// Corresponde ao ID_EMPRESA do Firebird.
    /// </summary>
    public int ErpEmpresaId { get; private set; }
    
    /// <summary>
    /// Corresponde ao ID vinculado ao departamento para consultar Estoque no Firebird.
    /// </summary>
    public int ErpDeptoPadrao { get; private set; }
    
    /// <summary>
    /// Corresponde ao ID vinculado ao Centro de Custo no Financeiro no Firebird.
    /// </summary>
    public int ErpCentroPadrao { get; private set; }
    
    /// <summary>
    /// Define se esta é a filial matriz padrão usada como fallback ou filial principal da empresa.
    /// Apenas uma filial na empresa pode ter isso como verdadeiro.
    /// </summary>
    public bool IsDefault { get; private set; }
    
    public CompanyStatus Status { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    // Navigation (opcional: poderia ter coleções de pedidos se o C# genciasse, mas quem gerencia é o Node)
    
    private Branch() { }

    public static Branch Create(
        Guid companyId,
        string name,
        int erpEmpresaId,
        int erpDeptoPadrao,
        int erpCentroPadrao,
        bool isDefault = false,
        string? cnpj = null)
    {
        if (companyId == Guid.Empty)
            throw new ArgumentException("CompanyId é obrigatório.", nameof(companyId));
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome da filial é obrigatório.", nameof(name));
            
        return new Branch
        {
            Id = Guid.NewGuid(),
            CompanyId = companyId,
            Name = name.Trim(),
            ErpEmpresaId = erpEmpresaId,
            ErpDeptoPadrao = erpDeptoPadrao,
            ErpCentroPadrao = erpCentroPadrao,
            IsDefault = isDefault,
            Cnpj = cnpj?.Trim(),
            Status = CompanyStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
    }

    public void UpdateDetails(string name, string? cnpj, int erpEmpresaId, int erpDeptoPadrao, int erpCentroPadrao)
    {
        if (!string.IsNullOrWhiteSpace(name))
            Name = name.Trim();
            
        Cnpj = cnpj?.Trim();
        ErpEmpresaId = erpEmpresaId;
        ErpDeptoPadrao = erpDeptoPadrao;
        ErpCentroPadrao = erpCentroPadrao;
        
        UpdatedAt = DateTime.UtcNow;
    }

    public void SetDefault(bool isDefault)
    {
        IsDefault = isDefault;
        UpdatedAt = DateTime.UtcNow;
    }

    public void Suspend()
    {
        Status = CompanyStatus.Suspended;
        UpdatedAt = DateTime.UtcNow;
    }

    public void Activate()
    {
        Status = CompanyStatus.Active;
        UpdatedAt = DateTime.UtcNow;
    }
}
