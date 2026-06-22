using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Interfaces;
using Coliseu.Identity.Infrastructure.Persistence;
using Coliseu.Identity.Infrastructure.Persistence.Repositories;
using Coliseu.Identity.Infrastructure.Security;
using Coliseu.Identity.Infrastructure.Notifications;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace Coliseu.Identity.Infrastructure;

/// <summary>
/// Extensão para registrar todos os serviços de infraestrutura no DI container.
/// Chamado em Program.cs da camada API.
/// </summary>
public static class DependencyInjection
{
    /// <summary>
    /// Registra DbContext, repositórios e serviços de segurança.
    /// </summary>
    public static IServiceCollection AddIdentityInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // ── PostgreSQL ou SQLite (Local Dev) ──────────────────────────────────
        var connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException(
                "[Infrastructure] ConnectionStrings:DefaultConnection não configurado.");

        services.AddDbContext<IdentityDbContext>(options =>
        {
            if (connectionString.StartsWith("Data Source="))
            {
                options.UseSqlite(connectionString, sqlite => 
                {
                    sqlite.MigrationsAssembly(typeof(IdentityDbContext).Assembly.FullName);
                });
            }
            else
            {
                options.UseNpgsql(connectionString, npgsql =>
                {
                    npgsql.MigrationsAssembly(typeof(IdentityDbContext).Assembly.FullName);
                    npgsql.EnableRetryOnFailure(3);
                });
            }
        });

        // ── Repositories ──────────────────────────────────────────────────────
        services.AddScoped<ICompanyRepository, CompanyRepository>();
        services.AddScoped<IDeviceRepository, DeviceRepository>();
        services.AddScoped<ISessionRepository, SessionRepository>();
        services.AddScoped<IAdminUserRepository, AdminUserRepository>();
        services.AddScoped<IAuditLogRepository, AuditLogRepository>();
        services.AddScoped<IPermissionGroupRepository, PermissionGroupRepository>();
        services.AddScoped<ICompanyModuleRepository, CompanyModuleRepository>();
        services.AddScoped<IBranchRepository, BranchRepository>();
        services.AddScoped<IPartnerRepository, PartnerRepository>();
        services.AddScoped<ILicenseRequestRepository, LicenseRequestRepository>();

        // ── Security Services ─────────────────────────────────────────────────
        services.Configure<JwtOptions>(configuration.GetSection(JwtOptions.Section));
        services.Configure<EncryptionOptions>(configuration.GetSection(EncryptionOptions.Section));
        services.Configure<WhatsAppOptions>(configuration.GetSection(WhatsAppOptions.Section));

        services.AddSingleton<IJwtService, JwtService>();
        services.AddSingleton<IEncryptionService, EncryptionService>();
        services.AddSingleton<ICompanyKeyGenerator, CompanyKeyGenerator>();
        services.AddSingleton<IPasswordHasher, PasswordHasher>();
        services.AddSingleton<IWhatsAppService, WhatsAppService>();

        return services;
    }
}
