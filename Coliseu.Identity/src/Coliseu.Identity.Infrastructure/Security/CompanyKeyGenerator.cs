using System.Security.Cryptography;
using System.Text;
using Coliseu.Identity.Application.Services;

namespace Coliseu.Identity.Infrastructure.Security;

/// <summary>
/// Gerador de CompanyKeys no formato COL-XXXX-XXXX-XXXX.
///
/// Usa CSPRNG (Cryptographically Secure Pseudo-Random Number Generator).
/// Charset sem caracteres ambíguos (0/O, 1/I/L removidos).
/// A key é exibida ao admin uma única vez; armazenada como SHA-256 hash.
/// </summary>
public sealed class CompanyKeyGenerator : ICompanyKeyGenerator
{
    /// <summary>Charset sem ambíguos: A-Z (sem I, L, O) + 2-9 (sem 0, 1).</summary>
    private const string Charset = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    /// <inheritdoc />
    public string Generate()
    {
        var segments = new string[3];
        for (var i = 0; i < 3; i++)
        {
            segments[i] = GenerateSegment(4);
        }
        return $"COL-{segments[0]}-{segments[1]}-{segments[2]}";
    }

    /// <inheritdoc />
    public string HashKey(string companyKey)
    {
        var bytes = Encoding.UTF8.GetBytes(companyKey.Trim().ToUpperInvariant());
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static string GenerateSegment(int length)
    {
        var result = new char[length];
        for (var i = 0; i < length; i++)
        {
            result[i] = Charset[RandomNumberGenerator.GetInt32(Charset.Length)];
        }
        return new string(result);
    }
}
