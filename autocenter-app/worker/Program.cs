using ColiseuSales.Worker;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Jobs;
using ColiseuSales.Worker.Services;
using Serilog;

// Registra provider de CodePages para suportar Charset=WIN1252 do Firebird
System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);

// ─────────────────────────────────────────────────────────────────────────────
// Logging inicial (antes da injeção de dependência)
// ─────────────────────────────────────────────────────────────────────────────

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("[Startup] Coliseu Sales Worker iniciando...");

    var builder = Host.CreateApplicationBuilder(args);

    // ── Windows Service ──────────────────────────────────────────────────────
    builder.Services.AddWindowsService(options =>
    {
        options.ServiceName = "Coliseu Sales Worker";
    });

    // ── Serilog ──────────────────────────────────────────────────────────────
    // IMPORTANTE: ReadFrom.Configuration falha em single-file publish sem
    // a seção "Serilog:Using" explícita (auto-discovery de assemblies não funciona).
    // Por isso configuramos os sinks diretamente em código.
    builder.Services.AddSerilog((services, logConfig) =>
    {
        var statusStore = services.GetRequiredService<StatusStore>();
        logConfig
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", Serilog.Events.LogEventLevel.Warning)
            .MinimumLevel.Override("Microsoft.Hosting.Lifetime", Serilog.Events.LogEventLevel.Information)
            .Enrich.FromLogContext()
            .WriteTo.Console()
            .WriteTo.File(
                path: "logs/worker-.log",
                rollingInterval: Serilog.RollingInterval.Day,
                retainedFileCountLimit: 30)
            .WriteTo.Sink(new ColiseuSales.Worker.Services.StatusStoreSink(statusStore));
    });

    // ── Configurações tipadas ────────────────────────────────────────────────
    builder.Services.Configure<FirebirdOptions>(
        builder.Configuration.GetSection(FirebirdOptions.Section));

    builder.Services.Configure<VpsApiOptions>(
        builder.Configuration.GetSection(VpsApiOptions.Section));

    builder.Services.Configure<WorkerOptions>(
        builder.Configuration.GetSection(WorkerOptions.Section));

    builder.Services.Configure<IdentityApiOptions>(
        builder.Configuration.GetSection(IdentityApiOptions.Section));

    builder.Services.Configure<AtendenteApiOptions>(
        builder.Configuration.GetSection(AtendenteApiOptions.Section));

    builder.Services.Configure<AutoCenterApiOptions>(
        builder.Configuration.GetSection(AutoCenterApiOptions.Section));

    builder.Services.Configure<DashboardApiOptions>(
        builder.Configuration.GetSection(DashboardApiOptions.Section));

    builder.Services.Configure<NexusApiOptions>(
        builder.Configuration.GetSection(NexusApiOptions.Section));

    builder.Services.Configure<VisionApiOptions>(
        builder.Configuration.GetSection(VisionApiOptions.Section));

    builder.Services.Configure<GarantiasApiOptions>(
        builder.Configuration.GetSection(GarantiasApiOptions.Section));

    builder.Services.Configure<ColiseSpeedApiOptions>(
        builder.Configuration.GetSection(ColiseSpeedApiOptions.Section));

    // ── Validação de configuração obrigatória ────────────────────────────────
    var identitySection = builder.Configuration.GetSection(IdentityApiOptions.Section);
    if (string.IsNullOrWhiteSpace(identitySection["BaseUrl"]))
        throw new InvalidOperationException("[Startup] IdentityApi:BaseUrl não configurado.");
    if (string.IsNullOrWhiteSpace(identitySection["TenantId"]))
        throw new InvalidOperationException("[Startup] IdentityApi:TenantId não configurado.");

    var vpsSection = builder.Configuration.GetSection(VpsApiOptions.Section);
    if (string.IsNullOrWhiteSpace(vpsSection["BaseUrl"]))
        throw new InvalidOperationException(
            "[Startup] VpsApi:BaseUrl não configurado. Verifique appsettings.json.");

    if (string.IsNullOrWhiteSpace(vpsSection["ApiKey"]))
        throw new InvalidOperationException(
            "[Startup] VpsApi:ApiKey não configurado. Sem API Key, todas as chamadas retornarão 401.");

    // ── HTTP Client para VPS API (com Polly retry) ────────────────────────────
    var vpsBaseUrl = vpsSection["BaseUrl"]!;
    var vpsApiKey  = vpsSection["ApiKey"]  ?? string.Empty;

    builder.Services
        .AddHttpClient<VpsApiClient>(client =>
        {
            client.BaseAddress = new Uri(vpsBaseUrl);
            client.DefaultRequestHeaders.Add("api-key", vpsApiKey);
            client.Timeout = TimeSpan.FromSeconds(
                int.TryParse(vpsSection["TimeoutSeconds"], out var t) ? t : 120);
        }); // Sem AddStandardResilienceHandler — o circuit-breaker é gerenciado pelo HealthCheckJob

    // ── HTTP Client para Identity API ─────────────────────────────────────────
    var identityBaseUrl = identitySection["BaseUrl"]!;
    var internalKey     = identitySection["InternalApiKey"] ?? string.Empty;

    builder.Services
        .AddHttpClient<IdentityApiClient>(client =>
        {
            client.BaseAddress = new Uri(identityBaseUrl);
            client.DefaultRequestHeaders.Add("X-Internal-Api-Key", internalKey);
            // FIX: timeout curto (5 s) — se o Identity API não responder,
            // o startup não fica bloqueado. Polly retries REMOVIDOS intencionalmente
            // porque FetchFirebirdCredentialsAsync já tem fallback para appsettings.json.
            client.Timeout = TimeSpan.FromSeconds(5);
        }); // Sem AddStandardResilienceHandler — fallback no appsettings.json garante resiliência

    // ── HTTP Client para Atendente do Futuro API (opcional) ───────────────────
    var atendenteSection = builder.Configuration.GetSection(AtendenteApiOptions.Section);
    var atendenteBaseUrl = atendenteSection["BaseUrl"] ?? string.Empty;
    var atendenteApiKey  = atendenteSection["ApiKey"]  ?? string.Empty;
    var atendenteEnabled = string.Equals(atendenteSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient<AtendenteApiClient>(client =>
        {
            if (!string.IsNullOrWhiteSpace(atendenteBaseUrl))
            {
                client.BaseAddress = new Uri(atendenteBaseUrl);
                client.DefaultRequestHeaders.Add("api-key", atendenteApiKey);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(atendenteSection["TimeoutSeconds"], out var at) ? at : 30);
            }
        });

    // ── HTTP Client para AutoCenter API (opcional) ────────────────────────────
    var acSection = builder.Configuration.GetSection(AutoCenterApiOptions.Section);
    var acBaseUrl = acSection["BaseUrl"] ?? string.Empty;
    var acApiKey  = acSection["InternalApiKey"]  ?? string.Empty;
    var acEnabled = string.Equals(acSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient("AutoCenterApiClient", client =>
        {
            if (!string.IsNullOrWhiteSpace(acBaseUrl))
            {
                client.BaseAddress = new Uri(acBaseUrl);
                client.DefaultRequestHeaders.Add("X-Internal-Api-Key", acApiKey);
                client.DefaultRequestHeaders.Add("X-Tenant-Id", identitySection["TenantId"]);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(acSection["TimeoutSeconds"], out var at) ? at : 30);
            }
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        });

    // ── HTTP Client para Dashboard API (opcional) ─────────────────────────────
    var dashSection = builder.Configuration.GetSection(DashboardApiOptions.Section);
    var dashBaseUrl = dashSection["BaseUrl"] ?? string.Empty;
    var dashApiKey  = dashSection["InternalApiKey"]  ?? string.Empty;
    var dashEnabled = string.Equals(dashSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient("DashboardApiClient", client =>
        {
            if (!string.IsNullOrWhiteSpace(dashBaseUrl))
            {
                client.BaseAddress = new Uri(dashBaseUrl);
                client.DefaultRequestHeaders.Add("X-Internal-Key", dashApiKey);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(dashSection["TimeoutSeconds"], out var t) ? t : 30);
            }
        });

    // ── HTTP Client para Nexus API (opcional) ─────────────────────────────────
    var nexusSection = builder.Configuration.GetSection(NexusApiOptions.Section);
    var nexusBaseUrl = nexusSection["BaseUrl"] ?? string.Empty;
    var nexusApiKey  = nexusSection["InternalApiKey"] ?? string.Empty;
    var nexusEnabled = string.Equals(nexusSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient("NexusApiClient", client =>
        {
            if (!string.IsNullOrWhiteSpace(nexusBaseUrl))
            {
                client.BaseAddress = new Uri(nexusBaseUrl);
                client.DefaultRequestHeaders.Add("X-Internal-Key", nexusApiKey);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(nexusSection["TimeoutSeconds"], out var t) ? t : 30);
            }
        });

    // ── HTTP Client para Vision API (opcional) ─────────────────────────────────
    var visionSection = builder.Configuration.GetSection(VisionApiOptions.Section);
    var visionBaseUrl = visionSection["BaseUrl"] ?? string.Empty;
    var visionApiKey  = visionSection["InternalApiKey"] ?? string.Empty;
    var visionEnabled = string.Equals(visionSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient("VisionApiClient", client =>
        {
            if (!string.IsNullOrWhiteSpace(visionBaseUrl))
            {
                client.BaseAddress = new Uri(visionBaseUrl);
                client.DefaultRequestHeaders.Add("X-Internal-Key", visionApiKey);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(visionSection["TimeoutSeconds"], out var t) ? t : 30);
            }
        });

    // ── HTTP Client para Garantias API (opcional) ─────────────────────────────
    var garantiasSection = builder.Configuration.GetSection(GarantiasApiOptions.Section);
    var garantiasBaseUrl = garantiasSection["BaseUrl"] ?? string.Empty;
    var garantiasApiKey  = garantiasSection["InternalApiKey"]  ?? string.Empty;
    var garantiasEnabled = string.Equals(garantiasSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient("GarantiasApiClient", client =>
        {
            if (!string.IsNullOrWhiteSpace(garantiasBaseUrl))
            {
                client.BaseAddress = new Uri(garantiasBaseUrl);
                client.DefaultRequestHeaders.Add("X-Internal-Api-Key", garantiasApiKey);
                client.DefaultRequestHeaders.Add("X-Tenant-Id", identitySection["TenantId"]);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(garantiasSection["TimeoutSeconds"], out var t) ? t : 30);
            }
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        });

    // ── HTTP Client para ColiseSpeed API (opcional) ───────────────────────────
    var speedSection = builder.Configuration.GetSection(ColiseSpeedApiOptions.Section);
    var speedBaseUrl = speedSection["BaseUrl"] ?? string.Empty;
    var speedApiKey  = speedSection["InternalApiKey"] ?? string.Empty;
    var speedEnabled = string.Equals(speedSection["Enabled"], "true", StringComparison.OrdinalIgnoreCase);

    builder.Services
        .AddHttpClient<ColiseSpeedApiClient>(client =>
        {
            if (!string.IsNullOrWhiteSpace(speedBaseUrl))
            {
                client.BaseAddress = new Uri(speedBaseUrl);
                client.DefaultRequestHeaders.Add("api-key", speedApiKey);
                client.Timeout = TimeSpan.FromSeconds(
                    int.TryParse(speedSection["TimeoutSeconds"], out var t) ? t : 120);
            }
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        });

    // ── Services ─────────────────────────────────────────────────────────────
    builder.Services.AddSingleton<FirebirdService>();
    builder.Services.AddSingleton<StatusStore>();
    builder.Services.AddSingleton<DeltaCacheService>();
    builder.Services.AddSingleton<ChangeTrackerService>();
    builder.Services.AddSingleton<MonitoringServer>();

    // ── Jobs ─────────────────────────────────────────────────────────────────
    builder.Services.AddSingleton<SyncCatalogJob>();
    builder.Services.AddSingleton<SyncOrdersJob>();
    builder.Services.AddSingleton<SyncAtendenteOrdersJob>();
    builder.Services.AddSingleton<SyncCustomerCreationJob>();
    builder.Services.AddSingleton<SyncSalesRankingsJob>();
    builder.Services.AddSingleton<SyncColiseSpeedCatalogJob>();
    builder.Services.AddSingleton<SyncColiseSpeedOrdersJob>();
    builder.Services.AddSingleton<SyncColiseSpeedCustomerCreationJob>();
    builder.Services.AddSingleton<SyncColiseSpeedSalesRankingsJob>();
    builder.Services.AddSingleton<SyncAutoCenterCatalogJob>();
    builder.Services.AddSingleton<SyncAutoCenterCustomersJob>();
    builder.Services.AddSingleton<SyncAutoCenterQuotesJob>();
    builder.Services.AddSingleton<SyncAutoCenterSellersJob>();
    builder.Services.AddSingleton<SyncAutoCenterVehiclesJob>();
    builder.Services.AddSingleton<SyncDashboardDataJob>();
    builder.Services.AddSingleton<SyncNexusDataJob>();
    builder.Services.AddSingleton<SyncVisionDataJob>();
    builder.Services.AddSingleton<SyncGarantiasCustomersJob>();

    builder.Services.AddSingleton<SyncGarantiasSuppliersJob>();
    builder.Services.AddSingleton<SyncGarantiasNotasJob>();
    builder.Services.AddSingleton<HealthCheckJob>();

    // ── Worker (IHostedService) ───────────────────────────────────────────────
    builder.Services.AddHostedService<WorkerService>();

    // ── Build e Run ────────────────────────────────────────────────────────────
    var host = builder.Build();

    Log.Information("[Startup] VPS API: {Url} | Tenant ID: {Tenant} | Atendente: {AtendenteEnabled} | AutoCenter: {AcEnabled} | Dashboard: {DashEnabled} | Nexus: {NexusEnabled} | Vision: {VisionEnabled} | Garantias: {GarantiasEnabled} | ColiseSpeed: {ColiseSpeedEnabled}",
        vpsBaseUrl,
        identitySection["TenantId"],
        atendenteEnabled ? atendenteBaseUrl : "DESABILITADO",
        acEnabled ? acBaseUrl : "DESABILITADO",
        dashEnabled ? dashBaseUrl : "DESABILITADO",
        nexusEnabled ? nexusBaseUrl : "DESABILITADO",
        visionEnabled ? visionBaseUrl : "DESABILITADO",
        garantiasEnabled ? garantiasBaseUrl : "DESABILITADO",
        speedEnabled ? speedBaseUrl : "DESABILITADO");

    // Inicia o servidor de monitoramento local (localhost:9001)
    var monitoringServer = host.Services.GetRequiredService<MonitoringServer>();
    await monitoringServer.StartAsync(CancellationToken.None);

    await host.RunAsync();

    monitoringServer.Stop();
    await Log.CloseAndFlushAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "[Startup] Falha crítica ao iniciar o Worker Service.");
    await Log.CloseAndFlushAsync();
    return 1;
}

return 0;
