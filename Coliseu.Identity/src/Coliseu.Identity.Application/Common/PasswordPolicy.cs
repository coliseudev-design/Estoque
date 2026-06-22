using System.Text.RegularExpressions;

namespace Coliseu.Identity.Application.Common;

/// <summary>
/// Política de complexidade de senha (Rule-07 — Higiene de Credenciais).
///
/// Requisitos obrigatórios:
///   - Mínimo 8 caracteres
///   - Pelo menos 1 letra maiúscula (A-Z)
///   - Pelo menos 1 letra minúscula (a-z)
///   - Pelo menos 1 dígito numérico (0-9)
///
/// Uso:
///   var (ok, erro) = PasswordPolicy.Validate(senha);
///   if (!ok) return Result.BadRequest(erro!);
/// </summary>
public static class PasswordPolicy
{
    public const int MinLength = 8;

    private static readonly Regex _hasUpper   = new(@"[A-Z]",  RegexOptions.Compiled);
    private static readonly Regex _hasLower   = new(@"[a-z]",  RegexOptions.Compiled);
    private static readonly Regex _hasDigit   = new(@"\d",     RegexOptions.Compiled);

    /// <summary>
    /// Valida a senha contra a política de complexidade.
    /// </summary>
    /// <param name="password">Senha em texto puro a validar.</param>
    /// <returns>
    ///   (true, null) se a senha é válida.
    ///   (false, mensagem) se inválida, com descrição do requisito não atendido.
    /// </returns>
    public static (bool IsValid, string? ErrorMessage) Validate(string? password)
    {
        if (string.IsNullOrWhiteSpace(password))
            return (false, "A senha não pode ser vazia.");

        if (password.Length < MinLength)
            return (false, $"A senha deve ter pelo menos {MinLength} caracteres.");

        if (!_hasUpper.IsMatch(password))
            return (false, "A senha deve conter pelo menos uma letra maiúscula.");

        if (!_hasLower.IsMatch(password))
            return (false, "A senha deve conter pelo menos uma letra minúscula.");

        if (!_hasDigit.IsMatch(password))
            return (false, "A senha deve conter pelo menos um número.");

        return (true, null);
    }
}
