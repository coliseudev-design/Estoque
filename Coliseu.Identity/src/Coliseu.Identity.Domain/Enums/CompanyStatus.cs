namespace Coliseu.Identity.Domain.Enums;

/// <summary>
/// Status operacional da empresa no ecossistema Coliseu.
/// </summary>
public enum CompanyStatus
{
    /// <summary>Empresa ativa — dispositivos podem autenticar.</summary>
    Active = 0,

    /// <summary>Empresa suspensa temporariamente — logins bloqueados.</summary>
    Suspended = 1,

    /// <summary>Empresa bloqueada permanentemente — requer intervenção manual.</summary>
    Blocked = 2
}
