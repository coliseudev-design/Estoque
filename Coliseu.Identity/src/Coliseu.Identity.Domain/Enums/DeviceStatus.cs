namespace Coliseu.Identity.Domain.Enums;

/// <summary>
/// Status operacional de um dispositivo vinculado a uma empresa.
/// </summary>
public enum DeviceStatus
{
    /// <summary>Dispositivo ativo — pode autenticar e sincronizar.</summary>
    Active = 0,

    /// <summary>Dispositivo bloqueado pelo administrador — login negado.</summary>
    Blocked = 1,

    /// <summary>Dispositivo revogado — requer reativação manual.</summary>
    Revoked = 2
}
