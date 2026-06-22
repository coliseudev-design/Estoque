using System.Net;
using System.Text.Json;

namespace Coliseu.Identity.Api.Middleware;

/// <summary>
/// Middleware global de tratamento de exceções.
///
/// Converte exceções não tratadas em respostas JSON padronizadas.
/// Nunca expõe stack traces em produção (Rule-04: sem dados sensíveis em logs).
/// </summary>
public sealed class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception on {Method} {Path}",
                context.Request.Method, context.Request.Path);

            context.Response.ContentType = "application/json";
            context.Response.StatusCode = (int)HttpStatusCode.InternalServerError;

            var response = new
            {
                error = "Erro interno do servidor.",
                details = ex.Message,
                source = ex.Source,
                stack = ex.StackTrace,
                traceId = context.TraceIdentifier,
            };

            await context.Response.WriteAsJsonAsync(response);
        }
    }
}
