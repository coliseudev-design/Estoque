using System.Collections.Concurrent;
using System.Threading.Channels;
using Serilog.Core;
using Serilog.Events;

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

        var msg = "";
        if (error == null)
            msg = $"[{syncedAt:HH:mm:ss}] ✓ {entity}: {count} registros";
        else if (error == "Desativado")
            msg = $"[{syncedAt:HH:mm:ss}] ⛔ {entity}: Desativado";
        else
            msg = $"[{syncedAt:HH:mm:ss}] ✗ {entity}: ERRO — {error}";

        AppendLog(msg);
    }

    /// <summary>Adiciona uma linha ao stream de log do monitoramento.</summary>
    public void AppendLog(string message)
    {
        _logChannel.Writer.TryWrite(message);
    }

    /// <summary>Inicializa o status de uma entidade no estado "Aguardando sincronismo..."</summary>
    public void InitializeWaiting(string entity)
    {
        _results.TryAdd(entity, new SyncEntityResult
        {
            Entity  = entity,
            Count   = 0,
            LastSync = DateTime.MinValue,
            Error   = "Aguardando sincronismo inicial de dados...",
            Success = false
        });
    }

    /// <summary>Retorna todos os resultados atuais (snapshot).</summary>
    public IReadOnlyDictionary<string, SyncEntityResult> GetAll() => _results;

    /// <summary>Reader do canal de log para o MonitoringServer consumir.</summary>
    public ChannelReader<string> LogReader => _logChannel.Reader;
}

/// <summary>
/// Serilog Sink customizado para desviar mensagens de sincronismo relevantes
/// diretamente para o canal SSE do configurador em tempo real.
/// </summary>
public sealed class StatusStoreSink : ILogEventSink
{
    private readonly StatusStore _statusStore;

    public StatusStoreSink(StatusStore statusStore)
    {
        _statusStore = statusStore;
    }

    public void Emit(LogEvent logEvent)
    {
        if (logEvent.Level < LogEventLevel.Information) return;

        var message = logEvent.RenderMessage();

        // Filtra para enviar apenas mensagens relevantes de sync
        var lower = message.ToLowerInvariant();
        if (lower.Contains("sync") || 
            lower.Contains("sincroniz") || 
            lower.Contains("lote de") || 
            lower.Contains("enviado") || 
            lower.Contains("processando") || 
            lower.Contains("iniciando ciclo") ||
            lower.Contains("ciclo completo"))
        {
            _statusStore.AppendLog(message);
        }
    }
}
