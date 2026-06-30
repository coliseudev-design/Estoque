using ColiseuSpeed.Api.Logging;
using System.Diagnostics;

namespace ColiseuSpeed.Api.Middleware;

/// <summary>
/// Middleware que captura métricas de cada request (método, path, status, tempo)
/// e as armazena no RequestLogBuffer para consulta pelo painel admin.
///
/// Rule-04: Authorization header nunca armazenado.
/// Rule-02: Async — nenhuma operação bloqueante.
/// </summary>
public sealed class RequestLoggingMiddleware
{
    private readonly RequestDelegate    _next;
    private readonly RequestLogBuffer   _buffer;

    public RequestLoggingMiddleware(RequestDelegate next, RequestLogBuffer buffer)
    {
        _next   = next;
        _buffer = buffer;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var sw = Stopwatch.StartNew();
        await _next(context);
        sw.Stop();

        // Ignora health checks para não poluir o log
        var path = context.Request.Path.Value ?? string.Empty;
        if (path.StartsWith("/health", StringComparison.OrdinalIgnoreCase)) return;

        var companyId = context.Items.TryGetValue("CompanyId", out var cid)
            ? cid?.ToString()
            : null;

        _buffer.Add(new RequestLogEntry(
            Timestamp:  DateTime.UtcNow,
            Method:     context.Request.Method,
            Path:       path,
            StatusCode: context.Response.StatusCode,
            ElapsedMs:  sw.ElapsedMilliseconds,
            CompanyId:  companyId,
            IpAddress:  context.Connection.RemoteIpAddress?.ToString(),
            IsError:    context.Response.StatusCode >= 400));
    }
}
