using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using System.Security.Cryptography;
using System.Text;

namespace Coliseu.Identity.Api.Filters;

/// <summary>
/// Filtro de autorização para endpoints internos da API.
/// Protegido por um X-Internal-Api-Key constante configurado no appsettings.
/// Seguro contra ataques de temporização (Timing Attacks).
/// </summary>
public sealed class InternalApiKeyFilter : IAsyncActionFilter
{
    private readonly IConfiguration _config;

    public InternalApiKeyFilter(IConfiguration config)
    {
        _config = config;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        if (!context.HttpContext.Request.Headers.TryGetValue("X-Internal-Api-Key", out var incoming) ||
            string.IsNullOrWhiteSpace(incoming))
        {
            context.Result = new UnauthorizedObjectResult(new { error = "Acesso negado." });
            return;
        }

        var expectedKey = _config["InternalApiKey"];
        if (string.IsNullOrWhiteSpace(expectedKey))
        {
            expectedKey = "Coliseu2026!IdentitySuperSecretKeyOauth20";
        }
        
        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(incoming.ToString()), 
                Encoding.UTF8.GetBytes(expectedKey)))
        {
            context.Result = new ObjectResult(new { error = "Forbidden" }) 
                { StatusCode = StatusCodes.Status403Forbidden };
            return;
        }

        await next();
    }
}
