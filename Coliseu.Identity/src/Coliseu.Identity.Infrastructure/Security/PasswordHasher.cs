using Coliseu.Identity.Application.Services;

namespace Coliseu.Identity.Infrastructure.Security;

/// <summary>
/// Hasher de senhas com bcrypt custo 12.
///
/// Rule-07 (Higiene de Credenciais): bcrypt com fator de custo 12.
/// Nunca SHA-256 ou MD5 para senhas (brute-force rápido demais).
/// </summary>
public sealed class PasswordHasher : IPasswordHasher
{
    private const int WorkFactor = 12;

    /// <inheritdoc />
    public string Hash(string password)
        => BCrypt.Net.BCrypt.HashPassword(password, workFactor: WorkFactor);

    /// <inheritdoc />
    public bool Verify(string password, string hash)
        => BCrypt.Net.BCrypt.Verify(password, hash);
}
