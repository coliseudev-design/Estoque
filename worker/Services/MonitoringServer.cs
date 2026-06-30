using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ColiseuSpeed.Worker.Services;

/// <summary>
/// MonitoringServer — Mini servidor HTTP local (porta 9001) usando HttpListener.
///
/// Endpoints:
///   GET  /status      → JSON com estado de todas as entidades sincronizadas
///   GET  /logs        → Server-Sent Events (stream de log em tempo real)
///   POST /force-sync  → Sinaliza para o WorkerService executar sync imediato
///
/// Escuta apenas em localhost — zero exposição externa.
/// </summary>
public sealed class MonitoringServer
{
    private readonly StatusStore                  _store;
    private readonly ILogger<MonitoringServer>    _logger;
    private readonly HttpListener                 _listener = new();
    private readonly ManualResetEventSlim         _forceSyncSignal = new(false);

    private static readonly JsonSerializerOptions _json = new()
    {
        WriteIndented       = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public const string BaseUrl = "http://localhost:9001/";

    /// <summary>True quando o Configurador clicou em "Forçar Sync".</summary>
    public bool ConsumeForceSyncSignal()
    {
        if (!_forceSyncSignal.IsSet) return false;
        _forceSyncSignal.Reset();
        return true;
    }

    public MonitoringServer(StatusStore store, ILogger<MonitoringServer> logger)
    {
        _store  = store;
        _logger = logger;
    }

    /// <summary>Inicia o servidor em background.</summary>
    public Task StartAsync(CancellationToken ct)
    {
        try
        {
            _listener.Prefixes.Add(BaseUrl);
            _listener.Start();
            _logger.LogInformation("[Monitor] Servidor de monitoramento em {Url}", BaseUrl);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] Monitor HTTP iniciado em {BaseUrl}");
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[Monitor] Falha ao iniciar: {Error}", ex.Message);
            return Task.CompletedTask;
        }

        // Loop de requisições em background
        _ = Task.Run(() => AcceptLoopAsync(ct), ct);
        return Task.CompletedTask;
    }

    public void Stop()
    {
        try { _listener.Stop(); } catch { /* ignore */ }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private async Task AcceptLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _listener.IsListening)
        {
            try
            {
                var ctx = await _listener.GetContextAsync().WaitAsync(ct);
                _ = HandleAsync(ctx, ct); // fire-and-forget por request
            }
            catch (OperationCanceledException) { break; }
            catch (HttpListenerException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                _logger.LogDebug("[Monitor] AcceptLoop: {Error}", ex.Message);
            }
        }
    }

    private async Task HandleAsync(HttpListenerContext ctx, CancellationToken ct)
    {
        var req  = ctx.Request;
        var resp = ctx.Response;

        // CORS para o Configurador local
        resp.Headers.Add("Access-Control-Allow-Origin", "*");

        try
        {
            switch (req.Url?.AbsolutePath)
            {
                case "/status":
                    await HandleStatusAsync(resp, ct);
                    break;

                case "/logs":
                    await HandleLogsAsync(resp, ct);
                    break;

                case "/force-sync" when req.HttpMethod == "POST":
                    _forceSyncSignal.Set();
                    resp.StatusCode = 202;
                    await WriteJsonAsync(resp, new { queued = true });
                    break;

                default:
                    resp.StatusCode = 404;
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug("[Monitor] Handler: {Error}", ex.Message);
        }
        finally
        {
            try { resp.Close(); } catch { /* ignore */ }
        }
    }

    private async Task HandleStatusAsync(HttpListenerResponse resp, CancellationToken ct)
    {
        var payload = new
        {
            serverTime = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
            entities   = _store.GetAll().Values.Select(r => new
            {
                entity   = r.Entity,
                count    = r.Count,
                lastSync = r.LastSync == DateTime.MinValue ? null : r.LastSync.ToString("o"),
                success  = r.Success,
                error    = r.Error,
            }).ToArray(),
        };

        await WriteJsonAsync(resp, payload);
    }

    private async Task HandleLogsAsync(HttpListenerResponse resp, CancellationToken ct)
    {
        resp.ContentType  = "text/event-stream; charset=utf-8";
        resp.SendChunked  = true;
        resp.Headers.Add("Cache-Control", "no-cache");
        resp.Headers.Add("Connection", "keep-alive");

        var stream = resp.OutputStream;

        // Mensagem de handshake
        await WriteSseAsync(stream, "[Monitor conectado — aguardando eventos de sync]");

        try
        {
            await foreach (var line in _store.LogReader.ReadAllAsync(ct))
            {
                await WriteSseAsync(stream, line);
            }
        }
        catch (OperationCanceledException) { }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task WriteJsonAsync(HttpListenerResponse resp, object payload)
    {
        var json  = JsonSerializer.Serialize(payload, _json);
        var bytes = Encoding.UTF8.GetBytes(json);
        resp.ContentType     = "application/json; charset=utf-8";
        resp.ContentLength64 = bytes.Length;
        await resp.OutputStream.WriteAsync(bytes);
    }

    private static async Task WriteSseAsync(Stream stream, string data)
    {
        // SSE format: "data: <message>\n\n"
        var payload = Encoding.UTF8.GetBytes($"data: {data}\n\n");
        await stream.WriteAsync(payload);
        await stream.FlushAsync();
    }
}
