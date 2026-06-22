using System.Text.Json.Serialization;

namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Parceiro comercial integrador cadastrado no ecossistema Coliseu.
/// </summary>
public sealed class Partner
{
    public Guid Id { get; private set; }
    public string Name { get; private set; } = null!;
    public string Cnpj { get; private set; } = null!;
    public string ContactName { get; private set; } = null!;
    public string Email { get; private set; } = null!;
    public string Phone { get; private set; } = null!;
    public DateTime CreatedAt { get; private set; }
    public DateTime? UpdatedAt { get; private set; }

    // Navigation
    private readonly List<LicenseRequest> _requests = new();
    public IReadOnlyCollection<LicenseRequest> Requests => _requests.AsReadOnly();

    // EF Core constructor
    private Partner() { }

    public Partner(Guid id, string name, string cnpj, string contactName, string email, string phone)
    {
        Id = id;
        Name = name;
        Cnpj = cnpj;
        ContactName = contactName;
        Email = email;
        Phone = phone;
        CreatedAt = DateTime.UtcNow;
    }

    public void Update(string name, string cnpj, string contactName, string email, string phone)
    {
        Name = name;
        Cnpj = cnpj;
        ContactName = contactName;
        Email = email;
        Phone = phone;
        UpdatedAt = DateTime.UtcNow;
    }
}
