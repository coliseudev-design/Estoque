namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Constantes para os slugs de módulos do ecossistema Coliseu.
/// Use sempre estas constantes para evitar strings mágicas.
/// </summary>
public static class ModuleSlugs
{
    /// <summary>App de força de vendas (Flutter mobile + Middleware Sales).</summary>
    public const string ColiseuSales = "coliseu-sales";

    /// <summary>App de pré-atendimento de oficina (Flutter mobile + Middleware AutoCenter).</summary>
    public const string AutoCenter = "autocenter";

    /// <summary>Dashboard Web Analítico (React frontend + Middleware Dash).</summary>
    public const string ColiseuDash = "coliseu-dash";

    /// <summary>Sistema Web de Gestão e Auditoria de Garantias.</summary>
    public const string ControleGarantias = "controle-garantias";

    /// <summary>Plataforma de Integração e APIs Nexus.</summary>
    public const string Nexus = "nexus";

    /// <summary>Módulo de Inteligência de Dados e Visão Computacional.</summary>
    public const string Vision = "vision";

    /// <summary>Valida se o slug é conhecido pelo sistema.</summary>
    public static bool IsValid(string slug) =>
        slug is ColiseuSales or AutoCenter or ColiseuDash or ControleGarantias or Nexus or Vision;

    /// <summary>Lista todos os slugs registrados.</summary>
    public static readonly IReadOnlyList<string> All = [ColiseuSales, AutoCenter, ColiseuDash, ControleGarantias, Nexus, Vision];
}
