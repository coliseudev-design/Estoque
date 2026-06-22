using OtpNet;

namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Serviço de autenticação de dois fatores usando TOTP (RFC 6238).
///
/// Compatível com Google Authenticator, Authy, e outros apps TOTP padrão.
/// Secret armazenado criptografado na tabela admin_users (Rule-04 Cofre de Segredos).
/// </summary>
public sealed class TotpService
{
    private const int WindowSeconds = 30;
    private const int AllowedSteps  = 1; // ±1 intervalo de 30s de tolerância

    /// <summary>
    /// Gera um novo secret TOTP aleatório (Base32, 160 bits).
    /// </summary>
    /// <returns>Secret em Base32 (para armazenar criptografado no banco).</returns>
    public string GenerateSecret()
    {
        var key = KeyGeneration.GenerateRandomKey(20); // 160 bits = HMAC-SHA1 ideal
        return Base32Encoding.ToString(key);
    }

    /// <summary>
    /// Gera a URI otpauth:// para ser encodada em QR Code no front-end.
    /// </summary>
    /// <param name="email">E-mail do administrador (label do token).</param>
    /// <param name="secret">Secret em Base32.</param>
    /// <param name="issuer">Nome do emissor exibido no app (ex: "Coliseu Admin").</param>
    public string GetOtpAuthUri(string email, string secret, string issuer = "Coliseu Admin")
    {
        var encodedIssuer = Uri.EscapeDataString(issuer);
        var encodedEmail  = Uri.EscapeDataString(email);
        return $"otpauth://totp/{encodedIssuer}:{encodedEmail}?secret={secret}&issuer={encodedIssuer}&algorithm=SHA1&digits=6&period={WindowSeconds}";
    }

    /// <summary>
    /// Valida um código TOTP de 6 dígitos contra o secret do administrador.
    /// </summary>
    /// <param name="secret">Secret em Base32 (obtido descriptografado do banco).</param>
    /// <param name="code">Código digitado pelo usuário (6 dígitos).</param>
    /// <returns>True se o código é válido dentro da janela de tolerância.</returns>
    public bool Validate(string secret, string code)
    {
        if (string.IsNullOrWhiteSpace(secret) || string.IsNullOrWhiteSpace(code))
            return false;

        try
        {
            var key  = Base32Encoding.ToBytes(secret);
            var totp = new Totp(key, step: WindowSeconds, totpSize: 6);

            return totp.VerifyTotp(
                code.Trim(),
                out _,
                new VerificationWindow(AllowedSteps, AllowedSteps));
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Gera o código TOTP atual (usado apenas em testes automatizados).
    /// </summary>
    public string ComputeCurrentCode(string secret)
    {
        var key  = Base32Encoding.ToBytes(secret);
        var totp = new Totp(key, step: WindowSeconds, totpSize: 6);
        return totp.ComputeTotp();
    }
}
