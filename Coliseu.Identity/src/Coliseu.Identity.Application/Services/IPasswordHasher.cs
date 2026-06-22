namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Serviço de hashing de senhas com bcrypt.
/// Custo fixo de 12 rounds (Rule-07: Higiene de Credenciais).
/// </summary>
public interface IPasswordHasher
{
    /// <summary>Gera hash bcrypt da senha com custo 12.</summary>
    string Hash(string password);

    /// <summary>Verifica se a senha corresponde ao hash.</summary>
    bool Verify(string password, string hash);
}
