namespace Coliseu.Identity.Domain.Enums;

/// <summary>
/// Papéis administrativos no painel Coliseu.Identity.Admin.
/// </summary>
public enum AdminRole
{
    /// <summary>Operador — pode visualizar e bloquear dispositivos.</summary>
    Operator = 0,

    /// <summary>Super administrador — acesso total ao gerenciamento.</summary>
    SuperAdmin = 1
}
