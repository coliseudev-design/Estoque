using System.Collections.Concurrent;
using System.Threading.Channels;

namespace ColiseuSales.Worker.Services;

/// <summary>
/// Resultado da última sincronização de uma entidade.
/// </summary>
public sealed class SyncEntityResult
{
    public string Entity    { get; set; } = string.Empty;
    public int    Count     { get; set; }
    public DateTime LastSync { get; set; } = DateTime.MinValue;
    public string? Error    { get; set; }
    public bool   Success  { get; set; }
}

/// <summary>
/// StatusStore — Singleton thread-safe que mantém o estado de cada entidade sincronizada
/// e disponibiliza um canal de log para o MonitoringServer transmitir via SSE.
/// </summary>
public sealed class StatusStore
{
    private readonly ConcurrentDictionary<string, SyncEntityResult> _results = new();

    // Canal limitado: se cheio, descarta as mensagens mais antigas.
    private readonly Channel<string> _logChannel = Channel.CreateBounded<string>(
        new BoundedChannelOptions(1000)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleWriter = false,
            SingleReader = false,
        });

    /// <summary>Registra o resultado de sync de uma entidade.</summary>
    public void Update(string entity, int count, DateTime syncedAt, string? error = null)
    {
        _results[entity] = new SyncEntityResult
        {
            Entity  = entity,
            Count   = count,
            LastSync = syncedAt,
            Error   = error,
            Success = error is null,
        };

        var icon = error is null ? "✓" : "✗";
        var msg  = error is null
            ? $"[{syncedAt:HH:mm:ss}] {icon} {entity}: {count} registros"
            : $"[{syncedAt:HH:mm:ss}] {icon} {entity}: ERRO — {error}";

        AppendLog(msg);
    }

    /// <summary>Adiciona uma linha ao stream de log do monitoramento.</summary>
    public void AppendLog(string message)
    {
        _logChannel.Writer.TryWrite(message);
    }

    /// <summary>Retorna todos os resultados atuais (snapshot).</summary>
    public IReadOnlyDictionary<string, SyncEntityResult> GetAll() => _results;

    /// <summary>Reader do canal de log para o MonitoringServer consumir.</summary>
    public ChannelReader<string> LogReader => _logChannel.Reader;
}
