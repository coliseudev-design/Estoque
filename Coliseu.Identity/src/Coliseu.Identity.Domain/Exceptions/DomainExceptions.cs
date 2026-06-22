namespace Coliseu.Identity.Domain.Exceptions;

/// <summary>Empresa bloqueada ou suspensa — login de dispositivo negado.</summary>
public sealed class CompanyBlockedException : Exception
{
    public CompanyBlockedException(string companyName)
        : base($"Empresa '{companyName}' está suspensa ou bloqueada.") { }
}

/// <summary>Limite de dispositivos atingido para a empresa.</summary>
public sealed class DeviceLimitExceededException : Exception
{
    public DeviceLimitExceededException(int limit)
        : base($"Limite de {limit} dispositivos atingido para esta empresa.") { }
}

/// <summary>Dispositivo bloqueado ou revogado — login negado.</summary>
public sealed class DeviceBlockedException : Exception
{
    public DeviceBlockedException(string deviceUuid)
        : base($"Dispositivo '{deviceUuid}' está bloqueado ou revogado.") { }
}

/// <summary>CompanyKey inválida — não encontrada no sistema.</summary>
public sealed class InvalidCompanyKeyException : Exception
{
    public InvalidCompanyKeyException()
        : base("CompanyKey inválida. Verifique a chave informada.") { }
}

/// <summary>Refresh Token inválido, expirado ou revogado.</summary>
public sealed class InvalidRefreshTokenException : Exception
{
    public InvalidRefreshTokenException()
        : base("Refresh Token inválido ou expirado.") { }
}
