using System.Security.Cryptography;
using System.Text;

namespace ColiseuSpeed.Api.Auth;

/// <summary>
/// Middleware de autenticação por API Key.
///
/// Lê o header "API-Key" e valida contra as chaves configuradas em appsettings.json.
/// Rotas públicas (/health, /scalar, /openapi) são isentas.
///
/// Rule-01 (Security): API Key nunca logada.
/// Usa CryptographicOperations.FixedTimeEquals para comparação constant-time
/// (resistente a timing attacks — substitui .Contains() que é vulnerável).
/// </summary>
public sealed class ApiKeyMiddleware(RequestDelegate next, IConfiguration config)
{
    private static readonly string[] PublicPaths = ["/health", "/scalar", "/openapi"];

    public async Task InvokeAsync(HttpContext ctx)
    {
        var path = ctx.Request.Path.Value ?? string.Empty;

        // Bypass para rotas públicas
        if (PublicPaths.Any(p => path.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
        {
            await next(ctx);
            return;
        }

        // Permite bypass se já estiver autenticado via JWT
        if (ctx.User.Identity?.IsAuthenticated == true)
        {
            await next(ctx);
            return;
        }

        // Lê o header API-Key
        if (!ctx.Request.Headers.TryGetValue("API-Key", out var incoming) ||
            string.IsNullOrWhiteSpace(incoming))
        {
            ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await ctx.Response.WriteAsJsonAsync(new { error = "API-Key header ausente ou JWT inválido." });
            return;
        }

        // Valida contra a lista de chaves configuradas usando comparação constant-time
        // (previne timing attacks — o tempo de resposta não revela quantos bytes coincidem)
        var validKeys = config.GetSection("Auth:ApiKeys").Get<string[]>() ?? [];
        var incomingBytes = Encoding.UTF8.GetBytes(incoming.ToString());

        var isValid = validKeys.Any(key =>
        {
            var keyBytes = Encoding.UTF8.GetBytes(key);
            return CryptographicOperations.FixedTimeEquals(incomingBytes, keyBytes);
        });

        if (!isValid)
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            await ctx.Response.WriteAsJsonAsync(new { error = "API Key inválida." });
            return;
        }

        // Constrói uma identidade para o pipeline do ASP.NET Core reconhecer como autenticado
        var claims = new[] { new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Name, "Worker") };
        var identity = new System.Security.Claims.ClaimsIdentity(claims, "ApiKey");
        ctx.User = new System.Security.Claims.ClaimsPrincipal(identity);

        await next(ctx);
    }
}
