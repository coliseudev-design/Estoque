using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Coliseu.Identity.Application.Services;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Coliseu.Identity.Infrastructure.Security;

/// <summary>
/// Configuração JWT lida de appsettings.json.
/// </summary>
public sealed class JwtOptions
{
    public const string Section = "Jwt";

    /// <summary>Chave de assinatura para tokens de dispositivos.</summary>
    public string DeviceSigningKey { get; set; } = string.Empty;

    /// <summary>Chave de assinatura para tokens de administradores.</summary>
    public string AdminSigningKey { get; set; } = string.Empty;

    /// <summary>Expiração do token de dispositivo em minutos (padrão: 30).</summary>
    public int DeviceExpirationMinutes { get; set; } = 30;

    /// <summary>Expiração do token de admin em minutos (padrão: 15).</summary>
    public int AdminExpirationMinutes { get; set; } = 15;

    /// <summary>
    /// Validade do Refresh Token em dias.
    /// Configurável via appsettings: Jwt:RefreshTokenDays.
    /// Padrão: 30 dias.
    /// </summary>
    public int RefreshTokenDays { get; set; } = 30;
}

/// <summary>
/// Implementação do serviço JWT com chaves separadas para Device e Admin.
///
/// Device JWT: issuer=coliseu-identity-device, audience=coliseu-speed-api
/// Admin JWT:  issuer=coliseu-identity-admin,  audience=coliseu-identity-api
/// </summary>
public sealed class JwtService : IJwtService
{
    private readonly JwtOptions _options;

    public JwtService(IOptions<JwtOptions> options)
    {
        _options = options.Value;

        if (string.IsNullOrWhiteSpace(_options.DeviceSigningKey))
            throw new InvalidOperationException("[JwtService] DeviceSigningKey não configurada.");
        if (string.IsNullOrWhiteSpace(_options.AdminSigningKey))
            throw new InvalidOperationException("[JwtService] AdminSigningKey não configurada.");
    }

    /// <inheritdoc />
    public (string Token, int ExpiresInSeconds) GenerateDeviceToken(
        Guid tenantId, Guid deviceId, string companyName,
        string moduleSlug = "coliseu-speed")
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim("deviceId", deviceId.ToString()),
            new Claim("companyName", companyName),
            new Claim("module", moduleSlug),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        return GenerateToken(
            claims,
            _options.DeviceSigningKey,
            "coliseu-identity-device",
            "coliseu-speed-api",
            _options.DeviceExpirationMinutes);
    }

    /// <inheritdoc />
    public (string Token, int ExpiresInSeconds) GenerateDeviceTokenWithBranch(
        Guid tenantId, Guid deviceId, string companyName,
        Guid branchId, int erpEmpresaId, string moduleSlug = "coliseu-speed")
    {
        var claims = new[]
        {
            new Claim("tenantId", tenantId.ToString()),
            new Claim("deviceId", deviceId.ToString()),
            new Claim("companyName", companyName),
            new Claim("module", moduleSlug),
            new Claim("branchId", branchId.ToString()),
            new Claim("erpEmpresaId", erpEmpresaId.ToString()),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        return GenerateToken(
            claims,
            _options.DeviceSigningKey,
            "coliseu-identity-device",
            "coliseu-speed-api",
            _options.DeviceExpirationMinutes);
    }

    /// <inheritdoc />
    public (string Token, int ExpiresInSeconds) GenerateAdminToken(
        Guid adminId, string email, string role, IEnumerable<string>? permissions = null)
    {
        var claims = new List<Claim>
        {
            new("adminId", adminId.ToString()),
            new(ClaimTypes.Email, email),
            new(ClaimTypes.Role, role),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        // Adiciona cada permissão como claim separada "perm"
        foreach (var perm in permissions ?? Enumerable.Empty<string>())
            claims.Add(new Claim("perm", perm));

        return GenerateToken(
            claims.ToArray(),
            _options.AdminSigningKey,
            "coliseu-identity-admin",
            "coliseu-identity-api",
            _options.AdminExpirationMinutes);
    }

    private static (string Token, int ExpiresInSeconds) GenerateToken(
        Claim[] claims, string signingKey, string issuer, string audience, int expirationMinutes)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(signingKey));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(expirationMinutes),
            signingCredentials: credentials);

        var tokenString = new JwtSecurityTokenHandler().WriteToken(token);
        return (tokenString, expirationMinutes * 60);
    }
}
