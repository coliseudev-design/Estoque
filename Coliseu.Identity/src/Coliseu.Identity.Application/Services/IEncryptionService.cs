namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Serviço de criptografia AES-256-GCM para credenciais sensíveis.
///
/// Usado para cifrar/decifrar senhas Firebird e outras credenciais
/// que precisam ser armazenadas em repouso de forma segura (Rule-04).
/// </summary>
public interface IEncryptionService
{
    /// <summary>Cifra texto plano com AES-256-GCM.</summary>
    /// <param name="plaintext">Texto a ser cifrado.</param>
    /// <returns>Base64 contendo IV + ciphertext + auth tag.</returns>
    string Encrypt(string plaintext);

    /// <summary>Decifra texto cifrado com AES-256-GCM.</summary>
    /// <param name="ciphertext">Base64 contendo IV + ciphertext + auth tag.</param>
    /// <returns>Texto plano original.</returns>
    string Decrypt(string ciphertext);
}
