using System.Security.Cryptography;
using System.Text;
using Coliseu.Identity.Application.Services;
using Microsoft.Extensions.Options;

namespace Coliseu.Identity.Infrastructure.Security;

/// <summary>
/// Configuração de criptografia lida de variáveis de ambiente.
/// </summary>
public sealed class EncryptionOptions
{
    public const string Section = "Encryption";

    /// <summary>Chave AES-256 em Base64 (32 bytes = 256 bits).</summary>
    public string Key { get; set; } = string.Empty;
}

/// <summary>
/// Implementação de criptografia AES-256-GCM para credenciais sensíveis.
///
/// Formato do ciphertext: Base64(nonce[12] + ciphertext + tag[16])
///
/// Rule-04 (Secrets Vault): credenciais Firebird nunca em texto plano no banco.
/// </summary>
public sealed class EncryptionService : IEncryptionService
{
    private readonly byte[] _key;
    private const int NonceSize = 12;  // AES-GCM standard
    private const int TagSize = 16;    // AES-GCM standard

    public EncryptionService(IOptions<EncryptionOptions> options)
    {
        var keyBase64 = options.Value.Key;
        if (string.IsNullOrWhiteSpace(keyBase64))
            throw new InvalidOperationException(
                "[EncryptionService] ENCRYPTION_KEY não configurada.");

        try
        {
            _key = Convert.FromBase64String(keyBase64);
        }
        catch (FormatException)
        {
            throw new InvalidOperationException(
                "[EncryptionService] ENCRYPTION_KEY deve ser Base64 válido.");
        }

        if (_key.Length != 32)
            throw new InvalidOperationException(
                "[EncryptionService] ENCRYPTION_KEY deve ter 256 bits (32 bytes em Base64).");
    }

    /// <inheritdoc />
    public string Encrypt(string plaintext)
    {
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var nonce = new byte[NonceSize];
        RandomNumberGenerator.Fill(nonce);

        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(_key, TagSize);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        // nonce + ciphertext + tag → Base64
        var result = new byte[NonceSize + ciphertext.Length + TagSize];
        Buffer.BlockCopy(nonce, 0, result, 0, NonceSize);
        Buffer.BlockCopy(ciphertext, 0, result, NonceSize, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, result, NonceSize + ciphertext.Length, TagSize);

        return Convert.ToBase64String(result);
    }

    /// <inheritdoc />
    public string Decrypt(string ciphertextBase64)
    {
        var combined = Convert.FromBase64String(ciphertextBase64);

        if (combined.Length < NonceSize + TagSize)
            throw new CryptographicException("Ciphertext inválido — tamanho insuficiente.");

        var nonce = new byte[NonceSize];
        var ciphertext = new byte[combined.Length - NonceSize - TagSize];
        var tag = new byte[TagSize];

        Buffer.BlockCopy(combined, 0, nonce, 0, NonceSize);
        Buffer.BlockCopy(combined, NonceSize, ciphertext, 0, ciphertext.Length);
        Buffer.BlockCopy(combined, NonceSize + ciphertext.Length, tag, 0, TagSize);

        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_key, TagSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return Encoding.UTF8.GetString(plaintext);
    }
}
