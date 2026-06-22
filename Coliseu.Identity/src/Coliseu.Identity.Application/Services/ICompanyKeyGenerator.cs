namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Gerador de CompanyKeys no formato COL-XXXX-XXXX-XXXX.
/// Usa criptografia segura (CSPRNG) para gerar os caracteres.
/// </summary>
public interface ICompanyKeyGenerator
{
    /// <summary>Gera uma nova CompanyKey criptograficamente segura.</summary>
    /// <returns>CompanyKey no formato COL-XXXX-XXXX-XXXX.</returns>
    string Generate();

    /// <summary>Gera o hash SHA-256 de uma CompanyKey.</summary>
    /// <param name="companyKey">CompanyKey em texto plano.</param>
    /// <returns>Hash SHA-256 hex.</returns>
    string HashKey(string companyKey);
}
