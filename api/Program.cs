using ColiseuSales.Api.Auth;
using ColiseuSales.Api.Data;
using ColiseuSales.Api.Endpoints;
using ColiseuSales.Api.Logging;
using ColiseuSales.Api.Middleware;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
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
    Log.Information("[Startup] Coliseu Sales API iniciando...");

    var builder = WebApplication.CreateBuilder(args);

    // ── Serilog ──────────────────────────────────────────────────────────────
    builder.Host.UseSerilog((ctx, logConfig) =>
        logConfig.ReadFrom.Configuration(ctx.Configuration));

    // ── EF Core + SQLite ─────────────────────────────────────────────────────
    var connString = builder.Configuration.GetConnectionString("DefaultConnection")
        ?? throw new InvalidOperationException("[Startup] ConnectionStrings:DefaultConnection não configurado.");

    builder.Services.AddDbContext<AppDbContext>(opt =>
        opt.UseSqlite(connString));

    // ── RequestLogBuffer (Singleton) ──────────────────────────────────
    // Buffer circular em memória com os últimos 200 requests (sem I/O, sem DB)
    builder.Services.AddSingleton<RequestLogBuffer>();

    // ── CORS — origens permitidas via appsettings (nunca AllowAnyOrigin em prod) ─────
    var allowedOrigins = builder.Configuration
        .GetSection("Cors:AllowedOrigins")
        .Get<string[]>() ?? ["http://localhost:3000", "http://localhost:5173"];

    builder.Services.AddCors(opt => opt.AddDefaultPolicy(policy =>
        policy.WithOrigins(allowedOrigins)
              .AllowAnyMethod()
              .AllowAnyHeader()));

    // ── HttpContext Accessor (para Multi-Tenant no DbContext) ─────────────────
    builder.Services.AddHttpContextAccessor();

    // ── OpenAPI / Swagger ─────────────────────────────────────────────────────
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(c =>
    {
        c.SwaggerDoc("v1", new OpenApiInfo { Title = "Coliseu Sales API", Version = "v1" });
        c.AddSecurityDefinition("ApiKey", new OpenApiSecurityScheme
        {
            Name         = "API-Key",
            In           = ParameterLocation.Header,
            Type         = SecuritySchemeType.ApiKey,
            Description  = "Informe a API Key no header: API-Key: <valor>"
        });
        c.AddSecurityRequirement(new OpenApiSecurityRequirement
        {
            [new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "ApiKey" } }] = Array.Empty<string>()
        });
    });

    // ── Autenticação JWT ──────────────────────────────────────────────────────
    builder.Services.AddAuthentication(Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            var key = builder.Configuration["Jwt:DeviceSigningKey"] ?? 
                throw new InvalidOperationException("[Startup] Jwt:DeviceSigningKey não configurado.");
            
            options.TokenValidationParameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = "coliseu-identity-device",
                ValidateAudience = true,
                ValidAudience = "coliseu-sales-api",
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(key)),
                ClockSkew = TimeSpan.Zero
            };
        });
    builder.Services.AddAuthorization();

    // ── Rate Limiting — protege endpoints pública contra abuso ─────────────────
    builder.Services.AddRateLimiter(options =>
    {
        options.RejectionStatusCode = 429;

        // Sync: 30 requisições/minuto por IP (Worker sincronizando catálogo)
        options.AddFixedWindowLimiter("sync", o =>
        {
            o.PermitLimit      = builder.Configuration.GetValue("RateLimit:SyncPerMinute", 30);
            o.Window           = TimeSpan.FromMinutes(1);
            o.QueueProcessingOrder = System.Threading.RateLimiting.QueueProcessingOrder.OldestFirst;
            o.QueueLimit       = 5;
        });

        // Orders: 10 requisições/minuto por IP (Mobile enviando pedidos)
        options.AddFixedWindowLimiter("orders", o =>
        {
            o.PermitLimit      = builder.Configuration.GetValue("RateLimit:OrdersPerMinute", 10);
            o.Window           = TimeSpan.FromMinutes(1);
            o.QueueProcessingOrder = System.Threading.RateLimiting.QueueProcessingOrder.OldestFirst;
            o.QueueLimit       = 2;
        });

        // Monitoring: 20 requisições/minuto (painel admin consultando)
        options.AddFixedWindowLimiter("monitoring", o =>
        {
            o.PermitLimit      = builder.Configuration.GetValue("RateLimit:MonitoringPerMinute", 20);
            o.Window           = TimeSpan.FromMinutes(1);
            o.QueueProcessingOrder = System.Threading.RateLimiting.QueueProcessingOrder.OldestFirst;
            o.QueueLimit       = 2;
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    var app = builder.Build();

    // ── Migrations automáticas na inicialização ───────────────────────────────
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
        Log.Information("[Startup] Banco SQLite pronto em: {Conn}", connString);
    }

    // ── Middlewares ───────────────────────────────────────────────────────────
    app.UseSerilogRequestLogging(opt =>
    {
        opt.MessageTemplate = "[{Method}] {RequestPath} → {StatusCode} ({Elapsed:0}ms)";
    });

    app.UseCors();
    app.UseRateLimiter();  // Aplica as políticas de rate limit configuradas no DI
    app.UseMiddleware<RequestLoggingMiddleware>();  // Buffer de logs para o painel admin

    app.UseAuthentication();

    // Autenticação por API Key (fallback para Worker se não tiver JWT. Bypassa se JWT for válido)
    app.UseMiddleware<ApiKeyMiddleware>();

    // Multi-Tenant: extrai CompanyId do header X-Company-Id ou JWT claim
    app.UseMiddleware<TenantMiddleware>();

    app.UseAuthorization();

    // ── Endpoints ─────────────────────────────────────────────────────────────

    // Health check público (sem API Key)
    app.MapGet("/health", (AppDbContext db) => new
    {
        status  = "ok",
        service = "Coliseu Sales API",
        db      = db.Database.CanConnect() ? "ok" : "unavailable",
        time    = DateTime.UtcNow.ToString("O"),
    }).WithTags("Health").AllowAnonymous();

    // Swagger — documentação interativa
    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI(c =>
        {
            c.SwaggerEndpoint("/swagger/v1/swagger.json", "Coliseu Sales API v1");
            c.RoutePrefix = "swagger";
        });
        Log.Information("[Startup] Swagger UI disponível em: /swagger");
    }

    // Sync endpoints (Worker ↔ API ↔ Flutter)
    app.MapSyncEndpoints();
    app.MapOrderEndpoints();
    app.MapMonitoringEndpoints();
    app.MapAdminSalesEndpoints();  // Painel admin: stats, config, logs

    // ── Run ───────────────────────────────────────────────────────────────────
    Log.Information("[Startup] API pronta. Endpoints registrados.");
    await app.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "[Startup] Falha crítica ao iniciar a API.");
    return 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}

return 0;
