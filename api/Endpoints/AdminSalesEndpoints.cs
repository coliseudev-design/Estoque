using ColiseuSales.Api.Auth;
using ColiseuSales.Api.Data;
using ColiseuSales.Api.Logging;
using Microsoft.EntityFrameworkCore;

namespace ColiseuSales.Api.Endpoints;

/// <summary>
/// Endpoints de administração do Sales API.
/// Autenticados via API Key (apenas o Worker/Admin têm essa chave).
///
/// Expostos em: /api/admin/*
///
/// Endpoints:
/// - GET  /api/admin/stats          → métricas globais (pedidos, sync, etc.)
/// - GET  /api/admin/config         → configuração efetiva atual (CORS, RateLimit)
/// - PUT  /api/admin/config/cors    → atualiza origens CORS permitidas
/// - PUT  /api/admin/config/ratelimit → atualiza limites de rate limiting
/// - GET  /api/admin/logs           → últimas N requisições do buffer
/// </summary>
public static class AdminSalesEndpoints
{
    public static void MapAdminSalesEndpoints(this WebApplication app)
    {
        var group = app
            .MapGroup("/api/admin")
            .AddEndpointFilter<ApiKeyEndpointFilter>()
            .WithTags("Admin");

        // ── GET /api/admin/stats ──────────────────────────────────────────────
        group.MapGet("/stats", async (AppDbContext db) =>
        {
            var orders = await db.Orders
                .IgnoreQueryFilters()
                .GroupBy(o => o.Status)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync();

            var orderDict  = orders.ToDictionary(o => o.Status, o => o.Count);
            var totalOrders = orders.Sum(o => o.Count);

            var products  = await db.Products.IgnoreQueryFilters().CountAsync();
            var customers = await db.Customers.IgnoreQueryFilters().CountAsync();
            // Conta empresas distintas a partir dos pedidos existentes
            var companies = await db.Orders.IgnoreQueryFilters()
                .Select(o => o.CompanyId).Distinct().CountAsync();

            // Último pedido sincronizado (SyncedAt é string no formato ISO)
            var lastSync = await db.Orders
                .IgnoreQueryFilters()
                .Where(o => o.Status == "synced" && o.SyncedAt != null)
                .OrderByDescending(o => o.SyncedAt)
                .Select(o => o.SyncedAt)
                .FirstOrDefaultAsync();

            return Results.Ok(new
            {
                orders = new
                {
                    total      = totalOrders,
                    pending    = orderDict.GetValueOrDefault("Pending"),
                    processing = orderDict.GetValueOrDefault("Processing"),
                    synced     = orderDict.GetValueOrDefault("Synced"),
                    error      = orderDict.GetValueOrDefault("Error"),
                },
                catalog = new
                {
                    products,
                    customers,
                },
                companies,
                lastSyncAt = lastSync,  // string ISO ou null
                serverTime = DateTime.UtcNow,
                uptime     = GetUptime(),
            });
        })
        .WithSummary("Métricas globais do Sales API");

        // ── GET /api/admin/config ─────────────────────────────────────────────
        group.MapGet("/config", (IConfiguration config) =>
        {
            var cors      = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
            var rateLimit = new
            {
                syncPerMinute      = config.GetValue("RateLimit:SyncPerMinute", 30),
                ordersPerMinute    = config.GetValue("RateLimit:OrdersPerMinute", 10),
                monitoringPerMinute = config.GetValue("RateLimit:MonitoringPerMinute", 20),
            };

            return Results.Ok(new
            {
                cors           = cors,
                rateLimit,
                connectionString = MaskConnectionString(config.GetConnectionString("DefaultConnection")),
                jwtConfigured  = !string.IsNullOrEmpty(config["Jwt:DeviceSigningKey"]),
                apiKeysCount   = config.GetSection("Auth:ApiKeys").Get<string[]>()?.Length ?? 0,
            });
        })
        .WithSummary("Configuração efetiva atual (somente leitura)");

        // ── GET /api/admin/logs ───────────────────────────────────────────────
        group.MapGet("/logs", (RequestLogBuffer buffer,
                               int count = 50,
                               bool? errorsOnly = null) =>
        {
            var logs = buffer.GetRecent(Math.Min(count, 200));
            IEnumerable<RequestLogEntry> result = logs;

            if (errorsOnly == true)
                result = result.Where(l => l.IsError);

            return Results.Ok(result.Select(l => new
            {
                timestamp   = l.Timestamp,
                method      = l.Method,
                path        = l.Path,
                statusCode  = l.StatusCode,
                elapsedMs   = l.ElapsedMs,
                companyId   = l.CompanyId,
                ipAddress   = l.IpAddress,
                isError     = l.IsError,
            }));
        })
        .WithSummary("Últimas requisições capturadas em memória");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>Uptime em segundos desde o início do processo.</summary>
    private static long GetUptime()
        => (long)(DateTime.UtcNow - System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalSeconds;

    /// <summary>
    /// Mascara dados sensíveis da connection string no output.
    /// Exibe apenas o caminho do arquivo, nunca senha.
    /// </summary>
    private static string MaskConnectionString(string? cs)
    {
        if (string.IsNullOrEmpty(cs)) return "Não configurado";
        // SQLite: "Data Source=/path/to/file.db" → safe to show path
        if (cs.StartsWith("Data Source=", StringComparison.OrdinalIgnoreCase))
            return cs;
        // Para outros providers, mascara tudo exceto o tipo de banco
        return cs.Length > 20 ? cs[..20] + "..." : "***";
    }
}

/// <summary>
/// Filtro de endpoint para verificar API Key antes de executar handlers de admin.
/// Reutiliza o serviço de validação existente.
/// </summary>
internal sealed class ApiKeyEndpointFilter : IEndpointFilter
{
    private readonly IConfiguration _config;

    public ApiKeyEndpointFilter(IConfiguration config)
    {
        _config = config;
    }

    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        var apiKeys    = _config.GetSection("Auth:ApiKeys").Get<string[]>() ?? [];

        if (!httpContext.Request.Headers.TryGetValue("X-Api-Key", out var key) ||
            !apiKeys.Contains(key.ToString()))
        {
            return Results.Json(new { error = "API Key inválida ou ausente." }, statusCode: 401);
        }

        return await next(context);
    }
}
