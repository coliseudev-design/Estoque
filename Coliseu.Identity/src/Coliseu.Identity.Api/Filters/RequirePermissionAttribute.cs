using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Coliseu.Identity.Api.Filters;

/// <summary>
/// Verifica se o usuário autenticado (AdminJwt) possui a permissão requerida.
///
/// Regras:
/// - SuperAdmin: bypassa todas as verificações (acesso total).
/// - Operator com permissão "*": acesso total (equivalente a SuperAdmin no grupo).
/// - Demais Operators: precisam ter a claim "perm" correspondente no JWT.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true)]
public sealed class RequirePermissionAttribute : ActionFilterAttribute
{
    private readonly string _permission;

    /// <param name="permission">Chave da permissão (ex: "companies.update").</param>
    public RequirePermissionAttribute(string permission)
    {
        _permission = permission;
    }

    public override void OnActionExecuting(ActionExecutingContext context)
    {
        var user = context.HttpContext.User;

        // SuperAdmin bypassa tudo
        if (user.IsInRole("SuperAdmin"))
            return;

        // Verifica wildcard ("*") — grupo com todas as permissões
        var perms = user.FindAll("perm").Select(c => c.Value).ToHashSet();
        if (perms.Contains("*") || perms.Contains(_permission))
            return;

        context.Result = new ObjectResult(new
        {
            error = $"Acesso negado. Permissão requerida: {_permission}."
        })
        { StatusCode = 403 };
    }
}
