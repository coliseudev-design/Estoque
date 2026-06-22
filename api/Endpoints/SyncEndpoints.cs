using ColiseuSales.Api.Auth;
using ColiseuSales.Api.Data;
using ColiseuSales.Api.Data.Entities;
using ColiseuSales.Shared.Dtos;
using Microsoft.EntityFrameworkCore;

namespace ColiseuSales.Api.Endpoints;

/// <summary>
/// Endpoints de sincronização do catálogo.
///
/// PUSH (Worker → API): POST /api/sync/{entity}
///   - Worker envia snapshot do Firebird; API faz upsert no SQLite
///
/// PULL (API → Flutter): GET /api/sync/{entity}
///   - Flutter busca dados com suporte a delta sync (?since=timestamp)
/// </summary>
public static class SyncEndpoints
{
    public static void MapSyncEndpoints(this WebApplication app)
    {
        var sync = app.MapGroup("/api/sync")
            .WithTags("Sync")
            .RequireAuthorization();

        // ── SELLERS ──────────────────────────────────────────────────────────

        sync.MapPost("/sellers", PushSellers)
            .WithName("PushSellers")
            .WithSummary("Worker → API: envia vendedores do ERP");

        sync.MapGet("/sellers", GetSellers)
            .WithName("GetSellers")
            .WithSummary("Flutter ← API: retorna vendedores com acesso mobile");

        // ── CATALOG ──────────────────────────────────────────────────────────

        sync.MapPost("/catalog", PushCatalog)
            .WithName("PushCatalog")
            .WithSummary("Worker → API: envia catálogo de produtos");

        sync.MapGet("/catalog", GetCatalog)
            .WithName("GetCatalog")
            .WithSummary("Flutter ← API: retorna catálogo (delta por ?since=)");

        // ── CUSTOMERS ────────────────────────────────────────────────────────

        sync.MapPost("/customers", PushCustomers)
            .WithName("PushCustomers")
            .WithSummary("Worker → API: envia clientes");

        sync.MapGet("/customers", GetCustomers)
            .WithName("GetCustomers")
            .WithSummary("Flutter ← API: retorna clientes");

        // ── PAYMENT SPECIES ───────────────────────────────────────────────────

        sync.MapPost("/payment-species", PushPaymentSpecies)
            .WithName("PushPaymentSpecies")
            .WithSummary("Worker → API: envia espécies de pagamento");

        sync.MapGet("/payment-species", GetPaymentSpecies)
            .WithName("GetPaymentSpecies")
            .WithSummary("Flutter ← API: retorna espécies de pagamento");

        // ── PAYMENT CONDITIONS ───────────────────────────────────────────────────

        sync.MapPost("/payment-conditions", PushPaymentConditions)
            .WithName("PushPaymentConditions")
            .WithSummary("Worker → API: envia condições de pagamento (MOB_ACESSO=1)");

        sync.MapGet("/payment-conditions", GetPaymentConditions)
            .WithName("GetPaymentConditions")
            .WithSummary("Flutter ← API: retorna condições de pagamento");

        // ── NATUREZA OPERAÇÃO ───────────────────────────────────────────────

        sync.MapPost("/natureza", PushNatureza)
            .WithName("PushNatureza")
            .WithSummary("Worker → API: envia naturezas de operação (MOB_ACESSO='S')");

        sync.MapGet("/natureza", GetNatureza)
            .WithName("GetNatureza")
            .WithSummary("Flutter ← API: retorna naturezas de operação do app");

        // ── FINANCIALS ────────────────────────────────────────────────────────

        sync.MapPost("/financials", PushFinancials)
            .WithName("PushFinancials")
            .WithSummary("Worker → API: envia títulos financeiros");

        sync.MapGet("/financials", GetFinancials)
            .WithName("GetFinancials")
            .WithSummary("Flutter ← API: retorna contas a receber por cliente");

        // ── SALES RANKINGS ────────────────────────────────────────────────────

        sync.MapPost("/sales-rankings", PushSalesRankings)
            .WithName("PushSalesRankings")
            .WithSummary("Worker → API: envia rankings de vendas e dashboards");

        sync.MapGet("/sales-rankings", GetSalesRankings)
            .WithName("GetSalesRankings")
            .WithSummary("Flutter ← API: retorna rankings de vendas");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SELLERS
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushSellers(
        PushSellersRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        if (req.Sellers is not { Count: > 0 })
            return Results.BadRequest(new ErrorResponse("Lista de vendedores vazia."));

        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        var inserted = 0;

        foreach (var dto in req.Sellers)
        {
            var existing = await db.Sellers.IgnoreQueryFilters()
                .FirstOrDefaultAsync(s => s.Id == dto.Id && s.CompanyId == companyId, ct);
            if (existing is null)
            {
                db.Sellers.Add(new Seller {
                    Id           = dto.Id,
                    CompanyId    = companyId,
                    MobileId     = dto.MobileId,
                    Name         = dto.Name,
                    Email        = dto.Email,
                    PasswordHash = dto.PasswordHash,
                    MaxDiscount  = dto.MaxDiscount,
                    CommissionRate = dto.CommissionRate,
                    SyncedAt     = now,
                });
                inserted++;
            }
            else
            {
                existing.MobileId      = dto.MobileId;
                existing.Name          = dto.Name;
                existing.Email         = dto.Email;
                existing.PasswordHash  = dto.PasswordHash;
                existing.MaxDiscount   = dto.MaxDiscount;
                existing.CommissionRate = dto.CommissionRate;
                existing.SyncedAt      = now;
            }
        }

        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Sellers.Count} vendedores sincronizados.", req.Sellers.Count));
    }

    private static async Task<IResult> GetSellers(AppDbContext db, CancellationToken ct)
    {
        var sellers = await db.Sellers
            .OrderBy(s => s.Name)
            .Select(s => new SellerDto(
                s.Id, s.MobileId, s.Name, s.Email,
                s.PasswordHash, s.MaxDiscount, s.CommissionRate))
            .ToListAsync(ct);

        return Results.Ok(new {
            sellers,
            syncedAt = DateTime.UtcNow.ToString("O"),
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CATALOG
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushCatalog(
        PushCatalogRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        if (req.Products is not { Count: > 0 })
            return Results.BadRequest(new ErrorResponse("Lista de produtos vazia."));

        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");

        foreach (var dto in req.Products)
        {
            var code = dto.Code?.ToString() ?? "";
            if (string.IsNullOrWhiteSpace(code)) continue;

            var existing = await db.Products.IgnoreQueryFilters()
                .FirstOrDefaultAsync(p => p.Code == code && p.CompanyId == companyId, ct);
            if (existing is null)
            {
                db.Products.Add(MapProduct(dto, now, companyId));
            }
            else
            {
                UpdateProduct(existing, dto, now);
            }
        }

        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Products.Count} produtos sincronizados.", req.Products.Count));
    }

    private static async Task<IResult> GetCatalog(
        AppDbContext db, string? since, CancellationToken ct)
    {
        var query = db.Products.AsQueryable();

        if (!string.IsNullOrWhiteSpace(since) &&
            DateTime.TryParse(since, out var sinceDate))
        {
            var sinceParsed = sinceDate.ToString("O");
            query = query.Where(p => string.Compare(p.SyncedAt, sinceParsed) > 0);
        }

        var products = await query
            .OrderBy(p => p.Name)
            .Select(p => new ProductDto(
                p.Code, p.Name, p.NameShort, p.Price, p.PriceMin,
                p.Stock, p.Unit, p.Brand, p.BarCode, p.Reference,
                p.MaxDiscount, p.UpdatedAt))
            .ToListAsync(ct);

        return Results.Ok(new {
            products,
            total    = products.Count,
            syncedAt = DateTime.UtcNow.ToString("O"),
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CUSTOMERS
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushCustomers(
        PushCustomersRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        if (req.Customers is not { Count: > 0 })
            return Results.BadRequest(new ErrorResponse("Lista de clientes vazia."));

        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");

        foreach (var dto in req.Customers)
        {
            var id = dto.Id?.ToString() ?? "";
            if (string.IsNullOrWhiteSpace(id)) continue;

            var existing = await db.Customers.IgnoreQueryFilters()
                .FirstOrDefaultAsync(c => c.Id == id && c.CompanyId == companyId, ct);
            if (existing is null)
            {
                db.Customers.Add(new Customer {
                    Id          = id, CompanyId  = companyId,
                    Name        = dto.Name,
                    TradeName   = dto.TradeName, Cnpj       = dto.Cnpj,
                    Phone       = dto.Phone,     Mobile     = dto.Mobile,
                    Email       = dto.Email,     City       = dto.City,
                    State       = dto.State,     CreditLimit = dto.CreditLimit,
                    Status      = dto.Status,    SellerId   = dto.SellerId,
                    SyncedAt    = now,
                });
            }
            else
            {
                existing.Name       = dto.Name;     existing.TradeName  = dto.TradeName;
                existing.Cnpj       = dto.Cnpj;     existing.Phone      = dto.Phone;
                existing.Mobile     = dto.Mobile;   existing.Email      = dto.Email;
                existing.City       = dto.City;     existing.State      = dto.State;
                existing.CreditLimit = dto.CreditLimit; existing.Status = dto.Status;
                existing.SellerId   = dto.SellerId; existing.SyncedAt   = now;
            }
        }

        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Customers.Count} clientes sincronizados.", req.Customers.Count));
    }

    private static async Task<IResult> GetCustomers(
        AppDbContext db, string? since, CancellationToken ct)
    {
        var query = db.Customers.AsQueryable();

        if (!string.IsNullOrWhiteSpace(since) &&
            DateTime.TryParse(since, out var sinceDate))
        {
            var sinceParsed = sinceDate.ToString("O");
            query = query.Where(c => string.Compare(c.SyncedAt, sinceParsed) > 0);
        }

        var customers = await query
            .OrderBy(c => c.Name)
            .Select(c => new CustomerDto(
                c.Id, c.Name, c.TradeName, c.Cnpj, c.Phone, c.Mobile,
                c.Email, c.City, c.State, c.CreditLimit, c.Status, c.SellerId, null))
            .ToListAsync(ct);

        return Results.Ok(new {
            customers,
            total    = customers.Count,
            syncedAt = DateTime.UtcNow.ToString("O"),
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PAYMENT SPECIES
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushPaymentSpecies(
        PushPaymentSpeciesRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        foreach (var dto in req.Species ?? [])
        {
            var existing = await db.PaymentSpecies.IgnoreQueryFilters()
                .FirstOrDefaultAsync(s => s.Id == dto.Id && s.CompanyId == companyId, ct);
            if (existing is null)
                db.PaymentSpecies.Add(new PaymentSpecies { Id = dto.Id, CompanyId = companyId, Name = dto.Name, Type = dto.Type, Days = dto.Days, SyncedAt = now });
            else
            { existing.Name = dto.Name; existing.Type = dto.Type; existing.Days = dto.Days; existing.SyncedAt = now; }
        }
        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Species?.Count ?? 0} espécies sincronizadas."));
    }

    private static async Task<IResult> GetPaymentSpecies(AppDbContext db, CancellationToken ct)
    {
        var data = await db.PaymentSpecies
            .OrderBy(s => s.Name)
            .Select(s => new PaymentSpeciesDto(s.Id, s.Name, s.Type, s.Days))
            .ToListAsync(ct);
        return Results.Ok(new { data, total = data.Count, syncedAt = DateTime.UtcNow.ToString("O") });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PAYMENT CONDITIONS
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushPaymentConditions(
        PushPaymentConditionRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        foreach (var dto in req.Conditions ?? [])
        {
            var existing = await db.PaymentConditions.IgnoreQueryFilters()
                .FirstOrDefaultAsync(c => c.Id == dto.Id && c.CompanyId == companyId, ct);
            if (existing is null)
                db.PaymentConditions.Add(new PaymentCondition {
                    Id = dto.Id,
                    CompanyId = companyId,
                    Descricao = dto.Descricao,
                    DescontoMax = dto.DescontoMax,
                    Parcelas = dto.Parcelas,
                    DiasEntrada = dto.DiasEntrada,
                    DiasParcelas = dto.DiasParcelas,
                    MobOrdem = dto.MobOrdem,
                    SyncedAt = now
                });
            else
            {
                existing.Descricao = dto.Descricao;
                existing.DescontoMax = dto.DescontoMax;
                existing.Parcelas = dto.Parcelas;
                existing.DiasEntrada = dto.DiasEntrada;
                existing.DiasParcelas = dto.DiasParcelas;
                existing.MobOrdem = dto.MobOrdem;
                existing.SyncedAt = now;
            }
        }
        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Conditions?.Count ?? 0} condições de pagamento sincronizadas."));
    }

    private static async Task<IResult> GetPaymentConditions(AppDbContext db, CancellationToken ct)
    {
        var data = await db.PaymentConditions
            .OrderBy(c => c.MobOrdem).ThenBy(c => c.Descricao)
            .Select(c => new PaymentConditionDto(
                c.Id, c.Descricao, c.DescontoMax, c.Parcelas,
                c.DiasEntrada, c.DiasParcelas, c.MobOrdem))
            .ToListAsync(ct);
        return Results.Ok(new { data, total = data.Count, syncedAt = DateTime.UtcNow.ToString("O") });
    }

    private static async Task<IResult> PushNatureza(
        PushNaturezaRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        foreach (var dto in req.Naturezas ?? [])
        {
            var existing = await db.NaturezasOperacao.IgnoreQueryFilters()
                .FirstOrDefaultAsync(n => n.Id == dto.Id && n.CompanyId == companyId, ct);
            if (existing is null)
                db.NaturezasOperacao.Add(new NaturezaOperacao {
                    Id = dto.Id, CompanyId = companyId, Descricao = dto.Descricao,
                    DescricaoNota = dto.DescricaoNota, CodigoFiscal = dto.CodigoFiscal,
                    Es = dto.Es, MobOrdem = dto.MobOrdem, SyncedAt = now,
                });
            else
            {
                existing.Descricao     = dto.Descricao;
                existing.DescricaoNota = dto.DescricaoNota;
                existing.CodigoFiscal  = dto.CodigoFiscal;
                existing.Es            = dto.Es;
                existing.MobOrdem      = dto.MobOrdem;
                existing.SyncedAt      = now;
            }
        }
        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Naturezas?.Count ?? 0} naturezas sincronizadas."));
    }

    private static async Task<IResult> GetNatureza(AppDbContext db, CancellationToken ct)
    {
        var naturezas = await db.NaturezasOperacao
            .OrderBy(n => n.MobOrdem)
            .ThenBy(n => n.Descricao)
            .Select(n => new {
                id            = n.Id,
                descricao     = n.Descricao,
                descricaoNota = n.DescricaoNota,
                codigoFiscal  = n.CodigoFiscal,
                es            = n.Es,
                mobOrdem      = n.MobOrdem,
            })
            .ToListAsync(ct);
        return Results.Ok(new { data = naturezas, total = naturezas.Count, syncedAt = DateTime.UtcNow.ToString("O") });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FINANCIALS
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushFinancials(
        PushFinancialsRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        foreach (var dto in req.Financials ?? [])
        {
            var existing = await db.Financials.IgnoreQueryFilters()
                .FirstOrDefaultAsync(f => f.Id == dto.Id && f.CompanyId == companyId, ct);
            if (existing is null)
                db.Financials.Add(new Financial {
                    Id = dto.Id, CompanyId = companyId, CustomerId = dto.CustomerId,
                    DocNumber = dto.DocNumber,
                    Amount = dto.Amount, Interest = dto.Interest ?? 0, DueDate = dto.DueDate,
                    PaymentSpeciesId = dto.PaymentSpeciesId, IsPaid = dto.IsPaid,
                    Type = dto.Type, PaymentDate = dto.PaymentDate, SyncedAt = now,
                });
            else
            {
                existing.IsPaid = dto.IsPaid; existing.PaymentDate = dto.PaymentDate;
                existing.Amount = dto.Amount; existing.SyncedAt = now;
            }
        }
        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Financials?.Count ?? 0} títulos sincronizados."));
    }

    private static async Task<IResult> GetFinancials(
        AppDbContext db, string? customerId, CancellationToken ct)
    {
        var query = db.Financials.AsQueryable();
        if (!string.IsNullOrWhiteSpace(customerId))
            query = query.Where(f => f.CustomerId == customerId);

        var financials = await query
            .OrderByDescending(f => f.DueDate)
            .Select(f => new FinancialDto(
                f.Id, f.CustomerId, f.DocNumber, f.Amount, f.Interest,
                f.DueDate, f.PaymentSpeciesId, f.IsPaid, f.Type, f.PaymentDate))
            .ToListAsync(ct);

        return Results.Ok(new { financials, total = financials.Count, syncedAt = DateTime.UtcNow.ToString("O") });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers — Mapeamento de entidades
    // ─────────────────────────────────────────────────────────────────────────

    private static Product MapProduct(ProductDto dto, string now, string companyId) => new()
    {
        Code = dto.Code.ToString(), CompanyId = companyId,
        Name = dto.Name, NameShort = dto.NameShort,
        Price = dto.Price ?? 0, PriceMin = dto.PriceMin, Stock = dto.Stock, Unit = dto.Unit,
        Brand = dto.Brand, BarCode = dto.BarCode, Reference = dto.Reference,
        MaxDiscount = dto.MaxDiscount, UpdatedAt = dto.UpdatedAt ?? now, SyncedAt = now,
    };

    private static void UpdateProduct(Product p, ProductDto dto, string now)
    {
        p.Name = dto.Name;       p.NameShort = dto.NameShort;
        p.Price = dto.Price ?? 0;     p.PriceMin = dto.PriceMin;
        p.Stock = dto.Stock;     p.Unit = dto.Unit;
        p.Brand = dto.Brand;     p.BarCode = dto.BarCode;
        p.Reference = dto.Reference; p.MaxDiscount = dto.MaxDiscount;
        p.UpdatedAt = dto.UpdatedAt ?? now; p.SyncedAt = now;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SALES RANKINGS
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> PushSalesRankings(
        PushSalesRankingsRequest req, AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        if (req.Rankings is not { Count: > 0 })
            return Results.BadRequest(new ErrorResponse("Lista de rankings vazia."));
            
        var companyId = httpContext.RequireCompanyId();
        var now = DateTime.UtcNow.ToString("O");
        
        foreach (var ele in req.Rankings)
        {
            if (!ele.TryGetProperty("sellerId", out var sellerProp)) continue;
            var sellerId = sellerProp.ToString();
            var id = $"{companyId}_{sellerId}";
            
            var existing = await db.SalesRankings.IgnoreQueryFilters()
                .FirstOrDefaultAsync(s => s.Id == id, ct);
                
            var content = ele.GetRawText();
            
            if (existing is null)
            {
                db.SalesRankings.Add(new SalesRanking {
                    Id = id, CompanyId = companyId, SellerId = sellerId, Content = content, SyncedAt = now
                });
            }
            else
            {
                existing.Content = content; existing.SyncedAt = now;
            }
        }
        await db.SaveChangesAsync(ct);
        return Results.Ok(new SuccessResponse($"{req.Rankings.Count} dashboards sincronizados."));
    }

    private static async Task<IResult> GetSalesRankings(
        AppDbContext db, string? sellerId, CancellationToken ct)
    {
        var q = db.SalesRankings.AsQueryable();
        if (!string.IsNullOrWhiteSpace(sellerId))
            q = q.Where(s => s.SellerId == sellerId);
            
        var rankings = await q.ToListAsync(ct);
        
        var resultList = new List<object>();
        foreach (var r in rankings) {
            try { 
                resultList.Add(System.Text.Json.JsonDocument.Parse(r.Content).RootElement); 
            }
            catch { /* ignore */ }
        }
        
        return Results.Ok(new { rankings = resultList, total = resultList.Count, syncedAt = DateTime.UtcNow.ToString("O") });
    }
}

// Nota: PushRequest records foram movidos para ColiseuSales.Shared.Dtos.SyncDtos.cs
// Este arquivo usa os tipos do Shared via ColiseuSales.Shared.Dtos namespace
