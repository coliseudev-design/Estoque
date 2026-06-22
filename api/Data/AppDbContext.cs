using ColiseuSales.Api.Auth;
using ColiseuSales.Api.Data.Entities;
using Microsoft.EntityFrameworkCore;

namespace ColiseuSales.Api.Data;

/// <summary>
/// DbContext SQLite — banco buffer da VPS entre Worker e Flutter.
///
/// Responsabilidades:
/// - Armazenar snapshot mais recente do catálogo/clientes/vendedores (do Worker)
/// - Receber pedidos do Flutter e disponibilizá-los ao Worker
/// - Delta sync via UpdatedAt/SyncedAt
///
/// Rule-03 (Multi-Tenant): Global Query Filters isolam dados por CompanyId.
/// O CompanyId é extraído do HttpContext pelo TenantMiddleware.
/// </summary>
public sealed class AppDbContext : DbContext
{
    private readonly IHttpContextAccessor? _httpContextAccessor;

    public AppDbContext(DbContextOptions<AppDbContext> options, IHttpContextAccessor? httpContextAccessor = null)
        : base(options)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public DbSet<Product>          Products         { get; set; }
    public DbSet<Seller>           Sellers          { get; set; }
    public DbSet<Customer>         Customers        { get; set; }
    public DbSet<PaymentSpecies>   PaymentSpecies   { get; set; }
    public DbSet<PaymentCondition> PaymentConditions { get; set; }
    public DbSet<NaturezaOperacao> NaturezasOperacao { get; set; }
    public DbSet<Financial>        Financials       { get; set; }
    public DbSet<Order>            Orders           { get; set; }
    public DbSet<OrderItem>        OrderItems       { get; set; }
    public DbSet<SalesRanking>     SalesRankings    { get; set; }


    /// <summary>CompanyId do tenant atual (extraído do HttpContext).</summary>
    private string? CurrentCompanyId =>
        _httpContextAccessor?.HttpContext?.GetCompanyId();

    protected override void OnModelCreating(ModelBuilder b)
    {
        // ── Product: chave composta Code + CompanyId ──────────────────────────
        b.Entity<Product>()
            .HasKey(p => new { p.Code, p.CompanyId });

        // ── OrderItem → Order FK ─────────────────────────────────────────────
        b.Entity<OrderItem>()
            .HasOne(i => i.Order)
            .WithMany(o => o.Items)
            .HasForeignKey(i => i.OrderId)
            .OnDelete(DeleteBehavior.Cascade);

        // ── Índices compostos para queries frequentes ─────────────────────────
        b.Entity<Order>().HasIndex(o => new { o.CompanyId, o.Status });
        b.Entity<Order>().HasIndex(o => o.CreatedAt);
        b.Entity<Product>().HasIndex(p => new { p.CompanyId, p.Name });
        b.Entity<Customer>().HasIndex(c => new { c.CompanyId, c.Name });
        b.Entity<Seller>().HasIndex(s => new { s.CompanyId, s.Id });

        // ── Global Query Filters (Rule-03: isolamento multi-tenant) ──────────
        // Aplicados automaticamente em TODAS as queries.
        // Para desabilitar em cenários de manutenção: .IgnoreQueryFilters()
        b.Entity<Product>().HasQueryFilter(p => CurrentCompanyId == null || p.CompanyId == CurrentCompanyId);
        b.Entity<Seller>().HasQueryFilter(s => CurrentCompanyId == null || s.CompanyId == CurrentCompanyId);
        b.Entity<Customer>().HasQueryFilter(c => CurrentCompanyId == null || c.CompanyId == CurrentCompanyId);
        b.Entity<PaymentSpecies>().HasQueryFilter(s => CurrentCompanyId == null || s.CompanyId == CurrentCompanyId);
        b.Entity<PaymentCondition>().HasQueryFilter(c => CurrentCompanyId == null || c.CompanyId == CurrentCompanyId);
        b.Entity<NaturezaOperacao>().HasQueryFilter(n => CurrentCompanyId == null || n.CompanyId == CurrentCompanyId);
        b.Entity<Financial>().HasQueryFilter(f => CurrentCompanyId == null || f.CompanyId == CurrentCompanyId);
        b.Entity<Order>().HasQueryFilter(o => CurrentCompanyId == null || o.CompanyId == CurrentCompanyId);
        b.Entity<SalesRanking>().HasQueryFilter(s => CurrentCompanyId == null || s.CompanyId == CurrentCompanyId);
    }
}

