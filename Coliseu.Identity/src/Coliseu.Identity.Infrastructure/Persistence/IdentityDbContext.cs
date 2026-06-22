using Coliseu.Identity.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Coliseu.Identity.Infrastructure.Persistence;

/// <summary>
/// DbContext central do Coliseu.Identity — PostgreSQL.
///
/// Gerencia todas as entidades do servidor de identidade:
/// Companies, Devices, Sessions, AdminUsers, AuditLogs.
/// </summary>
public sealed class IdentityDbContext : DbContext
{
    public IdentityDbContext(DbContextOptions<IdentityDbContext> options)
        : base(options) { }

    public DbSet<Company>         Companies        => Set<Company>();
    public DbSet<Branch>          Branches         => Set<Branch>();
    public DbSet<CompanyModule>   CompanyModules   => Set<CompanyModule>();
    public DbSet<Device>          Devices          => Set<Device>();
    public DbSet<Session>         Sessions         => Set<Session>();
    public DbSet<AdminUser>       AdminUsers       => Set<AdminUser>();
    public DbSet<AuditLog>        AuditLogs        => Set<AuditLog>();
    public DbSet<PermissionGroup> PermissionGroups => Set<PermissionGroup>();
    public DbSet<Partner>              Partners              => Set<Partner>();
    public DbSet<LicenseRequest>        LicenseRequests       => Set<LicenseRequest>();
    public DbSet<LicenseRequestModule>  LicenseRequestModules => Set<LicenseRequestModule>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(IdentityDbContext).Assembly);
    }
}
