namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Grupo de permissões RBAC para usuários administrativos.
///
/// Cada grupo define um conjunto de permissões (chaves string)
/// que determinam o que um Operator pode fazer no painel admin.
/// SuperAdmin bypassa todas as permissões.
/// </summary>
public sealed class PermissionGroup
{
    public Guid Id { get; private set; }
    public string Name { get; private set; } = null!;
    public string? Description { get; private set; }

    /// <summary>Lista de chaves de permissão (ex: "companies.create", "devices.revoke").</summary>
    public List<string> Permissions { get; private set; } = new();

    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    // Navigation
    public ICollection<AdminUser> Users { get; private set; } = new List<AdminUser>();

    // EF Core
    private PermissionGroup() { }

    /// <summary>
    /// Cria um novo grupo de permissões.
    /// </summary>
    /// <param name="name">Nome do grupo (ex: "Operador Básico").</param>
    /// <param name="description">Descrição opcional.</param>
    /// <param name="permissions">Lista de chaves de permissão.</param>
    public static PermissionGroup Create(string name, string? description, List<string> permissions)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome do grupo é obrigatório.", nameof(name));

        return new PermissionGroup
        {
            Id = Guid.NewGuid(),
            Name = name.Trim(),
            Description = description?.Trim(),
            Permissions = permissions ?? new List<string>(),
            CreatedAt = DateTime.UtcNow,
        };
    }

    /// <summary>Atualiza nome, descrição e permissões.</summary>
    public void Update(string name, string? description, List<string> permissions)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Nome do grupo é obrigatório.", nameof(name));

        Name = name.Trim();
        Description = description?.Trim();
        Permissions = permissions ?? new List<string>();
        UpdatedAt = DateTime.UtcNow;
    }

    /// <summary>Verifica se o grupo contém determinada permissão.</summary>
    public bool HasPermission(string key) => Permissions.Contains(key, StringComparer.OrdinalIgnoreCase);
}
