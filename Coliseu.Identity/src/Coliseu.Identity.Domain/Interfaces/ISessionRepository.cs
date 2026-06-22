using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Domain.Interfaces;

/// <summary>Repositório de sessões (refresh tokens).</summary>
public interface ISessionRepository
{
    /// <summary>Busca sessão válida pelo refresh token.</summary>
    Task<Session?> GetByRefreshTokenAsync(string refreshToken, CancellationToken ct = default);

    /// <summary>Revoga todas as sessões de um dispositivo.</summary>
    Task RevokeAllByDeviceAsync(Guid deviceId, CancellationToken ct = default);

    /// <summary>Adiciona uma nova sessão.</summary>
    Task AddAsync(Session session, CancellationToken ct = default);

    /// <summary>Persiste alterações.</summary>
    Task SaveChangesAsync(CancellationToken ct = default);
}
