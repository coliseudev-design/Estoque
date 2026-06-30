namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Serviço de geração e validação de JWT.
/// Separado em Device JWT e Admin JWT com chaves diferentes.
/// </summary>
public interface IJwtService
{
    /// <summary>Gera JWT para um dispositivo autenticado.</summary>
    /// <param name="tenantId">ID da empresa (claim: tenantId).</param>
    /// <param name="deviceId">ID do dispositivo (claim: deviceId).</param>
    /// <param name="companyName">Nome da empresa (claim: companyName).</param>
    /// <param name="moduleSlug">Módulo do produto (claim: module). Padrão: coliseu-speed.</param>
    /// <returns>Token JWT e duração em segundos.</returns>
    (string Token, int ExpiresInSeconds) GenerateDeviceToken(
        Guid tenantId, Guid deviceId, string companyName,
        string moduleSlug = "coliseu-speed");

    /// <summary>Gera JWT para um dispositivo autenticado, incluindo contexto da filial (Branch).</summary>
    (string Token, int ExpiresInSeconds) GenerateDeviceTokenWithBranch(
        Guid tenantId, Guid deviceId, string companyName,
        Guid branchId, int erpEmpresaId, string moduleSlug = "coliseu-speed");

    /// <summary>Gera JWT para um administrador autenticado.</summary>
    /// <param name="adminId">ID do admin (claim: adminId).</param>
    /// <param name="email">E-mail do admin (claim: email).</param>
    /// <param name="role">Papel do admin (claim: role).</param>
    /// <param name="permissions">Permissões do grupo (claim: perm). SuperAdmin recebe ["*"].</param>
    /// <returns>Token JWT e duração em segundos.</returns>
    (string Token, int ExpiresInSeconds) GenerateAdminToken(
        Guid adminId, string email, string role, IEnumerable<string>? permissions = null);
}
