namespace Coliseu.Identity.Domain.Entities;

/// <summary>
/// Sessão ativa de um dispositivo — contém o Refresh Token rotativo.
///
/// Cada device-login gera uma nova Session e revoga a anterior.
/// O Refresh Token é gerado com segurança criptográfica (64 bytes random).
/// Tokens expirados ou revogados não permitem refresh.
/// </summary>
public sealed class Session
{
    public Guid Id { get; private set; }
    public Guid DeviceId { get; private set; }
    public string RefreshToken { get; private set; } = null!;
    public DateTime ExpiresAt { get; private set; }
    public DateTime CreatedAt { get; private set; }
    public bool IsRevoked { get; private set; }

    // Navigation
    public Device Device { get; private set; } = null!;

    // EF Core
    private Session() { }

    /// <summary>
    /// Cria uma nova sessão para um dispositivo.
    /// </summary>
    /// <param name="deviceId">ID do dispositivo autenticado.</param>
    /// <param name="refreshToken">Token de refresh gerado com segurança criptográfica.</param>
    /// <param name="expiresAt">Data de expiração do refresh token.</param>
    public static Session Create(Guid deviceId, string refreshToken, DateTime expiresAt)
    {
        if (deviceId == Guid.Empty)
            throw new ArgumentException("DeviceId é obrigatório.", nameof(deviceId));
        if (string.IsNullOrWhiteSpace(refreshToken))
            throw new ArgumentException("RefreshToken é obrigatório.", nameof(refreshToken));
        if (expiresAt <= DateTime.UtcNow)
            throw new ArgumentException("ExpiresAt deve ser no futuro.", nameof(expiresAt));

        return new Session
        {
            Id = Guid.NewGuid(),
            DeviceId = deviceId,
            RefreshToken = refreshToken,
            ExpiresAt = expiresAt,
            CreatedAt = DateTime.UtcNow,
            IsRevoked = false,
        };
    }

    /// <summary>Revoga esta sessão — o refresh token não pode mais ser utilizado.</summary>
    public void Revoke()
    {
        IsRevoked = true;
    }

    /// <summary>Verifica se a sessão é válida (não expirada e não revogada).</summary>
    public bool IsValid => !IsRevoked && ExpiresAt > DateTime.UtcNow;
}
