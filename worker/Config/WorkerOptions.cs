namespace ColiseuSales.Worker.Config;

/// <summary>
/// Configurações de conexão com a VPS API (que serve o app Flutter).
/// Lidas de appsettings.json > seção "VpsApi".
/// </summary>
public sealed class VpsApiOptions
{
    public const string Section = "VpsApi";

    public bool   Enabled        { get; set; } = true;
    public string BaseUrl        { get; set; } = string.Empty;
    public string ApiKey         { get; set; } = string.Empty;
    /// <summary>UUID da empresa que este Worker representa no sistema multi-tenant.</summary>
    public string CompanyId      { get; set; } = string.Empty;
    public int    TimeoutSeconds { get; set; } = 30;
    public int    MaxRetries     { get; set; } = 3;
}

/// <summary>
/// Intervalos de execução de cada job.
/// Lidas de appsettings.json > seção "Worker".
/// </summary>
public sealed class WorkerOptions
{
    public const string Section = "Worker";

    /// <summary>Intervalo em minutos para sync do catálogo (Firebird → API).</summary>
    public int CatalogSyncIntervalMinutes { get; set; } = 15;

    /// <summary>
    /// Intervalo em SEGUNDOS para buscar/enviar pedidos (API → Firebird).
    /// Valores recomendados: 15–60s. Mínimo: 10s.
    /// Substitui OrderSyncIntervalMinutes para respostas mais rápidas.
    /// </summary>
    public int OrderSyncIntervalSeconds { get; set; } = 30;

    /// <summary>Intervalo em minutos para health check.</summary>
    public int HealthCheckIntervalMinutes { get; set; } = 5;

    /// <summary>Sufixo do serviço configurado para isolar múltiplos Workers rodando na mesma máquina.</summary>
    public string ServiceSuffix { get; set; } = string.Empty;
}
