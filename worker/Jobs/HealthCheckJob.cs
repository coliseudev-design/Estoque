using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// HealthCheckJob — Verifica a saúde de todas as dependências do Worker.
///
/// Implementa circuit-breaker simples:
/// - Se Firebird ficou offline consecutivamente por ≥ ThresholdFailures vezes
///   → expõe IsFirebirdCircuitOpen = true (WorkerService pode pular sync)
/// - Circuit fecha automaticamente após CircuitResetMinutes (padrão 5min)
///   ou na próxima verificação bem-sucedida.
///
/// Verifica periodicamente (configurável via appsettings):
/// - Conexão com o Firebird (banco ERP local)
/// - Conexão com a VPS API (servidor em nuvem)
/// </summary>
public sealed class HealthCheckJob
{
    private readonly FirebirdService         _firebird;
    private readonly VpsApiClient            _vps;
    private readonly IHttpClientFactory      _httpClientFactory;
    private readonly ILogger<HealthCheckJob> _logger;

    // ─────────────────────────────────────────────────────────────────────────
    // Circuit-breaker (Firebird)
    // ─────────────────────────────────────────────────────────────────────────

    /// Número de falhas consecutivas antes de abrir o circuit-breaker.
    private const int ThresholdFailures    = 3;

    /// Tempo mínimo com circuit aberto antes de tentar novamente.
    private static readonly TimeSpan CircuitResetTime = TimeSpan.FromMinutes(5);

    private int       _consecutiveFirebirdFailures = 0;
    private DateTime? _circuitOpenedAt             = null;

    /// <summary>
    /// true = Firebird estava com muitas falhas consecutivas.
    /// WorkerService deve verificar isso antes de tentar sync de catálogo.
    /// </summary>
    public bool IsFirebirdCircuitOpen
    {
        get
        {
            if (_circuitOpenedAt is null) return false;
            // Auto-reset após CircuitResetTime
            if (DateTime.UtcNow - _circuitOpenedAt > CircuitResetTime)
            {
                ResetCircuit();
                return false;
            }
            return true;
        }
    }

    private readonly ChangeTrackerService    _changeTracker;
    private readonly VpsApiOptions           _vpsOpts;

    public HealthCheckJob(
        FirebirdService        firebird,
        VpsApiClient           vps,
        IHttpClientFactory     httpClientFactory,
        ILogger<HealthCheckJob> logger,
        ChangeTrackerService changeTracker,
        IOptions<VpsApiOptions> vpsOpts)
    {
        _firebird = firebird;
        _vps      = vps;
        _httpClientFactory = httpClientFactory;
        _logger   = logger;
        _changeTracker = changeTracker;
        _vpsOpts   = vpsOpts.Value;
    }

    /// <summary>Executa verificação de saúde e atualiza o circuit-breaker.</summary>
    public async Task<HealthStatus> RunAsync(CancellationToken ct = default)
    {
        var firebirdOk = await _firebird.IsAvailableAsync(ct);
        var vpsOk      = _vpsOpts.Enabled ? await _vps.IsAvailableAsync(ct) : true;

        // [Fase 15] Heartbeat do AutoCenter (Pulso de vida pra VPS)
        bool autoCenterOk = false;
        try
        {
            var apiClient = _httpClientFactory.CreateClient("AutoCenterApiClient");
            if (apiClient.BaseAddress != null)
            {
                var livenessRes = await apiClient.GetAsync("/health/liveness", ct);
                autoCenterOk = livenessRes.IsSuccessStatusCode;
            }
        }
        catch (OperationCanceledException) { /* Ignora se interrompido */ }
        catch (Exception ex)
        {
             _logger.LogWarning("[HealthCheck] Falha no Heartbeat da API do AutoCenter: {Msg}", ex.Message);
        }

        UpdateCircuitBreaker(firebirdOk);

        var status = new HealthStatus(firebirdOk, vpsOk, IsFirebirdCircuitOpen);

        if (firebirdOk)
        {
            _ = Task.Run(async () => await _changeTracker.PruneOldLogsAsync(), ct);
        }

        if (status.AllHealthy)
        {
            _logger.LogInformation("[HealthCheck] ✓ Firebird: OK | VPS API: {VpsStatus} | AutoCenter Middle: {Status}", 
                _vpsOpts.Enabled ? "OK" : "DISABLED", 
                autoCenterOk ? "OK" : "DOWN");
        }
        else
        {
            if (!firebirdOk)
            {
                _logger.LogError(
                    "[HealthCheck] ✗ Firebird INDISPONÍVEL (falha #{Count}).{CircuitMsg}",
                    _consecutiveFirebirdFailures,
                    status.FirebirdCircuitOpen
                        ? $" Circuit-breaker ABERTO — sync suspenso por até {CircuitResetTime.TotalMinutes}min."
                        : string.Empty);
            }
            if (!vpsOk && _vpsOpts.Enabled)
                _logger.LogError("[HealthCheck] ✗ VPS API INDISPONÍVEL — dados não chegarão ao app.");
        }

        return status;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Circuit-breaker helpers
    // ─────────────────────────────────────────────────────────────────────────

    private void UpdateCircuitBreaker(bool firebirdOk)
    {
        if (firebirdOk)
        {
            if (_consecutiveFirebirdFailures > 0)
            {
                _logger.LogInformation(
                    "[HealthCheck] Firebird recuperado após {Count} falhas consecutivas.",
                    _consecutiveFirebirdFailures);
            }
            ResetCircuit();
        }
        else
        {
            _consecutiveFirebirdFailures++;
            if (_consecutiveFirebirdFailures >= ThresholdFailures && _circuitOpenedAt is null)
            {
                _circuitOpenedAt = DateTime.UtcNow;
                _logger.LogWarning(
                    "[HealthCheck] Circuit-breaker ABERTO após {Threshold} falhas consecutivas. " +
                    "Sync de catálogo suspenso por até {Reset}min.",
                    ThresholdFailures, CircuitResetTime.TotalMinutes);
            }
        }
    }

    private void ResetCircuit()
    {
        _consecutiveFirebirdFailures = 0;
        _circuitOpenedAt             = null;
    }
}

/// <summary>Resultado do health check.</summary>
public sealed record HealthStatus(bool FirebirdOk, bool VpsApiOk, bool FirebirdCircuitOpen = false)
{
    public bool AllHealthy => FirebirdOk && VpsApiOk;
}
