using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Jobs;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker;

/// <summary>
/// WorkerService — Host principal do Windows Service.
///
/// Roda como IHostedService e gerencia os timers de cada job:
/// - HealthCheckJob  (a cada HealthCheckIntervalMinutes)  ← primeiro sempre
/// - SyncCatalogJob  (a cada CatalogSyncIntervalMinutes)  ← depende do circuit-breaker
/// - SyncOrdersJob   (a cada OrderSyncIntervalMinutes)
///
/// Circuit-breaker: se o Firebird estiver com falhas consecutivas (≥3),
/// HealthCheckJob abre o circuit e CatalogSync é suspenso automaticamente
/// até que o banco se recupere.
///
/// Rule-02: Event loop nunca bloqueado. Cada timer dispara uma Task sem await.
/// </summary>
public sealed class WorkerService : BackgroundService
{
    private readonly SyncCatalogJob              _catalog;
    private readonly SyncOrdersJob               _orders;
    private readonly SyncAtendenteOrdersJob      _atendenteOrders;
    private readonly SyncCustomerCreationJob     _customerCreation;
    private readonly SyncSalesRankingsJob        _salesRankings;
    private readonly SyncAutoCenterCatalogJob    _acCatalog;
    private readonly SyncAutoCenterCustomersJob  _acCustomers;
    private readonly SyncAutoCenterQuotesJob     _acQuotes;
    private readonly SyncDashboardDataJob        _dashboardData;
    private readonly SyncNexusDataJob            _nexusData;
    private readonly SyncVisionDataJob           _visionData;
    private readonly SyncGarantiasCustomersJob   _garantiasCustomers;
    private readonly SyncGarantiasSuppliersJob   _garantiasSuppliers;
    private readonly SyncGarantiasNotasJob       _garantiasNotas;
    private readonly HealthCheckJob          _health;
    private readonly IdentityApiClient       _identity;
    private readonly MonitoringServer        _monitoringServer;
    private readonly WorkerOptions           _opts;
    private readonly VpsApiOptions           _vpsOpts;
    private readonly IdentityApiOptions      _identityOpts;
    private readonly FirebirdOptions         _firebirdOpts;
    private readonly AutoCenterApiOptions    _acOpts;
    private readonly DashboardApiOptions     _dashOpts;
    private readonly NexusApiOptions         _nexusOpts;
    private readonly VisionApiOptions        _visionOpts;
    private readonly GarantiasApiOptions     _garantiasOpts;
    private readonly StatusStore             _statusStore;
    private readonly ILogger<WorkerService>  _logger;
    private readonly ChangeTrackerService   _changeTracker;

    // Mantém timestamp da última sync do catálogo para delta sync
    private DateTime? _lastCatalogSync;

    private readonly System.Threading.SemaphoreSlim _catalogSyncSemaphore = new System.Threading.SemaphoreSlim(1, 1);
    private readonly System.Threading.SemaphoreSlim _orderSyncSemaphore = new System.Threading.SemaphoreSlim(1, 1);

    public WorkerService(
        SyncCatalogJob             catalog,
        SyncOrdersJob              orders,
        SyncAtendenteOrdersJob     atendenteOrders,
        SyncCustomerCreationJob    customerCreation,
        SyncSalesRankingsJob       salesRankings,
        SyncAutoCenterCatalogJob   acCatalog,
        SyncAutoCenterCustomersJob acCustomers,
        SyncAutoCenterQuotesJob    acQuotes,
        SyncDashboardDataJob       dashboardData,
        SyncNexusDataJob           nexusData,
        SyncVisionDataJob          visionData,
        SyncGarantiasCustomersJob  garantiasCustomers,
        SyncGarantiasSuppliersJob  garantiasSuppliers,
        SyncGarantiasNotasJob      garantiasNotas,
        HealthCheckJob             health,
        IdentityApiClient      identity,
        MonitoringServer       monitoringServer,
        StatusStore            statusStore,
        IOptions<WorkerOptions> opts,
        IOptions<VpsApiOptions> vpsOpts,
        IOptions<IdentityApiOptions> identityOpts,
        IOptions<FirebirdOptions> firebirdOpts,
        IOptions<AutoCenterApiOptions> acOpts,
        IOptions<DashboardApiOptions> dashOpts,
        IOptions<NexusApiOptions> nexusOpts,
        IOptions<VisionApiOptions> visionOpts,
        IOptions<GarantiasApiOptions> garantiasOpts,
        ILogger<WorkerService>  logger,
        ChangeTrackerService   changeTracker)
    {
        _catalog          = catalog;
        _orders           = orders;
        _atendenteOrders  = atendenteOrders;
        _customerCreation = customerCreation;
        _salesRankings    = salesRankings;
        _acCatalog        = acCatalog;
        _acCustomers      = acCustomers;
        _acQuotes         = acQuotes;
        _dashboardData    = dashboardData;
        _nexusData        = nexusData;
        _visionData       = visionData;
        _garantiasCustomers = garantiasCustomers;
        _garantiasSuppliers = garantiasSuppliers;
        _garantiasNotas   = garantiasNotas;
        _health           = health;
        _identity         = identity;
        _monitoringServer = monitoringServer;
        _statusStore      = statusStore;
        _opts             = opts.Value;
        _vpsOpts          = vpsOpts.Value;
        _identityOpts     = identityOpts.Value;
        _firebirdOpts     = firebirdOpts.Value;
        _acOpts           = acOpts.Value;
        _dashOpts         = dashOpts.Value;
        _nexusOpts        = nexusOpts.Value;
        _visionOpts       = visionOpts.Value;
        _garantiasOpts    = garantiasOpts.Value;
        _logger           = logger;
        _changeTracker    = changeTracker;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(
            "[Worker] Coliseu Sales Worker iniciado. Host={Host} | " +
            "CatalogInterval={Catalog}min | OrderInterval={Order}s | HealthInterval={Health}min",
            Environment.MachineName,
            _opts.CatalogSyncIntervalMinutes,
            _opts.OrderSyncIntervalSeconds,
            _opts.HealthCheckIntervalMinutes);

        // Pré-popula os estados iniciais dos módulos habilitados para melhor UX
        InitializeMonitoringStatus();

        // ── Gap B: Buscar credenciais Firebird do Identity API ────────────────
        await FetchFirebirdCredentialsAsync(stoppingToken);

        // Health check inicial — antes de qualquer sync
        var initialHealth = await _health.RunAsync(stoppingToken);

        // Sync inicial do catálogo (full) — somente se Firebird disponível e módulo Força de Vendas habilitado
        if (initialHealth.FirebirdOk)
        {
            if (_vpsOpts.Enabled)
            {
                await RunCatalogSyncAsync(false, stoppingToken);
            }
            else
            {
                _logger.LogInformation("[Worker] Sync inicial do catálogo do App Sales ignorado pois o módulo está desativado.");
            }
        }
        else
        {
            _logger.LogWarning(
                "[Worker] Sync inicial do catálogo ADIADO — Firebird indisponível na inicialização.");
        }

        // Loop principal com timers independentes
        var catalogTimer = TimeSpan.FromMinutes(_opts.CatalogSyncIntervalMinutes);
        // Math.Max(10, ...): garante mínimo de 10 segundos, prevenindo loop excessivo se mal configurado.
        var orderTimer   = TimeSpan.FromSeconds(Math.Max(10, _opts.OrderSyncIntervalSeconds));
        var healthTimer  = TimeSpan.FromMinutes(_opts.HealthCheckIntervalMinutes);

        var lastCatalog = DateTime.UtcNow;
        var lastOrder   = DateTime.UtcNow;
        var lastHealth  = DateTime.UtcNow;

        while (!stoppingToken.IsCancellationRequested)
        {
            // Tick curto para responder rapidamente ao "Forçar Sync"
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);

            var now = DateTime.UtcNow;

            // ── Forçar Sync manual via Configurador ──────────────────────────
            if (_monitoringServer.ConsumeForceSyncSignal())
            {
                _logger.LogInformation("[Worker] ⚡ Sync forçado pelo Configurador — executando agora...");
                _ = Task.Run(async () => {
                    if (!await _catalogSyncSemaphore.WaitAsync(0))
                    {
                        _logger.LogWarning("[Worker] Não foi possível forçar sync: Catalog sync já está em execução.");
                        return;
                    }
                    try
                    {
                        var tasks = new List<Task>();
                        if (_vpsOpts.Enabled)
                        {
                            tasks.Add(SafeRunAsync(RunCatalogSyncAsync(true, stoppingToken), "ForcedCatalogSync"));
                            tasks.Add(SafeRunAsync(_orders.RunAsync(stoppingToken),    "ForcedOrderSync"));
                            tasks.Add(SafeRunAsync(_customerCreation.RunAsync(stoppingToken), "ForcedCustomerCreationSync"));
                            tasks.Add(SafeRunAsync(_salesRankings.RunAsync(true, stoppingToken), "ForcedSalesRankingsSync"));
                        }
                        tasks.Add(SafeRunAsync(_atendenteOrders.RunAsync(stoppingToken), "ForcedAtendenteOrderSync"));
                        
                        // Executa syncs do AutoCenter sequencialmente para evitar sobrecarga de concorrência/timeout no middleware
                        if (_acOpts.Enabled)
                        {
                            tasks.Add(Task.Run(async () =>
                            {
                                await SafeRunAsync(_acCatalog.RunAsync(stoppingToken), "ForcedAcCatalogSync");
                                await SafeRunAsync(_acCustomers.RunAsync(stoppingToken), "ForcedAcCustomersSync");
                                await SafeRunAsync(_acQuotes.RunAsync(stoppingToken), "ForcedAcQuotesSync");
                            }, stoppingToken));
                        }
                        else
                        {
                            _statusStore.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
                        }

                        tasks.Add(SafeRunAsync(_dashboardData.RunAsync(true, stoppingToken), "ForcedDashboardSync"));
                        tasks.Add(SafeRunAsync(_nexusData.RunAsync(true, stoppingToken), "ForcedNexusSync"));
                        tasks.Add(SafeRunAsync(_visionData.RunAsync(true, stoppingToken), "ForcedVisionSync"));
                        tasks.Add(SafeRunAsync(_garantiasCustomers.RunAsync(true, stoppingToken), "ForcedGarantiasCustomersSync"));
                        tasks.Add(SafeRunAsync(_garantiasSuppliers.RunAsync(true, stoppingToken), "ForcedGarantiasSuppliersSync"));
                        tasks.Add(SafeRunAsync(_garantiasNotas.RunAsync(true, stoppingToken), "ForcedGarantiasNotasSync"));

                        await Task.WhenAll(tasks);
                    }
                    finally
                    {
                        _catalogSyncSemaphore.Release();
                    }
                }, stoppingToken);
                lastCatalog = now;
                lastOrder   = now;
                continue; // já sincronizou, não verifica timers neste ciclo
            }

            // 1. Health check — tem prioridade para atualizar o circuit-breaker
            if (now - lastHealth >= healthTimer)
            {
                lastHealth = now;
                _ = SafeRunAsync(_health.RunAsync(stoppingToken), "HealthCheck");
            }

            // 2. Catalog sync — só roda se circuit-breaker do Firebird estiver fechado
            if (now - lastCatalog >= catalogTimer)
            {
                lastCatalog = now;

                if (_health.IsFirebirdCircuitOpen)
                {
                    _logger.LogWarning(
                        "[Worker] Catalog sync IGNORADO — circuit-breaker do Firebird está aberto. " +
                        "O sync será retomado automaticamente quando o banco se recuperar.");
                }
                else
                {
                    _ = Task.Run(async () => {
                        if (!await _catalogSyncSemaphore.WaitAsync(0))
                        {
                            _logger.LogWarning("[Worker] Catalog sync já está em execução. Ignorando este ciclo.");
                            return;
                        }
                        try
                        {
                            var tasks = new List<Task>();
                            if (_vpsOpts.Enabled)
                            {
                                tasks.Add(SafeRunAsync(RunCatalogSyncAsync(false, stoppingToken), "CatalogSync"));
                                tasks.Add(SafeRunAsync(_salesRankings.RunAsync(false, stoppingToken), "SalesRankingsSync"));
                            }
                            
                            // Executa syncs do AutoCenter sequencialmente para evitar sobrecarga de concorrência/timeout no middleware
                            if (_acOpts.Enabled)
                            {
                                tasks.Add(Task.Run(async () =>
                                {
                                    await SafeRunAsync(_acCatalog.RunAsync(stoppingToken), "AcCatalogSync");
                                    await SafeRunAsync(_acCustomers.RunAsync(stoppingToken), "AcCustomersSync");
                                    await SafeRunAsync(_acQuotes.RunAsync(stoppingToken), "AcQuotesSync");
                                }, stoppingToken));
                            }
                            else
                            {
                                _statusStore.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
                            }

                            tasks.Add(SafeRunAsync(_dashboardData.RunAsync(false, stoppingToken), "DashboardSync"));
                            tasks.Add(SafeRunAsync(_nexusData.RunAsync(false, stoppingToken), "NexusSync"));
                            tasks.Add(SafeRunAsync(_visionData.RunAsync(false, stoppingToken), "VisionSync"));
                            tasks.Add(SafeRunAsync(_garantiasCustomers.RunAsync(false, stoppingToken), "GarantiasCustomersSync"));
                            tasks.Add(SafeRunAsync(_garantiasSuppliers.RunAsync(false, stoppingToken), "GarantiasSuppliersSync"));
                            tasks.Add(SafeRunAsync(_garantiasNotas.RunAsync(false, stoppingToken), "GarantiasNotasSync"));

                            await Task.WhenAll(tasks);
                        }
                        finally
                        {
                            _catalogSyncSemaphore.Release();
                        }
                    }, stoppingToken);
                }
            }

            // 3. Order sync — não depende do Firebird (puxa pedidos da VPS)
            if (now - lastOrder >= orderTimer)
            {
                lastOrder = now;
                _ = Task.Run(async () => {
                    if (!await _orderSyncSemaphore.WaitAsync(0))
                    {
                        _logger.LogWarning("[Worker] Order sync já está em execução. Ignorando este ciclo.");
                        return;
                    }
                    try
                    {
                        if (_vpsOpts.Enabled)
                        {
                            await SafeRunAsync(_orders.RunAsync(stoppingToken), "OrderSync");
                            await SafeRunAsync(_customerCreation.RunAsync(stoppingToken), "CustomerCreationSync");
                        }
                        await SafeRunAsync(_atendenteOrders.RunAsync(stoppingToken), "AtendenteOrderSync");
                    }
                    finally
                    {
                        _orderSyncSemaphore.Release();
                    }
                }, stoppingToken);
            }
        }

        _logger.LogInformation("[Worker] Encerrando graciosamente...");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private async Task RunCatalogSyncAsync(bool force, CancellationToken ct)
    {
        var since = _lastCatalogSync;
        _lastCatalogSync = DateTime.UtcNow;
        await _catalog.RunAsync(force, since, ct);
    }

    /// <summary>
    /// Executa uma Task "fire and forget" com logging de exceções.
    /// Garante que exceções não derrubem o loop principal.
    /// </summary>
    private async Task SafeRunAsync(Task task, string jobName)
    {
        try   { await task; }
        catch (OperationCanceledException) { /* shutdown normal */ }
        catch (Exception ex)              { _logger.LogError("[Worker/{Job}] Exceção não tratada: {Error}", jobName, ex.Message); }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Gap B: Credenciais Firebird dinâmicas do Identity API
    // ─────────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Busca as credenciais do Firebird de forma dinâmica a partir do Identity API.
    /// 
    /// Fluxo:
    /// 1. Usa TenantId configurado no appsettings.json (IdentityApi:TenantId)
    /// 2. Chama GET /internal/companies/{tenantId}/firebird-config no Identity
    /// 3. Sobrescreve Host/Database/User/Password nas FirebirdOptions em memória
    /// 4. Se falhar, mantém valores do appsettings.json (fallback para dev local)
    /// </summary>
    private async Task FetchFirebirdCredentialsAsync(CancellationToken ct)
    {
        if (_identityOpts.TenantId == Guid.Empty)
        {
            _logger.LogWarning(
                "[Worker] ⚠️  IdentityApi:TenantId não configurado!\n" +
                "         O Worker está usando as credenciais Firebird do appsettings.json.\n" +
                "         Para configurar:\n" +
                "         1. Acesse o painel admin em {AdminUrl}\n" +
                "         2. Vá para Empresas → sua empresa → copie o ID\n" +
                "         3. Edite appsettings.json: \"TenantId\": \"<ID copiado>\"\n" +
                "         4. Reinicie o Worker Service.",
                _identityOpts.BaseUrl.Replace("/api", "").Replace("/internal", ""));
            return;
        }

        _logger.LogInformation(
            "[Worker] Buscando credenciais Firebird do Identity API para tenant {TenantId}...",
            _identityOpts.TenantId);

        try
        {
            var config = await _identity.GetFirebirdConfigAsync(_identityOpts.TenantId, ct);

            if (config is null)
            {
                _logger.LogWarning(
                    "[Worker] Identity API retornou null para o tenant {TenantId}. " +
                    "Usando credenciais do appsettings.json.", _identityOpts.TenantId);
                return;
            }

            // Sobrescreve as opções em memória (Rule-04: password nunca logado)
            _firebirdOpts.Host     = config.Host;
            _firebirdOpts.Database = config.Database;
            _firebirdOpts.User     = config.User;
            _firebirdOpts.Password = config.Password;

            _logger.LogInformation(
                "[Worker] Credenciais Firebird obtidas do Identity API. " +
                "Host={Host} | Database={Db} | User={User}",
                config.Host, config.Database, config.User);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "[Worker] Falha ao buscar credenciais do Identity API. " +
                "Usando fallback do appsettings.json.");
        }
    }

    private void InitializeMonitoringStatus()
    {
        var store = _statusStore;

        // Core / Força de Vendas (Condicional)
        if (_vpsOpts.Enabled)
        {
            var coreEntities = new[] { 
                "CompanyData", "Sellers", "Catalog", "Customers", "PaymentSpecies", 
                "PaymentConditions", "PriceTables", "Natureza", "Financials", 
                "Performance", "SalesRankings" 
            };
            foreach (var entity in coreEntities)
            {
                store.InitializeWaiting(entity);
            }
        }

        // AutoCenter
        if (_acOpts.Enabled)
        {
            store.InitializeWaiting("AutoCenter_Catalog");
            store.InitializeWaiting("AutoCenter_Customers");
            store.InitializeWaiting("AutoCenter_Quotes");
        }
        else
        {
            store.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
            store.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
            store.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
        }

        // Dashboard
        if (_dashOpts.Enabled)
        {
            store.InitializeWaiting("Dash_Clientes");
            store.InitializeWaiting("Dash_Produtos");
            store.InitializeWaiting("Dash_Vendedores");
            store.InitializeWaiting("Dash_Vendas");
            store.InitializeWaiting("Dash_Vendas_Itens");
            store.InitializeWaiting("Dash_Caixas");
            store.InitializeWaiting("Dash_Financeiro");
            store.InitializeWaiting("Dash_Filiais");
        }

        // Nexus
        if (_nexusOpts.Enabled)
        {
            store.InitializeWaiting("Nexus_Clientes");
            store.InitializeWaiting("Nexus_Produtos");
            store.InitializeWaiting("Nexus_Vendedores");
            store.InitializeWaiting("Nexus_Vendas");
            store.InitializeWaiting("Nexus_Vendas_Itens");
            store.InitializeWaiting("Nexus_Caixas");
            store.InitializeWaiting("Nexus_Financeiro");
            store.InitializeWaiting("Nexus_Filiais");
        }

        // Vision
        if (_visionOpts.Enabled)
        {
            store.InitializeWaiting("Vision_Clientes");
            store.InitializeWaiting("Vision_Produtos");
            store.InitializeWaiting("Vision_Vendedores");
            store.InitializeWaiting("Vision_Vendas");
            store.InitializeWaiting("Vision_Vendas_Itens");
            store.InitializeWaiting("Vision_Caixas");
            store.InitializeWaiting("Vision_Financeiro");
            store.InitializeWaiting("Vision_Filiais");
        }

        // Garantias
        if (_garantiasOpts.Enabled)
        {
            store.InitializeWaiting("Garantias_Customers");
            store.InitializeWaiting("Garantias_Suppliers");
            store.InitializeWaiting("Garantias_Notas");
        }
    }
}
