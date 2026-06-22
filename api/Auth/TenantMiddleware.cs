using System.Security.Claims;

namespace ColiseuSales.Api.Auth;

/// <summary>
/// Middleware de Multi-Tenant — extrai o CompanyId de cada requisição.
///
/// Fontes (em ordem de prioridade):
/// 1. Header "X-Company-Id" — enviado pelo Worker (autenticado via API Key)
/// 2. JWT Claim "company_id" — emitido pelo Coliseu.Identity ao dispositivo
///
/// O valor extraído é armazenado em HttpContext.Items["CompanyId"]
/// e lido pelo AppDbContext para aplicar o Global Query Filter.
///
/// Rule-03: Nunca aceitar CompanyId de body/query. Sempre vem de header/JWT.
/// </summary>
public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<TenantMiddleware> _logger;

    public TenantMiddleware(RequestDelegate next, ILogger<TenantMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        string? companyId = null;

        // 1. Header explícito (Worker → API)
        if (context.Request.Headers.TryGetValue("X-Company-Id", out var headerValue))
        {
            companyId = headerValue.ToString();
        }

        // 2. JWT claim fallback (Flutter/Device → API)
        // Identity API emite como "tenantId"; também aceita "company_id" por compatibilidade
        if (string.IsNullOrWhiteSpace(companyId))
        {
            companyId = context.User?.FindFirstValue("tenantId")
                     ?? context.User?.FindFirstValue("company_id");
        }

        if (!string.IsNullOrWhiteSpace(companyId))
        {
            context.Items["CompanyId"] = companyId;
        }

        await _next(context);
    }
}

/// <summary>
/// Extension methods para registrar e usar o TenantMiddleware.
/// </summary>
public static class TenantMiddlewareExtensions
{
    /// <summary>
    /// Extrai o CompanyId do contexto HTTP.
    /// Retorna null se não identificado — endpoints que exigem devem validar.
    /// </summary>
    public static string? GetCompanyId(this HttpContext context)
    {
        return context.Items.TryGetValue("CompanyId", out var value)
            ? value as string
            : null;
    }

    /// <summary>
    /// Extrai o CompanyId de forma obrigatória.
    /// Lança InvalidOperationException se ausente.
    /// </summary>
    public static string RequireCompanyId(this HttpContext context)
    {
        return context.GetCompanyId()
            ?? throw new InvalidOperationException(
                "CompanyId não encontrado no contexto. O Worker deve enviar o header X-Company-Id.");
    }
}
