using System.Security.Cryptography;

namespace Coliseu.Identity.Application.Common;

/// <summary>
/// Gerador centralizado de tokens criptograficamente seguros.
///
/// Usado por DeviceLoginHandler e RefreshTokenHandler para gerar
/// Refresh Tokens rotativos. Centralizado aqui para seguir DRY (Rule-06).
/// </summary>
public static class TokenGenerator
{
    /// <summary>
    /// Gera um token de 64 bytes criptograficamente seguro em Base64.
    ///
    /// Returns:
    ///     String Base64 com 88 caracteres (512 bits de entropia).
    /// </summary>
    public static string GenerateRefreshToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(64);
        return Convert.ToBase64String(bytes);
    }
}
