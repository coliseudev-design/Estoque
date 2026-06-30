using ColiseuSpeed.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace ColiseuSpeed.Api.Endpoints;

/// <summary>
/// Endpoint de monitoramento por empresa para o painel admin.
///
/// Fornece dados de saúde da sincronização de cada tenant sem expor
/// dados de pedidos individuais — apenas contagens agregadas.
/// </summary>
public static class MonitoringEndpoints
{
    public static void MapMonitoringEndpoints(this WebApplication app)
    {
        var monitor = app.MapGroup("/api/monitoring")
            .WithTags("Monitoring")
            .RequireAuthorization();

        monitor.MapGet("/summary", GetSummary)
            .WithName("GetMonitoringSummary")
            .WithSummary("Admin: resumo de sincronização por empresa (contagens de pedidos)")
            .AllowAnonymous(); // Protegido apenas por API Key via middleware

        monitor.MapGet("/summary/{companyId}", GetCompanySummary)
            .WithName("GetCompanyMonitoringSummary")
            .WithSummary("Admin: resumo de sincronização de uma empresa específica")
            .AllowAnonymous();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /api/monitoring/summary — resumo de todas as empresas
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> GetSummary(AppDbContext db, CancellationToken ct)
    {
        // IgnoreQueryFilters para que o admin veja TODOS os tenants
        var orderStats = await db.Orders
            .IgnoreQueryFilters()
            .GroupBy(o => new { o.CompanyId, o.Status })
            .Select(g => new
            {
                g.Key.CompanyId,
                g.Key.Status,
                Count = g.Count(),
            })
            .ToListAsync(ct);

        var productCounts = await db.Products
            .IgnoreQueryFilters()
            .GroupBy(p => p.CompanyId)
            .Select(g => new { CompanyId = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        var customerCounts = await db.Customers
            .IgnoreQueryFilters()
            .GroupBy(c => c.CompanyId)
            .Select(g => new { CompanyId = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        // Consolida por empresa
        var allCompanyIds = orderStats.Select(o => o.CompanyId)
            .Concat(productCounts.Select(p => p.CompanyId))
            .Concat(customerCounts.Select(c => c.CompanyId))
            .Distinct()
            .ToList();

        var summaries = allCompanyIds.Select(companyId =>
        {
            var stats = orderStats.Where(o => o.CompanyId == companyId).ToList();
            return new
            {
                companyId,
                orders = new
                {
                    pending    = stats.FirstOrDefault(s => s.Status == "pending")?.Count    ?? 0,
                    processing = stats.FirstOrDefault(s => s.Status == "processing")?.Count ?? 0,
                    synced     = stats.FirstOrDefault(s => s.Status == "synced")?.Count     ?? 0,
                    error      = stats.FirstOrDefault(s => s.Status == "error")?.Count      ?? 0,
                    total      = stats.Sum(s => s.Count),
                },
                catalog = new
                {
                    products  = productCounts.FirstOrDefault(p => p.CompanyId == companyId)?.Count  ?? 0,
                    customers = customerCounts.FirstOrDefault(c => c.CompanyId == companyId)?.Count ?? 0,
                },
                generatedAt = DateTime.UtcNow.ToString("O"),
            };
        }).ToList();

        return Results.Ok(new { companies = summaries, total = allCompanyIds.Count });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /api/monitoring/summary/{companyId} — resumo de uma empresa
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> GetCompanySummary(
        string companyId, AppDbContext db, CancellationToken ct)
    {
        var orderStats = await db.Orders
            .IgnoreQueryFilters()
            .Where(o => o.CompanyId == companyId)
            .GroupBy(o => o.Status)
            .Select(g => new { Status = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        var lastOrder = await db.Orders
            .IgnoreQueryFilters()
            .Where(o => o.CompanyId == companyId)
            .OrderByDescending(o => o.CreatedAt)
            .Select(o => new { o.CreatedAt, o.Status, o.ErpOrderId })
            .FirstOrDefaultAsync(ct);

        var productCount  = await db.Products.IgnoreQueryFilters().CountAsync(p => p.CompanyId == companyId, ct);
        var customerCount = await db.Customers.IgnoreQueryFilters().CountAsync(c => c.CompanyId == companyId, ct);
        var sellerCount   = await db.Sellers.IgnoreQueryFilters().CountAsync(s => s.CompanyId == companyId, ct);

        var pendingCount = orderStats.FirstOrDefault(s => s.Status == "pending")?.Count ?? 0;

        return Results.Ok(new
        {
            companyId,
            orders = new
            {
                pending    = pendingCount,
                processing = orderStats.FirstOrDefault(s => s.Status == "processing")?.Count ?? 0,
                synced     = orderStats.FirstOrDefault(s => s.Status == "synced")?.Count     ?? 0,
                error      = orderStats.FirstOrDefault(s => s.Status == "error")?.Count      ?? 0,
                total      = orderStats.Sum(s => s.Count),
            },
            catalog = new
            {
                products  = productCount,
                customers = customerCount,
                sellers   = sellerCount,
            },
            lastOrder,
            health = pendingCount > 100
                ? "warning"   // Muitos pedidos pendentes — Worker pode estar offline
                : "ok",
            generatedAt = DateTime.UtcNow.ToString("O"),
        });
    }
}
