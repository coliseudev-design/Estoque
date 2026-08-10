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
    private readonly SyncAutoCenterSellersJob    _acSellers;
    private readonly SyncAutoCenterVehiclesJob   _acVehicles;
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
    private readonly SyncColiseSpeedCatalogJob          _speedCatalog;
    private readonly SyncColiseSpeedOrdersJob           _speedOrders;
    private readonly SyncColiseSpeedCustomerCreationJob  _speedCustomerCreation;
    private readonly SyncColiseSpeedSalesRankingsJob    _speedSalesRankings;
    private readonly ColiseSpeedApiOptions              _speedOpts;
    private readonly StatusStore             _statusStore;
    private readonly ILogger<WorkerService>  _logger;
    private readonly ChangeTrackerService   _changeTracker;

    // Mantém timestamp da última sync do catálogo para delta sync
    private DateTime? _lastCatalogSync;

    private readonly System.Threading.SemaphoreSlim _catalogSyncSemaphore = new System.Threading.SemaphoreSlim(1, 1);
    private readonly System.Threading.SemaphoreSlim _orderSyncSemaphore = new System.Threading.SemaphoreSlim(1, 1);
    private readonly System.Collections.Concurrent.ConcurrentDictionary<Task, bool> _activeTasks = new();

    public WorkerService(
        SyncCatalogJob             catalog,
        SyncOrdersJob              orders,
        SyncAtendenteOrdersJob     atendenteOrders,
        SyncCustomerCreationJob    customerCreation,
        SyncSalesRankingsJob       salesRankings,
        SyncAutoCenterCatalogJob   acCatalog,
        SyncAutoCenterCustomersJob acCustomers,
        SyncAutoCenterQuotesJob    acQuotes,
        SyncAutoCenterSellersJob   acSellers,
        SyncAutoCenterVehiclesJob  acVehicles,
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
        SyncColiseSpeedCatalogJob speedCatalog,
        SyncColiseSpeedOrdersJob speedOrders,
        SyncColiseSpeedCustomerCreationJob speedCustomerCreation,
        SyncColiseSpeedSalesRankingsJob speedSalesRankings,
        IOptions<ColiseSpeedApiOptions> speedOpts,
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
        _acSellers        = acSellers;
        _acVehicles       = acVehicles;
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
        _speedCatalog     = speedCatalog;
        _speedOrders      = speedOrders;
        _speedCustomerCreation = speedCustomerCreation;
        _speedSalesRankings = speedSalesRankings;
        _speedOpts        = speedOpts.Value;
        _logger           = logger;
        _changeTracker    = changeTracker;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Libera o thread principal para que o Windows Service seja marcado como RUNNING imediatamente
        await Task.Yield();

        _logger.LogInformation(
            "[Worker] Coliseu Sales Worker iniciado. Host={Host} | " +
            "CatalogInterval={Catalog}min | OrderInterval={Order}s | HealthInterval={Health}min",
            Environment.MachineName,
            _opts.CatalogSyncIntervalMinutes,
            _opts.OrderSyncIntervalSeconds,
            _opts.HealthCheckIntervalMinutes);

        // Pré-popula os estados iniciais dos módulos habilitados para melhor UX
        InitializeMonitoringStatus();

        // ── Buscar credenciais Firebird do Identity API ────────────────────────
        await FetchFirebirdCredentialsAsync(stoppingToken);

        // Health check inicial — antes de qualquer sync
        var initialHealth = await _health.RunAsync(stoppingToken);

        // Sync inicial — CatalogSync + DashboardSync + NexusSync em PARALELO
        // Evita timeout do Windows SCM que mata o serviço se o startup demorar > 30s
        if (initialHealth.FirebirdOk)
        {
            _logger.LogInformation("[Worker] Iniciando sync paralelo na startup (Catalog + Dashboard + Nexus + Speed)...");

            var startupTasks = new List<Task>();

            if (_vpsOpts.Enabled)
                startupTasks.Add(SafeRunAsync(() => RunCatalogSyncAsync(false, stoppingToken), "InitialCatalogSync"));
            else
                _logger.LogInformation("[Worker] Sync inicial do catálogo do App Sales ignorado pois o módulo está desativado.");

            if (_speedOpts.Enabled)
                startupTasks.Add(SafeRunAsync(() => RunSpeedCatalogSyncAsync(false, stoppingToken), "InitialSpeedCatalogSync"));
            else
                _logger.LogInformation("[Worker] Sync inicial do catálogo do ColiseSpeed ignorado pois o módulo está desativado.");

            if (_dashOpts.Enabled)
            {
                _logger.LogInformation("[Worker] Dashboard sync inicial em paralelo...");
                startupTasks.Add(SafeRunAsync(() => _dashboardData.RunAsync(true, stoppingToken), "InitialDashboardSync"));
            }

            if (_nexusOpts.Enabled)
            {
                _logger.LogInformation("[Worker] Nexus sync inicial em paralelo...");
                startupTasks.Add(SafeRunAsync(() => _nexusData.RunAsync(true, stoppingToken), "InitialNexusSync"));
            }

            if (startupTasks.Count > 0)
                await Task.WhenAll(startupTasks);

            _logger.LogInformation("[Worker] Sync inicial paralelo concluído.");
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
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            var now = DateTime.UtcNow;

            // ── Forçar Sync manual via Configurador ──────────────────────────
            if (_monitoringServer.ConsumeForceSyncSignal())
            {
                _logger.LogInformation("[Worker] ⚡ Sync forçado pelo Configurador — executando agora...");
                StartTrackedTask(async () => {
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
                            tasks.Add(SafeRunAsync(() => RunCatalogSyncAsync(true, stoppingToken), "ForcedCatalogSync"));
                            tasks.Add(SafeRunAsync(() => _orders.RunAsync(stoppingToken),    "ForcedOrderSync"));
                            tasks.Add(SafeRunAsync(() => _customerCreation.RunAsync(stoppingToken), "ForcedCustomerCreationSync"));
                            tasks.Add(SafeRunAsync(() => _salesRankings.RunAsync(true, stoppingToken), "ForcedSalesRankingsSync"));
                        }
                        if (_speedOpts.Enabled)
                        {
                            tasks.Add(SafeRunAsync(() => RunSpeedCatalogSyncAsync(true, stoppingToken), "ForcedSpeedCatalogSync"));
                            tasks.Add(SafeRunAsync(() => _speedOrders.RunAsync(stoppingToken), "ForcedSpeedOrderSync"));
                            tasks.Add(SafeRunAsync(() => _speedCustomerCreation.RunAsync(stoppingToken), "ForcedSpeedCustomerCreationSync"));
                            tasks.Add(SafeRunAsync(() => _speedSalesRankings.RunAsync(true, stoppingToken), "ForcedSpeedSalesRankingsSync"));
                        }
                        tasks.Add(SafeRunAsync(() => _atendenteOrders.RunAsync(stoppingToken), "ForcedAtendenteOrderSync"));
                        
                        // Executa syncs do AutoCenter sequencialmente para evitar sobrecarga de concorrência/timeout no middleware
                        if (_acOpts.Enabled)
                        {
                            tasks.Add(Task.Run(async () =>
                            {
                                await SafeRunAsync(() => _acCatalog.RunAsync(stoppingToken), "ForcedAcCatalogSync");
                                await SafeRunAsync(() => _acCustomers.RunAsync(stoppingToken), "ForcedAcCustomersSync");
                                await SafeRunAsync(() => _acQuotes.RunAsync(stoppingToken), "ForcedAcQuotesSync");
                                await SafeRunAsync(() => _acSellers.RunAsync(stoppingToken), "ForcedAcSellersSync");
                                await SafeRunAsync(() => _acVehicles.RunAsync(stoppingToken), "ForcedAcVehiclesSync");
                            }, stoppingToken));
                        }
                        else
                        {
                            _statusStore.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Sellers", 0, DateTime.Now, "Desativado");
                            _statusStore.Update("AutoCenter_Vehicles", 0, DateTime.Now, "Desativado");
                        }

                        tasks.Add(SafeRunAsync(() => _dashboardData.RunAsync(true, stoppingToken), "ForcedDashboardSync"));
                        tasks.Add(SafeRunAsync(() => _nexusData.RunAsync(true, stoppingToken), "ForcedNexusSync"));
                        tasks.Add(SafeRunAsync(() => _visionData.RunAsync(true, stoppingToken), "ForcedVisionSync"));
                        tasks.Add(SafeRunAsync(() => _garantiasCustomers.RunAsync(true, stoppingToken), "ForcedGarantiasCustomersSync"));
                        tasks.Add(SafeRunAsync(() => _garantiasSuppliers.RunAsync(true, stoppingToken), "ForcedGarantiasSuppliersSync"));
                        tasks.Add(SafeRunAsync(() => _garantiasNotas.RunAsync(true, stoppingToken), "ForcedGarantiasNotasSync"));

                        await Task.WhenAll(tasks);
                    }
                    finally
                    {
                        _catalogSyncSemaphore.Release();
                    }
                }, "ForcedSyncGroup");
                lastCatalog = now;
                lastOrder   = now;
                continue; // já sincronizou, não verifica timers neste ciclo
            }

            // 1. Health check — tem prioridade para atualizar o circuit-breaker
            if (now - lastHealth >= healthTimer)
            {
                lastHealth = now;
                StartTrackedTask(() => _health.RunAsync(stoppingToken), "HealthCheck");
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
                    StartTrackedTask(async () => {
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
                                tasks.Add(SafeRunAsync(() => RunCatalogSyncAsync(false, stoppingToken), "CatalogSync"));
                                tasks.Add(SafeRunAsync(() => _salesRankings.RunAsync(false, stoppingToken), "SalesRankingsSync"));
                            }
                            if (_speedOpts.Enabled)
                            {
                                tasks.Add(SafeRunAsync(() => RunSpeedCatalogSyncAsync(false, stoppingToken), "SpeedCatalogSync"));
                                tasks.Add(SafeRunAsync(() => _speedSalesRankings.RunAsync(false, stoppingToken), "SpeedSalesRankingsSync"));
                            }
                            
                            // Executa syncs do AutoCenter sequencialmente para evitar sobrecarga de concorrência/timeout no middleware
                            if (_acOpts.Enabled)
                            {
                                tasks.Add(Task.Run(async () =>
                                {
                                    await SafeRunAsync(() => _acCatalog.RunAsync(stoppingToken), "AcCatalogSync");
                                    await SafeRunAsync(() => _acCustomers.RunAsync(stoppingToken), "AcCustomersSync");
                                    await SafeRunAsync(() => _acQuotes.RunAsync(stoppingToken), "AcQuotesSync");
                                    await SafeRunAsync(() => _acSellers.RunAsync(stoppingToken), "AcSellersSync");
                                    await SafeRunAsync(() => _acVehicles.RunAsync(stoppingToken), "AcVehiclesSync");
                                }, stoppingToken));
                            }
                            else
                            {
                                _statusStore.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Sellers", 0, DateTime.Now, "Desativado");
                                _statusStore.Update("AutoCenter_Vehicles", 0, DateTime.Now, "Desativado");
                            }

                            tasks.Add(SafeRunAsync(() => _dashboardData.RunAsync(false, stoppingToken), "DashboardSync"));
                            tasks.Add(SafeRunAsync(() => _nexusData.RunAsync(false, stoppingToken), "NexusSync"));
                            tasks.Add(SafeRunAsync(() => _visionData.RunAsync(false, stoppingToken), "VisionSync"));
                            tasks.Add(SafeRunAsync(() => _garantiasCustomers.RunAsync(false, stoppingToken), "GarantiasCustomersSync"));
                            tasks.Add(SafeRunAsync(() => _garantiasSuppliers.RunAsync(false, stoppingToken), "GarantiasSuppliersSync"));
                            tasks.Add(SafeRunAsync(() => _garantiasNotas.RunAsync(false, stoppingToken), "GarantiasNotasSync"));

                            await Task.WhenAll(tasks);
                        }
                        finally
                        {
                            _catalogSyncSemaphore.Release();
                        }
                    }, "CatalogSyncGroup");
                }
            }

            // 3. Order sync — não depende do Firebird (puxa pedidos da VPS)
            if (now - lastOrder >= orderTimer)
            {
                lastOrder = now;
                StartTrackedTask(async () => {
                    if (!await _orderSyncSemaphore.WaitAsync(0))
                    {
                        _logger.LogWarning("[Worker] Order sync já está em execução. Ignorando este ciclo.");
                        return;
                    }
                    try
                    {
                        if (_vpsOpts.Enabled)
                        {
                            await SafeRunAsync(() => _orders.RunAsync(stoppingToken), "OrderSync");
                            await SafeRunAsync(() => _customerCreation.RunAsync(stoppingToken), "CustomerCreationSync");
                        }
                        if (_speedOpts.Enabled)
                        {
                            await SafeRunAsync(() => _speedOrders.RunAsync(stoppingToken), "SpeedOrderSync");
                            await SafeRunAsync(() => _speedCustomerCreation.RunAsync(stoppingToken), "SpeedCustomerCreationSync");
                        }
                        await SafeRunAsync(() => _atendenteOrders.RunAsync(stoppingToken), "AtendenteOrderSync");
                    }
                    finally
                    {
                        _orderSyncSemaphore.Release();
                    }
                }, "OrderSyncGroup");
            }
        }

        _logger.LogInformation("[Worker] Encerrando graciosamente...");

        if (!_activeTasks.IsEmpty)
        {
            _logger.LogInformation("[Worker] Aguardando a finalização de {Count} tarefas ativas...", _activeTasks.Count);
            var shutdownTimeout = TimeSpan.FromSeconds(15);
            var allTasks = Task.WhenAll(_activeTasks.Keys);
            
            // Usamos CancellationTokenSource separado para o timeout
            using var cts = new CancellationTokenSource(shutdownTimeout);
            try
            {
                await Task.WhenAny(allTasks, Task.Delay(shutdownTimeout, cts.Token));
                
                if (allTasks.IsCompleted)
                {
                    _logger.LogInformation("[Worker] Todas as tarefas ativas foram concluídas com sucesso.");
                }
                else
                {
                    _logger.LogWarning("[Worker] Tempo limite de shutdown atingido. Algumas tarefas ativas foram abortadas.");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[Worker] Erro ao aguardar a finalização das tarefas.");
            }
        }
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

    private DateTime? _lastSpeedCatalogSync;
    private async Task RunSpeedCatalogSyncAsync(bool force, CancellationToken ct)
    {
        var since = _lastSpeedCatalogSync;
        _lastSpeedCatalogSync = DateTime.UtcNow;
        await _speedCatalog.RunAsync(force, since, ct);
    }

    /// <summary>
    /// Executa uma Task com logging de exceções, offloaded para a thread pool.
    /// Garante que exceções não derrubem o loop principal.
    /// </summary>
    private async Task SafeRunAsync(Func<Task> taskFactory, string jobName)
    {
        try
        {
            await Task.Run(taskFactory);
        }
        catch (OperationCanceledException)
        {
            // shutdown normal
        }
        catch (Exception ex)
        {
            _logger.LogError("[Worker/{Job}] Exceção não tratada: {Error}", jobName, ex.Message);
        }
    }

    private void StartTrackedTask(Func<Task> taskFactory, string jobName)
    {
        var task = SafeRunAsync(taskFactory, jobName);
        _activeTasks.TryAdd(task, true);
        task.ContinueWith(t => _activeTasks.TryRemove(t, out _), TaskContinuationOptions.ExecuteSynchronously);
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
            store.InitializeWaiting("AutoCenter_Vehicles");
        }
        else
        {
            store.Update("AutoCenter_Catalog", 0, DateTime.Now, "Desativado");
            store.Update("AutoCenter_Customers", 0, DateTime.Now, "Desativado");
            store.Update("AutoCenter_Quotes", 0, DateTime.Now, "Desativado");
            store.Update("AutoCenter_Vehicles", 0, DateTime.Now, "Desativado");
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

        // ColiseSpeed
        if (_speedOpts.Enabled)
        {
            var speedEntities = new[] { 
                "ColiseSpeed_CompanyData", "ColiseSpeed_Sellers", "ColiseSpeed_Catalog", "ColiseSpeed_Customers", 
                "ColiseSpeed_PaymentSpecies", "ColiseSpeed_PaymentConditions", "ColiseSpeed_PriceTables", 
                "ColiseSpeed_Natureza", "ColiseSpeed_Financials", "ColiseSpeed_Performance", "ColiseSpeed_SalesRankings" 
            };
            foreach (var entity in speedEntities)
            {
                store.InitializeWaiting(entity);
            }
        }
        else
        {
            var speedEntities = new[] { 
                "ColiseSpeed_CompanyData", "ColiseSpeed_Sellers", "ColiseSpeed_Catalog", "ColiseSpeed_Customers", 
                "ColiseSpeed_PaymentSpecies", "ColiseSpeed_PaymentConditions", "ColiseSpeed_PriceTables", 
                "ColiseSpeed_Natureza", "ColiseSpeed_Financials", "ColiseSpeed_Performance", "ColiseSpeed_SalesRankings" 
            };
            foreach (var entity in speedEntities)
            {
                store.Update(entity, 0, DateTime.Now, "Desativado");
            }
        }
    }
}
