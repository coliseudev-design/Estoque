using System.Collections.Concurrent;

namespace ColiseuSpeed.Api.Logging;

/// <summary>
/// Buffer circular em memória para os últimos N requests HTTP.
/// Permite ao painel admin visualizar logs recentes sem acesso SSH.
///
/// Rule-02: Singleton thread-safe via ConcurrentQueue.
/// Rule-04: Sanitiza dados sensíveis (Authorization header nunca logado).
/// </summary>
public sealed class RequestLogBuffer
{
    private readonly ConcurrentQueue<RequestLogEntry> _queue = new();
    private readonly int _maxSize;

    public RequestLogBuffer(int maxSize = 200)
    {
        _maxSize = maxSize;
    }

    /// <summary>Adiciona uma entrada ao buffer. Remove a mais antiga se cheio.</summary>
    public void Add(RequestLogEntry entry)
    {
        _queue.Enqueue(entry);
        while (_queue.Count > _maxSize)
            _queue.TryDequeue(out _);
    }

    /// <summary>Retorna as últimas N entradas em ordem decrescente.</summary>
    public IEnumerable<RequestLogEntry> GetRecent(int count = 50)
        => _queue.Reverse().Take(count);
}

/// <summary>Registro de uma requisição HTTP capturada pelo middleware.</summary>
public sealed record RequestLogEntry(
    DateTime Timestamp,
    string   Method,
    string   Path,
    int      StatusCode,
    long     ElapsedMs,
    string?  CompanyId,
    string?  IpAddress,
    bool     IsError);
