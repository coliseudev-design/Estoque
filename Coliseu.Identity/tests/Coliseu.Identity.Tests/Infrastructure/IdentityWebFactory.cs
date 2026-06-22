using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Application.Auth.Handlers;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Interfaces;
using Coliseu.Identity.Infrastructure;
using Coliseu.Identity.Infrastructure.Persistence;
using Coliseu.Identity.Infrastructure.Security;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using System.Text;

namespace Coliseu.Identity.Tests.Infrastructure;

/// <summary>
/// Factory de teste usando TestServer (in-process, sem Kestrel).
/// Não usa portas de rede — zero conflito entre testes paralelos.
/// SQLite em arquivo temporário por instância.
/// </summary>
public sealed class IdentityWebFactory : IDisposable
{
    public const string TestDeviceSigningKey = "test-device-signing-key-256bits-minimum-length-ok!!";
    public const string TestAdminSigningKey  = "test-admin-signing-key-256bits-minimum-length-ok!!!!";
    /// <summary>32 bytes = 256 bits em Base64 (obrigatório para AES-256-GCM)</summary>
    public const string TestEncryptionKey    = "dGVzdC1lbmNyeXB0aW9uLWtleS0zMmJ5dGVzLW9rISE=";
    public const string TestInternalApiKey   = "test-internal-api-key-secret";


    private readonly string _testDbPath;
    private WebApplication? _app;
    private TestServer? _testServer;
    private HttpClient? _client;
    private IServiceProvider? _services;

    public IdentityWebFactory()
    {
        _testDbPath = Path.Combine(Path.GetTempPath(), $"id-test-{Guid.NewGuid():N}.db");
    }

    public async Task<HttpClient> GetClientAsync()
    {
        if (_client is not null) return _client;

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:DefaultConnection"] = $"Data Source={_testDbPath}",
                ["Jwt:DeviceSigningKey"]                = TestDeviceSigningKey,
                ["Jwt:AdminSigningKey"]                 = TestAdminSigningKey,
                ["Jwt:DeviceExpirationMinutes"]         = "30",
                ["Jwt:AdminExpirationMinutes"]          = "15",
                ["Jwt:RefreshTokenDays"]                = "30",
                ["Encryption:Key"]                      = TestEncryptionKey,
                ["InternalApiKey"]                      = TestInternalApiKey,  // chave sem dois-pontos (como o filtro lê)
                ["SalesApi:BaseUrl"]                    = "https://test.internal",
                ["Serilog:MinimumLevel:Default"]        = "Error",
            })
            .Build();

        var builder = WebApplication.CreateBuilder();
        builder.Configuration.AddConfiguration(config);
        builder.WebHost.UseTestServer(); // ← In-process, sem Kestrel real

        // ── Infra com SQLite ──────────────────────────────────────────────────
        builder.Services.AddIdentityInfrastructure(builder.Configuration);
        // Substitui o DbContext com SQLite temporário
        var dbDesc = builder.Services.SingleOrDefault(
            d => d.ServiceType == typeof(DbContextOptions<IdentityDbContext>));
        if (dbDesc is not null) builder.Services.Remove(dbDesc);
        builder.Services.AddDbContext<IdentityDbContext>(o =>
            o.UseSqlite($"Data Source={_testDbPath}"));

        // ── Handlers (mesma lógica do Program.cs de produção) ─────────────────
        builder.Services.AddScoped(sp => new DeviceLoginHandler(
            sp.GetRequiredService<ICompanyRepository>(),
            sp.GetRequiredService<IDeviceRepository>(),
            sp.GetRequiredService<ISessionRepository>(),
            sp.GetRequiredService<IAuditLogRepository>(),
            sp.GetRequiredService<IJwtService>(),
            sp.GetRequiredService<ICompanyKeyGenerator>(),
            "https://test.internal",
            30,
            sp.GetRequiredService<ICompanyModuleRepository>()));

        builder.Services.AddScoped(sp => new RefreshTokenHandler(
            sp.GetRequiredService<ISessionRepository>(),
            sp.GetRequiredService<IDeviceRepository>(),
            sp.GetRequiredService<ICompanyRepository>(),
            sp.GetRequiredService<IAuditLogRepository>(),
            sp.GetRequiredService<IJwtService>(), 30));

        builder.Services.AddScoped(sp => new SelectBranchHandler(
            sp.GetRequiredService<IBranchRepository>(),
            sp.GetRequiredService<ICompanyRepository>(),
            sp.GetRequiredService<IDeviceRepository>(),
            sp.GetRequiredService<ISessionRepository>(),
            sp.GetRequiredService<IAuditLogRepository>(),
            sp.GetRequiredService<IJwtService>(),
            "https://test.internal",
            30,
            sp.GetRequiredService<ICompanyModuleRepository>()));

        builder.Services.AddScoped<AdminLoginHandler>();
        builder.Services.AddScoped<CreateCompanyHandler>();
        builder.Services.AddSingleton<TotpService>();
        builder.Services.AddHttpClient();
        builder.Services.AddRateLimiter(opts =>
        {
            // Registra todas as policies usadas pelos controllers como no-op nos testes.
            // AuthController usa 'DeviceLogin', AdminAuthController usa 'AdminLogin'.
            foreach (var policyName in new[] { "DeviceLogin", "AdminLogin", "auth" })
            {
                opts.AddPolicy(policyName, _ =>
                    System.Threading.RateLimiting.RateLimitPartition.GetNoLimiter(policyName));
            }
        });
        builder.Services.AddHealthChecks();

        // ── JWT (usando TestDeviceSigningKey para validação) ───────────────────
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(opts =>
            {
                opts.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer           = false,
                    ValidateAudience         = false,
                    ValidateLifetime         = true,
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = new SymmetricSecurityKey(
                        Encoding.UTF8.GetBytes(TestDeviceSigningKey)),
                    ClockSkew = TimeSpan.Zero,
                };
            });

        builder.Services.AddAuthorization();
        // Descobre controllers do assembly da API (InternalController, DeviceController, etc.)
        builder.Services.AddControllers()
            .AddApplicationPart(typeof(Coliseu.Identity.Api.Controllers.InternalController).Assembly);

        var app = builder.Build();
        _app = app;
        _services = app.Services;

        // Cria o esquema do banco de testes
        using (var scope = app.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();
            db.Database.EnsureCreated();
        }

        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter();
        app.MapControllers();
        app.MapHealthChecks("/health");

        await app.StartAsync();

        _testServer = app.GetTestServer();
        _client = _testServer.CreateClient();
        return _client;
    }

    public IServiceProvider Services => _services
        ?? throw new InvalidOperationException("Chame GetClientAsync() primeiro.");

    public void Dispose()
    {
        _client?.Dispose();
        _testServer?.Dispose();
        _app?.DisposeAsync().AsTask().GetAwaiter().GetResult();
        if (File.Exists(_testDbPath))
            try { File.Delete(_testDbPath); } catch { /* ignora se locked */ }
    }
}
