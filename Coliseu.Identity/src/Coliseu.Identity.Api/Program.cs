using System.Text;
using System.Threading.RateLimiting;
using Coliseu.Identity.Api.Middleware;
using Coliseu.Identity.Application.Auth.Handlers;
using Coliseu.Identity.Application.Admin.Handlers;
using Coliseu.Identity.Infrastructure;
using Coliseu.Identity.Infrastructure.Persistence;
using Coliseu.Identity.Infrastructure.Security;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Serilog;

// ─────────────────────────────────────────────────────────────────────────────
// Bootstrap logger
// ─────────────────────────────────────────────────────────────────────────────

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("[Startup] Coliseu.Identity API iniciando...");

    var builder = WebApplication.CreateBuilder(args);

    // ── Serilog ──────────────────────────────────────────────────────────────
    builder.Host.UseSerilog((ctx, logConfig) =>
        logConfig.ReadFrom.Configuration(ctx.Configuration));

    // ── Infrastructure (PostgreSQL, Repositories, Security) ──────────────────
    builder.Services.AddIdentityInfrastructure(builder.Configuration);

    // IHttpClientFactory — usado pelo CompaniesController.SyncKeyWithMiddlewareAsync
    builder.Services.AddHttpClient();

    // ── Application Handlers ─────────────────────────────────────────────
    // S2 FIX: Loga warning se SalesApi:BaseUrl não estiver configurada.
    // Em produção, deixar como fallback para api.dominio.com causaria falhas silenciosas.
    var salesApiBaseUrl = builder.Configuration["SalesApi:BaseUrl"];
    if (string.IsNullOrWhiteSpace(salesApiBaseUrl))
    {
        salesApiBaseUrl = "https://api.dominio.com";
        Log.Warning("[Startup] SalesApi:BaseUrl não configurada. Usando fallback '{Fallback}'. " +
                    "Configure a variável de ambiente Sales_Api__BaseUrl ou appsettings.",
                    salesApiBaseUrl);
    }
    else
    {
        Log.Information("[Startup] SalesApi baseUrl: {Url}", salesApiBaseUrl);
    }

    // Lê RefreshTokenDays de JwtOptions para passar aos handlers (S1)
    var jwtRefreshDays = builder.Configuration.GetValue<int>("Jwt:RefreshTokenDays", defaultValue: 30);

    builder.Services.AddScoped(sp => new DeviceLoginHandler(
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ICompanyRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IDeviceRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ISessionRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IAuditLogRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Application.Services.IJwtService>(),
        sp.GetRequiredService<Coliseu.Identity.Application.Services.ICompanyKeyGenerator>(),
        salesApiBaseUrl,
        jwtRefreshDays,
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ICompanyModuleRepository>()));

    builder.Services.AddScoped(sp => new RefreshTokenHandler(
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ISessionRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IDeviceRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ICompanyRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IAuditLogRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Application.Services.IJwtService>(),
        jwtRefreshDays));
    builder.Services.AddScoped(sp => new SelectBranchHandler(
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IBranchRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ICompanyRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IDeviceRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ISessionRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.IAuditLogRepository>(),
        sp.GetRequiredService<Coliseu.Identity.Application.Services.IJwtService>(),
        salesApiBaseUrl,
        jwtRefreshDays,
        sp.GetRequiredService<Coliseu.Identity.Domain.Interfaces.ICompanyModuleRepository>()));
    builder.Services.AddScoped<AdminLoginHandler>();
    builder.Services.AddScoped<CreateCompanyHandler>();
    builder.Services.AddScoped<AdminUsersHandler>();
    builder.Services.AddScoped<PermissionGroupHandler>();
    builder.Services.AddSingleton<Coliseu.Identity.Application.Services.TotpService>();

    var adminSigningKey = builder.Configuration["Jwt:AdminSigningKey"]
        ?? throw new InvalidOperationException("[Startup] Jwt:AdminSigningKey não configurado.");
    var deviceSigningKey = builder.Configuration["Jwt:DeviceSigningKey"]
        ?? throw new InvalidOperationException("[Startup] Jwt:DeviceSigningKey não configurado.");

    builder.Services.AddAuthentication()
        .AddJwtBearer("AdminJwt", options =>
        {
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = "coliseu-identity-admin",
                ValidateAudience = true,
                ValidAudience = "coliseu-identity-api",
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(
                    Encoding.UTF8.GetBytes(adminSigningKey)),
                ClockSkew = TimeSpan.FromSeconds(30),
            };
        })
        .AddJwtBearer("DeviceJwt", options =>
        {
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = "coliseu-identity-device",
                ValidateAudience = true,
                ValidAudience = "coliseu-speed-api",
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(
                    Encoding.UTF8.GetBytes(deviceSigningKey)),
                ClockSkew = TimeSpan.FromSeconds(30),
            };
        });

    builder.Services.AddAuthorization();

    // ── Rate Limiting ────────────────────────────────────────────────────────
    builder.Services.AddRateLimiter(options =>
    {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

        options.AddPolicy("DeviceLogin", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    Window = TimeSpan.FromMinutes(1),
                    PermitLimit = 5,
                    QueueLimit = 0,
                }));

        options.AddPolicy("AdminLogin", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    Window = TimeSpan.FromMinutes(1),
                    PermitLimit = 3,
                    QueueLimit = 0,
                }));
    });

    // ── CORS ─────────────────────────────────────────────────────────────────
    var isDev = builder.Environment.IsDevelopment();
    builder.Services.AddCors(opt => opt.AddDefaultPolicy(policy =>
    {
        if (isDev)
        {
            policy.SetIsOriginAllowed(origin =>
                    new Uri(origin).Host == "localhost" ||
                    new Uri(origin).Host == "127.0.0.1")
                  .AllowAnyMethod()
                  .AllowAnyHeader()
                  .AllowCredentials();
        }
        else
        {
            policy.WithOrigins(
                    "https://adminlicencas.coliseusistemas.com.br",
                    "https://licencas.coliseusistemas.com.br",
                    "https://autocenter.coliseusistemas.com.br")
                  .AllowAnyMethod()
                  .AllowAnyHeader()
                  .AllowCredentials();
        }
    }));

    // ── Controllers + Swagger ────────────────────────────────────────────────
    builder.Services.AddControllers();
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(c =>
    {
        c.SwaggerDoc("v1", new OpenApiInfo
        {
            Title = "Coliseu.Identity API",
            Version = "v1",
            Description = "Servidor central de autenticação e licenciamento",
        });
        c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
        {
            Name = "Authorization",
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            In = ParameterLocation.Header,
        });
        c.AddSecurityRequirement(new OpenApiSecurityRequirement
        {
            [new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer",
                },
            }] = Array.Empty<string>(),
        });
    });

    // ── Health Checks ────────────────────────────────────────────────────────
    var hcBuilder = builder.Services.AddHealthChecks();
    var connStr = builder.Configuration.GetConnectionString("DefaultConnection") ?? "";
    if (!connStr.StartsWith("Data Source="))
    {
        hcBuilder.AddNpgSql(connStr, name: "postgresql");
    }

    // ─────────────────────────────────────────────────────────────────────────
    var app = builder.Build();

    // ── Migrations e Seed automáticos ───────────────────────────────────────
    await DbInitializer.InitializeAsync(app.Services);

    // ── Middleware pipeline ──────────────────────────────────────────────────
    app.UseMiddleware<ExceptionHandlingMiddleware>();
    app.UseSerilogRequestLogging(opt =>
    {
        opt.MessageTemplate = "[{Method}] {RequestPath} → {StatusCode} ({Elapsed:0}ms)";
    });

    app.UseCors();
    app.UseRateLimiter();
    app.UseAuthentication();
    app.UseAuthorization();

    // ── Endpoints ────────────────────────────────────────────────────────────
    app.MapControllers();

    // Health check público
    app.MapHealthChecks("/health").AllowAnonymous();

    // Swagger (apenas em Development)
    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI(c =>
        {
            c.SwaggerEndpoint("/swagger/v1/swagger.json", "Coliseu.Identity API v1");
            c.RoutePrefix = "swagger";
        });
        Log.Information("[Startup] Swagger UI: /swagger");
    }

    // ── Inline Migrations (idempotent) ────────────────────────────────────
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<Coliseu.Identity.Infrastructure.Persistence.IdentityDbContext>();
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS \"AdminEmail\" VARCHAR(200)");
            Log.Information("[Startup] Migration: admin_email column ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: admin_email column check failed (non-fatal).");
        }

        // ── AllowNegativeStock (migration 20260327) ───────────────────────────
        // Garante que a coluna existe no PostgreSQL da VPS mesmo que o EF migrate
        // runner não tenha sido executado (ex: container re-startado sem rebuild).
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE companies ADD COLUMN IF NOT EXISTS \"AllowNegativeStock\" BOOLEAN NOT NULL DEFAULT false");
            Log.Information("[Startup] Migration: AllowNegativeStock column ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: AllowNegativeStock column check failed (non-fatal).");
        }

        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE companies ADD COLUMN IF NOT EXISTS \"PriceTableMode\" character varying(50) NOT NULL DEFAULT 'none'");
            Log.Information("[Startup] Migration: PriceTableMode column ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: PriceTableMode column check failed (non-fatal).");
        }

        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE companies ADD COLUMN IF NOT EXISTS \"ContactEmail\" character varying(255) NULL");
            Log.Information("[Startup] Migration: ContactEmail column ensured.");
        }
        catch (Exception ex) { }

        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE companies ADD COLUMN IF NOT EXISTS \"LogoBase64\" text NULL");
            Log.Information("[Startup] Migration: LogoBase64 column ensured.");
        }
        catch (Exception ex) { }

        // ── CompanyModules Table (migration 20260416 — Multi-App Platform) ────
        try
        {
            await db.Database.ExecuteSqlRawAsync(@"
                CREATE TABLE IF NOT EXISTS company_modules (
                    ""Id""               UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
                    ""CompanyId""        UUID NOT NULL REFERENCES companies(""Id"") ON DELETE CASCADE,
                    ""ModuleSlug""       VARCHAR(50) NOT NULL,
                    ""ApiKeyHash""       VARCHAR(64) NOT NULL,
                    ""DeviceLimit""      INT NOT NULL DEFAULT 5,
                    ""IsActive""         BOOLEAN NOT NULL DEFAULT true,
                    ""MiddlewareBaseUrl"" VARCHAR(500) NULL,
                    ""CreatedAt""        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    ""UpdatedAt""        TIMESTAMPTZ NULL,
                    CONSTRAINT ""IX_company_modules_CompanyId_ModuleSlug"" UNIQUE (""CompanyId"", ""ModuleSlug"")
                )");
            Log.Information("[Startup] Migration: company_modules table ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: company_modules table check failed (non-fatal).");
        }

        // ── Index on ApiKeyHash for fast lookup ───────────────────────────────
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "CREATE INDEX IF NOT EXISTS \"IX_company_modules_ApiKeyHash\" ON company_modules (\"ApiKeyHash\")");
            Log.Information("[Startup] Migration: IX_company_modules_ApiKeyHash ensured.");
        }
        catch (Exception ex) { }

        // ── ModuleSlug column in devices (backward compat: default coliseu-speed) ──
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "ALTER TABLE devices ADD COLUMN IF NOT EXISTS \"ModuleSlug\" VARCHAR(50) NOT NULL DEFAULT 'coliseu-speed'");
            Log.Information("[Startup] Migration: devices.ModuleSlug column ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: devices.ModuleSlug column check failed (non-fatal).");
        }

        // ── Replace old unique index with module-scoped one ───────────────────
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                "DROP INDEX IF EXISTS \"IX_devices_DeviceUuid_CompanyId\"");
            await db.Database.ExecuteSqlRawAsync(@"
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_devices_DeviceUuid_CompanyId_Module""
                    ON devices (""DeviceUuid"", ""CompanyId"", ""ModuleSlug"")
                    WHERE ""DeviceUuid"" IS NOT NULL");
            Log.Information("[Startup] Migration: IX_devices_DeviceUuid_CompanyId_Module ensured.");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "[Startup] Migration: device index migration failed (non-fatal).");
        }
    }

    // ── Run ──────────────────────────────────────────────────────────────────
    Log.Information("[Startup] Coliseu.Identity API pronta.");
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "[Startup] Falha crítica ao iniciar o Identity Server.");
    return 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}

return 0;

// Expõe a classe Program para o WebApplicationFactory nos projetos de testes.
// Não tem efeito em produção — é o padrão .NET 8 para integração com xUnit.
public partial class Program { }
